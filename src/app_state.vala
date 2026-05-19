/* src/app_state.vala
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
