/* src/map/bounding_box.vala
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

const double MIN_LATITUDE = -85.0511287798;
const double MAX_LATITUDE = 85.0511287798;
const double MIN_LONGITUDE = -180.0;
const double MAX_LONGITUDE = 180.0;

static double meters_to_deg_lat (double meters) {
    return meters / 111320.0;
}

static double meters_to_deg_lon (double meters, double latitude_deg) {
    double lat_rad = Distance.to_radians (latitude_deg);

    return meters / (111320.0 * Math.cos (lat_rad));
}

public class BoundingBox : Object {
    public double min_lat { get; private set; }
    public double min_lon { get; private set; }
    public double max_lat { get; private set; }
    public double max_lon { get; private set; }

    public BoundingBox () {
        clear ();
    }

    public BoundingBox.from_points (Gee.Collection<Coordinate> coords) {
        clear ();
        foreach (var c in coords) {
            extend (c.latitude, c.longitude);
        }
    }

    public void clear () {
        min_lat = MAX_LATITUDE;
        max_lat = MIN_LATITUDE;
        min_lon = MAX_LONGITUDE;
        max_lon = MIN_LONGITUDE;
    }

    public bool is_valid () {
        return min_lat <= max_lat && min_lon <= max_lon;
    }

    public void extend (double lat, double lon) {
        lat = clamp (lat, MIN_LATITUDE, MAX_LATITUDE);
        lon = normalize_longitude (lon);

        if (!is_valid ()) {
            min_lat = max_lat = lat;
            min_lon = max_lon = lon;
            return;
        }

        if (lat < min_lat)
            min_lat = lat;
        if (lat > max_lat)
            max_lat = lat;

        if (lon_distance (lon, min_lon) < lon_distance (lon, max_lon)) {
            if (lon < min_lon)
                min_lon = lon;
        } else {
            if (lon > max_lon)
                max_lon = lon;
        }
    }

    public void extend_coord (Coordinate? coord) {
        if (coord == null)
            return;

        extend (coord.latitude, coord.longitude);
    }

    public void expand (int padding_meters = 50000) {
        if (!is_valid ())
            return;

        double lat_center = (min_lat + max_lat) / 2.0;

        double lat_pad = meters_to_deg_lat (padding_meters);
        double lon_pad = meters_to_deg_lon (padding_meters, lat_center);

        min_lat -= lat_pad;
        max_lat += lat_pad;
        min_lon -= lon_pad;
        max_lon += lon_pad;

        min_lat = clamp (min_lat, MIN_LATITUDE, MAX_LATITUDE);
        max_lat = clamp (max_lat, MIN_LATITUDE, MAX_LATITUDE);
        min_lon = clamp (min_lon, MIN_LONGITUDE, MAX_LONGITUDE);
        max_lon = clamp (max_lon, MIN_LONGITUDE, MAX_LONGITUDE);
    }

    public Coordinate center () {
        var c_lat = (min_lat + max_lat) * 0.5;
        var c_lon = normalize_longitude ((min_lon + max_lon) * 0.5);
        return new Coordinate.full (c_lat, c_lon);
    }

    public bool contains (double lat, double lon) {
        lat = clamp (lat, MIN_LATITUDE, MAX_LATITUDE);
        lon = normalize_longitude (lon);
        return lat >= min_lat && lat <= max_lat &&
               lon >= min_lon && lon <= max_lon;
    }

    public string to_string () {
        return "BBox(lat: %.5f-%.5f, lon: %.5f-%.5f)".printf (min_lat, max_lat,
            min_lon, max_lon);
    }

    private static double normalize_longitude (double lon) {
        while (lon < -180.0) {
            lon += 360.0;
        }

        while (lon > 180.0) {
            lon -= 360.0;
        }

        return lon;
    }

    private static double lon_distance (double a, double b) {
        double d = Math.fabs (a - b);
        return d > 180.0 ? 360.0 - d : d;
    }
}
