/* src/wsjtx/wsjtx_packet.vala
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
    public const uint32 MAGIC = (uint32) 0xadbccbdaU;
    public const uint32 MAX_SCHEMA = 3U;

    public errordomain PacketError {
        BAD_MAGIC,
        UNSUPPORTED_SCHEMA,
        UNKNOWN_TYPE,
        MALFORMED_PACKET,
        INVALID_UTF8
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
            return "%02d:%02d:%02d.%03d".printf (
                hour,
                minute,
                second,
                millisecond
            );
        }
    }

    public struct WsjtxDateTime {
        public int64 julian_day;
        public uint32 msecs_since_midnight;
        public uint8 time_spec;
        public int32 utc_offset_seconds;
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

    public struct ClearPacket {
        public Header header;
        public bool has_window;
        public uint8 window;
    }

    public struct LoggedAdifPacket {
        public Header header;
        public string adif;
    }

    public struct QsoLoggedPacket {
        public Header header;
        public WsjtxDateTime time_off;
        public string dx_call;
        public string dx_grid;
        public uint64 tx_frequency_hz;
        public string mode;
        public string report_sent;
        public string report_received;
        public string tx_power;
        public string comments;
        public string name;
        public WsjtxDateTime time_on;
        public string operator_call;
        public string my_call;
        public string my_grid;
        public string exchange_sent;
        public string exchange_received;
    }

    public struct UnknownPacket {
        public Header header;
        public uint32 raw_type;
        public uint8[] payload;
    }

    [Compact (opaque = true)]
    public class Packet {
        public MessageType type { get; private set; }
        public Header header { get; private set; }
        public bool is_unknown { get; private set; default = false; }

        private HeartbeatPacket heartbeat_packet;
        private StatusPacket status_packet;
        private DecodePacket decode_packet;
        private ClearPacket clear_packet;
        private LoggedAdifPacket logged_adif_packet;
        private QsoLoggedPacket qso_logged_packet;
        private UnknownPacket unknown_packet;

        public Packet.heartbeat (HeartbeatPacket packet) {
            type = MessageType.HEARTBEAT;
            header = packet.header;
            heartbeat_packet = packet;
        }

        public Packet.status (StatusPacket packet) {
            type = MessageType.STATUS;
            header = packet.header;
            status_packet = packet;
        }

        public Packet.decode (DecodePacket packet) {
            type = MessageType.DECODE;
            header = packet.header;
            decode_packet = packet;
        }

        public Packet.clear (ClearPacket packet) {
            type = MessageType.CLEAR;
            header = packet.header;
            clear_packet = packet;
        }

        public Packet.logged_adif (LoggedAdifPacket packet) {
            type = MessageType.LOGGED_ADIF;
            header = packet.header;
            logged_adif_packet = packet;
        }

        public Packet.qso_logged (QsoLoggedPacket packet) {
            type = MessageType.QSO_LOGGED;
            header = packet.header;
            qso_logged_packet = packet;
        }

        public Packet.unknown (UnknownPacket packet) {
            type = packet.header.type;
            header = packet.header;
            is_unknown = true;
            unknown_packet = packet;
        }

        public HeartbeatPacket get_heartbeat () {
            return heartbeat_packet;
        }

        public StatusPacket get_status () {
            return status_packet;
        }

        public DecodePacket get_decode () {
            return decode_packet;
        }

        public ClearPacket get_clear () {
            return clear_packet;
        }

        public LoggedAdifPacket get_logged_adif () {
            return logged_adif_packet;
        }

        public QsoLoggedPacket get_qso_logged () {
            return qso_logged_packet;
        }

        public UnknownPacket get_unknown () {
            return unknown_packet;
        }
    }
}
