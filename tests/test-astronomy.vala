/* tests/test-astronomy.vala
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

private DateTime utc_time (int hour, int minute = 0) {
    return new DateTime.utc (2026, 6, 2, hour, minute, 0.0);
}

private void test_shift_for_prime_meridian () {
    assert (Astronomy.shift_for_longitude (0.0, utc_time (17, 59)) == Astronomy.Shift.NORMAL);
    assert (Astronomy.shift_for_longitude (0.0, utc_time (2)) == Astronomy.Shift.EARLY);
    assert (Astronomy.shift_for_longitude (0.0, utc_time (7, 59)) == Astronomy.Shift.EARLY);
    assert (Astronomy.shift_for_longitude (0.0, utc_time (8)) == Astronomy.Shift.NORMAL);
    assert (Astronomy.shift_for_longitude (0.0, utc_time (18)) == Astronomy.Shift.LATE);
    assert (Astronomy.shift_for_longitude (0.0, utc_time (1, 59)) == Astronomy.Shift.LATE);
}

private void test_shift_for_western_grid () {
    try {
        assert (Astronomy.shift_for_grid ("EN45", utc_time (0)) == Astronomy.Shift.LATE);
        assert (Astronomy.shift_for_grid ("EN45", utc_time (7, 59)) == Astronomy.Shift.LATE);
        assert (Astronomy.shift_for_grid ("EN45", utc_time (8)) == Astronomy.Shift.EARLY);
        assert (Astronomy.shift_for_grid ("EN45AA", utc_time (13, 59)) == Astronomy.Shift.EARLY);
        assert (Astronomy.shift_for_grid ("EN45AA", utc_time (14)) == Astronomy.Shift.NORMAL);
    } catch (Error err) {
        error ("Grid shift lookup failed: %s", err.message);
    }
}

private void test_shift_wraps_around_utc_day () {
    assert (Astronomy.shift_for_longitude (-180.0, utc_time (5, 59)) == Astronomy.Shift.NORMAL);
    assert (Astronomy.shift_for_longitude (-180.0, utc_time (14)) == Astronomy.Shift.EARLY);
    assert (Astronomy.shift_for_longitude (-180.0, utc_time (19, 59)) == Astronomy.Shift.EARLY);
    assert (Astronomy.shift_for_longitude (-180.0, utc_time (20)) == Astronomy.Shift.NORMAL);
    assert (Astronomy.shift_for_longitude (-180.0, utc_time (6)) == Astronomy.Shift.LATE);
    assert (Astronomy.shift_for_longitude (-180.0, utc_time (13, 59)) == Astronomy.Shift.LATE);
}

private void test_shift_rejects_invalid_grid () {
    try {
        Astronomy.shift_for_grid ("BAD", utc_time (12));
        assert_not_reached ();
    } catch (MaidenheadLocatorError err) {
        assert (err is MaidenheadLocatorError.INVALID_LENGTH);
    } catch (Error err) {
        assert_not_reached ();
    }
}

public int main (string[] args) {
    Test.init (ref args);

    Test.add_func ("/astronomy/shift-for-prime-meridian", test_shift_for_prime_meridian);
    Test.add_func ("/astronomy/shift-for-western-grid", test_shift_for_western_grid);
    Test.add_func ("/astronomy/shift-wraps-around-utc-day", test_shift_wraps_around_utc_day);
    Test.add_func ("/astronomy/shift-rejects-invalid-grid", test_shift_rejects_invalid_grid);

    return Test.run ();
}
