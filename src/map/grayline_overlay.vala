/* src/map/grayline_overlay.vala
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

using Gee;
using Shumate;

private sealed class GraylineLayer : Layer {
    private ArrayList<Coordinate> points = new ArrayList<Coordinate> ();
    private Gdk.RGBA fill_color = rgba (0.05, 0.08, 0.16, 0.22);
    private ulong viewport_changed_handler_id = 0;

    public GraylineLayer (Viewport viewport) {
        Object (viewport: viewport);

        viewport_changed_handler_id = viewport.changed.connect (() => {
            queue_draw ();
        });
    }

    ~GraylineLayer () {
        if (viewport_changed_handler_id != 0) {
            viewport.disconnect (viewport_changed_handler_id);
            viewport_changed_handler_id = 0;
        }
    }

    public void set_points (Gee.Collection<Coordinate> points) {
        this.points.clear ();
        this.points.add_all (points);
        queue_draw ();
    }

    protected override void snapshot (Gtk.Snapshot snapshot) {
        int width = get_width ();
        int height = get_height ();

        if (width <= 0 || height <= 0 || points.size < 3)
            return;

        Graphene.Rect bounds = {};
        bounds.init (0.0f, 0.0f, (float) width, (float) height);

        var cr = snapshot.append_cairo (bounds);
        double world_width = get_world_width_pixels ();

        for (int world = -1; world <= 1; world++) {
            append_world_path (cr, world_width * world);
            Gdk.cairo_set_source_rgba (cr, fill_color);
            cr.fill ();
        }
    }

    private void append_world_path (Cairo.Context cr, double x_offset) {
        bool first = true;
        foreach (var point in points) {
            double x;
            double y;
            viewport.location_to_widget_coords (
                this,
                point.latitude,
                point.longitude,
                out x,
                out y
            );

            x += x_offset;

            if (first) {
                cr.move_to (x, y);
                first = false;
            } else {
                cr.line_to (x, y);
            }
        }

        cr.close_path ();
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

public class GraylineOverlay : Object {
    private const double LONGITUDE_STEP_DEGREES = 2.0;

    public Layer layer { get; private set; }

    public bool visible {
        get {
            return layer.visible;
        }
        set {
            layer.visible = value;
        }
    }

    public GraylineOverlay (Viewport viewport) {
        layer = new GraylineLayer (viewport);
    }

    public void update (DateTime now) {
        bool close_to_north_pole = !Astronomy.is_sunlit (
            now,
            new Coordinate.full (89.9, 0.0)
        );
        double closure_latitude = close_to_north_pole ? 90.0 : -90.0;
        var nodes = new ArrayList<Coordinate> ();

        double longitude = -180.0;
        while (longitude <= 180.0) {
            nodes.add (new Coordinate.full (
                Astronomy.solar_terminator_latitude (now, longitude),
                longitude
            ));
            longitude += LONGITUDE_STEP_DEGREES;
        }

        if (longitude - LONGITUDE_STEP_DEGREES < 180.0) {
            nodes.add (new Coordinate.full (
                Astronomy.solar_terminator_latitude (now, 180.0),
                180.0
            ));
        }

        nodes.add (new Coordinate.full (closure_latitude, 180.0));
        nodes.add (new Coordinate.full (closure_latitude, -180.0));
        ((GraylineLayer) layer).set_points (nodes);
    }
}
