/* tests/test-wsjtx-decode-matcher.vala
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

using Artemis.Wsjtx;

private void assert_heard_callsign (string decode_text, string expected) {
    assert_cmpstr (heard_callsign_from_decode_text (decode_text), CompareOperator.EQ, expected);
}

private void test_cq_decode_returns_caller () {
    assert_heard_callsign ("CQ K1ABC FN31", "K1ABC");
}

private void test_cq_pota_decode_returns_caller () {
    assert_heard_callsign ("CQ POTA K1ABC DM33", "K1ABC");
}

private void test_cq_pota_decode_with_trailing_text_returns_caller () {
    assert_heard_callsign ("CQ POTA WL4ES BP51   Alaska", "WL4ES");
}

private void test_cq_pota_decode_with_alaska_grid_matches_caller () {
    assert (decode_text_heard_callsign_matches ("CQ POTA WL4ES BP51", "WL4ES"));
}

private void test_cq_test_decode_returns_caller () {
    assert_heard_callsign ("CQ TEST K1ABC FN31", "K1ABC");
}

private void test_full_decode_line_uses_message_after_sync_marker () {
    assert_heard_callsign ("153000 -10 0.1 700 ~ CQ  POTA  K1ABC DM33", "K1ABC");
}

private void test_directed_decode_returns_second_callsign () {
    assert_heard_callsign ("K0VCZ K1ABC R-15", "K1ABC");
}

private void test_directed_decode_does_not_match_first_callsign () {
    assert (!decode_text_heard_callsign_matches ("K1ABC K0VCZ R-15", "K1ABC"));
}

private void test_directed_decode_matches_second_callsign () {
    assert (decode_text_heard_callsign_matches ("K0VCZ K1ABC R-15", "K1ABC"));
}

private void test_directed_decode_with_positive_report_matches_second_callsign () {
    assert (decode_text_heard_callsign_matches ("K2DBK WL4ES +02", "WL4ES"));
}

private void test_directed_decode_with_rr73_matches_second_callsign () {
    assert (decode_text_heard_callsign_matches ("K2DBK WL4ES RR73", "WL4ES"));
}

private void test_bracketed_directed_decode_matches_second_callsign () {
    assert (decode_text_heard_callsign_matches ("K0VCZ <K1ABC> R-15", "K1ABC"));
}

private void test_bracketed_cq_decode_matches_caller () {
    assert (decode_text_heard_callsign_matches ("CQ POTA <K1ABC> DM33", "K1ABC"));
}

private void test_profile_callsign_can_match_heard_callsign () {
    assert (decode_text_heard_callsign_matches ("CQ POTA K1ABC DM33", "K1ABC/P", "K1ABC"));
}

private void test_portable_heard_callsign_matches_spot_profile () {
    assert (decode_text_heard_callsign_matches ("CQ POTA K1ABC/P DM33", "K1ABC", "K1ABC"));
}

private void test_directed_portable_heard_callsign_matches_spot_profile () {
    assert (decode_text_heard_callsign_matches ("K0VCZ K1ABC/P R-15", "K1ABC", "K1ABC"));
}

private void test_non_callsign_decode_does_not_match_substrings () {
    assert (!decode_text_heard_callsign_matches ("CQ POTA PARK US-1234", "K1ABC"));
}

public int main (string[] args) {
    Test.init (ref args);

    Test.add_func (
        "/wsjtx-decode-matcher/cq-decode-returns-caller",
        test_cq_decode_returns_caller
    );
    Test.add_func (
        "/wsjtx-decode-matcher/cq-pota-decode-returns-caller",
        test_cq_pota_decode_returns_caller
    );
    Test.add_func (
        "/wsjtx-decode-matcher/cq-pota-decode-with-trailing-text-returns-caller",
        test_cq_pota_decode_with_trailing_text_returns_caller
    );
    Test.add_func (
        "/wsjtx-decode-matcher/cq-pota-decode-with-alaska-grid-matches-caller",
        test_cq_pota_decode_with_alaska_grid_matches_caller
    );
    Test.add_func (
        "/wsjtx-decode-matcher/cq-test-decode-returns-caller",
        test_cq_test_decode_returns_caller
    );
    Test.add_func (
        "/wsjtx-decode-matcher/full-decode-line-uses-message-after-sync-marker",
        test_full_decode_line_uses_message_after_sync_marker
    );
    Test.add_func (
        "/wsjtx-decode-matcher/directed-decode-returns-second-callsign",
        test_directed_decode_returns_second_callsign
    );
    Test.add_func (
        "/wsjtx-decode-matcher/directed-decode-does-not-match-first-callsign",
        test_directed_decode_does_not_match_first_callsign
    );
    Test.add_func (
        "/wsjtx-decode-matcher/directed-decode-matches-second-callsign",
        test_directed_decode_matches_second_callsign
    );
    Test.add_func (
        "/wsjtx-decode-matcher/directed-decode-with-positive-report-matches-second-callsign",
        test_directed_decode_with_positive_report_matches_second_callsign
    );
    Test.add_func (
        "/wsjtx-decode-matcher/directed-decode-with-rr73-matches-second-callsign",
        test_directed_decode_with_rr73_matches_second_callsign
    );
    Test.add_func (
        "/wsjtx-decode-matcher/bracketed-directed-decode-matches-second-callsign",
        test_bracketed_directed_decode_matches_second_callsign
    );
    Test.add_func (
        "/wsjtx-decode-matcher/bracketed-cq-decode-matches-caller",
        test_bracketed_cq_decode_matches_caller
    );
    Test.add_func (
        "/wsjtx-decode-matcher/profile-callsign-can-match-heard-callsign",
        test_profile_callsign_can_match_heard_callsign
    );
    Test.add_func (
        "/wsjtx-decode-matcher/portable-heard-callsign-matches-spot-profile",
        test_portable_heard_callsign_matches_spot_profile
    );
    Test.add_func (
        "/wsjtx-decode-matcher/directed-portable-heard-callsign-matches-spot-profile",
        test_directed_portable_heard_callsign_matches_spot_profile
    );
    Test.add_func (
        "/wsjtx-decode-matcher/non-callsign-decode-does-not-match-substrings",
        test_non_callsign_decode_does_not_match_substrings
    );

    return Test.run ();
}
