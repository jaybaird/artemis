/* tests/test-space-weather-client.vala
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

private void test_label_for_kp_thresholds () {
    assert (SpaceWeatherClient.label_for_kp (0.67) == "Very Quiet");
    assert (SpaceWeatherClient.label_for_kp (1.99) == "Very Quiet");
    assert (SpaceWeatherClient.label_for_kp (2.00) == "Quiet");
    assert (SpaceWeatherClient.label_for_kp (2.67) == "Quiet");
    assert (SpaceWeatherClient.label_for_kp (4.00) == "Unsettled");
    assert (SpaceWeatherClient.label_for_kp (5.00) == "Storm");
}

private void test_parse_planetary_kp_json_uses_latest_valid_row () {
    var snapshot = SpaceWeatherClient.parse_planetary_kp_json ("""
        [
          {"time_tag":"2026-06-12T15:00:00","Kp":1.67,"a_running":6},
          {"time_tag":"2026-06-12T18:00:00","Kp":2.00,"a_running":7},
          {"time_tag":"2026-06-12T21:00:00","Kp":3.00,"a_running":15},
          {"time_tag":"2026-06-13T00:00:00","Kp":3.00,"a_running":15},
          {"time_tag":"2026-06-13T03:00:00","Kp":3.00,"a_running":15},
          {"time_tag":"2026-06-13T06:00:00","Kp":2.67,"a_running":12},
          {"time_tag":"2026-06-13T09:00:00","Kp":2.67,"a_running":12},
          {"time_tag":"invalid","Kp":"bad"},
          {"time_tag":"2026-06-13T12:00:00","Kp":4.00,"a_running":27}
        ]
    """);

    assert (snapshot.has_kp ());
    assert (snapshot.kp == 4.00);
    assert (snapshot.a_index == 27);
    assert (snapshot.geomagnetic_label == "Unsettled");
    assert (snapshot.updated_at_utc != null);
    assert (snapshot.has_kp_history ());
    assert (snapshot.kp_history.size == 8);
    assert (snapshot.kp_history[0] == 1.67);
    assert (snapshot.kp_history[7] == 4.00);
}

private void test_parse_solar_flux_json_uses_latest_f107_flux () {
    var snapshot = SpaceWeatherClient.parse_solar_flux_json ("""
        [
          {"time_tag":"2026-06-18T17:00:00","frequency":2800,"flux":109,"reporting_schedule":"Morning"},
          {"time_tag":"2026-06-18T22:00:00","frequency":245,"flux":4,"reporting_schedule":"Afternoon"},
          {"time_tag":"2026-06-18T20:00:00","frequency":2800,"flux":111,"reporting_schedule":"Noon"}
        ]
    """);

    assert (snapshot.has_sfi ());
    assert (snapshot.sfi == 111);
    assert (snapshot.updated_at_utc != null);
}

private void test_parse_silso_sunspot_csv_uses_latest_estimated_ssn () {
    var snapshot = SpaceWeatherClient.parse_silso_sunspot_csv ("""
        2026, 06, 01, 2026.415, 116,  11.0,  32,  39,
        2026, 06, 02, 2026.418, 127,  13.8,  26,  34,
    """);

    assert (snapshot.has_ssn ());
    assert (snapshot.ssn == 127);
    assert (snapshot.updated_at_utc != null);
}

private void test_parse_xray_flux_json_uses_latest_long_channel_flux () {
    var snapshot = SpaceWeatherClient.parse_xray_flux_json ("""
        [
          {"time_tag":"2026-06-18T20:00:00Z","flux":8.0e-9,"energy":"0.05-0.4nm"},
          {"time_tag":"2026-06-18T20:00:00Z","flux":4.5e-7,"energy":"0.1-0.8nm"},
          {"time_tag":"2026-06-18T20:01:00Z","flux":4.7e-7,"energy":"0.1-0.8nm"}
        ]
    """);

    assert (snapshot.has_xray_flux ());
    assert (snapshot.xray_flux > 4.6e-7);
    assert (snapshot.xray_flux_display () == "B4.7");
    assert (snapshot.updated_at_utc != null);
}

private void test_parse_solar_wind_json_uses_latest_speed_and_density () {
    var snapshot = SpaceWeatherClient.parse_solar_wind_json ("""
        [
          ["time_tag","density","speed","temperature"],
          ["2026-06-18 20:00:00.000","6.50","365.8","31047"],
          ["2026-06-18 20:01:00.000","6.62","371.0","40276"]
        ]
    """);

    assert (snapshot.has_solar_wind_speed ());
    assert (snapshot.solar_wind_speed == 371.0);
    assert (snapshot.has_solar_wind_density ());
    assert (snapshot.solar_wind_density == 6.62);
    assert (snapshot.solar_wind_speed_display () == "371 km/s");
    assert (snapshot.updated_at_utc != null);
}

private void test_parse_planetary_kp_json_handles_malformed_payload () {
    var snapshot = SpaceWeatherClient.parse_planetary_kp_json ("{broken");
    assert (!snapshot.has_any_value ());
}

public int main (string[] args) {
    Test.init (ref args);

    Test.add_func ("/space-weather/label-for-kp-thresholds",
        test_label_for_kp_thresholds);
    Test.add_func ("/space-weather/parse-kp-json",
        test_parse_planetary_kp_json_uses_latest_valid_row);
    Test.add_func ("/space-weather/parse-solar-flux-json",
        test_parse_solar_flux_json_uses_latest_f107_flux);
    Test.add_func ("/space-weather/parse-silso-sunspot-csv",
        test_parse_silso_sunspot_csv_uses_latest_estimated_ssn);
    Test.add_func ("/space-weather/parse-xray-flux-json",
        test_parse_xray_flux_json_uses_latest_long_channel_flux);
    Test.add_func ("/space-weather/parse-solar-wind-json",
        test_parse_solar_wind_json_uses_latest_speed_and_density);
    Test.add_func ("/space-weather/malformed-json",
        test_parse_planetary_kp_json_handles_malformed_payload);

    return Test.run ();
}
