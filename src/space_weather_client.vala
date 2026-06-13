/* src/space_weather_client.vala
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

public sealed class SpaceWeatherClient : Object {
    private const string SOURCE_NAME = "NOAA SWPC";
    private const int KP_HISTORY_LIMIT = 8;
    private const string PLANETARY_KP_URL = "https://services.swpc.noaa.gov/products/noaa-planetary-k-index.json";
    private const string WWV_URL = "https://services.swpc.noaa.gov/text/wwv.txt";
    private const string SOLAR_CYCLE_URL = "https://services.swpc.noaa.gov/json/solar-cycle/observed-solar-cycle-indices.json";

    private Soup.Session session;

    public SpaceWeatherClient () {
        Object ();
    }

    construct {
        session = new Soup.Session () {
            timeout = 20,
            user_agent = Build.USER_AGENT
        };
    }

    public async SpaceWeatherSnapshot fetch_snapshot (Cancellable? cancellable = null) {
        var snapshot = new SpaceWeatherSnapshot ();

        try {
            merge_snapshot (
                snapshot,
                parse_planetary_kp_json (
                    yield fetch_text (PLANETARY_KP_URL, cancellable)
                )
            );
        } catch (Error err) {
            warning ("Unable to load NOAA planetary K-index: %s", err.message);
        }

        try {
            merge_snapshot (
                snapshot,
                parse_solar_cycle_json (
                    yield fetch_text (SOLAR_CYCLE_URL, cancellable)
                )
            );
        } catch (Error err) {
            warning ("Unable to load NOAA solar-cycle indices: %s", err.message);
        }

        try {
            merge_snapshot (
                snapshot,
                parse_wwv_text (
                    yield fetch_text (WWV_URL, cancellable)
                )
            );
        } catch (Error err) {
            warning ("Unable to load NOAA WWV bulletin: %s", err.message);
        }

        snapshot.source = SOURCE_NAME;
        snapshot.geomagnetic_label = snapshot.has_kp ()
            ? label_for_kp (snapshot.kp)
            : "Unknown";
        snapshot.hf_note = snapshot.geomagnetic_label;
        return snapshot;
    }

    private async string fetch_text (string url, Cancellable? cancellable) throws Error {
        var message = new Soup.Message ("GET", url);
        message.request_headers.replace ("User-Agent", session.user_agent);

        var response = yield session.send_and_read_async (
            message,
            Priority.DEFAULT,
            cancellable
        );

        if (message.status_code != Soup.Status.OK) {
            throw new IOError.FAILED ("%s returned %u %s".printf (
                url,
                message.status_code,
                message.reason_phrase
            ));
        }

        return ((string) response.get_data ()).substring (0, (long) response.get_size ());
    }

    public static string label_for_kp (double kp) {
        if (kp >= 5.0)
            return "Storm";
        if (kp >= 4.0)
            return "Unsettled";
        return "Quiet";
    }

    public static SpaceWeatherSnapshot parse_planetary_kp_json (string json_text) {
        var snapshot = new SpaceWeatherSnapshot ();
        var parser = new Json.Parser ();

        try {
            parser.load_from_data (json_text, (ssize_t) json_text.length);
        } catch (Error err) {
            message ("Unable to parse NOAA planetary K-index JSON: %s", err.message);
            return snapshot;
        }

        var root = parser.get_root ();
        if ((root == null) || (root.get_node_type () != Json.NodeType.ARRAY))
            return snapshot;

        var array = root.get_array ();
        if (array.get_length () == 0)
            return snapshot;

        var first_row = array.get_element (0);
        if ((first_row != null) && (first_row.get_node_type () == Json.NodeType.ARRAY)) {
            parse_planetary_kp_table (array, snapshot);
        } else {
            parse_planetary_kp_objects (array, snapshot);
        }

        snapshot.source = SOURCE_NAME;
        if (snapshot.has_kp ()) {
            snapshot.geomagnetic_label = label_for_kp (snapshot.kp);
            snapshot.hf_note = snapshot.geomagnetic_label;
        }

        return snapshot;
    }

    public static SpaceWeatherSnapshot parse_wwv_text (string text) {
        var snapshot = new SpaceWeatherSnapshot ();
        snapshot.source = SOURCE_NAME;

        int parsed_int = -1;
        if (extract_first_int (text, "Solar flux\\s+([0-9]+)", out parsed_int))
            snapshot.sfi = parsed_int;
        if (extract_first_int (text, "A-index\\s+([0-9]+)", out parsed_int))
            snapshot.a_index = parsed_int;

        double parsed_double = -1.0;
        if (extract_first_double (
            text,
            "K-index[^\\n]*?was\\s+([0-9]+(?:\\.[0-9]+)?)",
            out parsed_double
        )) {
            snapshot.kp = parsed_double;
        }

        var issued_at = parse_issued_at_utc (text);
        if (issued_at != null)
            snapshot.updated_at_utc = issued_at;

        if (snapshot.has_kp ()) {
            snapshot.geomagnetic_label = label_for_kp (snapshot.kp);
            snapshot.hf_note = snapshot.geomagnetic_label;
        }

        return snapshot;
    }

    public static SpaceWeatherSnapshot parse_solar_cycle_json (string json_text) {
        var snapshot = new SpaceWeatherSnapshot ();
        snapshot.source = SOURCE_NAME;

        var parser = new Json.Parser ();
        try {
            parser.load_from_data (json_text, (ssize_t) json_text.length);
        } catch (Error err) {
            message ("Unable to parse NOAA solar-cycle JSON: %s", err.message);
            return snapshot;
        }

        var root = parser.get_root ();
        if ((root == null) || (root.get_node_type () != Json.NodeType.ARRAY))
            return snapshot;

        var array = root.get_array ();
        for (int i = (int) array.get_length () - 1; i >= 0; i--) {
            var object = array.get_object_element ((uint) i);
            if (object == null)
                continue;

            double observed_ssn = get_double_member_or_default (
                object,
                "observed_swpc_ssn",
                -1.0
            );
            double fallback_ssn = get_double_member_or_default (object, "ssn", -1.0);
            double best_ssn = observed_ssn >= 0.0 ? observed_ssn : fallback_ssn;
            if (best_ssn < 0.0)
                continue;

            snapshot.ssn = (int) Math.round (best_ssn);
            break;
        }

        return snapshot;
    }

    private static void merge_snapshot (
        SpaceWeatherSnapshot target,
        SpaceWeatherSnapshot update
    ) {
        if (update.has_kp ())
            target.kp = update.kp;
        if (update.has_a_index ())
            target.a_index = update.a_index;
        if (update.has_sfi ())
            target.sfi = update.sfi;
        if (update.has_ssn ())
            target.ssn = update.ssn;
        if (update.has_kp_history ()) {
            target.kp_history.clear ();
            target.kp_history_times_utc.clear ();
            foreach (double? kp_value in update.kp_history)
                target.kp_history.add (kp_value);
            foreach (DateTime? history_time in update.kp_history_times_utc)
                target.kp_history_times_utc.add (history_time);
        }

        if (should_replace_updated_at (target.updated_at_utc, update.updated_at_utc))
            target.updated_at_utc = update.updated_at_utc;
    }

    private static bool should_replace_updated_at (
        DateTime? current_value,
        DateTime? candidate_value
    ) {
        if (candidate_value == null)
            return false;
        if (current_value == null)
            return true;
        return candidate_value.to_unix () > current_value.to_unix ();
    }

    private static void parse_planetary_kp_objects (
        Json.Array array,
        SpaceWeatherSnapshot snapshot
    ) {
        var history = new Gee.ArrayList<double?> ();
        var history_times = new Gee.ArrayList<DateTime?> ();

        for (int i = (int) array.get_length () - 1; i >= 0; i--) {
            var object = array.get_object_element ((uint) i);
            if (object == null)
                continue;

            double kp_value = get_double_member_or_default (object, "Kp", -1.0);
            if (kp_value < 0.0)
                continue;

            var time_text = get_string_member_or_default (object, "time_tag", "");
            var history_time = parse_time_tag_utc (time_text);

            if (history.size < KP_HISTORY_LIMIT) {
                history.insert (0, kp_value);
                history_times.insert (0, history_time);
            }

            if (snapshot.has_kp ())
                continue;

            snapshot.kp = kp_value;
            double a_running = get_double_member_or_default (object, "a_running", -1.0);
            if (a_running >= 0.0)
                snapshot.a_index = (int) Math.round (a_running);

            if (history_time != null)
                snapshot.updated_at_utc = history_time;
        }

        foreach (double? kp_value in history)
            snapshot.kp_history.add (kp_value);
        foreach (DateTime? history_time in history_times)
            snapshot.kp_history_times_utc.add (history_time);
    }

    private static void parse_planetary_kp_table (
        Json.Array array,
        SpaceWeatherSnapshot snapshot
    ) {
        var history = new Gee.ArrayList<double?> ();
        var history_times = new Gee.ArrayList<DateTime?> ();
        var header_row = array.get_array_element (0);
        if (header_row == null)
            return;

        int time_index = find_header_index (header_row, "time_tag");
        int kp_index = find_header_index (header_row, "kp");
        int a_index = find_header_index (header_row, "a_running");

        if ((time_index < 0) || (kp_index < 0))
            return;

        for (int i = (int) array.get_length () - 1; i >= 1; i--) {
            var row = array.get_array_element ((uint) i);
            if (row == null)
                continue;

            double kp_value = get_array_double_or_default (row, kp_index, -1.0);
            if (kp_value < 0.0)
                continue;

            var time_text = get_array_string_or_default (row, time_index, "");
            var history_time = parse_time_tag_utc (time_text);

            if (history.size < KP_HISTORY_LIMIT) {
                history.insert (0, kp_value);
                history_times.insert (0, history_time);
            }

            if (snapshot.has_kp ())
                continue;

            snapshot.kp = kp_value;
            if (a_index >= 0) {
                double parsed_a_index = get_array_double_or_default (row, a_index, -1.0);
                if (parsed_a_index >= 0.0)
                    snapshot.a_index = (int) Math.round (parsed_a_index);
            }

            if (history_time != null)
                snapshot.updated_at_utc = history_time;
        }

        foreach (double? kp_value in history)
            snapshot.kp_history.add (kp_value);
        foreach (DateTime? history_time in history_times)
            snapshot.kp_history_times_utc.add (history_time);
    }

    private static int find_header_index (Json.Array header_row, string expected_name) {
        for (uint i = 0; i < header_row.get_length (); i++) {
            var value = get_array_string_or_default (header_row, (int) i, "").down ();
            if (value == expected_name)
                return (int) i;
        }

        return -1;
    }

    private static string get_string_member_or_default (
        Json.Object object,
        string member,
        string fallback
    ) {
        if (!object.has_member (member))
            return fallback;

        return json_node_to_string (object.get_member (member), fallback);
    }

    private static double get_double_member_or_default (
        Json.Object object,
        string member,
        double fallback
    ) {
        if (!object.has_member (member))
            return fallback;

        return json_node_to_double (object.get_member (member), fallback);
    }

    private static string get_array_string_or_default (
        Json.Array array,
        int index,
        string fallback
    ) {
        if ((index < 0) || ((uint) index >= array.get_length ()))
            return fallback;

        return json_node_to_string (array.get_element ((uint) index), fallback);
    }

    private static double get_array_double_or_default (
        Json.Array array,
        int index,
        double fallback
    ) {
        if ((index < 0) || ((uint) index >= array.get_length ()))
            return fallback;

        return json_node_to_double (array.get_element ((uint) index), fallback);
    }

    private static string json_node_to_string (Json.Node? node, string fallback) {
        if (node == null)
            return fallback;

        var text = Json.to_string (node, false).strip ();
        if (text == "null")
            return fallback;

        if (text.has_prefix ("\"") && text.has_suffix ("\"") && text.length >= 2)
            return text.substring (1, text.length - 2);

        return text;
    }

    private static double json_node_to_double (Json.Node? node, double fallback) {
        var text = json_node_to_string (node, "");
        if (text == "")
            return fallback;

        double value = 0.0;
        return double.try_parse (text, out value) ? value : fallback;
    }

    private static bool extract_first_int (
        string text,
        string pattern,
        out int value
    ) {
        value = -1;

        MatchInfo match_info;
        try {
            var regex = new Regex (pattern, RegexCompileFlags.CASELESS);
            if (!regex.match (text, 0, out match_info))
                return false;
        } catch (RegexError err) {
            warning ("Invalid space-weather regex %s: %s", pattern, err.message);
            return false;
        }

        var matched = match_info.fetch (1);
        if ((matched == null) || (matched == ""))
            return false;

        return int.try_parse (matched, out value);
    }

    private static bool extract_first_double (
        string text,
        string pattern,
        out double value
    ) {
        value = -1.0;

        MatchInfo match_info;
        try {
            var regex = new Regex (pattern, RegexCompileFlags.CASELESS);
            if (!regex.match (text, 0, out match_info))
                return false;
        } catch (RegexError err) {
            warning ("Invalid space-weather regex %s: %s", pattern, err.message);
            return false;
        }

        var matched = match_info.fetch (1);
        if ((matched == null) || (matched == ""))
            return false;

        return double.try_parse (matched, out value);
    }

    private static DateTime? parse_issued_at_utc (string text) {
        MatchInfo match_info;
        try {
            var regex = new Regex (
                "^\\s*:Issued:\\s+([0-9]{4})\\s+([A-Za-z]{3})\\s+([0-9]{1,2})\\s+([0-9]{4})\\s+UTC\\s*$",
                RegexCompileFlags.MULTILINE
            );
            if (!regex.match (text, 0, out match_info))
                return null;
        } catch (RegexError err) {
            warning ("Unable to compile NOAA issued-at regex: %s", err.message);
            return null;
        }

        var year = match_info.fetch (1);
        var month = match_info.fetch (2);
        var day = match_info.fetch (3);
        var hhmm = match_info.fetch (4);
        if ((year == null) || (month == null) || (day == null) || (hhmm == null))
            return null;

        var month_number = month_number_from_abbreviation (month);
        if (month_number == 0)
            return null;

        var iso8601 = "%s-%02d-%02dT%s:%s:00Z".printf (
            year,
            month_number,
            int.parse (day),
            hhmm.substring (0, 2),
            hhmm.substring (2, 2)
        );
        return parse_time_tag_utc (iso8601);
    }

    private static int month_number_from_abbreviation (string month) {
        switch (month.down ()) {
            case "jan":
                return 1;
            case "feb":
                return 2;
            case "mar":
                return 3;
            case "apr":
                return 4;
            case "may":
                return 5;
            case "jun":
                return 6;
            case "jul":
                return 7;
            case "aug":
                return 8;
            case "sep":
                return 9;
            case "oct":
                return 10;
            case "nov":
                return 11;
            case "dec":
                return 12;
            default:
                return 0;
        }
    }

    private static DateTime? parse_time_tag_utc (string time_tag) {
        var trimmed = time_tag.strip ();
        if (trimmed == "")
            return null;

        if (!trimmed.has_suffix ("Z") &&
            !trimmed.has_suffix ("+00:00") &&
            !trimmed.has_suffix ("-00:00")) {
            trimmed = "%sZ".printf (trimmed);
        }

        return new DateTime.from_iso8601 (trimmed, null);
    }
}
