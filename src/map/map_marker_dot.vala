/* src/map/map_marker_dot.vala
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

public class MapMarkerDot : Gtk.DrawingArea {
    private bool _selected = false;

    public bool selected {
        get {
            return _selected;
        }
        set {
            if (_selected == value)
                return;

            _selected = value;
            queue_draw ();
        }
    }

    public MapMarkerDot (string band) {
        width_request = 18;
        height_request = 18;
        halign = Gtk.Align.CENTER;
        valign = Gtk.Align.CENTER;

        add_css_class ("map-marker-dot");
        add_css_class ("map-marker-%s".printf (band));

        set_draw_func ((area, cr, width, height) => {
            var color = area.get_color ();
            double size = (double) int.min (width, height);
            double center_x = width / 2.0;
            double center_y = height / 2.0;
            double radius = (size / 2.0) - 1.5;

            cr.arc (center_x, center_y, radius, 0, 2.0 * Math.PI);
            Gdk.cairo_set_source_rgba (cr, color);
            if (selected)
                cr.fill_preserve ();
            else
                cr.fill ();

            if (selected) {
                cr.set_line_width (2.5);
                cr.set_source_rgba (0.98, 0.98, 0.98, 0.98);
                cr.stroke ();
            }
        });
    }
}
