/* src/map/wrapped_marker_layer.vala
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

private sealed class WrappedMarkerPlacement : Object {
    public Gtk.Widget widget { get; construct; }
    public double latitude { get; construct; }
    public double longitude { get; construct; }
    public int world_offset { get; construct; }

    public WrappedMarkerPlacement (
        Gtk.Widget widget,
        double latitude,
        double longitude,
        int world_offset
    ) {
        Object (
            widget: widget,
            latitude: latitude,
            longitude: longitude,
            world_offset: world_offset
        );
    }
}

public sealed class WrappedMarkerLayer : Layer {
    private ArrayList<WrappedMarkerPlacement> placements = new ArrayList<WrappedMarkerPlacement> ();
    private ulong viewport_changed_handler_id = 0;

    public WrappedMarkerLayer (Viewport viewport) {
        Object (viewport: viewport);

        viewport_changed_handler_id = viewport.changed.connect (() => {
            queue_allocate ();
            queue_draw ();
        });
    }

    ~WrappedMarkerLayer () {
        if (viewport_changed_handler_id != 0) {
            viewport.disconnect (viewport_changed_handler_id);
            viewport_changed_handler_id = 0;
        }

        remove_all_markers ();
    }

    public void add_marker (
        Gtk.Widget widget,
        double latitude,
        double longitude,
        int world_offset
    ) {
        widget.set_parent (this);
        placements.add (new WrappedMarkerPlacement (
            widget,
            latitude,
            longitude,
            world_offset
        ));
        queue_allocate ();
        queue_draw ();
    }

    public void remove_marker (Gtk.Widget widget) {
        WrappedMarkerPlacement? target = null;
        foreach (var placement in placements) {
            if (placement.widget == widget) {
                target = placement;
                break;
            }
        }

        if (target == null)
            return;

        target.widget.unparent ();
        placements.remove (target);
        queue_allocate ();
        queue_draw ();
    }

    public void raise_marker (Gtk.Widget widget) {
        WrappedMarkerPlacement? target = null;
        foreach (var placement in placements) {
            if (placement.widget == widget) {
                target = placement;
                break;
            }
        }

        if (target == null)
            return;

        placements.remove (target);
        placements.add (target);
        queue_draw ();
    }

    public void remove_all_markers () {
        foreach (var placement in placements)
            placement.widget.unparent ();
        placements.clear ();
        queue_allocate ();
        queue_draw ();
    }

    protected override void measure (
        Gtk.Orientation orientation,
        int for_size,
        out int minimum,
        out int natural,
        out int minimum_baseline,
        out int natural_baseline
    ) {
        minimum = 0;
        natural = 0;
        minimum_baseline = -1;
        natural_baseline = -1;
    }

    protected override void size_allocate (int width, int height, int baseline) {
        base.size_allocate (width, height, baseline);

        double world_width = get_world_width_pixels ();

        foreach (var placement in placements) {
            int min_width;
            int nat_width;
            int min_height;
            int nat_height;
            int ignored_min_baseline;
            int ignored_nat_baseline;

            placement.widget.measure (
                Gtk.Orientation.HORIZONTAL,
                -1,
                out min_width,
                out nat_width,
                out ignored_min_baseline,
                out ignored_nat_baseline
            );
            placement.widget.measure (
                Gtk.Orientation.VERTICAL,
                nat_width,
                out min_height,
                out nat_height,
                out ignored_min_baseline,
                out ignored_nat_baseline
            );

            double x;
            double y;
            viewport.location_to_widget_coords (
                this,
                placement.latitude,
                placement.longitude,
                out x,
                out y
            );

            x += world_width * placement.world_offset;

            var transform = new Gsk.Transform ();
            transform = transform.translate (Graphene.Point () {
                x = (float) (x - (nat_width / 2.0)),
                y = (float) (y - (nat_height / 2.0))
            });
            placement.widget.allocate (nat_width, nat_height, -1, transform);
        }
    }

    protected override void snapshot (Gtk.Snapshot snapshot) {
        foreach (var placement in placements)
            snapshot_child (placement.widget, snapshot);
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
