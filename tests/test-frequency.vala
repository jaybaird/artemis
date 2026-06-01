/* tests/test-frequency.vala
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

private void test_frequency_parse_unit_conversions () {
    try {
        assert (Math.fabs (
            parse_frequency ("14.074", FrequencyUnit.MHZ, FrequencyUnit.KHZ) - 14074.0
        ) < 0.0001);
        assert (Math.fabs (
            parse_frequency ("14074000", FrequencyUnit.HZ, FrequencyUnit.KHZ) - 14074.0
        ) < 0.0001);
        assert (Math.fabs (
            parse_frequency ("14074", FrequencyUnit.KHZ, FrequencyUnit.MHZ) - 14.074
        ) < 0.0001);
    } catch (FrequencyError err) {
        assert_not_reached ();
    }
}

private void test_frequency_parse_invalid () {
    try {
        parse_frequency ("14.074abc", FrequencyUnit.MHZ, FrequencyUnit.KHZ);
        assert_not_reached ();
    } catch (FrequencyError err) {
        assert (err is FrequencyError.INVALID);
    }

    try {
        parse_frequency ("-14.074", FrequencyUnit.MHZ, FrequencyUnit.KHZ);
        assert_not_reached ();
    } catch (FrequencyError err) {
        assert (err is FrequencyError.INVALID);
    }

    assert (parse_mhz_to_khz_or_zero ("") == 0.0);
}

private void test_frequency_formatting () {
    assert (format_frequency_khz (14074.0) == "14074");
    assert (format_frequency_khz (14074.125) == "14074.125");
    assert (format_frequency_mhz_from_khz (14074.0) == "14.074");
    assert (format_frequency_mhz_from_khz (14000.0) == "14");
}

public int main (string[] args) {
    Test.init (ref args);

    Test.add_func ("/frequency/parse-unit-conversions", test_frequency_parse_unit_conversions);
    Test.add_func ("/frequency/parse-invalid", test_frequency_parse_invalid);
    Test.add_func ("/frequency/formatting", test_frequency_formatting);

    return Test.run ();
}
