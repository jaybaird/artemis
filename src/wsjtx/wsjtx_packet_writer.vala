/* src/wsjtx/wsjtx_packet_writer.vala
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
    public sealed class PacketWriter : Object {
        private MemoryOutputStream memory;
        private DataOutputStream output;

        public PacketWriter () {
            memory = new MemoryOutputStream.resizable ();
            output = new DataOutputStream (memory);
            output.byte_order = DataStreamByteOrder.BIG_ENDIAN;
            output.set_close_base_stream (true);
        }

        public void write_u8 (uint8 value) throws Error {
            output.put_byte (value);
        }

        public void write_i8 (int8 value) throws Error {
            output.put_byte ((uint8) value);
        }

        public void write_u16 (uint16 value) throws Error {
            output.put_uint16 (value);
        }

        public void write_bool (bool value) throws Error {
            write_u8 (value ? (uint8) 1 : (uint8) 0);
        }

        public void write_u32 (uint32 value) throws Error {
            output.put_uint32 (value);
        }

        public void write_i32 (int32 value) throws Error {
            output.put_int32 (value);
        }

        public void write_u64 (uint64 value) throws Error {
            output.put_uint64 (value);
        }

        public void write_i64 (int64 value) throws Error {
            output.put_int64 (value);
        }

        public void write_double (double value) throws Error {
            uint64 bits = 0;
            Memory.copy (&bits, &value, sizeof (double));
            write_u64 (bits);
        }

        public void write_utf8 (string value) throws Error {
            write_u32 ((uint32) value.length);
            if (value.length == 0)
                return;

            unowned uint8[] raw = (uint8[]) value.data;
            size_t bytes_written = 0;
            output.write_all (raw[0:value.length], out bytes_written);

            if (bytes_written != value.length) {
                throw new IOError.FAILED (
                    "Unable to write %u bytes of UTF-8 packet data".printf (value.length)
                );
            }
        }

        public void write_qtime (WsjtxTime value) throws Error {
            write_u32 (value.msecs_since_midnight);
        }

        public void write_qdatetime (WsjtxDateTime value) throws Error {
            write_i64 (value.julian_day);
            write_u32 (value.msecs_since_midnight);
            write_u8 (value.time_spec);
            if (value.time_spec == 2)
                write_i32 (value.utc_offset_seconds);
        }

        public void write_qcolor_rgb (
            uint8 red,
            uint8 green,
            uint8 blue,
            uint8 alpha = 255
        ) throws Error {
            write_i8 (1);
            write_u16 ((uint16) alpha * 257);
            write_u16 ((uint16) red * 257);
            write_u16 ((uint16) green * 257);
            write_u16 ((uint16) blue * 257);
            write_u16 (0);
        }

        public void write_header (
            MessageType type,
            string id,
            uint32 schema = MAX_SCHEMA
        ) throws Error {
            write_u32 (MAGIC);
            write_u32 (schema);
            write_u32 ((uint32) type);
            write_utf8 (id);
        }

        private Bytes finish_bytes () throws Error {
            output.flush ();
            output.close ();
            memory.close ();

            int length = (int) memory.get_data_size ();
            unowned uint8[] written = memory.get_data ();
            uint8[] copy = new uint8[length];

            for (int i = 0; i < length; i++)
                copy[i] = written[i];

            return new Bytes.take ((owned) copy);
        }

        public uint8[] finish () throws Error {
            return Bytes.unref_to_data (finish_bytes ());
        }

        public static uint8[] build_heartbeat (
            string id,
            string version,
            string revision,
            uint32 max_schema = MAX_SCHEMA,
            uint32 schema = MAX_SCHEMA
        ) throws Error {
            var writer = new PacketWriter ();
            writer.write_header (MessageType.HEARTBEAT, id, schema);
            writer.write_u32 (max_schema);
            writer.write_utf8 (version);
            writer.write_utf8 (revision);
            return writer.finish ();
        }

        public static uint8[] build_replay (
            string id,
            uint32 schema = MAX_SCHEMA
        ) throws Error {
            var writer = new PacketWriter ();
            writer.write_header (MessageType.REPLAY, id, schema);
            return writer.finish ();
        }

        public static uint8[] build_halt_tx (
            string id,
            bool auto_tx_only = false,
            uint32 schema = MAX_SCHEMA
        ) throws Error {
            var writer = new PacketWriter ();
            writer.write_header (MessageType.HALT_TX, id, schema);
            writer.write_bool (auto_tx_only);
            return writer.finish ();
        }

        public static uint8[] build_free_text (
            string id,
            string text,
            bool send_now,
            uint32 schema = MAX_SCHEMA
        ) throws Error {
            var writer = new PacketWriter ();
            writer.write_header (MessageType.FREE_TEXT, id, schema);
            writer.write_utf8 (text);
            writer.write_bool (send_now);
            return writer.finish ();
        }

        public static uint8[] build_location (
            string id,
            string location,
            uint32 schema = MAX_SCHEMA
        ) throws Error {
            var writer = new PacketWriter ();
            writer.write_header (MessageType.LOCATION, id, schema);
            writer.write_utf8 (location);
            return writer.finish ();
        }

        public static uint8[] build_clear (
            string id,
            bool include_window = false,
            uint8 window = 0,
            uint32 schema = MAX_SCHEMA
        ) throws Error {
            var writer = new PacketWriter ();
            writer.write_header (MessageType.CLEAR, id, schema);
            if (include_window)
                writer.write_u8 (window);
            return writer.finish ();
        }

        public static uint8[] build_highlight_callsign (
            string id,
            string callsign,
            bool highlight_last = true,
            uint32 schema = MAX_SCHEMA
        ) throws Error {
            var writer = new PacketWriter ();
            writer.write_header (MessageType.HIGHLIGHT_CALLSIGN, id, schema);
            writer.write_utf8 (callsign);
            writer.write_qcolor_rgb (46, 160, 67);
            writer.write_qcolor_rgb (255, 255, 255);
            writer.write_bool (highlight_last);
            return writer.finish ();
        }
    }
}
