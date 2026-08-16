/* src/map/signal_report_heatmap_layer.vala
 *
 * Copyright 2026 Jay Baird (K0VCZ)
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <https://www.gnu.org/licenses/>.
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

using Shumate;
using Gee;

private class RenderedHeatmapPoint : Object {
    public HeatmapPoint point { get; construct; }
    public double x { get; construct; }
    public double y { get; construct; }

    public RenderedHeatmapPoint (HeatmapPoint point, double x, double y) {
        Object (point: point, x: x, y: y);
    }
}

public class SignalReportHeatmapLayer : Layer {
    public const uint DEFAULT_STAMP_RADIUS_PIXELS = 28;
    private const int MAX_RENDERED_BUCKETS = 4000;
    private const uint AGE_REFRESH_INTERVAL_SECONDS = 60;
    private const uint RENDER_SCALE = 2;
    private const double HEATMAP_ALPHA_SCALE = 0.62;
    // Point weights are capped at 1.0; this leaves room for overlapping reports
    // before the heatmap reaches the hottest color.
    private const float HEATMAP_SATURATION = 2.0f;

    private HeatmapModel model;
    private HeatmapStamp stamp;
    private uint _stamp_radius_pixels = DEFAULT_STAMP_RADIUS_PIXELS;
    private ulong model_changed_handler_id = 0;
    private ulong viewport_changed_handler_id = 0;
    private uint age_refresh_timeout_id = 0;
    private uint render_timeout_id = 0;
    private Gdk.Texture? cached_texture = null;
    private int cached_width = 0;
    private int cached_height = 0;
    private bool render_dirty = true;
    private ArrayList<RenderedHeatmapPoint> rendered_points =
        new ArrayList<RenderedHeatmapPoint> ();

    public uint stamp_radius_pixels {
        get { return _stamp_radius_pixels; }
        set {
            if (_stamp_radius_pixels == value)
                return;

            _stamp_radius_pixels = value;
            stamp = HeatmapStamp.gen (scaled_stamp_radius_pixels ());
            invalidate_render ();
        }
    }

    public SignalReportHeatmapLayer (Viewport viewport, HeatmapModel model) {
        Object (viewport: viewport);
        this.model = model;
        stamp = HeatmapStamp.gen (scaled_stamp_radius_pixels ());
        can_target = false;
        overflow = Gtk.Overflow.HIDDEN;

        model_changed_handler_id = model.changed.connect (() => {
            invalidate_render ();
        });
        viewport_changed_handler_id = viewport.changed.connect (() => {
            invalidate_render ();
        });
        age_refresh_timeout_id = Timeout.add_seconds (AGE_REFRESH_INTERVAL_SECONDS, () => {
            model.expire_old_reports ();
            invalidate_render ();
            return Source.CONTINUE;
        });
    }

    ~SignalReportHeatmapLayer () {
        if (model_changed_handler_id != 0) {
            model.disconnect (model_changed_handler_id);
            model_changed_handler_id = 0;
        }

        if (viewport_changed_handler_id != 0) {
            viewport.disconnect (viewport_changed_handler_id);
            viewport_changed_handler_id = 0;
        }

        if (age_refresh_timeout_id != 0) {
            Source.remove (age_refresh_timeout_id);
            age_refresh_timeout_id = 0;
        }

        if (render_timeout_id != 0) {
            Source.remove (render_timeout_id);
            render_timeout_id = 0;
        }
    }

    protected override void size_allocate (int width, int height, int baseline) {
        base.size_allocate (width, height, baseline);

        if ((width != cached_width) || (height != cached_height)) {
            invalidate_render ();
        }
    }

    protected override void snapshot (Gtk.Snapshot snapshot) {
        int width = get_width ();
        int height = get_height ();

        if (width <= 0 || height <= 0)
            return;

        if (cached_texture == null || cached_width != width || cached_height != height) {
            invalidate_render ();
            return;
        }

        Graphene.Rect bounds = {};
        bounds.init (0.0f, 0.0f, (float) width, (float) height);
        snapshot.append_texture (cached_texture, bounds);
    }

    private void invalidate_render () {
        render_dirty = true;
        rebuild_cached_texture ();
    }

    private void rebuild_cached_texture () {
        if (!render_dirty)
            return;

        int width = get_width ();
        int height = get_height ();

        if (width <= 0 || height <= 0)
            return;

        var points = model.get_heatmap_points ();
        if (points.size == 0) {
            clear_cached_texture ();
            render_dirty = false;
            queue_draw ();
            return;
        }

        uint render_width = (uint) int.max (1, (int) Math.ceil (width / (double) RENDER_SCALE));
        uint render_height = (uint) int.max (1, (int) Math.ceil (height / (double) RENDER_SCALE));
        double world_width = get_world_width_pixels ();
        var heatmap = new Heatmap (render_width, render_height);
        rendered_points.clear ();
        // Keep a single GTK snapshot bounded even if the feed produces many unique buckets.
        var rendered = 0;
        foreach (var point in points) {
            if (rendered >= MAX_RENDERED_BUCKETS)
                break;

            double x;
            double y;
            viewport.location_to_widget_coords (this, point.latitude, point.longitude, out x, out y);

            if (y < 0 || y >= height)
                continue;

            for (int world = -1; world <= 1; world++) {
                double shifted_x = x + (world_width * world);
                if (shifted_x < 0 || shifted_x >= width)
                    continue;

                rendered_points.add (new RenderedHeatmapPoint (point, shifted_x, y));
                heatmap.add_weighted_point_with_stamp (
                    (uint) Math.round (shifted_x / RENDER_SCALE),
                    (uint) Math.round (y / RENDER_SCALE),
                    point.weight,
                    stamp
                );
            }
            rendered++;
        }

        uint8[] rgba = new uint8[render_width * render_height * 4];
        heatmap.render_saturated_to (
            default_color_scheme,
            HEATMAP_SATURATION,
            (uchar*) rgba
        );
        apply_alpha_scale (rgba);

        var bytes = new Bytes.take ((owned) rgba);
        cached_texture = new Gdk.MemoryTexture (
            (int) render_width,
            (int) render_height,
            Gdk.MemoryFormat.R8G8B8A8,
            bytes,
            (size_t) render_width * 4
        );
        cached_width = width;
        cached_height = height;
        render_dirty = false;
        queue_draw ();
    }

    private void clear_cached_texture () {
        cached_texture = null;
        cached_width = 0;
        cached_height = 0;
        rendered_points.clear ();
    }

    private void apply_alpha_scale (uint8[] rgba) {
        for (var i = 3; i < rgba.length; i += 4) {
            rgba[i] = (uint8) int.min (
                255,
                (int) Math.round ((double) rgba[i] * HEATMAP_ALPHA_SCALE)
            );
        }
    }

    private uint scaled_stamp_radius_pixels () {
        var scaled_radius = (_stamp_radius_pixels + RENDER_SCALE - 1) / RENDER_SCALE;
        return scaled_radius > 0 ? scaled_radius : 1;
    }

    public bool query_tooltip_at (
        int x,
        int y,
        bool keyboard_mode,
        Gtk.Tooltip tooltip
    ) {
        if (keyboard_mode)
            return false;

        var hovered_point = find_hovered_point ((double) x, (double) y);
        if (hovered_point == null)
            return false;

        tooltip.set_text (tooltip_text_for_point (hovered_point.point));
        return true;
    }

    private RenderedHeatmapPoint? find_hovered_point (double x, double y) {
        RenderedHeatmapPoint? closest_point = null;
        var max_distance = (double) stamp_radius_pixels;
        var closest_distance = max_distance * max_distance;

        foreach (var rendered_point in rendered_points) {
            var dx = rendered_point.x - x;
            var dy = rendered_point.y - y;
            var distance_squared = (dx * dx) + (dy * dy);

            if (distance_squared > closest_distance)
                continue;

            closest_distance = distance_squared;
            closest_point = rendered_point;
        }

        return closest_point;
    }

    private string tooltip_text_for_point (HeatmapPoint point) {
        string time_text = _("Unknown");
        if (point.latest_timestamp_unix > 0) {
            var timestamp = new DateTime.from_unix_utc (point.latest_timestamp_unix);
            time_text = timestamp.format ("%H:%M UTC");
        }

        return _("%s\nStrongest: %d dB\nAverage: %.1f dB\nReports: %u\nLast heard: %s").printf (
            point.grid,
            point.strongest_snr,
            point.average_snr,
            point.count,
            time_text
        );
    }

    private double get_world_width_pixels () {
        var reference_map_source = viewport.get_reference_map_source ();
        if (reference_map_source == null)
            return 0.0;

        return Math.fabs (
            reference_map_source.get_x (viewport.zoom_level, 180.0) -
            reference_map_source.get_x (viewport.zoom_level, -180.0)
        );
    }
}
