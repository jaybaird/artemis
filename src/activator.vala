/* src/activator.vala
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

public sealed class Activator : Object {
    public string callsign { get; construct; }
    public string name { get; construct; }
    public string qth { get; construct; }
    public string gravatar_hash { get; construct; }
    public uint activations { get; construct; }
    public uint parks { get; construct; }
    public uint qsos { get; construct; }
    public Activator (string callsign,
                      string name,
                      string qth,
                      string gravatar_hash,
                      uint activations,
                      uint parks,
                      uint qsos) {
        Object (
            callsign: callsign,
            name: name,
            qth: qth,
            gravatar_hash: gravatar_hash,
            activations: activations,
            parks: parks,
            qsos: qsos
        );
    }

    public Activator.from_json (Json.Object object) {
        Object (
            callsign: object.get_string_member ("callsign"),
            name: object.get_string_member ("name"),
            qth: object.get_string_member ("qth"),
            gravatar_hash: object.get_string_member ("gravatar"),
            activations: (uint)object.get_int_member_with_default (
                "activations",
                0),
            parks: (uint)object.get_int_member_with_default ("parks", 0),
            qsos: (uint)object.get_int_member_with_default ("qsos", 0)
        );
    }

    construct {
    }
} /* class Activator */
