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

        private WsjtxListener? listener;
        private uint stale_timeout_id = 0;
        private string last_sender = "";
        private string last_instance_id = "";
        private uint32 last_schema = 0;
        private string last_error_message = "";
        private string last_highlighted_callsign = "";
        private string last_selected_tx_callsign = "";

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
            last_highlighted_callsign = "";
            last_selected_tx_callsign = "";
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
                    select_transmitting_spot_if_needed ();
                    break;
                case MessageType.DECODE:
                    var decode = packet.get_decode ();
                    highlight_active_spot_decode (decode);
                    decode_received (decode);
                    break;
                case MessageType.CLEAR:
                    dx_call = "";
                    last_selected_tx_callsign = "";
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

        private void highlight_active_spot_decode (DecodePacket decode) {
            var spot = Application.spot_repo.get_spot_for_decode_text (decode.text);
            if (spot == null)
                return;

            var callsign = spot.callsign.strip ().up ();
            if (callsign == "" || callsign == last_highlighted_callsign)
                return;

            try {
                var datagram = PacketWriter.build_highlight_callsign (
                    last_instance_id,
                    callsign
                );
                if (listener != null)
                    listener.send_to_last_sender (datagram);
                last_highlighted_callsign = callsign;
            } catch (Error err) {
                warning ("Unable to highlight %s in WSJT-X: %s", callsign, err.message);
            }
        }

        private void select_transmitting_spot_if_needed () {
            var callsign = dx_call.strip ().up ();
            if (!transmitting || callsign == "") {
                last_selected_tx_callsign = "";
                return;
            }

            if (callsign == last_selected_tx_callsign)
                return;

            var spot = Application.spot_repo.get_spot_for_callsign (callsign);
            if (spot == null)
                return;

            Application.state.current_spot_hash = spot.hash;
            last_selected_tx_callsign = callsign;
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
            public string mode;
            public double frequency_khz;
            public string rst_sent;
            public string rst_rcvd;
            public string comment;
            public DateTime? spot_time;
            public string dedupe_key;
        }

        private async void handle_logged_adif (LoggedAdifPacket packet) {
            ParsedLoggedAdif? parsed = parse_logged_adif (packet.adif);
            if (parsed == null)
                return;

            var active_spot = Application.spot_repo.get_spot_for_callsign (parsed.call);
            var park_ref = active_spot != null ? active_spot.park_ref : "";
            var mode = parsed.mode != "" ? parsed.mode : active_spot != null ? active_spot.mode : "";
            var frequency_khz = parsed.frequency_khz > 0.0 ?
                parsed.frequency_khz :
                active_spot != null ? active_spot.frequency_khz : 0.0;
            var dedupe_key = "%s|%s|%s".printf (
                parsed.dedupe_key,
                park_ref,
                mode
            );

            if (Application.logging_service.has_completed_logged_adif (dedupe_key))
                return;

            if ((mode == "") || (frequency_khz <= 0.0) ||
                (parsed.station_callsign == "") || (parsed.spot_time == null)) {
                warning ("Skipping WSJT-X logged QSO for %s: ADIF record missing required fields",
                    parsed.call);
                return;
            }

            var spot = new Spot.from_add_spot (
                parsed.call,
                park_ref,
                parsed.spot_time,
                "%.3f".printf (frequency_khz),
                mode,
                parsed.station_callsign,
                parsed.comment,
                parsed.rst_sent,
                parsed.rst_rcvd
            );

            try {
                var result = yield Application.logging_service.submit_spot_qso (
                    spot,
                    park_ref != ""
                );
                Application.logging_service.mark_logged_adif_completed (dedupe_key);
                if (result.pota_error != null)
                    Application.show_toast (_("WSJT-X QSO saved locally; POTA spot failed"));
                if (result.qrz_error != null)
                    Application.show_toast (_("WSJT-X QSO saved locally; QRZ upload failed"));
            } catch (Error err) {
                warning ("Unable to auto spot WSJT-X POTA contact %s: %s",
                    parsed.call,
                    err.message);
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

            var mode = map_record_value (record, "MODE").up ();
            var frequency_khz = parse_mhz_to_khz_or_zero (map_record_value (record, "FREQ"));
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
            parsed.mode = mode;
            parsed.frequency_khz = frequency_khz;
            parsed.rst_sent = map_record_value (record, "RST_SENT");
            parsed.rst_rcvd = map_record_value (record, "RST_RCVD");
            parsed.comment = comment;
            parsed.spot_time = Artemis.Adif.parse_qso_datetime_utc (qso_date, time_on);
            parsed.dedupe_key = "%s|%s|%s|%s".printf (
                call,
                "",
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
