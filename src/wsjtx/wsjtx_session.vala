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
        private LoggedAdifHandler logged_adif_handler;

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

        public signal void status_changed ();
        public signal void decode_received (DecodePacket packet);
        public signal void logged_adif_received (LoggedAdifPacket packet);
        public signal void receive_error (Error error);

        public WsjtxSession () {
            Object ();
        }

        construct {
            logged_adif_handler = new LoggedAdifHandler (
                Application.logging_service,
                Application.spot_repo,
                new SettingsLoggingPreferences (Application.settings)
            );
            logged_adif_handler.user_message.connect ((message) => {
                Application.show_toast (message);
            });
            Application.settings.changed["enable-wsjtx-integration"].connect (restart_listener);
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

            if (!Application.settings.get_boolean ("enable-wsjtx-integration")) {
                set_status (
                    false,
                    false,
                    _("Inactive"),
                    _("WSJT-X integration disabled")
                );
                return;
            }

            var ip_text = Application.settings.get_string ("wsjtx-listen-ip").strip ();
            var port = Application.settings.get_int ("wsjtx-listen-port");

            if (ip_text == "") {
                set_status (
                    false,
                    false,
                    _("Inactive"),
                    _("Not listening: enter a valid listen IP.")
                );
                return;
            }

            var configured_address = new InetAddress.from_string (ip_text);
            if (configured_address == null) {
                set_status (
                    false,
                    false,
                    _("Listener error"),
                    _("Unable to listen: the listen IP is not a valid IP address.")
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
                    _("Receive error: %s".printf (err.message))
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
                    _("Waiting for packets")
                );
            } catch (Error err) {
                last_error_message = err.message;
                receive_error (err);
                set_status (
                    false,
                    false,
                    _("Listener error"),
                    _("Unable to listen: %s".printf (err.message))
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
                    _("Waiting for packets")
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
                    handle_decode (decode);
                    decode_received (decode);
                    break;
                case MessageType.CLEAR:
                    dx_call = "";
                    last_selected_tx_callsign = "";
                    break;
                case MessageType.LOGGED_ADIF:
                    var logged_adif = packet.get_logged_adif ();
                    logged_adif_received (logged_adif);
                    logged_adif_handler.handle.begin (logged_adif);
                    break;
                default:
                    break;
            }

            set_status (
                true,
                true,
                _("Connected"),
                connected_subtitle ()
            );
        }

        private string connected_subtitle () {
            var version_text = version_display ();
            if (version_text != "") {
                return _("Connected to WSJT-X v%s").printf (version_text);
            }

            return _("Connected to WSJT-X");
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

        private void handle_decode (DecodePacket decode) {
            var spot = Application.spot_repo.get_spot_for_decode_text (decode.text);
            if (spot == null)
                return;

            spot.mark_heard_recently ();
            highlight_spot_callsign (spot);
        }

        private void highlight_spot_callsign (Spot spot) {
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

        private void set_status (
            bool listening,
            bool connected,
            string label,
            string subtitle
        ) {
            this.listening = listening;
            this.connected = connected;
            status_label = label;
            status_subtitle = subtitle;
            status_changed ();
        }
    }
}
