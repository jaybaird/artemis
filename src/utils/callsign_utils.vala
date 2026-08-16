/* src/utils/callsign_utils.vala
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

public static string normalize_callsign (string callsign) {
    return callsign.strip ().ascii_up ();
}

public static string normalize_callsign_key (string callsign) {
    return normalize_callsign (callsign).ascii_down ();
}

public static string display_callsign (string callsign) {
    return normalize_callsign (callsign).replace ("0", "Ø");
}

public static string pota_profile_callsign (string callsign) {
    var stripped_callsign = callsign.strip ();
    var profile_callsign = "";

    foreach (var part in stripped_callsign.split ("/")) {
        var candidate = part.strip ();
        if (candidate.length > profile_callsign.length)
            profile_callsign = candidate;
    }

    return (profile_callsign != "") ? profile_callsign : stripped_callsign;
}
