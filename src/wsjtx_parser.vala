/* src/wsjtx_parser.vala
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

using GLib;

namespace Artemis.Wsjtx {
  public errordomain PacketError {
    BAD_MAGIC,
    UNSUPPORTED_SCHEMA,
    MALFORMED_PACKET,
    INVALID_UTF8
  }

  public sealed class PacketReader : Object {
    private MemoryInputStream memory;
    private DataInputStream input;

    public PacketReader (uint8[] bytes) {
      memory = new MemoryInputStream.from_data (bytes, null);
      input = new DataInputStream (memory);
      input.byte_order = DataStreamByteOrder.BIG_ENDIAN;
    }

    public uint8 read_u8 () throws Error {
      return input.read_byte ();
    }

    public bool read_bool () throws Error {
      return input.read_byte () != 0;
    }

    public uint32 read_u32 () throws Error {
      return input.read_uint32 ();
    }

    public int32 read_i32 () throws Error {
      return input.read_int32 ();
    }

    public uint64 read_u64 () throws Error {
      return input.read_uint64 ();
    }

    public int64 read_i64 () throws Error {
      return input.read_int64 ();
    }

    public double read_double () throws Error {
      uint64 bits = input.read_uint64 ();

      double value = 0.0;
      Memory.copy (&value, &bits, sizeof (double));

      return value;
    }

    public string read_utf8 () throws Error {
      uint32 len = read_u32 ();

      // Qt QByteArray null marker.
      // WSJT-X normally uses real strings, but this is valid QDataStream shape.
      if (len == 0xffffffff) {
        return "";
      }

      uint8[] bytes = new uint8[len + 1];

      size_t bytes_read = 0;
      input.read_all (bytes[0:len], out bytes_read);

      if (bytes_read != len) {
        throw new PacketError.MALFORMED_PACKET (
            "String length exceeds remaining packet data"
        );
      }

      bytes[len] = 0;

      string s = ((string) bytes).dup ();

      if (!s.validate ()) {
          throw new PacketError.INVALID_UTF8 ("Invalid UTF-8 string");
      }

      return s;
    }

    public WsjtxTime read_qtime () throws Error {
      WsjtxTime t = {};
      t.msecs_since_midnight = read_u32 ();
      return t;
    }

    public WsjtxDateTime read_qdatetime () throws Error {
      WsjtxDateTime dt = {};

      dt.julian_day = read_i64 ();
      dt.msecs_since_midnight = read_u32 ();
      dt.time_spec = read_u8 ();
      dt.utc_offset_seconds = 0;

      if (dt.time_spec == 2) {
        dt.utc_offset_seconds = read_i32 ();
      }

      if (dt.time_spec == 3) {
        throw new PacketError.MALFORMED_PACKET (
            "QDateTime timezone serialization is not supported"
        );
      }

      return dt;
    }
  }
}
