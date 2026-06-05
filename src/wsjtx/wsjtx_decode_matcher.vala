/* src/wsjtx/wsjtx_decode_matcher.vala
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

using Gee;

namespace Artemis.Wsjtx {
    public string heard_callsign_from_decode_text (string decode_text) {
        var tokens = tokenize_message_text (decode_text);
        if (tokens.length == 0)
            return "";

        var cq_callsign = callsign_from_cq_message (tokens);
        if (cq_callsign != "")
            return cq_callsign;

        if ((tokens.length >= 2) &&
            looks_like_callsign (tokens[0]) &&
            looks_like_callsign (tokens[1])) {
            return normalize_decode_token (tokens[1]);
        }

        return "";
    }

    public bool decode_text_heard_callsign_matches (
        string decode_text,
        string callsign,
        string? profile_callsign = null
    ) {
        var heard_callsign = heard_callsign_from_decode_text (decode_text);
        if (heard_callsign == "")
            return false;

        var normalized_callsign = normalize_decode_token (callsign);
        var normalized_profile = normalize_decode_token (profile_callsign ?? "");
        var heard_profile = profile_callsign_from_token (heard_callsign);
        return (heard_callsign == normalized_callsign) ||
            ((normalized_profile != "") &&
                ((heard_callsign == normalized_profile) || (heard_profile == normalized_profile)));
    }

    private string callsign_from_cq_message (string[] tokens) {
        for (int i = 0; i < tokens.length; i++) {
            if (tokens[i] != "CQ")
                continue;

            for (int j = i + 1; j < tokens.length && j <= i + 5; j++) {
                if (is_cq_modifier (tokens[j]))
                    continue;

                if (looks_like_callsign (tokens[j]))
                    return normalize_decode_token (tokens[j]);
            }
        }

        return "";
    }

    private bool is_cq_modifier (string token) {
        switch (token) {
            case "POTA":
            case "SOTA":
            case "WWFF":
            case "TEST":
            case "DX":
            case "NA":
            case "SA":
            case "EU":
            case "AF":
            case "AS":
            case "OC":
            case "JA":
            case "VE":
            case "VK":
            case "QRP":
                return true;
            default:
                return false;
        }
    }

    private bool looks_like_callsign (string token) {
        var normalized = normalize_decode_token (token);
        if (normalized.length < 3 || normalized.length > 16)
            return false;

        bool has_letter = false;
        bool has_digit = false;
        for (int i = 0; i < normalized.length; i++) {
            char c = normalized[i];
            if (c >= 'A' && c <= 'Z') {
                has_letter = true;
                continue;
            }

            if (c >= '0' && c <= '9') {
                has_digit = true;
                continue;
            }

            if (c == '/')
                continue;

            return false;
        }

        return has_letter && has_digit;
    }

    private string[] tokenize_message_text (string decode_text) {
        var tokens = new ArrayList<string> ();
        foreach (var raw_token in decode_text.up ().split_set (" \t\r\n")) {
            var token = raw_token.strip ();
            if (token == "")
                continue;

            if (token == "~") {
                tokens.clear ();
                continue;
            }

            tokens.add (token);
        }

        string[] result = new string[tokens.size];
        for (int i = 0; i < tokens.size; i++)
            result[i] = tokens[i];

        return result;
    }

    private string normalize_decode_token (string token) {
        return strip_up (token).delimit ("<>", ' ').strip ();
    }

    private string profile_callsign_from_token (string callsign) {
        var profile_callsign = "";
        foreach (var part in callsign.split ("/")) {
            var candidate = normalize_decode_token (part);
            if (candidate.length > profile_callsign.length)
                profile_callsign = candidate;
        }

        return profile_callsign;
    }
}
