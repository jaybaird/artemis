/* src/app_state.vala
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

public sealed class AppState : Object {
    private Quark _current_spot_hash = BLANK_HASH;
    private string _current_band_filter = "All";
    private string? _current_mode_filter = null;
    private string? _current_program_filter = null;
    private string? _current_search_text = null;

    public Quark current_spot_hash {
        get {
            return _current_spot_hash;
        }
    }

    public string current_band_filter {
        get {
            return _current_band_filter;
        }
    }

    public string? current_mode_filter {
        get {
            return _current_mode_filter;
        }
    }

    public string? current_program_filter {
        get {
            return _current_program_filter;
        }
    }

    public string? current_search_text {
        get {
            return _current_search_text;
        }
    }

    public signal void current_spot_changed (Quark spot_hash);
    public signal void filters_changed ();

    public void select_spot (Quark spot_hash) {
        set_current_spot_hash (spot_hash);
    }

    public void toggle_spot (Quark spot_hash) {
        if (spot_hash != BLANK_HASH && _current_spot_hash == spot_hash)
            clear_spot_selection ();
        else
            select_spot (spot_hash);
    }

    public void clear_spot_selection () {
        set_current_spot_hash (BLANK_HASH);
    }

    public void restore_spot_selection (Quark spot_hash) {
        set_current_spot_hash (spot_hash);
    }

    public void set_band_filter (string? band) {
        var normalized = normalize_band_filter (band);
        if (_current_band_filter == normalized)
            return;

        _current_band_filter = normalized;
        filters_changed ();
    }

    public void set_mode_filter (string? mode) {
        var normalized = normalize_optional_filter (mode);
        if (_current_mode_filter == normalized)
            return;

        _current_mode_filter = normalized;
        filters_changed ();
    }

    public void set_program_filter (string? program) {
        var normalized = normalize_optional_filter (program);
        if (_current_program_filter == normalized)
            return;

        _current_program_filter = normalized;
        filters_changed ();
    }

    public void set_search_text (string? search_text) {
        var normalized = normalize_text_filter (search_text);
        if (_current_search_text == normalized)
            return;

        _current_search_text = normalized;
        filters_changed ();
    }

    public void reset_filters () {
        var changed = false;

        if (_current_band_filter != "All") {
            _current_band_filter = "All";
            changed = true;
        }
        if (_current_mode_filter != null) {
            _current_mode_filter = null;
            changed = true;
        }
        if (_current_program_filter != null) {
            _current_program_filter = null;
            changed = true;
        }
        if (_current_search_text != null) {
            _current_search_text = null;
            changed = true;
        }

        if (changed)
            filters_changed ();
    }

    private void set_current_spot_hash (Quark spot_hash) {
        if (_current_spot_hash == spot_hash)
            return;

        _current_spot_hash = spot_hash;
        current_spot_changed (spot_hash);
    }

    private static string normalize_band_filter (string? band) {
        var normalized = (band ?? "").strip ();
        return normalized == "" ? "All" : normalized;
    }

    private static string? normalize_optional_filter (string? value) {
        var normalized = normalize_text_filter (value);
        if (normalized == "All")
            return null;

        return normalized;
    }

    private static string? normalize_text_filter (string? value) {
        var normalized = (value ?? "").strip ();
        return normalized == "" ? null : normalized;
    }
}
