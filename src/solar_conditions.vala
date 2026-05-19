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
using Json;

public sealed class SolarAlertEntry : GLib.Object {
    public string issue_time_text { get; set; default = ""; }
    public string summary { get; set; default = ""; }

    public SolarAlertEntry (
        string issue_time_text = "",
        string summary = ""
    ) {
        GLib.Object (
            issue_time_text: issue_time_text,
            summary: summary
        );
    }
}

public sealed class SolarConditionsModel : GLib.Object {
    public bool refreshing { get; set; default = false; }
    public DateTime? last_updated { get; set; default = null; }
    public string? error_message { get; set; default = null; }

    public ArrayList<SolarAlertEntry> alerts { get; private set; }

    public SolarConditionsModel () {
        GLib.Object ();
        alerts = new ArrayList<SolarAlertEntry> ();
    }

    public void copy_from (SolarConditionsModel src) {
        refreshing = src.refreshing;
        last_updated = src.last_updated;
        error_message = src.error_message;

        alerts.clear ();
        foreach (var alert in src.alerts) {
            alerts.add (new SolarAlertEntry (
                alert.issue_time_text,
                alert.summary
            ));
        }
    }
}

public sealed class SolarConditionsService : GLib.Object {
    private const string NOAA_ALERTS_URL = "https://services.swpc.noaa.gov/products/alerts.json";
    private const uint REFRESH_INTERVAL_SECONDS = 600;

    private Soup.Session session;
    private uint timer_id = 0;
    private bool refresh_in_progress = false;

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

        timer_id = Timeout.add_seconds (REFRESH_INTERVAL_SECONDS, () => {
            refresh.begin ();
            return true;
        });

        refresh.begin ();
    }

    ~SolarConditionsService () {
        if (timer_id != 0) {
            Source.remove (timer_id);
            timer_id = 0;
        }
    }

    private async string fetch_text (string url, string source_name) throws GLib.Error {
        var message = new Soup.Message ("GET", url);
        message.request_headers.replace ("Accept", "application/json, */*;q=0.1");
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
        if (normalized.has_suffix ("Z"))
            return new DateTime.from_iso8601 (normalized, new TimeZone.utc ());

        return new DateTime.from_iso8601 ("%sZ".printf (normalized), new TimeZone.utc ());
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

    private ArrayList<SolarAlertEntry> parse_noaa_alerts (string json_text) throws GLib.Error {
        var parser = new Json.Parser ();
        parser.load_from_data (json_text, (ssize_t) json_text.length);

        var root = parser.get_root ();
        if ((root == null) || (root.get_node_type () != Json.NodeType.ARRAY))
            throw new IOError.INVALID_DATA ("NOAA alerts feed was not a JSON array");

        var array = root.get_array ();
        var alerts = new ArrayList<SolarAlertEntry> ();
        var cutoff = new DateTime.now_utc ().add_seconds (-24 * 60 * 60);

        for (uint i = 0; i < array.get_length (); i++) {
            var item = array.get_object_element (i);
            if (item == null)
                continue;

            var issue_text = item.get_string_member_with_default ("issue_datetime", "");
            var message = item.get_string_member_with_default ("message", "").strip ();

            if ((issue_text.strip () == "") || (message == ""))
                continue;

            var issue_time = parse_iso_utc ("%sZ".printf (issue_text.strip ().replace (" ", "T")));
            if (issue_time.compare (cutoff) < 0)
                continue;

            alerts.add (new SolarAlertEntry (
                issue_time.format ("%Y-%m-%d %H:%M UTC"),
                alert_summary (message)
            ));
        }

        return alerts;
    }

    public async void refresh () {
        if (refresh_in_progress)
            return;

        refresh_in_progress = true;
        model.refreshing = true;
        model.error_message = null;
        updated ();

        var errors = new ArrayList<string> ();
        var snapshot = new SolarConditionsModel ();

        try {
            var alerts_text = yield fetch_text (NOAA_ALERTS_URL, "NOAA alerts");
            foreach (var alert in parse_noaa_alerts (alerts_text))
                snapshot.alerts.add (alert);
        } catch (GLib.Error e) {
            warning ("NOAA alerts refresh failed: %s", e.message);
            errors.add (e.message);
        }

        snapshot.last_updated = new DateTime.now_utc ();
        snapshot.refreshing = false;
        snapshot.error_message = errors.size > 0 ? string.joinv ("; ", errors.to_array ()) : null;

        model.copy_from (snapshot);
        updated ();
        refresh_in_progress = false;
    }
}
