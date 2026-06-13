/* tests/test-space-weather-client.vala
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

private void test_label_for_kp_thresholds () {
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

private void test_parse_wwv_text_extracts_partial_snapshot () {
    var snapshot = SpaceWeatherClient.parse_wwv_text ("""
        :Product: Geophysical Alert Message wwv.txt
        :Issued: 2026 Jun 13 1510 UTC
        Solar-terrestrial indices for 12 June follow.
        Solar flux 128 and estimated planetary A-index 16.
        The estimated planetary K-index at 1500 UTC on 13 June was 2.67.
    """);

    assert (snapshot.sfi == 128);
    assert (snapshot.a_index == 16);
    assert (snapshot.kp == 2.67);
    assert (snapshot.updated_at_utc != null);
}

private void test_parse_wwv_text_allows_missing_sfi () {
    var snapshot = SpaceWeatherClient.parse_wwv_text ("""
        :Product: Geophysical Alert Message wwv.txt
        :Issued: 2026 Jun 13 1510 UTC
        The estimated planetary K-index at 1500 UTC on 13 June was 2.67.
    """);

    assert (!snapshot.has_sfi ());
    assert (snapshot.has_kp ());
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
    Test.add_func ("/space-weather/parse-wwv-text",
        test_parse_wwv_text_extracts_partial_snapshot);
    Test.add_func ("/space-weather/missing-sfi",
        test_parse_wwv_text_allows_missing_sfi);
    Test.add_func ("/space-weather/malformed-json",
        test_parse_planetary_kp_json_handles_malformed_payload);

    return Test.run ();
}
