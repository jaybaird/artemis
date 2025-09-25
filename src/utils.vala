using GLib;

public static Gee.ArrayList<T> to_array<T> (Gee.Iterator<T> iter)
{
    var list = new Gee.ArrayList<T> ();

    while (iter.next ())
    {
        list.add (iter.get ());
    }

    return list;
}

namespace Distance {
public enum MaidenheadError
{
    TOO_SHORT,
}

public static GLib.Quark distance_error_quark ()
{
    return GLib.Quark.from_string ("maidenhead-error");
}

public struct LatLon
{
    public double lat;
    public double lon;
}

public inline static double to_radians (double degrees)
{
    return degrees * (Math.PI / 180.0);
}

// Convert radians to degrees
public inline static double to_degrees (double radians)
{
    return radians * (180.0 / Math.PI);
}

// Parse a Maidenhead locator to decimal degrees (approx center of square)
public static LatLon maidenhead_to_latlon (string grid) throws Error
{
    if (grid.length < 4)
        throw new Error (distance_error_quark (), MaidenheadError.TOO_SHORT,
            "Grid locator %s is too short", grid);

    var loc = grid.ascii_down ();   // simplify handling
    double lon = (loc[0] - 'a') * 20.0 - 180.0;
    double lat = (loc[1] - 'a') * 10.0 - 90.0;

    lon += (loc[2] - '0') * 2.0;
    lat += (loc[3] - '0') * 1.0;

    if (loc.length >= 6)
    {
        lon += (loc[4] - 'a') * (5.0 / 60.0);
        lat += (loc[5] - 'a') * (2.5 / 60.0);
        // add half of subsquare to get center
        lon += 2.5 / 60.0;
        lat += 1.25 / 60.0;
    }
    else
    {
        // add half of square for center if no subsquare
        lon += 1.0;
        lat += 0.5;
    }

    return { lat, lon };
}

// Haversine distance in kilometers
public static double haversine_distance (LatLon a, LatLon b)
{
    double R = 6371.0;   // km
    double dlat = to_radians (b.lat - a.lat);
    double dlon = to_radians (b.lon - a.lon);
    double lat1 = to_radians (a.lat);
    double lat2 = to_radians (b.lat);

    double h = Math.sin (dlat / 2) * Math.sin (dlat / 2) +
        Math.sin (dlon / 2) * Math.sin (dlon / 2) * Math.cos (lat1) * Math.cos (
        lat2);
    double c = 2 * Math.atan2 (Math.sqrt (h), Math.sqrt (1 - h));
    return R * c;
}

// Initial bearing from point A to B
public static double bearing (LatLon a, LatLon b)
{
    double lat1 = to_radians (a.lat);
    double lat2 = to_radians (b.lat);
    double dlon = to_radians (b.lon - a.lon);

    double y = Math.sin (dlon) * Math.cos (lat2);
    double x = Math.cos (lat1) * Math.sin (lat2) - Math.sin (lat1) * Math.cos (
        lat2) * Math.cos (dlon);
    double brng = Math.atan2 (y, x);
    brng = to_degrees (brng);
    return (brng + 360) % 360;   // normalize 0–360°
}
} /* namespace Distance */
