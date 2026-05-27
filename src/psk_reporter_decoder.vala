/* src/psk_reporter_decoder.vala
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

public errordomain PskReporterDecodeError {
    INVALID_PAYLOAD,
    MISSING_FIELD
}

namespace PskReporterDecoder {
    public const string SOURCE = "PSKREPORTER";

    public SignalReport decode_payload (string topic, Bytes payload) throws Error {
        var raw = payload_to_string (payload);
        var parser = new Json.Parser ();
        parser.load_from_data (raw);

        var root = parser.get_root ();
        if ((root == null) || (root.get_node_type () != Json.NodeType.OBJECT)) {
            throw new PskReporterDecodeError.INVALID_PAYLOAD ("PSKReporter MQTT payload is not a JSON object");
        }

        var object = root.get_object ();
        var topic_parts = topic.split ("/");
        var topic_band = topic_parts.length > 3 ? topic_parts[3] : "";
        var topic_mode = topic_parts.length > 4 ? topic_parts[4] : "";

        var receiver_call = required_string (object, "rc");
        var receiver_grid = required_string (object, "rl");
        required_string (object, "sc");

        return new SignalReport.from_grid (
            receiver_call,
            receiver_grid,
            string_member (object, "b") ?? topic_band,
            string_member (object, "md") ?? topic_mode,
            frequency_mhz (object),
            required_int (object, "rp"),
            required_int64 (object, "t"),
            SOURCE,
            receiver_call,
            string_member (object, "ra"),
            string_member (object, "ra"),
            null,
            raw
        );
    }

    private string payload_to_string (Bytes payload) {
        var data = payload.get_data ();
        if (data.length == 0)
            return "";

        return ((string) data).make_valid ((ssize_t) data.length);
    }

    private string required_string (Json.Object object, string member) throws Error {
        var value = string_member (object, member);
        if (value == null || value == "") {
            throw new PskReporterDecodeError.MISSING_FIELD (
                "PSKReporter MQTT payload is missing %s".printf (member)
            );
        }

        return value;
    }

    private string? string_member (Json.Object object, string member) {
        if (!object.has_member (member))
            return null;

        var node = object.get_member (member);
        if ((node == null) || (node.get_node_type () == Json.NodeType.NULL))
            return null;

        var value = node.dup_string ();
        if (value == null)
            return null;

        return value.strip ();
    }

    private int required_int (Json.Object object, string member) throws Error {
        if (!object.has_member (member)) {
            throw new PskReporterDecodeError.MISSING_FIELD (
                "PSKReporter MQTT payload is missing %s".printf (member)
            );
        }

        return (int) object.get_int_member (member);
    }

    private int64 required_int64 (Json.Object object, string member) throws Error {
        if (!object.has_member (member)) {
            throw new PskReporterDecodeError.MISSING_FIELD (
                "PSKReporter MQTT payload is missing %s".printf (member)
            );
        }

        return object.get_int_member (member);
    }

    private double frequency_mhz (Json.Object object) throws Error {
        if (!object.has_member ("f")) {
            throw new PskReporterDecodeError.MISSING_FIELD (
                "PSKReporter MQTT payload is missing f"
            );
        }

        return object.get_double_member ("f") / 1000000.0;
    }
}
