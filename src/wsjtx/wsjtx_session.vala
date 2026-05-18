/* src/wsjtx/wsjtx_session.vala
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

namespace Artemis.Wsjtx {
    public sealed class WsjtxSession : Object {
        private const uint PACKET_STALE_SECONDS = 30;
        private const int64 CQ_POTA_TRACK_WINDOW_USEC = 30 * GLib.TimeSpan.MINUTE;

        private WsjtxListener? listener;
        private uint stale_timeout_id = 0;
        private string last_sender = "";
        private string last_instance_id = "";
        private uint32 last_schema = 0;
        private string last_error_message = "";
        private HashMap<string, int64?> recent_cq_pota_calls = new HashMap<string, int64?> ();
        private HashSet<string> processed_logged_adif_keys = new HashSet<string> ();

        public bool listening { get; private set; default = false; }
        public bool connected { get; private set; default = false; }
        public uint64 dial_frequency_hz { get; private set; default = 0; }
        public string mode { get; private set; default = ""; }
        public string dx_call { get; private set; default = ""; }
        public bool transmitting { get; private set; default = false; }
        public bool decoding { get; private set; default = false; }
        public string client_id { get; private set; default = ""; }
        public string client_version { get; private set; default = ""; }
        public string client_revision { get; private set; default = ""; }
        public string status_label { get; private set; default = ""; }
        public string status_subtitle { get; private set; default = ""; }
        public string status_detail { get; private set; default = ""; }

        public signal void status_changed ();
        public signal void decode_received (DecodePacket packet);
        public signal void logged_adif_received (LoggedAdifPacket packet);
        public signal void receive_error (Error error);

        public WsjtxSession () {
            Object ();
        }

        construct {
            Application.settings.changed["wsjtx-listen-ip"].connect (restart_listener);
            Application.settings.changed["wsjtx-listen-port"].connect (restart_listener);
            restart_listener ();
        }

        protected override void dispose () {
            stop_listener ();
            base.dispose ();
        }

        private void restart_listener () {
            stop_listener ();

            var ip_text = Application.settings.get_string ("wsjtx-listen-ip").strip ();
            var port = Application.settings.get_int ("wsjtx-listen-port");

            if (ip_text == "") {
                set_status (
                    false,
                    false,
                    _("Inactive"),
                    _("Not listening"),
                    _("Enter a listen IP to enable the WSJT-X UDP listener.")
                );
                return;
            }

            var configured_address = new InetAddress.from_string (ip_text);
            if (configured_address == null) {
                set_status (
                    false,
                    false,
                    _("Listener error"),
                    _("Unable to listen"),
                    _("The configured WSJT-X listen IP is not a valid IP address.")
                );
                return;
            }

            string bind_ip = ip_text;
            string? multicast_group = null;
            if (configured_address.is_multicast) {
                multicast_group = ip_text;
                bind_ip = configured_address.get_family () == SocketFamily.IPV6 ? "::" : "0.0.0.0";
            }

            listener = new WsjtxListener ((uint16) port, bind_ip, multicast_group);
            listener.packet_received.connect (on_packet_received);
            listener.receive_error.connect ((err) => {
                last_error_message = err.message;
                receive_error (err);
                set_status (
                    listening,
                    false,
                    _("Listener error"),
                    _("Receive error"),
                    err.message
                );
            });

            try {
                listener.start ();
                listening = true;
                connected = false;
                set_status (
                    true,
                    false,
                    _("Listening"),
                    _("Waiting for packets"),
                    listener_detail (configured_address.is_multicast, ip_text, port)
                );
            } catch (Error err) {
                last_error_message = err.message;
                receive_error (err);
                set_status (
                    false,
                    false,
                    _("Listener error"),
                    _("Unable to listen"),
                    err.message
                );
            }
        }

        private void stop_listener () {
            if (stale_timeout_id != 0) {
                Source.remove (stale_timeout_id);
                stale_timeout_id = 0;
            }

            if (listener != null) {
                listener.stop ();
                listener = null;
            }

            listening = false;
            connected = false;
            last_sender = "";
            last_instance_id = "";
            last_error_message = "";
        }

        private void on_packet_received (Artemis.Wsjtx.Packet packet, string sender) {
            last_sender = sender;
            last_instance_id = packet.header.id;
            last_schema = packet.header.schema;
            client_id = packet.header.id;
            listening = true;
            connected = true;
            last_error_message = "";

            if (stale_timeout_id != 0) {
                Source.remove (stale_timeout_id);
                stale_timeout_id = 0;
            }

            stale_timeout_id = Timeout.add_seconds (PACKET_STALE_SECONDS, () => {
                stale_timeout_id = 0;
                connected = false;
                set_status (
                    listening,
                    false,
                    _("Listening"),
                    _("Waiting for packets"),
                    last_packet_detail ()
                );
                return Source.REMOVE;
            });

            switch (packet.type) {
                case MessageType.HEARTBEAT:
                    var heartbeat = packet.get_heartbeat ();
                    client_version = heartbeat.version;
                    client_revision = heartbeat.revision;
                    break;
                case MessageType.STATUS:
                    var status = packet.get_status ();
                    dial_frequency_hz = status.dial_frequency_hz;
                    mode = status.mode;
                    dx_call = status.dx_call;
                    transmitting = status.transmitting;
                    decoding = status.decoding;
                    break;
                case MessageType.DECODE:
                    var decode = packet.get_decode ();
                    remember_cq_pota_decode (decode);
                    decode_received (decode);
                    break;
                case MessageType.LOGGED_ADIF:
                    var logged_adif = packet.get_logged_adif ();
                    logged_adif_received (logged_adif);
                    handle_logged_adif.begin (logged_adif);
                    break;
                default:
                    break;
            }

            set_status (
                true,
                true,
                _("Connected"),
                connected_subtitle (),
                connected_detail ()
            );
        }

        private string connected_subtitle () {
            var version_text = version_display ();
            if (version_text != "") {
                return _("Connected to WSJT-X v%s").printf (version_text);
            }

            return _("Connected to WSJT-X");
        }

        private string connected_detail () {
            return "";
        }

        private string last_packet_detail () {
            var source_text = last_sender != "" ? last_sender : _("Unknown");
            var version_text = version_display ();
            if (version_text != "") {
                return _("Listening on %s. Last heartbeat: %s from %s.").printf (
                    endpoint_description (),
                    version_text,
                    source_text
                );
            }

            return _("Listening on %s. Last packet source: %s.").printf (
                endpoint_description (),
                source_text
            );
        }

        private string version_display () {
            var version = client_version.strip ();
            var revision = client_revision.strip ();

            if ((version == "") && (revision == ""))
                return "";
            if (revision == "")
                return version;
            if (version == "")
                return revision;

            return "%s (%s)".printf (version, revision);
        }

        private string endpoint_description () {
            var ip_text = Application.settings.get_string ("wsjtx-listen-ip").strip ();
            var port = Application.settings.get_int ("wsjtx-listen-port");
            return "%s:%d".printf (ip_text, port);
        }

        private string listener_detail (bool multicast, string ip_text, int port) {
            if (multicast) {
                return _("Joined multicast group %s on UDP port %d.").printf (
                    ip_text,
                    port
                );
            }

            return _("Listening for WSJT-X UDP packets on %s:%d.").printf (
                ip_text,
                port
            );
        }

        private struct ParsedLoggedAdif {
            public string call;
            public string station_callsign;
            public string park_ref;
            public string mode;
            public double frequency_khz;
            public string rst_sent;
            public string rst_rcvd;
            public string comment;
            public DateTime? spot_time;
            public string dedupe_key;
        }

        private void remember_cq_pota_decode (DecodePacket decode) {
            prune_recent_cq_pota_calls ();

            var callsign = parse_cq_pota_callsign (decode.text);
            if (callsign == null)
                return;

            recent_cq_pota_calls.set (callsign, GLib.get_monotonic_time ());
        }

        private void prune_recent_cq_pota_calls () {
            var cutoff = GLib.get_monotonic_time () - CQ_POTA_TRACK_WINDOW_USEC;
            var expired = new HashSet<string> ();

            foreach (var entry in recent_cq_pota_calls.entries) {
                if (entry.value < cutoff)
                    expired.add (entry.key);
            }

            foreach (var key in expired)
                recent_cq_pota_calls.unset (key);
        }

        private string? parse_cq_pota_callsign (string decode_text) {
            try {
                MatchInfo match_info;
                string[] patterns = {
                    "^\\s*CQ\\s+POTA\\s+([A-Z0-9/]+)\\b",
                    "^\\s*CQ\\s+([A-Z0-9/]+)\\s+POTA\\b"
                };

                foreach (var pattern in patterns) {
                    var regex = new Regex (pattern, RegexCompileFlags.CASELESS);
                    if (regex.match (decode_text.strip (), 0, out match_info)) {
                        var match = match_info.fetch (1);
                        if ((match != null) && (match.strip () != ""))
                            return match.strip ().up ();
                    }
                }
            } catch (RegexError err) {
                warning ("Unable to parse CQ POTA decode: %s", err.message);
            }

            return null;
        }

        private async void handle_logged_adif (LoggedAdifPacket packet) {
            ParsedLoggedAdif? parsed = parse_logged_adif (packet.adif);
            if (parsed == null)
                return;

            prune_recent_cq_pota_calls ();
            if (!recent_cq_pota_calls.has_key (parsed.call.up ()))
                return;

            if (processed_logged_adif_keys.contains (parsed.dedupe_key))
                return;

            processed_logged_adif_keys.add (parsed.dedupe_key);

            if ((parsed.park_ref == "") || (parsed.mode == "") || (parsed.frequency_khz <= 0.0) ||
                (parsed.station_callsign == "") || (parsed.spot_time == null)) {
                warning ("Skipping WSJT-X auto spot for %s: ADIF record missing required POTA fields",
                    parsed.call);
                return;
            }

            var spot = new Spot.from_add_spot (
                parsed.call,
                parsed.park_ref,
                parsed.spot_time,
                "%.3f".printf (parsed.frequency_khz),
                parsed.mode,
                parsed.station_callsign,
                parsed.comment,
                parsed.rst_sent,
                parsed.rst_rcvd
            );

            try {
                yield Application.pota_client.post_spot (spot);

                Error? db_error = null;
                Application.spot_database.add_qso_from_spot (spot, out db_error);
                if (db_error != null) {
                    warning ("Unable to save WSJT-X auto-spotted QSO: %s", db_error.message);
                }

                bool enable_logging = Application.settings.get_boolean ("enable-logging");
                string qrz_api_key = Application.settings.get_string ("qrz-api-key").strip ();
                if (enable_logging && (qrz_api_key != "")) {
                    try {
                        yield Application.qrz_client.upload_adif_record (packet.adif);
                    } catch (Error err) {
                        warning ("Unable to upload WSJT-X ADIF to QRZ: %s", err.message);
                    }
                }
            } catch (Error err) {
                warning ("Unable to auto spot CQ POTA contact %s: %s", parsed.call, err.message);
            }
        }

        private ParsedLoggedAdif? parse_logged_adif (string adif_text) {
            string normalized = adif_text.strip ();
            if (normalized == "")
                return null;

            if (!normalized.down ().contains ("<eor>"))
                normalized += "<eor>";

            Artemis.Adif.Document document;
            try {
                document = Artemis.Adif.Parser.from_string (normalized);
            } catch (Artemis.Adif.Error error) {
                warning ("Unable to parse WSJT-X logged ADIF: %s", error.message);
                return null;
            }

            if (document.records.size == 0)
                return null;

            Artemis.Adif.Record record = document.records[0];

            var call = map_record_value (record, "CALL").up ();
            if (call == "")
                return null;

            var sig = map_record_value (record, "SIG").up ();
            var park_ref = first_non_empty (
                map_record_value (record, "POTAREF"),
                map_record_value (record, "SIG_INFO")
            ).up ();
            if ((sig != "") && (sig != "POTA"))
                park_ref = "";

            var mode = map_record_value (record, "MODE").up ();
            var frequency_khz = parse_frequency_khz (map_record_value (record, "FREQ"));
            var station_callsign = first_non_empty (
                map_record_value (record, "STATION_CALLSIGN"),
                Application.settings.get_string ("callsign").strip ()
            ).up ();
            var comment = first_non_empty (
                map_record_value (record, "COMMENT"),
                map_record_value (record, "NOTES"),
                Application.settings.get_string ("spot-message").strip ()
            );
            var qso_date = map_record_value (record, "QSO_DATE");
            var time_on = first_non_empty (
                map_record_value (record, "TIME_ON"),
                map_record_value (record, "TIME_OFF")
            );

            ParsedLoggedAdif parsed = {};
            parsed.call = call;
            parsed.station_callsign = station_callsign;
            parsed.park_ref = park_ref;
            parsed.mode = mode;
            parsed.frequency_khz = frequency_khz;
            parsed.rst_sent = map_record_value (record, "RST_SENT");
            parsed.rst_rcvd = map_record_value (record, "RST_RCVD");
            parsed.comment = comment;
            parsed.spot_time = parse_adif_datetime (qso_date, time_on);
            parsed.dedupe_key = "%s|%s|%s|%s".printf (
                call,
                park_ref,
                qso_date,
                time_on
            );

            return parsed;
        }

        private string map_record_value (Artemis.Adif.Record record, string key) {
            var value = record.get (key);
            return value != null ? value.strip () : "";
        }

        private string first_non_empty (string first, string second = "", string third = "") {
            if (first.strip () != "")
                return first.strip ();
            if (second.strip () != "")
                return second.strip ();
            return third.strip ();
        }

        private double parse_frequency_khz (string mhz_text) {
            if (mhz_text.strip () == "")
                return 0.0;

            double mhz = 0.0;
            unowned string unparsed;
            if (!double.try_parse (mhz_text.strip (), out mhz, out unparsed) || (unparsed != ""))
                return 0.0;

            return mhz * 1000.0;
        }

        private DateTime? parse_adif_datetime (string qso_date, string time_on) {
            if ((qso_date.length != 8) || (time_on.length < 4))
                return null;

            int year;
            int month;
            int day;
            int hour;
            int minute;
            int second = 0;
            unowned string unparsed;

            if (!int.try_parse (qso_date.substring (0, 4), out year, out unparsed) || (unparsed != ""))
                return null;
            if (!int.try_parse (qso_date.substring (4, 2), out month, out unparsed) || (unparsed != ""))
                return null;
            if (!int.try_parse (qso_date.substring (6, 2), out day, out unparsed) || (unparsed != ""))
                return null;
            if (!int.try_parse (time_on.substring (0, 2), out hour, out unparsed) || (unparsed != ""))
                return null;
            if (!int.try_parse (time_on.substring (2, 2), out minute, out unparsed) || (unparsed != ""))
                return null;
            if ((time_on.length >= 6) &&
                (!int.try_parse (time_on.substring (4, 2), out second, out unparsed) || (unparsed != ""))) {
                return null;
            }

            return new DateTime.utc (year, month, day, hour, minute, (double) second);
        }

        private void set_status (
            bool listening,
            bool connected,
            string label,
            string subtitle,
            string detail
        ) {
            this.listening = listening;
            this.connected = connected;
            status_label = label;
            status_subtitle = subtitle;
            status_detail = detail;
            status_changed ();
        }
    }
}
