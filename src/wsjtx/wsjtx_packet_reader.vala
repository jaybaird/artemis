/* src/wsjtx/wsjtx_packet_reader.vala
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
    public class PacketReader {
        private MemoryInputStream memory;
        private DataInputStream input;
        private size_t offset = 0;
        private size_t total_length = 0;

        public PacketReader (uint8[] datagram) {
            memory = new MemoryInputStream.from_data (datagram, null);
            input = new DataInputStream (memory);
            input.byte_order = DataStreamByteOrder.BIG_ENDIAN;
            total_length = datagram.length;
        }

        public size_t remaining_bytes () {
            return total_length - offset;
        }

        public bool has_remaining () {
            return remaining_bytes () > 0;
        }

        public uint8 read_u8 () throws Error {
            ensure_remaining (1);
            offset += 1;
            return input.read_byte ();
        }

        public bool read_bool () throws Error {
            return read_u8 () != 0;
        }

        public uint32 read_u32 () throws Error {
            ensure_remaining (4);
            offset += 4;
            return input.read_uint32 ();
        }

        public int32 read_i32 () throws Error {
            ensure_remaining (4);
            offset += 4;
            return input.read_int32 ();
        }

        public uint64 read_u64 () throws Error {
            ensure_remaining (8);
            offset += 8;
            return input.read_uint64 ();
        }

        public int64 read_i64 () throws Error {
            ensure_remaining (8);
            offset += 8;
            return input.read_int64 ();
        }

        public double read_double () throws Error {
            uint64 bits = read_u64 ();
            double value = 0.0;
            Memory.copy (&value, &bits, sizeof (double));
            return value;
        }

        public string read_utf8 () throws Error {
            uint32 len = read_u32 ();

            if (len == 0xffffffffU)
                return "";

            if (len == 0)
                return "";

            ensure_remaining (len);

            uint8[] bytes = new uint8[len + 1];
            size_t bytes_read = 0;
            input.read_all (bytes[0:len], out bytes_read);

            if (bytes_read != len) {
                throw new PacketError.MALFORMED_PACKET (
                    "String length exceeds remaining packet data"
                );
            }

            offset += len;
            bytes[len] = 0;

            string parsed = ((string) bytes).dup ();
            if (!parsed.validate ()) {
                throw new PacketError.INVALID_UTF8 ("String field is not valid UTF-8");
            }

            return parsed;
        }

        public WsjtxTime read_qtime () throws Error {
            WsjtxTime time = {};
            time.msecs_since_midnight = read_u32 ();
            return time;
        }

        public WsjtxDateTime read_qdatetime () throws Error {
            WsjtxDateTime dt = {};
            dt.julian_day = read_i64 ();
            dt.msecs_since_midnight = read_u32 ();
            dt.time_spec = read_u8 ();
            dt.utc_offset_seconds = 0;

            if (dt.time_spec == 2)
                dt.utc_offset_seconds = read_i32 ();

            if (dt.time_spec == 3) {
                throw new PacketError.MALFORMED_PACKET (
                    "QDateTime timezone serialization is not supported"
                );
            }

            return dt;
        }

        public uint8[] read_remaining () throws Error {
            size_t remaining = remaining_bytes ();
            if (remaining == 0)
                return new uint8[0];

            uint8[] bytes = new uint8[remaining];
            size_t bytes_read = 0;
            input.read_all (bytes, out bytes_read);

            if (bytes_read != remaining) {
                throw new PacketError.MALFORMED_PACKET (
                    "Trailing payload exceeds remaining packet data"
                );
            }

            offset += remaining;
            return bytes;
        }

        private void ensure_remaining (size_t needed) throws PacketError {
            if (remaining_bytes () < needed) {
                throw new PacketError.MALFORMED_PACKET (
                    "Packet ended before all expected fields were read"
                );
            }
        }
    }
}
