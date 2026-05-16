/* src/solar_conditions.vala
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
using Gdk;
using Json;
using Xml;

public enum SolarFreshness {
    EMPTY,
    CACHED,
    FRESH,
    STALE
}

public sealed class SolarBandCondition : GLib.Object {
    public string band_group { get; set; default = ""; }
    public string day { get; set; default = "—"; }
    public string night { get; set; default = "—"; }

    public SolarBandCondition (string band_group = "", string day = "—", string night = "—") {
        GLib.Object (
            band_group: band_group,
            day: day,
            night: night
        );
    }
}

public sealed class SolarVhfCondition : GLib.Object {
    public string title { get; set; default = ""; }
    public string value { get; set; default = ""; }

    public SolarVhfCondition (string title = "", string value = "") {
        GLib.Object (title: title, value: value);
    }
}

public sealed class SolarAlertEntry : GLib.Object {
    public string product_id { get; set; default = ""; }
    public string issue_time_text { get; set; default = ""; }
    public string summary { get; set; default = ""; }
    public string message { get; set; default = ""; }

    public SolarAlertEntry (
        string product_id = "",
        string issue_time_text = "",
        string summary = "",
        string message = ""
    ) {
        GLib.Object (
            product_id: product_id,
            issue_time_text: issue_time_text,
            summary: summary,
            message: message
        );
    }
}

public sealed class SolarKpPoint : GLib.Object {
    public DateTime time { get; set; }
    public double kp { get; set; default = 0.0; }
    public double a_running { get; set; default = 0.0; }
    public int station_count { get; set; default = 0; }

    public SolarKpPoint (DateTime time, double kp, double a_running, int station_count) {
        GLib.Object (
            time: time,
            kp: kp,
            a_running: a_running,
            station_count: station_count
        );
    }
}

public sealed class SolarConditionsModel : GLib.Object {
    public SolarFreshness freshness { get; set; default = SolarFreshness.EMPTY; }
    public bool refreshing { get; set; default = false; }
    public DateTime? last_updated { get; set; default = null; }
    public string hamqsl_updated_text { get; set; default = ""; }
    public string? error_message { get; set; default = null; }

    public double sfi { get; set; default = 0.0; }
    public int sunspots { get; set; default = 0; }
    public double a_index { get; set; default = 0.0; }
    public double k_index { get; set; default = 0.0; }
    public string k_index_night { get; set; default = ""; }
    public string xray_class { get; set; default = ""; }
    public double helium_line { get; set; default = 0.0; }
    public double proton_flux { get; set; default = 0.0; }
    public double electron_flux { get; set; default = 0.0; }
    public int aurora { get; set; default = 0; }
    public double normalization { get; set; default = 0.0; }
    public double aurora_latitude_limit { get; set; default = 0.0; }
    public double solar_wind_speed { get; set; default = 0.0; }
    public double magnetic_field_bz { get; set; default = 0.0; }
    public string geomagnetic_field_label { get; set; default = ""; }
    public string signal_noise { get; set; default = ""; }
    public string muf { get; set; default = ""; }
    public string fof2 { get; set; default = ""; }
    public string hamqsl_kp_estimate { get; set; default = ""; }

    public ArrayList<SolarBandCondition> hf_conditions { get; private set; }
    public ArrayList<SolarVhfCondition> vhf_conditions { get; private set; }
    public ArrayList<SolarKpPoint> kp_history { get; private set; }
    public ArrayList<SolarAlertEntry> alerts { get; private set; }

    public SolarConditionsModel () {
        GLib.Object ();
        hf_conditions = new ArrayList<SolarBandCondition> ();
        vhf_conditions = new ArrayList<SolarVhfCondition> ();
        kp_history = new ArrayList<SolarKpPoint> ();
        alerts = new ArrayList<SolarAlertEntry> ();
    }

    public void clear_dynamic_data () {
        hf_conditions.clear ();
        vhf_conditions.clear ();
        kp_history.clear ();
        alerts.clear ();
    }

    public void copy_from (SolarConditionsModel src) {
        freshness = src.freshness;
        refreshing = src.refreshing;
        last_updated = src.last_updated;
        hamqsl_updated_text = src.hamqsl_updated_text;
        error_message = src.error_message;
        sfi = src.sfi;
        a_index = src.a_index;
        sunspots = src.sunspots;
        k_index = src.k_index;
        k_index_night = src.k_index_night;
        xray_class = src.xray_class;
        helium_line = src.helium_line;
        proton_flux = src.proton_flux;
        electron_flux = src.electron_flux;
        aurora = src.aurora;
        normalization = src.normalization;
        aurora_latitude_limit = src.aurora_latitude_limit;
        solar_wind_speed = src.solar_wind_speed;
        magnetic_field_bz = src.magnetic_field_bz;
        geomagnetic_field_label = src.geomagnetic_field_label;
        signal_noise = src.signal_noise;
        muf = src.muf;
        fof2 = src.fof2;
        hamqsl_kp_estimate = src.hamqsl_kp_estimate;

        clear_dynamic_data ();
        foreach (var item in src.hf_conditions) {
            hf_conditions.add (new SolarBandCondition (
                item.band_group,
                item.day,
                item.night
            ));
        }
        foreach (var item in src.vhf_conditions) {
            vhf_conditions.add (new SolarVhfCondition (
                item.title,
                item.value
            ));
        }
        foreach (var item in src.kp_history) {
            kp_history.add (new SolarKpPoint (
                item.time,
                item.kp,
                item.a_running,
                item.station_count
            ));
        }
        foreach (var item in src.alerts) {
            alerts.add (new SolarAlertEntry (
                item.product_id,
                item.issue_time_text,
                item.summary,
                item.message
            ));
        }
    }
}

public sealed class SolarConditionsService : GLib.Object {
    private const string HAMQSL_URL = "https://www.hamqsl.com/solarxml.php";
    private const string NOAA_KP_URL = "https://services.swpc.noaa.gov/products/noaa-planetary-k-index.json";
    private const string NOAA_ALERTS_URL = "https://services.swpc.noaa.gov/products/alerts.json";
    private const uint REFRESH_INTERVAL_SECONDS = 600;

    private Soup.Session session;
    private uint timer_id = 0;
    private bool refresh_in_progress = false;
    private string cache_path;

    public SolarConditionsModel model { get; private set; }

    public signal void updated ();

    public SolarConditionsService () {
        GLib.Object ();
    }

    construct {
        session = new Soup.Session ();
        session.timeout = 30;
        session.user_agent = "Artemis/%s".printf (Build.VERSION);

        model = new SolarConditionsModel ();
        cache_path = GLib.Path.build_filename (
            Environment.get_user_cache_dir (),
            "artemis",
            "solar-conditions.json"
        );

        load_cache ();

        timer_id = Timeout.add_seconds (REFRESH_INTERVAL_SECONDS, () => {
            refresh.begin ();
            return true;
        });

        refresh.begin ();
    }

    private async string fetch_text (string url, string source_name) throws GLib.Error {
        var message = new Soup.Message ("GET", url);
        message.request_headers.replace ("Accept", "application/xml, application/json;q=0.9, */*;q=0.1");
        message.request_headers.replace ("User-Agent", session.user_agent);

        var response = yield session.send_and_read_async (
            message,
            Priority.DEFAULT,
            null
        );

        if (message.status_code != Soup.Status.OK) {
            throw new IOError.FAILED (
                "%s request failed: %u %s".printf (
                    source_name,
                    message.status_code,
                    message.reason_phrase
                )
            );
        }

        return (string) response.get_data ();
    }

    private static DateTime parse_iso_utc (string text) throws GLib.Error {
        var normalized = text.strip ();
        if (normalized.has_suffix ("Z")) {
            return new DateTime.from_iso8601 (normalized, new TimeZone.utc ());
        }

        return new DateTime.from_iso8601 ("%sZ".printf (normalized), new TimeZone.utc ());
    }

    private static string? node_text (Xml.Node* parent, string child_name) {
        if (parent == null)
            return null;

        var child = parent->first_element_child ();
        while (child != null) {
            if ((child->name ?? "") == child_name) {
                var text = child->get_content ();
                return text != null ? text.strip () : null;
            }
            child = child->next_element_sibling ();
        }

        return null;
    }

    private static Xml.Node* child_node (Xml.Node* parent, string child_name) {
        if (parent == null)
            return null;

        var child = parent->first_element_child ();
        while (child != null) {
            if ((child->name ?? "") == child_name)
                return child;
            child = child->next_element_sibling ();
        }

        return null;
    }

    private static double parse_double_member (string? value, double fallback = 0.0) {
        if (value == null)
            return fallback;

        double parsed = 0.0;
        unowned string unparsed;
        if (double.try_parse (value, out parsed, out unparsed) && (unparsed == ""))
            return parsed;
        return fallback;
    }

    private static int parse_int_member (string? value, int fallback = 0) {
        if (value == null)
            return fallback;

        int parsed = 0;
        unowned string unparsed;
        if (int.try_parse (value, out parsed, out unparsed) && (unparsed == ""))
            return parsed;
        return fallback;
    }

    private static string pretty_label_for_vhf (string? name, string? location) {
        var pieces = new ArrayList<string> ();
        if ((name ?? "").strip () != "")
            pieces.add (name.strip ());
        if ((location ?? "").strip () != "")
            pieces.add (location.strip ());

        if (pieces.size == 0)
            return _("VHF Condition");
        if (pieces.size == 1)
            return pieces[0];

        return "%s (%s)".printf (pieces[0], pieces[1]);
    }

    private static string alert_summary (string message) {
        foreach (var raw_line in message.split ("\n")) {
            var line = raw_line.strip ();
            if (line == "")
                continue;
            if (line.has_prefix ("Space Weather Message Code:"))
                continue;
            if (line.has_prefix ("Serial Number:"))
                continue;
            if (line.has_prefix ("Issue Time:"))
                continue;
            if (line.has_prefix ("Comment:"))
                continue;

            return line;
        }

        return message.strip ();
    }

    private SolarConditionsModel parse_hamqsl_xml (string xml_text) throws GLib.Error {
        var doc = Xml.Parser.read_memory (xml_text, xml_text.length);
        if (doc == null) {
            throw new IOError.INVALID_DATA ("HamQSL XML could not be parsed");
        }

        var root = doc->get_root_element ();
        if (root == null) {
            throw new IOError.INVALID_DATA ("HamQSL XML was missing the root element");
        }

        var solar_data = child_node (root, "solardata");
        if (solar_data == null) {
            throw new IOError.INVALID_DATA ("HamQSL XML was missing solar data");
        }

        var snapshot = new SolarConditionsModel ();
        snapshot.hamqsl_updated_text = node_text (solar_data, "updated") ?? "";
        snapshot.sfi = parse_double_member (node_text (solar_data, "solarflux"));
        snapshot.a_index = parse_double_member (node_text (solar_data, "aindex"));
        snapshot.k_index = parse_double_member (node_text (solar_data, "kindex"));
        snapshot.k_index_night = node_text (solar_data, "kindexnt") ?? "";
        snapshot.xray_class = node_text (solar_data, "xray") ?? "";
        snapshot.sunspots = 0;
        snapshot.sunspots = parse_int_member (node_text (solar_data, "sunspots"));
        snapshot.helium_line = parse_double_member (node_text (solar_data, "heliumline"));
        snapshot.proton_flux = parse_double_member (node_text (solar_data, "protonflux"));
        snapshot.electron_flux = parse_double_member (node_text (solar_data, "electronflux"));
        snapshot.aurora = parse_int_member (node_text (solar_data, "aurora"));
        snapshot.normalization = parse_double_member (node_text (solar_data, "normalization"));
        snapshot.aurora_latitude_limit = parse_double_member (node_text (solar_data, "latdegree"));
        snapshot.solar_wind_speed = parse_double_member (node_text (solar_data, "solarwind"));
        snapshot.magnetic_field_bz = parse_double_member (node_text (solar_data, "magneticfield"));
        snapshot.geomagnetic_field_label = node_text (solar_data, "geomagfield") ?? "";
        snapshot.signal_noise = node_text (solar_data, "signalnoise") ?? "";
        snapshot.fof2 = node_text (solar_data, "fof2") ?? "";
        snapshot.muf = node_text (solar_data, "muf") ?? "";
        snapshot.hamqsl_kp_estimate = node_text (solar_data, "muffactor") ?? "";

        var band_root = child_node (solar_data, "calculatedconditions");
        if (band_root != null) {
            var band_map = new HashMap<string, SolarBandCondition> ();
            var band_order = new ArrayList<string> ();

            var band = band_root->first_element_child ();
            while (band != null) {
                if ((band->name ?? "") == "band") {
                    var group = (band->get_prop ("name") ?? "").strip ();
                    var time = (band->get_prop ("time") ?? "").strip ().down ();
                    var value = (band->get_content () ?? "").strip ();

                    if (group != "") {
                        SolarBandCondition entry;
                        if (!band_map.has_key (group)) {
                            entry = new SolarBandCondition (group);
                            band_map.set (group, entry);
                            band_order.add (group);
                        } else {
                            entry = band_map.get (group);
                        }

                        if (time == "day")
                            entry.day = value;
                        else if (time == "night")
                            entry.night = value;
                    }
                }

                band = band->next_element_sibling ();
            }

            foreach (var group in band_order) {
                var entry = band_map.get (group);
                if (entry != null)
                    snapshot.hf_conditions.add (entry);
            }
        }

        var vhf_root = child_node (solar_data, "calculatedvhfconditions");
        if (vhf_root != null) {
            var phenomenon = vhf_root->first_element_child ();
            while (phenomenon != null) {
                if ((phenomenon->name ?? "") == "phenomenon") {
                    var title = pretty_label_for_vhf (
                        phenomenon->get_prop ("name"),
                        phenomenon->get_prop ("location")
                    );
                    var value = (phenomenon->get_content () ?? "").strip ();
                    snapshot.vhf_conditions.add (new SolarVhfCondition (title, value));
                }
                phenomenon = phenomenon->next_element_sibling ();
            }
        }

        return snapshot;
    }

    private SolarConditionsModel parse_noaa_kp_history (string json_text) throws GLib.Error {
        var parser = new Json.Parser ();
        parser.load_from_data (json_text, (ssize_t) json_text.length);

        var root = parser.get_root ();
        if ((root == null) || (root.get_node_type () != Json.NodeType.ARRAY)) {
            throw new IOError.INVALID_DATA ("NOAA K-index feed was not a JSON array");
        }

        var array = root.get_array ();
        var snapshot = new SolarConditionsModel ();
        DateTime? latest_time = null;

        for (uint i = 0; i < array.get_length (); i++) {
            var item = array.get_object_element (i);
            if (item == null)
                continue;

            var time_tag = item.get_string_member_with_default ("time_tag", "");
            var kp = item.get_double_member_with_default ("Kp", 0.0);
            var a_running = item.get_double_member_with_default ("a_running", 0.0);
            var station_count = (int) item.get_int_member_with_default ("station_count", 0);

            if (time_tag.strip () == "")
                continue;

            var time = parse_iso_utc ("%sZ".printf (time_tag.strip ()));
            snapshot.kp_history.add (new SolarKpPoint (time, kp, a_running, station_count));
            if (latest_time == null || time.compare (latest_time) > 0)
                latest_time = time;
        }

        if (latest_time != null) {
            var cutoff = latest_time.add_seconds (-24 * 60 * 60);
            var filtered = new ArrayList<SolarKpPoint> ();
            foreach (var point in snapshot.kp_history) {
                if (point.time.compare (cutoff) >= 0)
                    filtered.add (point);
            }

            snapshot.kp_history.clear ();
            foreach (var point in filtered)
                snapshot.kp_history.add (point);
        }

        return snapshot;
    }

    private SolarConditionsModel parse_noaa_alerts (string json_text) throws GLib.Error {
        var parser = new Json.Parser ();
        parser.load_from_data (json_text, (ssize_t) json_text.length);

        var root = parser.get_root ();
        if ((root == null) || (root.get_node_type () != Json.NodeType.ARRAY)) {
            throw new IOError.INVALID_DATA ("NOAA alerts feed was not a JSON array");
        }

        var array = root.get_array ();
        var snapshot = new SolarConditionsModel ();
        var cutoff = new DateTime.now_utc ().add_seconds (-24 * 60 * 60);

        for (uint i = 0; i < array.get_length (); i++) {
            var item = array.get_object_element (i);
            if (item == null)
                continue;

            var issue_text = item.get_string_member_with_default ("issue_datetime", "");
            var product_id = item.get_string_member_with_default ("product_id", "");
            var message = item.get_string_member_with_default ("message", "").strip ();

            if ((issue_text.strip () == "") || (message == ""))
                continue;

            var issue_time = parse_iso_utc ("%sZ".printf (issue_text.strip ().replace (" ", "T")));
            if (issue_time.compare (cutoff) < 0)
                continue;

            snapshot.alerts.add (new SolarAlertEntry (
                product_id,
                issue_time.format ("%Y-%m-%d %H:%M UTC"),
                alert_summary (message),
                message
            ));
        }

        return snapshot;
    }

    private async SolarConditionsModel? build_snapshot () throws GLib.Error {
        var errors = new ArrayList<string> ();
        var snapshot = new SolarConditionsModel ();

        try {
            var xml_text = yield fetch_text (HAMQSL_URL, "HamQSL");
            var hamqsl = parse_hamqsl_xml (xml_text);
            snapshot.copy_from (hamqsl);
        } catch (GLib.Error e) {
            warning ("HamQSL refresh failed: %s", e.message);
            errors.add (e.message);
        }

        try {
            var kp_text = yield fetch_text (NOAA_KP_URL, "NOAA K-index");
            var kp = parse_noaa_kp_history (kp_text);
            snapshot.kp_history.clear ();
            foreach (var point in kp.kp_history)
                snapshot.kp_history.add (point);
        } catch (GLib.Error e) {
            warning ("NOAA K-index refresh failed: %s", e.message);
            errors.add (e.message);
        }

        try {
            var alerts_text = yield fetch_text (NOAA_ALERTS_URL, "NOAA alerts");
            var alerts = parse_noaa_alerts (alerts_text);
            snapshot.alerts.clear ();
            foreach (var alert in alerts.alerts)
                snapshot.alerts.add (alert);
        } catch (GLib.Error e) {
            warning ("NOAA alerts refresh failed: %s", e.message);
            errors.add (e.message);
        }

        if (errors.size > 0) {
            throw new IOError.FAILED (string.joinv ("; ", errors.to_array ()));
        }

        snapshot.last_updated = new DateTime.now_utc ();
        snapshot.freshness = SolarFreshness.FRESH;
        snapshot.error_message = null;
        snapshot.refreshing = false;
        return snapshot;
    }

    private string freshness_label () {
        switch (model.freshness) {
            case SolarFreshness.FRESH:
                return _("Fresh");
            case SolarFreshness.CACHED:
                return _("Cached");
            case SolarFreshness.STALE:
                return _("Stale");
            case SolarFreshness.EMPTY:
            default:
                return _("Empty");
        }
    }

    private void ensure_cache_dir () {
        var cache_dir = GLib.Path.get_dirname (cache_path);
        if (DirUtils.create_with_parents (cache_dir, 0700) != 0) {
            warning ("Failed to create solar cache directory %s: %s",
                cache_dir, strerror (errno));
        }
    }

    private void save_cache () {
        ensure_cache_dir ();

        var root = new Json.Object ();
        root.set_string_member ("freshness", freshness_label ().down ());
        root.set_string_member ("hamqsl-updated", model.hamqsl_updated_text);
        root.set_string_member (
            "last-updated",
            model.last_updated != null ? model.last_updated.format ("%Y-%m-%dT%H:%M:%SZ") : ""
        );
        root.set_double_member ("sfi", model.sfi);
        root.set_int_member ("sunspots", model.sunspots);
        root.set_double_member ("a-index", model.a_index);
        root.set_double_member ("k-index", model.k_index);
        root.set_string_member ("k-index-night", model.k_index_night);
        root.set_string_member ("xray-class", model.xray_class);
        root.set_double_member ("helium-line", model.helium_line);
        root.set_double_member ("proton-flux", model.proton_flux);
        root.set_double_member ("electron-flux", model.electron_flux);
        root.set_int_member ("aurora", model.aurora);
        root.set_double_member ("normalization", model.normalization);
        root.set_double_member ("aurora-latitude-limit", model.aurora_latitude_limit);
        root.set_double_member ("solar-wind-speed", model.solar_wind_speed);
        root.set_double_member ("magnetic-field-bz", model.magnetic_field_bz);
        root.set_string_member ("geomagnetic-field-label", model.geomagnetic_field_label);
        root.set_string_member ("signal-noise", model.signal_noise);
        root.set_string_member ("muf", model.muf);
        root.set_string_member ("fof2", model.fof2);
        root.set_string_member ("hamqsl-kp-estimate", model.hamqsl_kp_estimate);

        var hf_array = new Json.Array ();
        foreach (var band in model.hf_conditions) {
            var band_obj = new Json.Object ();
            band_obj.set_string_member ("band-group", band.band_group);
            band_obj.set_string_member ("day", band.day);
            band_obj.set_string_member ("night", band.night);
            hf_array.add_object_element (band_obj);
        }
        root.set_array_member ("hf-conditions", hf_array);

        var vhf_array = new Json.Array ();
        foreach (var vhf in model.vhf_conditions) {
            var vhf_obj = new Json.Object ();
            vhf_obj.set_string_member ("title", vhf.title);
            vhf_obj.set_string_member ("value", vhf.value);
            vhf_array.add_object_element (vhf_obj);
        }
        root.set_array_member ("vhf-conditions", vhf_array);

        var kp_array = new Json.Array ();
        foreach (var point in model.kp_history) {
            var kp_obj = new Json.Object ();
            kp_obj.set_string_member ("time", point.time.format ("%Y-%m-%dT%H:%M:%SZ"));
            kp_obj.set_double_member ("kp", point.kp);
            kp_obj.set_double_member ("a-running", point.a_running);
            kp_obj.set_int_member ("station-count", point.station_count);
            kp_array.add_object_element (kp_obj);
        }
        root.set_array_member ("kp-history", kp_array);

        var alerts_array = new Json.Array ();
        foreach (var alert in model.alerts) {
            var alert_obj = new Json.Object ();
            alert_obj.set_string_member ("product-id", alert.product_id);
            alert_obj.set_string_member ("issue-time-text", alert.issue_time_text);
            alert_obj.set_string_member ("summary", alert.summary);
            alert_obj.set_string_member ("message", alert.message);
            alerts_array.add_object_element (alert_obj);
        }
        root.set_array_member ("alerts", alerts_array);

        var node = new Json.Node (Json.NodeType.OBJECT);
        node.set_object (root);

        var generator = new Json.Generator ();
        generator.set_root (node);
        generator.pretty = true;

        size_t len = 0;
        var data = generator.to_data (out len);
        try {
            FileUtils.set_contents (cache_path, data, (ssize_t) len);
        } catch (GLib.Error e) {
            warning ("Unable to write solar cache: %s", e.message);
        }
    }

    private void load_cache () {
        if (!FileUtils.test (cache_path, FileTest.EXISTS))
            return;

        string contents;
        size_t len;
        try {
            if (!FileUtils.get_contents (cache_path, out contents, out len))
                return;
        } catch (GLib.Error e) {
            warning ("Unable to read solar cache: %s", e.message);
            return;
        }

        var parser = new Json.Parser ();
        try {
            parser.load_from_data (contents, (ssize_t) len);
        } catch (GLib.Error e) {
            warning ("Unable to parse solar cache: %s", e.message);
            return;
        }

        var root = parser.get_root ();
        if ((root == null) || (root.get_node_type () != Json.NodeType.OBJECT))
            return;

        var obj = root.get_object ();
        var loaded = new SolarConditionsModel ();
        loaded.freshness = SolarFreshness.CACHED;
        loaded.hamqsl_updated_text = obj.get_string_member_with_default ("hamqsl-updated", "");
        var last_updated_text = obj.get_string_member_with_default ("last-updated", "");
        if (last_updated_text != "") {
            try {
                loaded.last_updated = parse_iso_utc (last_updated_text);
            } catch (GLib.Error e) {
                warning ("Unable to parse cached solar timestamp: %s", e.message);
            }
        }
        loaded.sfi = obj.get_double_member_with_default ("sfi", 0.0);
        loaded.sunspots = (int) obj.get_int_member_with_default ("sunspots", 0);
        loaded.a_index = obj.get_double_member_with_default ("a-index", 0.0);
        loaded.k_index = obj.get_double_member_with_default ("k-index", 0.0);
        loaded.k_index_night = obj.get_string_member_with_default ("k-index-night", "");
        loaded.xray_class = obj.get_string_member_with_default ("xray-class", "");
        loaded.helium_line = obj.get_double_member_with_default ("helium-line", 0.0);
        loaded.proton_flux = obj.get_double_member_with_default ("proton-flux", 0.0);
        loaded.electron_flux = obj.get_double_member_with_default ("electron-flux", 0.0);
        loaded.aurora = (int) obj.get_int_member_with_default ("aurora", 0);
        loaded.normalization = obj.get_double_member_with_default ("normalization", 0.0);
        loaded.aurora_latitude_limit = obj.get_double_member_with_default ("aurora-latitude-limit", 0.0);
        loaded.solar_wind_speed = obj.get_double_member_with_default ("solar-wind-speed", 0.0);
        loaded.magnetic_field_bz = obj.get_double_member_with_default ("magnetic-field-bz", 0.0);
        loaded.geomagnetic_field_label = obj.get_string_member_with_default ("geomagnetic-field-label", "");
        loaded.signal_noise = obj.get_string_member_with_default ("signal-noise", "");
        loaded.muf = obj.get_string_member_with_default ("muf", "");
        loaded.fof2 = obj.get_string_member_with_default ("fof2", "");
        loaded.hamqsl_kp_estimate = obj.get_string_member_with_default ("hamqsl-kp-estimate", "");

        var hf_array = obj.get_array_member ("hf-conditions");
        if (hf_array != null) {
            for (uint i = 0; i < hf_array.get_length (); i++) {
                var item = hf_array.get_object_element (i);
                if (item == null)
                    continue;
                loaded.hf_conditions.add (new SolarBandCondition (
                    item.get_string_member_with_default ("band-group", ""),
                    item.get_string_member_with_default ("day", "—"),
                    item.get_string_member_with_default ("night", "—")
                ));
            }
        }

        var vhf_array = obj.get_array_member ("vhf-conditions");
        if (vhf_array != null) {
            for (uint i = 0; i < vhf_array.get_length (); i++) {
                var item = vhf_array.get_object_element (i);
                if (item == null)
                    continue;
                loaded.vhf_conditions.add (new SolarVhfCondition (
                    item.get_string_member_with_default ("title", ""),
                    item.get_string_member_with_default ("value", "")
                ));
            }
        }

        var kp_array = obj.get_array_member ("kp-history");
        if (kp_array != null) {
            for (uint i = 0; i < kp_array.get_length (); i++) {
                var item = kp_array.get_object_element (i);
                if (item == null)
                    continue;
                var time_text = item.get_string_member_with_default ("time", "");
                if (time_text == "")
                    continue;
                try {
                    loaded.kp_history.add (new SolarKpPoint (
                        parse_iso_utc (time_text),
                        item.get_double_member_with_default ("kp", 0.0),
                        item.get_double_member_with_default ("a-running", 0.0),
                        (int) item.get_int_member_with_default ("station-count", 0)
                    ));
                } catch (GLib.Error e) {
                    warning ("Unable to parse cached Kp history row: %s", e.message);
                }
            }
        }

        var alerts_array = obj.get_array_member ("alerts");
        if (alerts_array != null) {
            for (uint i = 0; i < alerts_array.get_length (); i++) {
                var item = alerts_array.get_object_element (i);
                if (item == null)
                    continue;
                loaded.alerts.add (new SolarAlertEntry (
                    item.get_string_member_with_default ("product-id", ""),
                    item.get_string_member_with_default ("issue-time-text", ""),
                    item.get_string_member_with_default ("summary", ""),
                    item.get_string_member_with_default ("message", "")
                ));
            }
        }

        model.copy_from (loaded);
        updated ();
    }

    public async void refresh () {
        if (refresh_in_progress)
            return;

        refresh_in_progress = true;
        model.refreshing = true;
        updated ();

        try {
            var snapshot = yield build_snapshot ();
            model.copy_from (snapshot);
            model.freshness = SolarFreshness.FRESH;
            model.refreshing = false;
            model.error_message = null;
            save_cache ();
            updated ();
        } catch (GLib.Error e) {
            warning ("Solar conditions refresh failed: %s", e.message);
            model.refreshing = false;
            model.freshness = model.last_updated != null ? SolarFreshness.STALE : SolarFreshness.EMPTY;
            model.error_message = e.message;
            updated ();
        } finally {
            refresh_in_progress = false;
        }
    }
}
