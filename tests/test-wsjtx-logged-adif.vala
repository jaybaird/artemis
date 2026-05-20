/* tests/test-wsjtx-logged-adif.vala
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

private sealed class FakeLoggingPreferences : Object, LoggingPreferences {
    public bool enable_qrz_logging {
        get { return false; }
    }

    public string qrz_api_key {
        owned get { return ""; }
    }

    public string station_callsign {
        owned get { return "N0CALL"; }
    }

    public string spot_message {
        owned get { return "Default comment"; }
    }

    public bool enable_local_adif_log {
        get { return true; }
    }

    public string local_adif_log_path {
        owned get { return ""; }
    }
}

private FakeLoggingPreferences preferences () {
    return new FakeLoggingPreferences ();
}

private void test_logged_adif_parses_record_without_header () {
    var parsed = Artemis.Wsjtx.parse_logged_adif (
        "<CALL:5>K1ABC<MODE:3>FT8<FREQ:6>14.074<QSO_DATE:8>20260519<TIME_ON:6>153000<EOR>",
        preferences ()
    );

    assert (parsed != null);
    assert (parsed.call == "K1ABC");
    assert (parsed.mode == "FT8");
    assert (Math.fabs (parsed.frequency_khz - 14074.0) < 0.0001);
    assert (parsed.station_callsign == "N0CALL");
    assert (parsed.comment == "Default comment");
    assert (parsed.spot_time != null);
}

private void test_logged_adif_parses_empty_header_marker () {
    var parsed = Artemis.Wsjtx.parse_logged_adif (
        "<EOH><CALL:5>K1ABC<STATION_CALLSIGN:5>K0XYZ<COMMENT:5>hello<QSO_DATE:8>20260519<TIME_ON:4>1530<EOR>",
        preferences ()
    );

    assert (parsed != null);
    assert (parsed.call == "K1ABC");
    assert (parsed.station_callsign == "K0XYZ");
    assert (parsed.comment == "hello");
}

private void test_logged_adif_accepts_missing_eor_terminator () {
    var parsed = Artemis.Wsjtx.parse_logged_adif (
        "<CALL:5>K1ABC<MODE:3>FT8<QSO_DATE:8>20260519<TIME_ON:6>153000",
        preferences ()
    );

    assert (parsed != null);
    assert (parsed.call == "K1ABC");
    assert (parsed.mode == "FT8");
    assert (parsed.spot_time != null);
}

private void test_logged_adif_uses_time_off_and_preference_fallbacks () {
    var parsed = Artemis.Wsjtx.parse_logged_adif (
        "<CALL:5>K1ABC<FREQ:6>14.074<QSO_DATE:8>20260519<TIME_OFF:4>1530<EOR>",
        preferences ()
    );

    assert (parsed != null);
    assert (Math.fabs (parsed.frequency_khz - 14074.0) < 0.0001);
    assert (parsed.station_callsign == "N0CALL");
    assert (parsed.comment == "Default comment");
    assert (parsed.spot_time != null);
    assert (parsed.spot_time.to_utc ().format ("%Y%m%d%H%M%S") == "20260519153000");
}

private void test_logged_adif_treats_invalid_frequency_as_zero () {
    var parsed = Artemis.Wsjtx.parse_logged_adif (
        "<CALL:5>K1ABC<FREQ:3>abc<QSO_DATE:8>20260519<TIME_ON:6>153000<EOR>",
        preferences ()
    );

    assert (parsed != null);
    assert (parsed.frequency_khz == 0.0);
    assert (parsed.call == "K1ABC");
}

private void test_logged_adif_rejects_missing_call () {
    assert (Artemis.Wsjtx.parse_logged_adif (
        "<MODE:3>FT8<QSO_DATE:8>20260519<TIME_ON:4>1530<EOR>",
        preferences ()
    ) == null);
}

private void test_logged_adif_rejects_malformed_field_specifier () {
    Test.expect_message (
        null,
        LogLevelFlags.LEVEL_WARNING,
        "*Unable to parse WSJT-X logged ADIF*"
    );

    assert (Artemis.Wsjtx.parse_logged_adif (
        "<CALL:abc>K1ABC<QSO_DATE:8>20260519<TIME_ON:6>153000<EOR>",
        preferences ()
    ) == null);

    Test.assert_expected_messages ();
}

private void test_logged_adif_from_wsjtx () {
    var parsed = Artemis.Wsjtx.parse_logged_adif (
        "\n<adif_ver:5>3.1.0\n<programid:6>WSJT-X\n<EOH>\n<call:5>N1PRR <gridsquare:4>DM33 <mode:3>FT8 <rst_sent:3>+04 <rst_rcvd:3>-04 <qso_date:8>20260520 <time_on:6>003515 <qso_date_off:8>20260520 <time_off:6>003615 <band:3>20m <freq:9>14.075649 <station_callsign:5>K0VCZ <my_gridsquare:4>DM14 <state:2>AZ <EOR>",
        preferences ()
    );

    assert (parsed != null);
    assert (parsed.mode == "FT8");
    assert (parsed.call == "N1PRR");
}

public int main (string[] args) {
    Test.init (ref args);

    Test.add_func ("/wsjtx-logged-adif/record-without-header",
        test_logged_adif_parses_record_without_header);
    Test.add_func ("/wsjtx-logged-adif/empty-header-marker",
        test_logged_adif_parses_empty_header_marker);
    Test.add_func ("/wsjtx-logged-adif/accepts-missing-eor-terminator",
        test_logged_adif_accepts_missing_eor_terminator);
    Test.add_func ("/wsjtx-logged-adif/uses-time-off-and-preference-fallbacks",
        test_logged_adif_uses_time_off_and_preference_fallbacks);
    Test.add_func ("/wsjtx-logged-adif/treats-invalid-frequency-as-zero",
        test_logged_adif_treats_invalid_frequency_as_zero);
    Test.add_func ("/wsjtx-logged-adif/rejects-missing-call",
        test_logged_adif_rejects_missing_call);
    Test.add_func ("/wsjtx-logged-adif/rejects-malformed-field-specifier",
        test_logged_adif_rejects_malformed_field_specifier);
    Test.add_func ("/wsjtx-logged-adif/test_logged_adif_from_wsjtx",
        test_logged_adif_from_wsjtx);

    return Test.run ();
}
