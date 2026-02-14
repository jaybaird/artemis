using GLib;
using Shumate;

public static inline uint clampi (uint v, uint min, uint max) {
    return (v < min) ? min : (max < v) ? max : v;
}

public static inline double clamp (double v, double min, double max) {
    return (v < min) ? min : (max < v) ? max : v;
}

public static T random_choice<T> (T[] array) {
    if (array.length == 0)
        critical ("Cannot choose from an empty array");
    return array[Random.int_range (0, array.length)];
}

public static Gee.ArrayList<T> to_array<T> (Gee.Iterator<T> iter) {
    var list = new Gee.ArrayList<T> ();

    while (iter.next ()) {
        list.add (iter.get ());
    }

    return list;
}

public static string format_vfo (float freq_khz) {
    uint freq_hz = (uint)(freq_khz * 1000.0 + 0.5);
    uint mhz = freq_hz / 1000000;
    uint khz = (freq_hz / 1000) % 1000;
    uint hz = freq_hz % 1000;

    return "%u.%03u.%02u".printf (mhz, khz, hz / 10);
}

namespace Distance {
    public enum MaidenheadError {
        TOO_SHORT,
    }

    public static GLib.Quark distance_error_quark () {
        return GLib.Quark.from_string ("maidenhead-error");
    }

    public inline static double to_radians (double degrees) {
        return degrees * (Math.PI / 180.0);
    }

    // Convert radians to degrees
    public inline static double to_degrees (double radians) {
        return radians * (180.0 / Math.PI);
    }

    // Parse a Maidenhead locator to decimal degrees (approx center of square)
    public static Coordinate maidenhead_to_latlon (string grid) throws Error {
        if (grid.length < 4)
            throw new Error (distance_error_quark (), MaidenheadError.TOO_SHORT,
                "Grid locator %s is too short", grid);

        var loc = grid.ascii_down ();      // simplify handling
        double lon = (loc[0] - 'a') * 20.0 - 180.0;
        double lat = (loc[1] - 'a') * 10.0 - 90.0;

        lon += (loc[2] - '0') * 2.0;
        lat += (loc[3] - '0') * 1.0;

        if (loc.length >= 6) {
            lon += (loc[4] - 'a') * (5.0 / 60.0);
            lat += (loc[5] - 'a') * (2.5 / 60.0);
            // add half of subsquare to get center
            lon += 2.5 / 60.0;
            lat += 1.25 / 60.0;
        } else {
            // add half of square for center if no subsquare
            lon += 1.0;
            lat += 0.5;
        }

        return new Coordinate.full (lat, lon);
    }

    public static double haversine_distance_km (Coordinate a, Coordinate b) {
        return a.distance (b) / 1000.0;
    }

    // Initial bearing from point A to B
    public static double bearing (Coordinate a, Coordinate b) {
        double lat1 = to_radians (a.latitude);
        double lat2 = to_radians (b.latitude);
        double dlon = to_radians (b.longitude - a.longitude);

        double y = Math.sin (dlon) * Math.cos (lat2);
        double x = Math.cos (lat1) * Math.sin (lat2) - Math.sin (lat1) * Math.cos (
            lat2) * Math.cos (dlon);
        double brng = Math.atan2 (y, x);
        brng = to_degrees (brng);
        return (brng + 360) % 360;      // normalize 0–360°
    }
} /* namespace Distance */
