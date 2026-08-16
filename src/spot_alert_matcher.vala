/* src/spot_alert_matcher.vala
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

namespace SpotAlerts {
    public string normalize_search_text (string? value) {
        if (value == null)
            return "";

        return value.strip ().casefold ();
    }

    public Gee.ArrayList<string> normalized_keywords (string[] raw_keywords) {
        var keywords = new Gee.ArrayList<string> ();

        foreach (var keyword in raw_keywords) {
            var normalized = normalize_search_text (keyword);
            if (normalized != "")
                keywords.add (normalized);
        }

        return keywords;
    }

    public bool spot_matches_keywords (Spot spot, Gee.ArrayList<string> keywords) {
        return fields_match_keywords (
            spot.callsign,
            spot.park_ref,
            spot.park_name,
            spot.location_desc,
            spot.grid4,
            spot.grid6,
            spot.activator_comment,
            spot.spotter_comment,
            keywords
        );
    }

    public bool fields_match_keywords (
        string? callsign,
        string? park_ref,
        string? park_name,
        string? location_desc,
        string? grid4,
        string? grid6,
        string? activator_comment,
        string? spotter_comment,
        Gee.ArrayList<string> keywords
    ) {
        if (keywords.size == 0)
            return false;

        var haystack = normalized_haystack (
            callsign,
            park_ref,
            park_name,
            location_desc,
            grid4,
            grid6,
            activator_comment,
            spotter_comment
        );
        var tokens = tokenize (haystack);

        foreach (var keyword in keywords) {
            if (keyword_matches (keyword, haystack, tokens))
                return true;
        }

        return false;
    }

    private string normalized_haystack (
        string? callsign,
        string? park_ref,
        string? park_name,
        string? location_desc,
        string? grid4,
        string? grid6,
        string? activator_comment,
        string? spotter_comment
    ) {
        var normalized_callsign = normalize_search_text (callsign);
        var profile_callsign = normalize_search_text (pota_profile_callsign (callsign ?? ""));

        return string.joinv ("\n", {
            normalized_callsign,
            profile_callsign,
            normalize_search_text (park_ref),
            normalize_search_text (park_name),
            normalize_search_text (location_desc),
            normalize_search_text (grid4),
            normalize_search_text (grid6),
            normalize_search_text (activator_comment),
            normalize_search_text (spotter_comment)
        });
    }

    private bool keyword_matches (
        string keyword,
        string haystack,
        Gee.HashSet<string> tokens
    ) {
        if (contains_whitespace (keyword))
            return haystack.contains (keyword);

        return tokens.contains (keyword);
    }

    private Gee.HashSet<string> tokenize (string normalized_haystack) {
        var tokens = new Gee.HashSet<string> ();
        var token = new StringBuilder ();

        for (int i = 0; i < normalized_haystack.length; i++) {
            var c = normalized_haystack[i];
            if (is_token_char (c)) {
                token.append_c (c);
                continue;
            }

            add_token (tokens, token);
        }

        add_token (tokens, token);
        return tokens;
    }

    private void add_token (Gee.HashSet<string> tokens, StringBuilder token) {
        if (token.len > 0) {
            tokens.add (token.str);
            token.truncate (0);
        }
    }

    private bool is_token_char (char c) {
        return (c >= 'a' && c <= 'z') ||
            (c >= '0' && c <= '9') ||
            c == '-';
    }

    private bool contains_whitespace (string value) {
        for (int i = 0; i < value.length; i++) {
            if (value[i].isspace ())
                return true;
        }

        return false;
    }
}
