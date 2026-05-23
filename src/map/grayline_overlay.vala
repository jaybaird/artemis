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

using Shumate;

public class GraylineOverlay : Object {
    private const double LONGITUDE_STEP_DEGREES = 2.0;

    public PathLayer layer { get; private set; }

    public bool visible {
        get {
            return layer.visible;
        }
        set {
            layer.visible = value;
        }
    }

    public GraylineOverlay (Viewport viewport) {
        layer = new PathLayer (viewport) {
            closed = true,
            fill = true,
            stroke = true,
            stroke_width = 1.5,
            outline_width = 0.0,
            fill_color = rgba (0.05, 0.08, 0.16, 0.22),
            stroke_color = rgba (1.0, 1.0, 1.0, 0.35)
        };
    }

    public void update (DateTime now) {
        bool close_to_north_pole = !Astronomy.is_sunlit (
            now,
            new Coordinate.full (89.9, 0.0)
        );
        double closure_latitude = close_to_north_pole ? 90.0 : -90.0;

        layer.remove_all ();

        double longitude = -180.0;
        while (longitude <= 180.0) {
            layer.add_node (new Coordinate.full (
                Astronomy.solar_terminator_latitude (now, longitude),
                longitude
            ));
            longitude += LONGITUDE_STEP_DEGREES;
        }

        if (longitude - LONGITUDE_STEP_DEGREES < 180.0) {
            layer.add_node (new Coordinate.full (
                Astronomy.solar_terminator_latitude (now, 180.0),
                180.0
            ));
        }

        layer.add_node (new Coordinate.full (closure_latitude, 180.0));
        layer.add_node (new Coordinate.full (closure_latitude, -180.0));
    }
}
