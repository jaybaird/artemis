/* src/utils/map.vala
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

public sealed class Coordinate : Object {
    public double latitude { get; construct; }
    public double longitude { get; construct; }

    public Coordinate () {
        Object (
            latitude: 0.0,
            longitude: 0.0
        );
    }

    public Coordinate.full (double latitude, double longitude) {
        Object (
            latitude: latitude,
            longitude: longitude
        );
    }

    public double distance (Coordinate other) {
        double lat1 = Distance.to_radians (latitude);
        double lat2 = Distance.to_radians (other.latitude);
        double dlat = Distance.to_radians (other.latitude - latitude);
        double dlon = Distance.to_radians (other.longitude - longitude);

        double a = Math.sin (dlat / 2.0) * Math.sin (dlat / 2.0)
            + Math.cos (lat1) * Math.cos (lat2)
            * Math.sin (dlon / 2.0) * Math.sin (dlon / 2.0);
        double c = 2.0 * Math.atan2 (Math.sqrt (a), Math.sqrt (1.0 - a));

        return 6371000.0 * c;
    }

    public double distance_km (Coordinate other) {
        return distance (other) / 1000.0;
    }

}
