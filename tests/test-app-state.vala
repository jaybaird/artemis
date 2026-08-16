/* tests/test-app-state.vala
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

private void test_app_state_selection_signals () {
    var state = new AppState ();
    var changed_count = 0;
    var last_hash = (Quark) BLANK_HASH;
    var first_hash = Quark.from_string ("K1ABC|US-0001");
    var second_hash = Quark.from_string ("N0CALL|US-0002");

    state.current_spot_changed.connect ((spot_hash) => {
        changed_count++;
        last_hash = spot_hash;
    });

    state.select_spot (first_hash);
    assert (state.current_spot_hash == first_hash);
    assert (last_hash == first_hash);
    assert (changed_count == 1);

    state.select_spot (first_hash);
    assert (changed_count == 1);

    state.toggle_spot (first_hash);
    assert (state.current_spot_hash == BLANK_HASH);
    assert (last_hash == BLANK_HASH);
    assert (changed_count == 2);

    state.toggle_spot (second_hash);
    assert (state.current_spot_hash == second_hash);
    assert (last_hash == second_hash);
    assert (changed_count == 3);

    state.restore_spot_selection (second_hash);
    assert (changed_count == 3);

    state.clear_spot_selection ();
    assert (state.current_spot_hash == BLANK_HASH);
    assert (changed_count == 4);
}

private void test_app_state_filter_normalization () {
    var state = new AppState ();
    var changed_count = 0;
    state.filters_changed.connect (() => {
        changed_count++;
    });

    state.set_band_filter (null);
    assert (state.current_band_filter == "All");
    assert (changed_count == 0);

    state.set_band_filter (" 20m ");
    assert (state.current_band_filter == "20m");
    assert (changed_count == 1);

    state.set_mode_filter ("All");
    assert (state.current_mode_filter == null);
    assert (changed_count == 1);

    state.set_mode_filter (" FT8 ");
    assert (state.current_mode_filter == "FT8");
    assert (changed_count == 2);

    state.set_program_filter ("");
    assert (state.current_program_filter == null);
    assert (changed_count == 2);

    state.set_program_filter (" US ");
    assert (state.current_program_filter == "US");
    assert (changed_count == 3);

    state.set_search_text (" activator ");
    assert (state.current_search_text == "activator");
    assert (changed_count == 4);

    state.reset_filters ();
    assert (state.current_band_filter == "All");
    assert (state.current_mode_filter == null);
    assert (state.current_program_filter == null);
    assert (state.current_search_text == null);
    assert (changed_count == 5);

    state.reset_filters ();
    assert (changed_count == 5);
}

public int main (string[] args) {
    Test.init (ref args);

    Test.add_func ("/app-state/selection-signals", test_app_state_selection_signals);
    Test.add_func ("/app-state/filter-normalization", test_app_state_filter_normalization);

    return Test.run ();
}
