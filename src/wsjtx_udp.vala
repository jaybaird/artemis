/* src/wsjtx_udp.vala
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

namespace Artemis.Wsjtx {
    public sealed class UdpService : GLib.Object {
        private const uint32 WSJTX_MAGIC = (uint32) 0xadbccbdaU;
        private const uint PACKET_STALE_SECONDS = 30;

        private Socket? socket;
        private Source? socket_source;
        private uint stale_timeout_id = 0;
        private string last_sender = "";
        private string last_instance_id = "";

        public bool is_listening { get; private set; default = false; }
        public bool is_connected { get; private set; default = false; }
        public string status_label { get; private set; default = ""; }
        public string status_subtitle { get; private set; default = ""; }
        public string status_detail { get; private set; default = ""; }

        public signal void status_changed ();

        public UdpService () {
            GLib.Object ();
        }

        construct {
            Application.settings.changed["wsjtx-listen-ip"].connect (restart_listener);
            Application.settings.changed["wsjtx-listen-port"].connect (restart_listener);

            restart_listener ();
        }

        private void restart_listener () {
            stop_listener ();

            var ip_text = Application.settings.get_string ("wsjtx-listen-ip").strip ();
            var port = Application.settings.get_int ("wsjtx-listen-port");
            if (ip_text == "") {
                set_status (false, false, _("Inactive"), _("Not listening"),
                    _("Enter a listen IP to enable the WSJT-X UDP listener."));
                return;
            }

            InetAddress? configured_address = new InetAddress.from_string (ip_text);
            if (configured_address == null) {
                set_status (false, false, _("Listener error"), _("Unable to listen"),
                    _("The configured WSJT-X listen IP is not a valid IP address."));
                return;
            }

            try {
                socket = new Socket (configured_address.get_family (),
                    SocketType.DATAGRAM,
                    SocketProtocol.UDP);
                socket.set_blocking (false);
                socket.set_broadcast (true);

                InetAddress bind_address = configured_address;
                if (configured_address.is_multicast) {
                    bind_address = new InetAddress.any (configured_address.get_family ());
                }

                var socket_address = new InetSocketAddress (bind_address, (uint16) port);
                socket.bind (socket_address, true);

                if (configured_address.is_multicast) {
                    socket.join_multicast_group (configured_address, false, null);
                }

                socket_source = socket.create_source (IOCondition.IN, null);
                socket_source.set_callback (() => {
                    receive_pending_packets ();
                    return Source.CONTINUE;
                });
                socket_source.attach (null);

                var detail = configured_address.is_multicast ?
                    _("Joined multicast group %s on UDP port %d.").printf (ip_text, port) :
                    _("Listening for WSJT-X UDP packets on %s:%d.").printf (ip_text, port);
                set_status (true, false, _("Listening"), _("Waiting for packets"), detail);
            } catch (GLib.Error e) {
                warning ("Unable to start WSJT-X UDP listener: %s", e.message);
                stop_listener ();
                set_status (false, false, _("Listener error"), _("Unable to listen"), e.message);
            }
        }

        private void stop_listener () {
            if (socket_source != null) {
                socket_source.destroy ();
                socket_source = null;
            }

            if (stale_timeout_id != 0) {
                Source.remove (stale_timeout_id);
                stale_timeout_id = 0;
            }

            if (socket != null) {
                try {
                    socket.close ();
                } catch (GLib.Error e) {
                    warning ("Unable to close WSJT-X UDP socket: %s", e.message);
                }
                socket = null;
            }

            last_sender = "";
            last_instance_id = "";
            is_listening = false;
            is_connected = false;
        }

        private void receive_pending_packets () {
            if (socket == null)
                return;

            while (true) {
                uint8[] buffer = new uint8[4096];
                SocketAddress? remote_address = null;

                try {
                    var received = socket.receive_from (out remote_address, buffer, null);
                    if (received <= 0)
                        break;

                    int packet_length = (int) received;
                    if (!handle_packet (buffer[0:packet_length], remote_address))
                        continue;
                } catch (GLib.Error e) {
                    if (!(e is IOError.WOULD_BLOCK)) {
                        warning ("WSJT-X UDP receive failed: %s", e.message);
                        set_status (is_listening, false, _("Listener error"),
                            _("Receive error"), e.message);
                    }
                    break;
                }
            }
        }

        private bool handle_packet (uint8[] packet, SocketAddress? remote_address) {
            try {
                var reader = new Artemis.Wsjtx.PacketReader (packet);
                var magic = reader.read_u32 ();
                if (magic != WSJTX_MAGIC)
                    return false;

                var schema = reader.read_u32 ();
                var message_type = (Artemis.Wsjtx.MessageType) reader.read_u32 ();
                var instance_id = reader.read_utf8 ();

                last_sender = format_sender (remote_address);
                last_instance_id = instance_id;
                note_packet_received (schema, message_type);
                return true;
            } catch (GLib.Error e) {
                warning ("Unable to parse WSJT-X packet: %s", e.message);
                return false;
            }
        }

        private void note_packet_received (uint32 schema, Artemis.Wsjtx.MessageType message_type) {
            if (stale_timeout_id != 0) {
                Source.remove (stale_timeout_id);
                stale_timeout_id = 0;
            }

            stale_timeout_id = Timeout.add_seconds (PACKET_STALE_SECONDS, () => {
                stale_timeout_id = 0;
                if (is_listening) {
                    var detail = _("Listening on %s. Last packet source: %s").printf (
                        current_endpoint_description (),
                        last_sender != "" ? last_sender : _("Unknown"));
                    set_status (true, false, _("Listening"), _("Waiting for packets"), detail);
                }
                return Source.REMOVE;
            });

            var source_text = last_instance_id != "" ?
                _("%s from %s").printf (last_instance_id, last_sender) :
                last_sender;
            var detail = _("Schema %u, message type %u. Last packet source: %s").printf (
                schema,
                (uint32) message_type,
                source_text != "" ? source_text : _("Unknown"));
            set_status (true, true, _("Connected"), _("Receiving packets"), detail);
        }

        private string current_endpoint_description () {
            var ip_text = Application.settings.get_string ("wsjtx-listen-ip").strip ();
            var port = Application.settings.get_int ("wsjtx-listen-port");
            return "%s:%d".printf (ip_text, port);
        }

        private string format_sender (SocketAddress? address) {
            var inet_address = address as InetSocketAddress;
            if (inet_address == null)
                return _("Unknown");

            return "%s:%u".printf (
                inet_address.address.to_string (),
                inet_address.port
            );
        }

        private void set_status (
            bool listening,
            bool connected,
            string label,
            string subtitle,
            string detail
        ) {
            is_listening = listening;
            is_connected = connected;
            status_label = label;
            status_subtitle = subtitle;
            status_detail = detail;
            status_changed ();
        }
    }
}
