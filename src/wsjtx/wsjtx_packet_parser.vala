/* src/wsjtx/wsjtx_packet_parser.vala
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
    [Compact (opaque = true)]
    public class PacketParser {
        public Packet parse (uint8[] datagram) throws Error {
            var reader = new PacketReader (datagram);
            var header = parse_header (reader);
            var raw_type = (uint32) header.type;

            switch (raw_type) {
                case MessageType.HEARTBEAT:
                    return new Packet.heartbeat (parse_heartbeat (header, reader));
                case MessageType.STATUS:
                    return new Packet.status (parse_status (header, reader));
                case MessageType.DECODE:
                    return new Packet.decode (parse_decode (header, reader));
                case MessageType.CLEAR:
                    return new Packet.clear (parse_clear (header, reader));
                case MessageType.LOGGED_ADIF:
                    return new Packet.logged_adif (parse_logged_adif (header, reader));
                default:
                    return new Packet.unknown (parse_unknown (header, raw_type, reader));
            }
        }

        private Header parse_header (PacketReader reader) throws Error {
            var magic = reader.read_u32 ();
            if (magic != MAGIC) {
                throw new PacketError.BAD_MAGIC (
                    "WSJT-X packet magic %#x did not match %#x".printf (magic, MAGIC)
                );
            }

            var schema = reader.read_u32 ();
            if (schema > MAX_SCHEMA) {
                throw new PacketError.UNSUPPORTED_SCHEMA (
                    "WSJT-X schema %u is newer than supported schema %u".printf (
                        schema,
                        MAX_SCHEMA
                    )
                );
            }

            uint32 raw_type = reader.read_u32 ();
            string id = reader.read_utf8 ();

            Header header = {};
            header.schema = schema;
            header.type = (MessageType) raw_type;
            header.id = id;
            return header;
        }

        private HeartbeatPacket parse_heartbeat (Header header, PacketReader reader) throws Error {
            var payload = reader.read_remaining ();

            if (header.schema >= 3) {
                return parse_heartbeat_payload (header, payload, true);
            }

            // Some real-world schema 2 peers still include the max-schema field
            // before version/revision. Accept both layouts.
            if (payload.length >= 4) {
                uint32 first_field = read_be_u32 (payload, 0);
                if (first_field <= MAX_SCHEMA) {
                    try {
                        return parse_heartbeat_payload (header, payload, true);
                    } catch (Error err) {
                        // Fall back to the older schema 2 layout with no max-schema field.
                    }
                }
            }

            return parse_heartbeat_payload (header, payload, false);
        }

        private StatusPacket parse_status (Header header, PacketReader reader) throws Error {
            StatusPacket packet = {};
            packet.header = header;
            packet.dial_frequency_hz = reader.read_u64 ();
            packet.mode = reader.read_utf8 ();
            packet.dx_call = reader.read_utf8 ();
            packet.report = reader.read_utf8 ();
            packet.tx_mode = reader.read_utf8 ();
            packet.tx_enabled = reader.read_bool ();
            packet.transmitting = reader.read_bool ();
            packet.decoding = reader.read_bool ();
            packet.rx_df = reader.read_u32 ();
            packet.tx_df = reader.read_u32 ();
            packet.de_call = reader.read_utf8 ();
            packet.de_grid = reader.read_utf8 ();
            packet.dx_grid = reader.read_utf8 ();
            packet.tx_watchdog = reader.read_bool ();

            // NetworkMessage.hpp specifies that new fields are only appended at the
            // end of an existing message and receivers must tolerate shorter older
            // variants as well as longer newer variants.
            packet.sub_mode = read_appended_utf8 (reader, "");
            packet.fast_mode = read_appended_bool (reader, false);
            packet.special_operation_mode = read_appended_u8 (reader, 0);
            packet.frequency_tolerance = read_appended_u32 (reader, 0U);
            packet.tr_period = read_appended_u32 (reader, 0U);
            packet.configuration_name = read_appended_utf8 (reader, "");
            packet.tx_message = read_appended_utf8 (reader, "");
            return packet;
        }

        private DecodePacket parse_decode (Header header, PacketReader reader) throws Error {
            DecodePacket packet = {};
            packet.header = header;
            packet.is_new = reader.read_bool ();
            packet.time = reader.read_qtime ();
            packet.snr = reader.read_i32 ();
            packet.delta_time = reader.read_double ();
            packet.delta_frequency_hz = reader.read_u32 ();
            packet.mode = reader.read_utf8 ();
            packet.text = reader.read_utf8 ();
            packet.low_confidence = read_appended_bool (reader, false);
            packet.off_air = read_appended_bool (reader, false);
            return packet;
        }

        private ClearPacket parse_clear (Header header, PacketReader reader) throws Error {
            ClearPacket packet = {};
            packet.header = header;
            packet.has_window = false;
            packet.window = 0;

            if (reader.has_remaining ()) {
                packet.window = reader.read_u8 ();
                packet.has_window = true;
            }

            return packet;
        }

        private LoggedAdifPacket parse_logged_adif (Header header, PacketReader reader) throws Error {
            LoggedAdifPacket packet = {};
            packet.header = header;
            packet.adif = reader.read_utf8 ();
            return packet;
        }

        private UnknownPacket parse_unknown (
            Header header,
            uint32 raw_type,
            PacketReader reader
        ) throws Error {
            UnknownPacket packet = {};
            packet.header = header;
            packet.raw_type = raw_type;
            packet.payload = reader.read_remaining ();
            return packet;
        }

        private HeartbeatPacket parse_heartbeat_payload (
            Header header,
            uint8[] payload,
            bool include_max_schema
        ) throws Error {
            var payload_reader = new PacketReader (payload);
            HeartbeatPacket packet = {};
            packet.header = header;
            packet.max_schema = include_max_schema && payload_reader.has_remaining () ?
                payload_reader.read_u32 () :
                (uint32) 2U;
            packet.version = payload_reader.has_remaining () ? payload_reader.read_utf8 () : "";
            packet.revision = payload_reader.has_remaining () ? payload_reader.read_utf8 () : "";
            return packet;
        }

        private uint32 read_be_u32 (uint8[] data, int offset) {
            return ((uint32) data[offset] << 24) |
                ((uint32) data[offset + 1] << 16) |
                ((uint32) data[offset + 2] << 8) |
                (uint32) data[offset + 3];
        }

        private bool read_appended_bool (PacketReader reader, bool fallback) throws Error {
            if (!reader.has_remaining ())
                return fallback;

            return reader.read_bool ();
        }

        private uint8 read_appended_u8 (PacketReader reader, uint8 fallback) throws Error {
            if (!reader.has_remaining ())
                return fallback;

            return reader.read_u8 ();
        }

        private uint32 read_appended_u32 (PacketReader reader, uint32 fallback) throws Error {
            if (!reader.has_remaining ())
                return fallback;

            return reader.read_u32 ();
        }

        private string read_appended_utf8 (PacketReader reader, string fallback) throws Error {
            if (!reader.has_remaining ())
                return fallback;

            return reader.read_utf8 ();
        }
    }
}
