/* src/distance.vala
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

namespace Distance {
    public inline static double to_radians (double degrees) {
        return degrees * (Math.PI / 180.0);
    }

    public inline static double to_degrees (double radians) {
        return radians * (180.0 / Math.PI);
    }

    public static double bearing (Coordinate a, Coordinate b) {
        double lat1 = to_radians (a.latitude);
        double lat2 = to_radians (b.latitude);
        double dlon = to_radians (b.longitude - a.longitude);

        double y = Math.sin (dlon) * Math.cos (lat2);
        double x = Math.cos (lat1) * Math.sin (lat2) - Math.sin (lat1) * Math.cos (
            lat2) * Math.cos (dlon);
        double brng = Math.atan2 (y, x);
        brng = to_degrees (brng);
        return (brng + 360) % 360;
    }

} /* namespace Distance */
