/* src/psk_reporter_client.vala
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

public errordomain PskReporterClientError {
    INVALID_CALLSIGN,
    HTTP_FAILED,
    PARSE_FAILED
}

public sealed class PskReporterReportCache : Object {
    public const int64 DEFAULT_TTL_SECONDS = 250;

    private string cache_path;
    private int64 ttl_seconds;

    public PskReporterReportCache (
        string? cache_path = null,
        int64 ttl_seconds = DEFAULT_TTL_SECONDS
    ) {
        Object ();
        this.cache_path = cache_path ?? Path.build_filename (
            Environment.get_user_cache_dir (),
            "artemis",
            "psk-reporter-cache.ini"
        );
        this.ttl_seconds = ttl_seconds;
    }

    public ArrayList<SignalReport>? get_reports (string callsign) {
        var normalized_callsign = normalize_cache_key (callsign);
        if (normalized_callsign == "")
            return null;

        var key_file = new KeyFile ();
        try {
            key_file.load_from_file (cache_path, KeyFileFlags.NONE);
        } catch (Error err) {
            return null;
        }

        var group = cache_group (normalized_callsign);
        if (!key_file.has_group (group))
            return null;

        try {
            var cached_at = key_file.get_int64 (group, "cached-at");
            var now = new DateTime.now_utc ().to_unix ();
            if (now - cached_at > ttl_seconds)
                return null;

            var count = key_file.get_integer (group, "count");
            var reports = new ArrayList<SignalReport> ();
            for (var i = 0; i < count; i++) {
                var report = read_report (key_file, "%s:%d".printf (group, i));
                if (report != null)
                    reports.add (report);
            }

            return reports;
        } catch (Error err) {
            warning ("Unable to read PSKReporter signal report cache: %s", err.message);
            return null;
        }
    }

    public void store_reports (
        Collection<SignalReport> reports,
        string callsign,
        int64 cached_at
    ) {
        var normalized_callsign = normalize_cache_key (callsign);
        if (normalized_callsign == "")
            return;

        var key_file = new KeyFile ();
        try {
            key_file.load_from_file (cache_path, KeyFileFlags.NONE);
        } catch (Error err) {
            // A missing or malformed cache file should not prevent replacing it.
        }

        var group = cache_group (normalized_callsign);
        remove_existing_report_groups (key_file, group);

        key_file.set_int64 (group, "cached-at", cached_at);
        key_file.set_integer (group, "count", reports.size);

        var index = 0;
        foreach (var report in reports) {
            write_report (key_file, "%s:%d".printf (group, index), report);
            index++;
        }

        ensure_cache_dir ();
        try {
            key_file.save_to_file (cache_path);
        } catch (Error err) {
            warning ("Unable to persist PSKReporter signal report cache: %s", err.message);
        }
    }

    public void store_reports_now (Collection<SignalReport> reports, string callsign) {
        store_reports (reports, callsign, new DateTime.now_utc ().to_unix ());
    }

    private SignalReport? read_report (KeyFile key_file, string group) throws Error {
        if (!key_file.has_group (group))
            return null;

        return new SignalReport.from_grid (
            key_file.get_string (group, "call"),
            key_file.get_string (group, "grid"),
            optional_string (key_file, group, "band"),
            optional_string (key_file, group, "mode"),
            key_file.get_double (group, "frequency"),
            key_file.get_integer (group, "snr"),
            key_file.get_int64 (group, "timestamp-unix"),
            key_file.get_string (group, "source"),
            optional_string (key_file, group, "reporter"),
            optional_string (key_file, group, "dxcc"),
            optional_string (key_file, group, "country"),
            optional_string (key_file, group, "state"),
            optional_string (key_file, group, "raw-payload")
        );
    }

    private void write_report (KeyFile key_file, string group, SignalReport report) {
        key_file.set_string (group, "call", report.call);
        key_file.set_string (group, "grid", report.grid);
        set_optional_string (key_file, group, "band", report.band);
        set_optional_string (key_file, group, "mode", report.mode);
        key_file.set_double (group, "frequency", report.frequency);
        key_file.set_integer (group, "snr", report.snr);
        key_file.set_int64 (group, "timestamp-unix", report.timestamp_unix);
        key_file.set_string (group, "source", report.source);
        set_optional_string (key_file, group, "reporter", report.reporter);
        set_optional_string (key_file, group, "dxcc", report.dxcc);
        set_optional_string (key_file, group, "country", report.country);
        set_optional_string (key_file, group, "state", report.state);
        set_optional_string (key_file, group, "raw-payload", report.raw_payload);
    }

    private void remove_existing_report_groups (KeyFile key_file, string group) {
        try {
            var count = key_file.has_group (group) ? key_file.get_integer (group, "count") : 0;
            for (var i = 0; i < count; i++) {
                key_file.remove_group ("%s:%d".printf (group, i));
            }
            if (key_file.has_group (group))
                key_file.remove_group (group);
        } catch (Error err) {
            // The new cache entry below replaces any readable portion.
        }
    }

    private static string? optional_string (KeyFile key_file, string group, string key) {
        try {
            var value = key_file.get_string (group, key);
            return value == "" ? null : value;
        } catch (Error err) {
            return null;
        }
    }

    private static void set_optional_string (KeyFile key_file, string group, string key, string? value) {
        if (value != null)
            key_file.set_string (group, key, value);
    }

    private void ensure_cache_dir () {
        var cache_dir = Path.get_dirname (cache_path);
        if (DirUtils.create_with_parents (cache_dir, 0700) != 0) {
            warning ("Failed to create PSKReporter cache directory %s: %s",
                cache_dir, strerror (errno));
        }
    }

    private static string normalize_cache_key (string callsign) {
        return callsign.strip ().ascii_down ();
    }

    private static string cache_group (string callsign) {
        return "callsign:%s".printf (GLib.Uri.escape_string (callsign, null, false));
    }
}

public sealed class PskReporterClient : Object {
    public const string BASE_URL = "https://retrieve.pskreporter.info/query";
    private const string APP_CONTACT = "jay@k0vcz.com";
    public const int DEFAULT_FLOW_START_SECONDS = -3600;

    private Soup.Session session;
    private string base_url;

    public PskReporterClient (string base_url = BASE_URL) {
        Object ();
        this.base_url = base_url;
        session = new Soup.Session () {
            timeout = 30,
            user_agent = Build.USER_AGENT
        };
    }

    public async ArrayList<SignalReport> fetch_reception_reports (
        string callsign,
        int flow_start_seconds = DEFAULT_FLOW_START_SECONDS
    ) throws Error {
        var normalized_callsign = callsign.strip ().ascii_up ();
        if (normalized_callsign == "")
            throw new PskReporterClientError.INVALID_CALLSIGN ("Callsign is required");

        var message = new Soup.Message (
            "GET",
            build_query_url (normalized_callsign, flow_start_seconds)
        );
        message.request_headers.replace ("Accept", "application/xml,text/xml,*/*");
        message.request_headers.replace ("User-Agent", session.user_agent);

        var response = yield session.send_and_read_async (
            message,
            Priority.DEFAULT,
            null
        );

        if (message.status_code < 200 || message.status_code > 299) {
            throw new PskReporterClientError.HTTP_FAILED (
                "PSKReporter request failed: %u %s%s".printf (
                    message.status_code,
                    message.reason_phrase,
                    server_error_message (response)
                )
            );
        }

        var reports = parse_reception_reports (response);
        reports = filter_sender_callsign (reports, normalized_callsign);
        return reports;
    }

    public static ArrayList<SignalReport> parse_reception_reports (Bytes response) throws Error {
        var data = response.get_data ();
        var xml = ((string) data).make_valid ((ssize_t) data.length);
        var doc = Xml.Parser.read_memory (xml, xml.length, null, null, 0);
        if (doc == null)
            throw new PskReporterClientError.PARSE_FAILED ("PSKReporter returned invalid XML");

        var reports = new ArrayList<SignalReport> ();
        collect_reception_reports (doc->get_root_element (), reports);
        delete doc;

        return reports;
    }

    private string build_query_url (string callsign, int flow_start_seconds) {
        return "%s?appcontact=%s&senderCallsign=%s&flowStartSeconds=%d".printf (
            base_url,
            GLib.Uri.escape_string (APP_CONTACT, null, false),
            GLib.Uri.escape_string (callsign, null, false),
            flow_start_seconds
        );
    }

    private static ArrayList<SignalReport> filter_sender_callsign (
        ArrayList<SignalReport> reports,
        string callsign
    ) {
        var filtered = new ArrayList<SignalReport> ();
        foreach (var report in reports) {
            if ((report.reporter ?? "").ascii_up () == callsign)
                filtered.add (report);
        }

        return filtered;
    }

    private static void collect_reception_reports (
        Xml.Node* node,
        ArrayList<SignalReport> reports
    ) {
        for (var current = node; current != null; current = current->next) {
            if (current->type == Xml.ElementType.ELEMENT_NODE &&
                current->name == "receptionReport") {
                var report = report_from_xml_node (current);
                if (report != null)
                    reports.add (report);
            }

            if (current->children != null)
                collect_reception_reports (current->children, reports);
        }
    }

    private static SignalReport? report_from_xml_node (Xml.Node* node) {
        var receiver_callsign = prop (node, "receiverCallsign");
        var receiver_locator = prop (node, "receiverLocator");
        var sender_callsign = prop (node, "senderCallsign");
        var frequency = int_prop (node, "frequency");
        var flow_start_seconds = int64_prop (node, "flowStartSeconds");
        var mode = prop (node, "mode");
        var snr = int_prop (node, "sNR");

        if (receiver_callsign == null ||
            receiver_locator == null ||
            sender_callsign == null ||
            frequency == null ||
            flow_start_seconds == null ||
            mode == null ||
            snr == null) {
            return null;
        }

        try {
            var frequency_mhz = ((double) frequency) / 1000000.0;
            return new SignalReport.from_grid (
                receiver_callsign,
                receiver_locator,
                band_for_frequency_khz (((double) frequency) / 1000.0),
                mode,
                frequency_mhz,
                snr,
                flow_start_seconds,
                PskReporterDecoder.SOURCE,
                sender_callsign,
                prop (node, "receiverDXCCCode"),
                prop (node, "receiverDXCC"),
                null
            );
        } catch (Error err) {
            return null;
        }
    }

    private static string? prop (Xml.Node* node, string name) {
        var value = node->get_prop (name);
        if (value == null)
            return null;

        var stripped = value.strip ();
        return stripped == "" ? null : stripped;
    }

    private static int? int_prop (Xml.Node* node, string name) {
        var value = prop (node, name);
        if (value == null)
            return null;

        int parsed;
        if (!int.try_parse (value, out parsed))
            return null;

        return parsed;
    }

    private static int64? int64_prop (Xml.Node* node, string name) {
        var value = prop (node, name);
        if (value == null)
            return null;

        int64 parsed;
        if (!int64.try_parse (value, out parsed))
            return null;

        return parsed;
    }

    private static string server_error_message (Bytes response) {
        var data = response.get_data ();
        if (data.length == 0)
            return "";

        var message = ((string) data).make_valid ((ssize_t) data.length).strip ();
        return message == "" ? "" : ": %s".printf (message);
    }
}
