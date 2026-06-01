/* src/spot.vala
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

public const uint32 BLANK_HASH = uint32.MAX;

public class RadioConstants {
    public const string UNKNOWN_MODE = "Unknown";

    public const string[] BANDS = {
        "All", "160m", "80m", "60m", "40m", "30m", "20m", "17m",
        "15m", "12m", "10m", "6m", "2m", "70cm"
    };

    public const string[] MODES = {
        "SSB", "CW", "FT8", "FT4", "FM", "AM", "RTTY", "JT65"
    };
}

public string band_from_khz (double khz) {
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

public sealed class Spot : Object, WeatherSpotDetails {
    public const uint HEARD_RECENTLY_TIMEOUT_SECONDS = 90;
    private uint heard_recently_timeout_id = 0;

    public string callsign { get; construct; }
    public string park_ref { get; construct; }
    public string park_name { get; construct; }
    public string location_desc { get; construct; }
    public string activator_comment { get; construct; }
    public double frequency_khz { get; construct; }
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
    public Quark hash { get; construct; default = BLANK_HASH; }
    public bool is_new_park { get; private set; default = false; }
    public bool was_hunted_today { get; private set; default = false; }
    public bool is_new_band { get; private set; default = false; }
    public string? rst_sent { get; construct; }
    public string? rst_rcvd { get; construct; }
    public bool heard_recently { get; private set; default = false; }

    public Spot (string callsign,
                 string park_ref,
                 string park_name,
                 string location_desc,
                 string activator_comment,
                 double frequency_khz,
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

    public string weather_park_ref () {
        return park_ref;
    }

    public string weather_grid4 () {
        return grid4;
    }

    public string weather_grid6 () {
        return grid6;
    }

    public Spot.from_add_spot (
        string callsign,
        string park_ref,
        DateTime spot_time,
        string frequency_khz,
        string mode,
        string spotter,
        string spotter_comment,
        string rst_sent,
        string rst_rcvd) {
        Object (
            callsign: callsign,
            park_ref: park_ref,
            spot_time: spot_time,
            frequency_khz: parse_khz_or_zero (frequency_khz),
            mode: mode,
            spotter: spotter,
            spotter_comment: spotter_comment,
            rst_sent: rst_sent,
            rst_rcvd: rst_rcvd
        );
    }

    private static string required_string_member (
        Json.Object object,
        string member
    ) throws Error {
        if (!object.has_member (member)) {
            throw new IOError.INVALID_DATA (
                "Spot is missing required member '%s'".printf (member)
            );
        }

        var value = object.get_string_member_with_default (member, "");
        if (value.strip () == "") {
            throw new IOError.INVALID_DATA (
                "Spot has empty required member '%s'".printf (member)
            );
        }

        return value;
    }

    private static string optional_mode_member (Json.Object object) {
        var value = object.get_string_member_with_default ("mode", "").strip ();
        return value != "" ? value : RadioConstants.UNKNOWN_MODE;
    }

    private static double parse_frequency_khz (Json.Object object) throws Error {
        var value = object.get_string_member_with_default ("frequency", "0").strip ();
        try {
            return parse_frequency (value, FrequencyUnit.KHZ, FrequencyUnit.KHZ);
        } catch (FrequencyError error) {
            throw new IOError.INVALID_DATA (
                "Spot has invalid frequency '%s'".printf (value)
            );
        }
    }

    private static DateTime parse_spot_time (Json.Object object) throws Error {
        var value = required_string_member (object, "spotTime");
        DateTime? parsed = new GLib.DateTime.from_iso8601 (
            value,
            new GLib.TimeZone.utc ()
        );

        if (parsed == null) {
            throw new IOError.INVALID_DATA (
                "Spot has invalid spotTime '%s'".printf (value)
            );
        }

        return parsed;
    }

    public Spot.from_json (Json.Object spot) throws Error {
        Object (
            callsign: required_string_member (spot, "activator"),
            park_ref: required_string_member (spot, "reference"),
            park_name: spot.get_string_member_with_default ("name", ""),
            mode: optional_mode_member (spot),
            location_desc: spot.get_string_member_with_default ("locationDesc", ""),
            activator_comment: spot.get_string_member_with_default (
                "activatorLastComments",
                ""
            ),
            spotter: spot.get_string_member_with_default ("spotter", ""),
            spotter_comment: spot.get_string_member_with_default ("comments", ""),
            spot_count: (int)spot.get_int_member_with_default ("count", 0),
            frequency_khz: parse_frequency_khz (spot),
            spot_time: parse_spot_time (spot),
            grid4: spot.get_string_member_with_default ("grid4", ""),
            grid6: spot.get_string_member_with_default ("grid6", "")
        );
    }

    construct {
        band = band_from_khz (frequency_khz);

        var key = @"$callsign|$park_ref";
        hash = GLib.Quark.from_string (key);
        if (hash == BLANK_HASH)
            hash = hash - 1;

        coordinate = null;
        distance = -1.0;
        bearing = -1.0;

        var park_grid = ((grid6 ?? "") == "") ? (grid4 ?? "") : grid6;
        if ((park_grid != null) && (park_grid.strip () != "")) {
            try {
                coordinate = Distance.maidenhead_to_latlon (park_grid);
            } catch (Error error) {
                warning (error.message);
                coordinate = null;
            }
        }

        var grid = Application.settings.get_string ("location");
        if ((coordinate != null) && (grid != "")) {
            try {
                var latlon = Distance.maidenhead_to_latlon (grid);
                distance = Distance.haversine_distance_km (latlon, coordinate);
                bearing = Distance.bearing (latlon, coordinate);
            } catch (Error error) {
                warning (error.message);
                distance = -1.0;
                bearing = -1.0;
            }
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
        builder.add_string_value (format_frequency_khz (frequency_khz));

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

    public void mark_heard_recently (uint timeout_seconds = HEARD_RECENTLY_TIMEOUT_SECONDS) {
        heard_recently = true;
        notify_property ("heard-recently");

        if (heard_recently_timeout_id != 0) {
            Source.remove (heard_recently_timeout_id);
            heard_recently_timeout_id = 0;
        }

        heard_recently_timeout_id = Timeout.add_seconds (timeout_seconds, () => {
            heard_recently_timeout_id = 0;
            if (heard_recently) {
                heard_recently = false;
                notify_property ("heard-recently");
            }
            return Source.REMOVE;
        });
    }

    public void set_log_status (
        bool was_hunted_today,
        bool is_new_park,
        bool is_new_band
    ) {
        if (this.was_hunted_today != was_hunted_today) {
            this.was_hunted_today = was_hunted_today;
            notify_property ("was-hunted-today");
        }
        if (this.is_new_park != is_new_park) {
            this.is_new_park = is_new_park;
            notify_property ("is-new-park");
        }
        if (this.is_new_band != is_new_band) {
            this.is_new_band = is_new_band;
            notify_property ("is-new-band");
        }
    }

    ~Spot () {
        if (heard_recently_timeout_id != 0) {
            Source.remove (heard_recently_timeout_id);
            heard_recently_timeout_id = 0;
        }
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
            try {
                var obj = element.get_object ();
                spot_store.append (new Spot.from_json (obj));
            } catch (Error err) {
                warning ("Skipping malformed POTA spot: %s", err.message);
            }
        }
    }
} /* class SpotStore */
