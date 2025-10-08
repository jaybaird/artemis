using Shumate;

public class RadioConstants {
    public const string[] BANDS = {
        "All", "160m", "80m", "60m", "40m", "30m", "20m", "17m",
        "15m", "12m", "10m", "6m", "2m", "70cm"
    };

    public const string[] MODES = {
        "SSB", "CW", "FT8", "FM", "AM", "RTTY", "JT65"
    };
}

public string band_from_khz (int khz) {
    double mhz = (double)khz / 1e3;

    if ((mhz >= 1.8) && (mhz < 2.0))
        return RadioConstants.BANDS[1];
    if ((mhz >= 3.5) && (mhz < 4.1))
        return RadioConstants.BANDS[2];
    if ((mhz >= 5.25) && (mhz < 5.45))
        return RadioConstants.BANDS[3];
    if ((mhz >= 7.0) && (mhz < 7.3))
        return RadioConstants.BANDS[4];
    if ((mhz >= 10.1) && (mhz < 10.15))
        return RadioConstants.BANDS[5];
    if ((mhz >= 14.0) && (mhz < 14.35))
        return RadioConstants.BANDS[6];
    if ((mhz >= 18.068) && (mhz < 18.168))
        return RadioConstants.BANDS[7];
    if ((mhz >= 21.0) && (mhz < 21.45))
        return RadioConstants.BANDS[8];
    if ((mhz >= 24.89) && (mhz < 24.99))
        return RadioConstants.BANDS[9];
    if ((mhz >= 28.0) && (mhz < 29.7))
        return RadioConstants.BANDS[10];
    if ((mhz >= 50.0) && (mhz < 54.0))
        return RadioConstants.BANDS[11];
    if ((mhz >= 144.0) && (mhz < 148.0))
        return RadioConstants.BANDS[12];
    if ((mhz >= 420.0) && (mhz < 450.0))
        return RadioConstants.BANDS[13];

    return "Other";
} /* band_from_khz */

public sealed class Spot : Object {
    public string callsign { get; construct; }
    public string park_ref { get; construct; }
    public string park_name { get; construct; }
    public string location_desc { get; construct; }
    public string activator_comment { get; construct; }
    public int frequency_khz { get; construct; }
    public string band { get; construct; }
    public string mode { get; construct; }
    public DateTime spot_time { get; construct; }
    public string spotter { get; construct; }
    public string spotter_comment { get; construct; }
    public int spot_count { get; construct; }
    public string grid4 { get; construct; }
    public string grid6 { get; construct; }
    public double distance { get; construct; }
    public double bearing { get; construct; }
    public Coordinate coordinate { get; construct; }
    public Quark hash { get; construct; default = uint32.MAX; }
    public bool is_new_park { get; construct; }
    public bool was_hunted_today { get; construct; }

    public Spot (string callsign,
                 string park_ref,
                 string park_name,
                 string location_desc,
                 string activator_comment,
                 int frequency_khz,
                 string mode,
                 DateTime created_utc,
                 DateTime spot_time,
                 string spotter,
                 string spotter_comment,
                 int spot_count,
                 string grid4,
                 string grid6) {
        Object (
            callsign: callsign,
            park_ref: park_ref,
            park_name: park_name,
            location_desc: location_desc,
            activator_comment: activator_comment,
            frequency_khz: frequency_khz,
            mode: mode,
            spot_time: spot_time,
            spotter: spotter,
            spotter_comment: spotter_comment,
            spot_count: spot_count,
            grid4: grid4,
            grid6: grid6
        );
    }

    public Spot.from_add_spot (
        string callsign,
        string park_ref,
        DateTime spot_time,
        string frequency_khz,
        string mode,
        string spotter,
        string spotter_comment) {
        Object (
            callsign: callsign,
            park_ref: park_ref,
            spot_time: spot_time,
            frequency_khz: int.parse (frequency_khz),
            mode: mode,
            spotter: spotter,
            spotter_comment: spotter_comment
        );
    }

    public Spot.from_json (Json.Object spot) {
        Object (
            callsign: spot.get_string_member ("activator"),
            park_ref: spot.get_string_member ("reference"),
            park_name: spot.get_string_member ("name"),
            mode: spot.get_string_member ("mode"),
            location_desc: spot.get_string_member ("locationDesc"),
            activator_comment: spot.get_string_member ("activatorLastComments"),
            spotter: spot.get_string_member ("spotter"),
            spotter_comment: spot.get_string_member ("comments"),
            spot_count: (int)spot.get_int_member_with_default ("count", 0),
            frequency_khz: int.parse (spot.get_string_member_with_default (
                "frequency", "0")),
            spot_time: new GLib.DateTime.from_iso8601 (spot.get_string_member (
                "spotTime"), new GLib.TimeZone.utc ()),
            grid4: spot.get_string_member_with_default ("grid4", ""),
            grid6: spot.get_string_member_with_default ("grid6", "")
        );
    }

    construct {
        band = band_from_khz (frequency_khz);

        var key = @"$callsign|$park_ref";
        hash = GLib.Quark.from_string (key);
        if (hash == uint32.MAX)
            hash = hash - 1;

        Error error = null;
        was_hunted_today = Application.spot_database.had_qso_with_park_on_utc_day (
            park_ref, new DateTime.now_utc (), out error);
        is_new_park = !Application.spot_database.is_park_hunted (park_ref, out
            error);

        var grid = Application.settings.get_string ("location");
        if (grid != "") {
            try {
                var latlon = Distance.maidenhead_to_latlon (grid);
                var park_grid = (grid6 == "") ? grid4 : grid6;
                if (park_grid != "") {
                    coordinate = Distance.maidenhead_to_latlon (park_grid);
                    distance = Distance.haversine_distance_km (latlon,
                        coordinate);
                    bearing = Distance.bearing (latlon, coordinate);
                }
            } catch (Error error) {
                warning (error.message);
                coordinate = null;
                distance = -1.0;
                bearing = -1.0;
            }
        } else {
            distance = -1.0;
            bearing = -1.0;
        }
    }

    public Json.Node to_json () {
        var builder = new Json.Builder ();
        builder.begin_object ();

        builder.set_member_name ("activator");
        builder.add_string_value (callsign);

        builder.set_member_name ("spotter");
        builder.add_string_value (spotter);

        builder.set_member_name ("frequency");
        builder.add_string_value (frequency_khz.to_string ("%d"));

        builder.set_member_name ("reference");
        builder.add_string_value (park_ref);

        builder.set_member_name ("mode");
        builder.add_string_value (mode);

        builder.set_member_name ("source");
        builder.add_string_value ("Web");

        if ((spotter_comment != null) && (spotter_comment.strip () != "")) {
            builder.set_member_name ("comments");
            builder.add_string_value (spotter_comment);
        }

        builder.end_object ();

        return builder.get_root ();
    }

    public string to_string () {
        return
            @"Spot(activator: $callsign\nspotter: $spotter\npark: $park_ref\nfrequency: $frequency_khz)";
    }
} /* class Spot */

public sealed class SpotStore : Object {
    public GLib.ListStore spot_store { get; construct; }
    public SpotStore () {
        Object ();
    }

    construct {
        spot_store = new GLib.ListStore (typeof (Spot));
    }

    public void clear () {
        spot_store.remove_all ();
    }

    public void add_from_json (Json.Array array) {
        foreach (var element in array.get_elements ()) {
            var obj = element.get_object ();
            spot_store.append (new Spot.from_json (obj));
        }
    }
} /* class SpotStore */
