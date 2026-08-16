/* tests/test-callsign-utils.vala
 *
 * Copyright 2026 Jay Baird (K0VCZ)
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

private void test_normalize_callsign_keeps_ascii_zero () {
    assert (normalize_callsign (" k0vcz ") == "K0VCZ");
}

private void test_display_callsign_uses_stroked_zero () {
    assert (display_callsign (" k0vcz/p ") == "KØVCZ/P");
}

private void test_display_callsign_preserves_calls_without_zero () {
    assert (display_callsign (" n1abc ") == "N1ABC");
}

int main (string[] args) {
    Test.init (ref args);

    Test.add_func ("/callsign-utils/normalize-ascii-zero",
        test_normalize_callsign_keeps_ascii_zero);
    Test.add_func ("/callsign-utils/display-stroked-zero",
        test_display_callsign_uses_stroked_zero);
    Test.add_func ("/callsign-utils/display-without-zero",
        test_display_callsign_preserves_calls_without_zero);

    return Test.run ();
}
