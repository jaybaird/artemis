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

using Shumate;

namespace Distance {
    public errordomain MaidenheadError {
        TOO_SHORT,
    }

    public inline static double to_radians (double degrees) {
        return degrees * (Math.PI / 180.0);
    }

    public inline static double to_degrees (double radians) {
        return radians * (180.0 / Math.PI);
    }

    public static Coordinate maidenhead_to_latlon (string grid) throws Error {
        if (grid.length < 4)
            throw new MaidenheadError.TOO_SHORT ("Grid locator %s is too short", grid);

        var loc = grid.ascii_down ();
        double lon = (loc[0] - 'a') * 20.0 - 180.0;
        double lat = (loc[1] - 'a') * 10.0 - 90.0;

        lon += (loc[2] - '0') * 2.0;
        lat += (loc[3] - '0') * 1.0;

        if (loc.length >= 6) {
            lon += (loc[4] - 'a') * (5.0 / 60.0);
            lat += (loc[5] - 'a') * (2.5 / 60.0);
            lon += 2.5 / 60.0;
            lat += 1.25 / 60.0;
        } else {
            lon += 1.0;
            lat += 0.5;
        }

        return new Coordinate.full (lat, lon);
    }

    public static double haversine_distance_km (Coordinate a, Coordinate b) {
        return a.distance (b) / 1000.0;
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
