/* src/input_parsing.vala
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

public static bool try_parse_port (string text, out int port) {
    port = 0;
    var stripped = text.strip ();
    if (stripped.length == 0)
        return false;

    int64 parsed_port64 = 0;
    if (!int64.try_parse (stripped, out parsed_port64))
        return false;

    if (parsed_port64 < 1 || parsed_port64 > 65535)
        return false;

    port = (int) parsed_port64;
    return true;
}

public static DateTime? parse_date_only_utc (string value) {
    if (value.length != 10 ||
        value.get_char (4) != '-' ||
        value.get_char (7) != '-') {
        return null;
    }

    int year = 0;
    int month = 0;
    int day = 0;
    unowned string unparsed;
    if (!int.try_parse (value.substring (0, 4), out year, out unparsed, 10) ||
        unparsed != "") {
        return null;
    }
    if (!int.try_parse (value.substring (5, 2), out month, out unparsed, 10) ||
        unparsed != "") {
        return null;
    }
    if (!int.try_parse (value.substring (8, 2), out day, out unparsed, 10) ||
        unparsed != "") {
        return null;
    }

    return new DateTime.utc (year, month, day, 0, 0, 0);
}
