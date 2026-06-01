/* src/wsjtx/wsjtx_listener.vala
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
    public sealed class WsjtxListener : Object {
        const int MAX_DATAGRAM_SIZE = 65536;

        private Socket? socket;
        private SocketAddress? last_remote_address = null;
        private PacketParser parser;

        private Cancellable? receive_cancellable;
        private Thread<void*>? receive_thread;
        private uint listener_generation = 0;

        public uint16 port { get; construct; }
        public string listen_ip { get; construct; }
        public string? multicast_group { get; construct; }

        public bool is_running { get; private set; default = false; }

        public signal void packet_received (Artemis.Wsjtx.Packet packet, string sender);
        public signal void receive_error (Error error);

        public WsjtxListener (
            uint16 port,
            string listen_ip,
            string? multicast_group = null
        ) {
            Object (
                port: port,
                listen_ip: listen_ip,
                multicast_group: multicast_group
            );
        }

        construct {
            parser = new PacketParser ();
        }

        protected override void dispose () {
            stop ();
            base.dispose ();
        }

        public void start () throws Error {
            if (is_running)
                return;

            var bind_ip = listen_ip.strip ();
            var multicast_ip = (multicast_group ?? "").strip ();

            InetAddress? configured_address = null;
            if (multicast_ip != "") {
                configured_address = new InetAddress.from_string (multicast_ip);
                if ((configured_address == null) || !configured_address.is_multicast) {
                    throw new IOError.INVALID_ARGUMENT (
                        "WSJT-X multicast address %s is not a valid multicast IP address".printf (
                            multicast_ip
                        )
                    );
                }
                bind_ip = configured_address.get_family () == SocketFamily.IPV6 ? "::" : "0.0.0.0";
            } else {
                configured_address = new InetAddress.from_string (bind_ip);
                if (configured_address == null) {
                    throw new IOError.INVALID_ARGUMENT (
                        "WSJT-X listen address %s is not a valid IP address".printf (bind_ip)
                    );
                }
            }

            var bind_address = new InetAddress.from_string (bind_ip);
            if (bind_address == null) {
                throw new IOError.INVALID_ARGUMENT (
                    "WSJT-X bind address %s is not a valid IP address".printf (bind_ip)
                );
            }

            socket = new Socket (
                bind_address.get_family (),
                SocketType.DATAGRAM,
                SocketProtocol.UDP
            );
            socket.set_blocking (false);
            socket.set_broadcast (true);

            var socket_address = new InetSocketAddress (bind_address, port);
            socket.bind (socket_address, true);

            if (configured_address.is_multicast) {
                socket.join_multicast_group (configured_address, false, null);
            }

            is_running = true;
            var generation = ++listener_generation;
            receive_cancellable = new Cancellable ();
            var receive_socket = socket;
            var cancellable = receive_cancellable;
            receive_thread = new Thread<void*> ("wsjtx-listener", () => {
                receive_loop (receive_socket, cancellable, generation);
                return null;
            });
        }

        public void stop () {
            if (!is_running && socket == null)
                return;

            listener_generation++;

            if (receive_cancellable != null) {
                receive_cancellable.cancel ();
                receive_cancellable = null;
            }

            if (socket != null) {
                try {
                    socket.close ();
                } catch (Error err) {
                    receive_error (err);
                }
                socket = null;
            }

            is_running = false;
            receive_thread = null;
        }

        private void receive_loop (
            Socket receive_socket,
            Cancellable cancellable,
            uint generation
        ) {
            while (!cancellable.is_cancelled ()) {
                try {
                    if (!receive_socket.condition_wait (IOCondition.IN, cancellable))
                        continue;

                    drain_ready_packets (receive_socket, cancellable, generation);
                } catch (Error err) {
                    if (err is IOError.CANCELLED || cancellable.is_cancelled ())
                        break;

                    dispatch_error (err, generation);
                    break;
                }
            }
        }

        private void drain_ready_packets (
            Socket receive_socket,
            Cancellable cancellable,
            uint generation
        ) throws Error {
            while (!cancellable.is_cancelled ()) {
                uint8[] buffer = new uint8[MAX_DATAGRAM_SIZE];
                SocketAddress remote_address;

                try {
                    var received = receive_socket.receive_from (
                        out remote_address,
                        buffer,
                        cancellable
                    );
                    if (received <= 0)
                        break;

                    var sender = format_sender (remote_address);
                    var datagram = buffer[0: (int)received];

                    try {
                        var packet = parser.parse (datagram);
                        dispatch_packet (packet, remote_address, sender, generation);
                    } catch (PacketError err) {
                        dispatch_error (err, generation);
                    }
                } catch (Error err) {
                    if (err is IOError.WOULD_BLOCK)
                        break;

                    throw err;
                }
            }
        }

        private void dispatch_packet (
            Artemis.Wsjtx.Packet packet,
            SocketAddress remote_address,
            string sender,
            uint generation
        ) {
            MainContext.default ().invoke (() => {
                if (!is_running || generation != listener_generation)
                    return Source.REMOVE;

                last_remote_address = remote_address;
                packet_received (packet, sender);
                return Source.REMOVE;
            });
        }

        private void dispatch_error (Error err, uint generation) {
            MainContext.default ().invoke (() => {
                if (!is_running || generation != listener_generation)
                    return Source.REMOVE;

                receive_error (err);
                return Source.REMOVE;
            });
        }

        public void send_to_last_sender (uint8[] datagram) throws Error {
            if (socket == null || last_remote_address == null)
                return;

            socket.send_to (last_remote_address, datagram, null);
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
    }
}
