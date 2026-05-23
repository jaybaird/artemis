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

    public Quark current_spot_hash {
        get {
            return _current_spot_hash;
        }
        set {
            if (_current_spot_hash == value)
                return;

            _current_spot_hash = value;
            current_spot_changed (value);
        }
    }

    public string? current_mode_filter { get; set; default = null; }
    public string? current_program_filter { get; set; default = null; }
    public string? current_search_text { get; set; default = null; }
    public string current_band_filter { get; set; default = "All"; }

    public signal void current_spot_changed (Quark spot_hash);

    public void reset_filters () {
        current_band_filter = "All";
        current_mode_filter = null;
        current_program_filter = null;
        current_search_text = null;
    }
}
