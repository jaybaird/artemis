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
    private const string SOURCE_NAME = "NOAA SWPC, SILSO";
    private const int KP_HISTORY_LIMIT = 8;
    private const string PLANETARY_KP_URL = "https://services.swpc.noaa.gov/products/noaa-planetary-k-index.json";
    private const string SOLAR_FLUX_URL = "https://services.swpc.noaa.gov/json/f107_cm_flux.json";
    private const string SILSO_SUNSPOT_URL = "https://www.sidc.be/SILSO/DATA/EISN/EISN_current.csv";
    private const string XRAY_FLUX_URL = "https://services.swpc.noaa.gov/json/goes/primary/xrays-1-day.json";
    private const string SOLAR_WIND_URL = "https://services.swpc.noaa.gov/products/solar-wind/plasma-7-day.json";

    private Soup.Session session;

    public SpaceWeatherClient () {
        Object ();
    }

    construct {
        session = HttpSessionFactory.create_cached_session (20);
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
                parse_solar_flux_json (
                    yield fetch_text (SOLAR_FLUX_URL, cancellable)
                )
            );
        } catch (Error err) {
            warning ("Unable to load NOAA F10.7cm solar flux: %s", err.message);
        }

        try {
            merge_snapshot (
                snapshot,
                parse_silso_sunspot_csv (
                    yield fetch_text (SILSO_SUNSPOT_URL, cancellable)
                )
            );
        } catch (Error err) {
            warning ("Unable to load SILSO estimated sunspot number: %s", err.message);
        }

        try {
            merge_snapshot (
                snapshot,
                parse_xray_flux_json (
                    yield fetch_text (XRAY_FLUX_URL, cancellable)
                )
            );
        } catch (Error err) {
            warning ("Unable to load NOAA GOES X-ray flux: %s", err.message);
        }

        try {
            merge_snapshot (
                snapshot,
                parse_solar_wind_json (
                    yield fetch_text (SOLAR_WIND_URL, cancellable)
                )
            );
        } catch (Error err) {
            warning ("Unable to load NOAA solar wind plasma: %s", err.message);
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
            return _("Storm");
        if (kp >= 4.0)
            return _("Unsettled");
        if (kp < 2.0)
            return _("Very Quiet");
        return _("Quiet");
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

    public static SpaceWeatherSnapshot parse_solar_flux_json (string json_text) {
        var snapshot = new SpaceWeatherSnapshot ();
        snapshot.source = SOURCE_NAME;

        var parser = new Json.Parser ();
        try {
            parser.load_from_data (json_text, (ssize_t) json_text.length);
        } catch (Error err) {
            message ("Unable to parse NOAA F10.7cm solar flux JSON: %s", err.message);
            return snapshot;
        }

        var root = parser.get_root ();
        if ((root == null) || (root.get_node_type () != Json.NodeType.ARRAY))
            return snapshot;

        var array = root.get_array ();
        double latest_flux = -1.0;
        DateTime? latest_time = null;

        for (uint i = 0; i < array.get_length (); i++) {
            var object = array.get_object_element (i);
            if (object == null)
                continue;

            double frequency = get_double_member_or_default (object, "frequency", -1.0);
            if (Math.round (frequency) != 2800.0)
                continue;

            double flux = get_double_member_or_default (object, "flux", -1.0);
            if (flux < 0.0)
                continue;

            var time_text = get_string_member_or_default (object, "time_tag", "");
            var flux_time = parse_time_tag_utc (time_text);

            if ((latest_flux < 0.0) ||
                ((flux_time != null) && should_replace_updated_at (latest_time, flux_time))) {
                latest_flux = flux;
                latest_time = flux_time;
            }
        }

        if (latest_flux >= 0.0) {
            snapshot.sfi = (int) Math.round (latest_flux);
            if (latest_time != null)
                snapshot.updated_at_utc = latest_time;
        }

        return snapshot;
    }

    public static SpaceWeatherSnapshot parse_silso_sunspot_csv (string csv_text) {
        var snapshot = new SpaceWeatherSnapshot ();
        snapshot.source = SOURCE_NAME;

        Gee.ArrayList<Gee.ArrayList<string>> rows;
        try {
            uint8[] bytes = csv_text.data;
            rows = new CsvParser ().parse_bytes (bytes);
        } catch (Error err) {
            message ("Unable to parse SILSO estimated sunspot CSV: %s", err.message);
            return snapshot;
        }

        for (int i = rows.size - 1; i >= 0; i--) {
            var row = rows[i];
            if (row.size < 5)
                continue;

            double estimated_ssn = -1.0;
            if (!double.try_parse (row[4].strip (), out estimated_ssn) ||
                (estimated_ssn < 0.0)) {
                continue;
            }

            snapshot.ssn = (int) Math.round (estimated_ssn);
            var observed_date = parse_silso_date_utc (row);
            if (observed_date != null)
                snapshot.updated_at_utc = observed_date;
            break;
        }

        return snapshot;
    }

    public static SpaceWeatherSnapshot parse_xray_flux_json (string json_text) {
        var snapshot = new SpaceWeatherSnapshot ();
        snapshot.source = SOURCE_NAME;

        var parser = new Json.Parser ();
        try {
            parser.load_from_data (json_text, (ssize_t) json_text.length);
        } catch (Error err) {
            message ("Unable to parse NOAA GOES X-ray flux JSON: %s", err.message);
            return snapshot;
        }

        var root = parser.get_root ();
        if ((root == null) || (root.get_node_type () != Json.NodeType.ARRAY))
            return snapshot;

        var array = root.get_array ();
        double latest_flux = -1.0;
        DateTime? latest_time = null;

        for (uint i = 0; i < array.get_length (); i++) {
            var object = array.get_object_element (i);
            if (object == null)
                continue;

            if (get_string_member_or_default (object, "energy", "") != "0.1-0.8nm")
                continue;

            double flux = get_double_member_or_default (object, "flux", -1.0);
            if (flux < 0.0)
                continue;

            var time_text = get_string_member_or_default (object, "time_tag", "");
            var flux_time = parse_time_tag_utc (time_text);

            if ((latest_flux < 0.0) ||
                ((flux_time != null) && should_replace_updated_at (latest_time, flux_time))) {
                latest_flux = flux;
                latest_time = flux_time;
            }
        }

        if (latest_flux >= 0.0) {
            snapshot.xray_flux = latest_flux;
            if (latest_time != null)
                snapshot.updated_at_utc = latest_time;
        }

        return snapshot;
    }

    public static SpaceWeatherSnapshot parse_solar_wind_json (string json_text) {
        var snapshot = new SpaceWeatherSnapshot ();
        snapshot.source = SOURCE_NAME;

        var parser = new Json.Parser ();
        try {
            parser.load_from_data (json_text, (ssize_t) json_text.length);
        } catch (Error err) {
            message ("Unable to parse NOAA solar wind plasma JSON: %s", err.message);
            return snapshot;
        }

        var root = parser.get_root ();
        if ((root == null) || (root.get_node_type () != Json.NodeType.ARRAY))
            return snapshot;

        var array = root.get_array ();
        var header_row = array.get_array_element (0);
        if (header_row == null)
            return snapshot;

        int time_index = find_header_index (header_row, "time_tag");
        int density_index = find_header_index (header_row, "density");
        int speed_index = find_header_index (header_row, "speed");

        if ((time_index < 0) || (speed_index < 0))
            return snapshot;

        for (int i = (int) array.get_length () - 1; i >= 1; i--) {
            var row = array.get_array_element ((uint) i);
            if (row == null)
                continue;

            double speed = get_array_double_or_default (row, speed_index, -1.0);
            if (speed < 0.0)
                continue;

            snapshot.solar_wind_speed = speed;
            if (density_index >= 0) {
                double density = get_array_double_or_default (row, density_index, -1.0);
                if (density >= 0.0)
                    snapshot.solar_wind_density = density;
            }

            var time_text = get_array_string_or_default (row, time_index, "");
            var wind_time = parse_time_tag_utc (time_text);
            if (wind_time != null)
                snapshot.updated_at_utc = wind_time;
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
        if (update.has_xray_flux ())
            target.xray_flux = update.xray_flux;
        if (update.has_solar_wind_speed ())
            target.solar_wind_speed = update.solar_wind_speed;
        if (update.has_solar_wind_density ())
            target.solar_wind_density = update.solar_wind_density;
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

    private static DateTime? parse_silso_date_utc (Gee.ArrayList<string> row) {
        if (row.size < 3)
            return null;

        int year = 0;
        int month = 0;
        int day = 0;
        if (!int.try_parse (row[0].strip (), out year) ||
            !int.try_parse (row[1].strip (), out month) ||
            !int.try_parse (row[2].strip (), out day)) {
            return null;
        }

        return new DateTime.utc (year, month, day, 0, 0, 0.0);
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

    private static DateTime? parse_time_tag_utc (string time_tag) {
        var trimmed = time_tag.strip ();
        if (trimmed == "")
            return null;

        if (!trimmed.contains ("T") && trimmed.contains (" "))
            trimmed = trimmed.replace (" ", "T");

        if (!trimmed.has_suffix ("Z") &&
            !trimmed.has_suffix ("+00:00") &&
            !trimmed.has_suffix ("-00:00")) {
            trimmed = "%sZ".printf (trimmed);
        }

        return new DateTime.from_iso8601 (trimmed, null);
    }
}
