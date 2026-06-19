/* tests/test-spot-filter.vala
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

private SpotFilterSnapshot spot_snapshot (
        string callsign = "K1ABC",
        string park_ref = "US-1234",
        string park_name = "Test Park",
        string activator_comment = "",
        string band = "20m",
        string mode = "FT8",
        DateTime? spot_time = null,
        bool was_hunted_today = false,
        string frequency = "14.074"
    ) {
    return new SpotFilterSnapshot (
        callsign,
        park_ref,
        park_name,
        activator_comment,
        frequency,
        band,
        mode,
        spot_time ?? new DateTime.now_utc (),
        was_hunted_today
    );
}

private SpotFilterState filter_state (
    string band = "All",
    string? mode = null,
    string? program = null,
    string? search_text = null,
    bool hide_qrt = false,
    bool hide_hunted = false,
    int hide_older_than_minutes = 30,
    DateTime? now_utc = null,
    OperatingLimitEvaluator? operating_limits = null
) {
    return new SpotFilterState (
        band,
        mode,
        program,
        search_text,
        hide_qrt,
        hide_hunted,
        hide_older_than_minutes,
        now_utc ?? new DateTime.now_utc (),
        operating_limits
    );
}

private void test_spot_filter_matches_basic_filters () {
    var spot = spot_snapshot ();

    assert (spot_matches_filter (spot, filter_state ("20m")));
    assert (!spot_matches_filter (spot, filter_state ("40m")));
    assert (spot_matches_filter (spot, filter_state ("All", "FT")));
    assert (!spot_matches_filter (spot, filter_state ("All", "SSB")));
    assert (spot_matches_filter (spot, filter_state ("All", null, "US")));
    assert (!spot_matches_filter (spot, filter_state ("All", null, "CA")));
}

private void test_spot_filter_searches_callsign_reference_and_name () {
    var spot = spot_snapshot ("K1ABC", "US-1234", "Split Rock");

    assert (spot_matches_filter (spot, filter_state ("All", null, null, "k1a")));
    assert (spot_matches_filter (spot, filter_state ("All", null, null, "1234")));
    assert (spot_matches_filter (spot, filter_state ("All", null, null, "rock")));
    assert (!spot_matches_filter (spot, filter_state ("All", null, null, "missing")));
}

private void test_spot_filter_searches_frequency_without_punctuation () {
    var spot = spot_snapshot ("K1ABC", "US-1234", "Split Rock", "", "20m", "FT8", null, false, "14.074");

    assert (spot_matches_filter (spot, filter_state ("All", null, null, "14.074")));
    assert (spot_matches_filter (spot, filter_state ("All", null, null, "14074")));
    assert (spot_matches_filter (spot, filter_state ("All", null, null, "14,074")));
    assert (!spot_matches_filter (spot, filter_state ("All", null, null, "7074")));
}

private void test_spot_filter_hides_qrt_hunted_and_stale_spots () {
    var now = new DateTime.now_utc ();

    assert (!spot_matches_filter (
        spot_snapshot ("K1ABC", "US-1234", "Test Park", "Going QRT"),
        filter_state ("All", null, null, null, true, false, 30, now)
    ));
    assert (!spot_matches_filter (
        spot_snapshot ("K1ABC", "US-1234", "Test Park", "", "20m", "FT8", null, true),
        filter_state ("All", null, null, null, false, true, 30, now)
    ));
    assert (!spot_matches_filter (
        spot_snapshot ("K1ABC", "US-1234", "Test Park", "", "20m", "FT8", now.add_minutes (-31)),
        filter_state ("All", null, null, null, false, false, 30, now)
    ));
    assert (spot_matches_filter (
        spot_snapshot ("K1ABC", "US-1234", "Test Park", "", "20m", "FT8", now.add_minutes (-29)),
        filter_state ("All", null, null, null, false, false, 30, now)
    ));
}

private OperatingLimitEvaluator operating_limits_for_test () {
    var modes = new Gee.ArrayList<string> ();
    modes.add ("CW");
    modes.add ("FT8");
    modes.add ("FT4");
    modes.add ("RTTY");
    modes.add ("JT65");

    var rules = new Gee.ArrayList<OperatingLimitRule> ();
    rules.add (new OperatingLimitRule ("20m", 14000.0, 14150.0, modes));

    var profile = new OperatingLimitProfile (
        "TS",
        "Testland",
        "TEST",
        "Test",
        false,
        new Gee.ArrayList<string> (),
        rules
    );
    return new OperatingLimitEvaluator (profile);
}

private void test_spot_filter_operating_limits_disabled_by_default () {
    assert (spot_matches_filter (
        spot_snapshot ("K1ABC", "US-1234", "Test Park", "", "20m", "SSB", null, false, "14.225"),
        filter_state ()
    ));
}

private void test_spot_filter_operating_limits_allow_and_block_spots () {
    var evaluator = operating_limits_for_test ();

    assert (spot_matches_filter (
        spot_snapshot ("K1ABC", "US-1234", "Test Park", "", "20m", "FT8", null, false, "14.074"),
        filter_state ("All", null, null, null, false, false, 30, null, evaluator)
    ));
    assert (!spot_matches_filter (
        spot_snapshot ("K1ABC", "US-1234", "Test Park", "", "20m", "SSB", null, false, "14.225"),
        filter_state ("All", null, null, null, false, false, 30, null, evaluator)
    ));
}

private void test_spot_filter_operating_limits_unknown_mode_blocks () {
    assert (!spot_matches_filter (
        spot_snapshot ("K1ABC", "US-1234", "Test Park", "", "20m", "Unknown", null, false, "14.074"),
        filter_state (
            "All",
            null,
            null,
            null,
            false,
            false,
            30,
            null,
            operating_limits_for_test ()
        )
    ));
}

public int main (string[] args) {
    Test.init (ref args);

    Test.add_func ("/spot-filter/basic-filters", test_spot_filter_matches_basic_filters);
    Test.add_func ("/spot-filter/search", test_spot_filter_searches_callsign_reference_and_name);
    Test.add_func ("/spot-filter/search-frequency-without-punctuation",
        test_spot_filter_searches_frequency_without_punctuation);
    Test.add_func ("/spot-filter/hide-qrt-hunted-stale",
        test_spot_filter_hides_qrt_hunted_and_stale_spots);
    Test.add_func ("/spot-filter/operating-limits-disabled-by-default",
        test_spot_filter_operating_limits_disabled_by_default);
    Test.add_func ("/spot-filter/operating-limits-allow-and-block",
        test_spot_filter_operating_limits_allow_and_block_spots);
    Test.add_func ("/spot-filter/operating-limits-unknown-mode-blocks",
        test_spot_filter_operating_limits_unknown_mode_blocks);

    return Test.run ();
}
