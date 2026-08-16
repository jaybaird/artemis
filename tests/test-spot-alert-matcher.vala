/* tests/test-spot-alert-matcher.vala
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

public class Spot : Object {
    public string? callsign { get; construct; }
    public string? park_ref { get; construct; }
    public string? park_name { get; construct; }
    public string? location_desc { get; construct; }
    public string? grid4 { get; construct; }
    public string? grid6 { get; construct; }
    public string? activator_comment { get; construct; }
    public string? spotter_comment { get; construct; }

    public Spot (
        string? callsign = null,
        string? park_ref = null,
        string? park_name = null,
        string? location_desc = null,
        string? grid4 = null,
        string? grid6 = null,
        string? activator_comment = null,
        string? spotter_comment = null
    ) {
        Object (
            callsign: callsign,
            park_ref: park_ref,
            park_name: park_name,
            location_desc: location_desc,
            grid4: grid4,
            grid6: grid6,
            activator_comment: activator_comment,
            spotter_comment: spotter_comment
        );
    }
}

private Gee.ArrayList<string> keywords (string[] values) {
    return SpotAlerts.normalized_keywords (values);
}

private bool matches (
    string[] keyword_values,
    string? callsign = "K1ABC",
    string? park_ref = "K-1234",
    string? park_name = "Split Rock",
    string? location_desc = "California",
    string? grid4 = "DM14",
    string? grid6 = "DM14AA",
    string? activator_comment = "CQ POTA",
    string? spotter_comment = "Strong signal"
) {
    return SpotAlerts.fields_match_keywords (
        callsign,
        park_ref,
        park_name,
        location_desc,
        grid4,
        grid6,
        activator_comment,
        spotter_comment,
        keywords (keyword_values)
    );
}

private void test_alert_matcher_handles_null_and_empty_fields () {
    assert (!matches ({ "k1abc" }, null, null, null, null, null, null, null, null));
    assert (!matches ({ "" }, null, null, null, null, null, null, null, null));
    assert (!matches ({ "   " }, null, null, null, null, null, null, null, null));
}

private void test_alert_matcher_matches_case_insensitively () {
    assert (matches ({ "split" }, "K1ABC", "K-1234", "Split Rock"));
    assert (matches ({ "k1abc" }, "K1ABC"));
    assert (matches ({ "dm14" }, "K1ABC", "K-1234", "Split Rock", "", "DM14"));
}

private void test_alert_matcher_matches_single_tokens_only () {
    assert (matches ({ "k1abc" }, "K1ABC/P"));
    assert (matches ({ "dm14" }));
    assert (matches ({ "k-1234" }));
    assert (!matches ({ "ca" }, "CALLSIGN", "", "", "", "", "", "activator"));
    assert (!matches ({ "pot" }, "K1ABC", "K-1234", "Split Rock", "", "", "", "CQ POTA"));
}

private void test_alert_matcher_matches_phrases_by_substring () {
    assert (matches ({ "split rock" }));
    assert (matches ({ "strong sig" }));
    assert (!matches ({ "rock split" }));
}

private void test_alert_matcher_matches_spot_entry_point () {
    var spot = new Spot (
        "N0CALL/7",
        "US-4567",
        "Granite Peak",
        "Montana",
        "DN45",
        "DN45BB",
        "Digital activation",
        "loud"
    );

    assert (SpotAlerts.spot_matches_keywords (spot, keywords ({ "n0call" })));
    assert (SpotAlerts.spot_matches_keywords (spot, keywords ({ "us-4567" })));
    assert (!SpotAlerts.spot_matches_keywords (spot, keywords ({ "ran" })));
}

public int main (string[] args) {
    Test.init (ref args);

    Test.add_func ("/spot-alert-matcher/null-empty-fields",
        test_alert_matcher_handles_null_and_empty_fields);
    Test.add_func ("/spot-alert-matcher/case-insensitive",
        test_alert_matcher_matches_case_insensitively);
    Test.add_func ("/spot-alert-matcher/single-token-whole-word",
        test_alert_matcher_matches_single_tokens_only);
    Test.add_func ("/spot-alert-matcher/phrase",
        test_alert_matcher_matches_phrases_by_substring);
    Test.add_func ("/spot-alert-matcher/spot-entry-point",
        test_alert_matcher_matches_spot_entry_point);

    return Test.run ();
}
