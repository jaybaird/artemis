/* src/wsjtx_message.vala
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
    public struct WsjtxTime {
        public uint32 msecs_since_midnight;

        public int hour {
            get {
                return (int) (msecs_since_midnight / 3600000);
            }
        }

        public int minute {
            get {
                return (int) ((msecs_since_midnight / 60000) % 60);
            }
        }

        public int second {
            get {
                return (int) ((msecs_since_midnight / 1000) % 60);
            }
        }

        public int millisecond {
            get {
                return (int) (msecs_since_midnight % 1000);
            }
        }

        public string to_display_string () {
            return "%02d:%02d:%02d".printf (hour, minute, second);
        }
    }

    public struct WsjtxDateTime {
      // Qt QDateTime schema described by WSJT-X:
      // qint64 Julian day, quint32 msecs, quint8 timespec,
      // optional qint32 offset if timespec == 2.
      public int64 julian_day;
      public uint32 msecs_since_midnight;
      public uint8 time_spec;
      public int32 utc_offset_seconds;
    }

    public enum MessageType {
        HEARTBEAT = 0,
        STATUS = 1,
        DECODE = 2,
        CLEAR = 3,
        REPLY = 4,
        QSO_LOGGED = 5,
        CLOSE = 6,
        REPLAY = 7,
        HALT_TX = 8,
        FREE_TEXT = 9,
        WSPR_DECODE = 10,
        LOCATION = 11,
        LOGGED_ADIF = 12,
        HIGHLIGHT_CALLSIGN = 13,
        SWITCH_CONFIGURATION = 14,
        CONFIGURE = 15,
        ANNOTATION_INFO = 16
    }

    public struct Header {
        public uint32 schema;
        public MessageType type;
        public string id;
    }

    public struct HeartbeatPacket {
        public Header header;
        public uint32 max_schema;
        public string version;
        public string revision;
    }

    public struct StatusPacket {
        public Header header;

        public uint64 dial_frequency_hz;
        public string mode;
        public string dx_call;
        public string report;
        public string tx_mode;

        public bool tx_enabled;
        public bool transmitting;
        public bool decoding;

        public uint32 rx_df;
        public uint32 tx_df;

        public string de_call;
        public string de_grid;
        public string dx_grid;

        public bool tx_watchdog;
        public string sub_mode;
        public bool fast_mode;

        public uint8 special_operation_mode;
        public uint32 frequency_tolerance;
        public uint32 tr_period;

        public string configuration_name;
        public string tx_message;
    }

    public struct DecodePacket {
        public Header header;

        public bool is_new;
        public WsjtxTime time;
        public int32 snr;
        public double delta_time;
        public uint32 delta_frequency_hz;
        public string mode;
        public string text;
        public bool low_confidence;
        public bool off_air;
    }

    public struct LoggedAdifPacket {
        public Header header;
        public string adif;
    }

    public struct ClearPacket {
        public Header header;
        public uint8 window;
    }
}
