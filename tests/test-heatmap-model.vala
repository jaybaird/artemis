/* tests/test-heatmap-model.vala
 *
 * Copyright 2026 Jay Baird (K0VCZ)
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <https://www.gnu.org/licenses/>.
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

using Gee;

private SignalReport report_for (
    string call = "K1ABC",
    string grid = "FN31",
    string band = "20m",
    string mode = "FT8",
    string source = "PSKREPORTER",
    int snr = -10,
    int64 timestamp_unix = 1000
) throws Error {
    return new SignalReport.from_grid (
        call,
        grid,
        band,
        mode,
        14.074,
        snr,
        timestamp_unix,
        source
    );
}

private void assert_close (double actual, double expected, double tolerance) {
    assert_true (Math.fabs (actual - expected) <= tolerance);
}

private Bytes bytes_from_string (string text) {
    uint8[] bytes = new uint8[text.length];
    for (int i = 0; i < text.length; i++) {
        bytes[i] = text[i];
    }

    return new Bytes.take ((owned) bytes);
}

private void test_snr_weight_clamping () {
    assert_close (HeatmapModel.snr_to_weight (-30), 0.0, 0.0001);
    assert_close (HeatmapModel.snr_to_weight (-25), 0.0, 0.0001);
    assert_close (HeatmapModel.snr_to_weight (-10), 0.5, 0.0001);
    assert_close (HeatmapModel.snr_to_weight (5), 1.0, 0.0001);
    assert_close (HeatmapModel.snr_to_weight (20), 1.0, 0.0001);
}

private void test_invalid_grid_rejection () {
    var model = new HeatmapModel ();
    var report = new SignalReport (
        "K1ABC",
        "NOPE",
        0.0,
        0.0,
        "20m",
        "FT8",
        14.074,
        -10,
        1000,
        "PSKREPORTER"
    );

    model.add_report (report);

    assert_cmpuint (model.bucket_count (), CompareOperator.EQ, 0);
    assert_cmpint (model.get_heatmap_points ().size, CompareOperator.EQ, 0);
}

private void test_valid_grid_center_conversion () throws Error {
    var center4 = Maidenhead.center ("FN31");
    assert_close (center4.latitude, 41.5, 0.0001);
    assert_close (center4.longitude, -73.0, 0.0001);

    var center6 = Maidenhead.center ("FN31pr");
    assert_close (center6.latitude, 41.7291667, 0.0001);
    assert_close (center6.longitude, -72.7083333, 0.0001);

    var center8 = Maidenhead.center ("FN31pr12");
    assert_close (center8.latitude, 41.71875, 0.0001);
    assert_close (center8.longitude, -72.7375, 0.0001);

    var center10 = Maidenhead.center ("EM12tu08wq");
    assert_close (center10.latitude, 32.8695313, 0.0001);
    assert_close (center10.longitude, -96.4088542, 0.0001);
}

private void test_bucket_deduplication () throws Error {
    var model = new HeatmapModel ();

    model.add_report (report_for ("K1ABC", "FN31", "20m", "FT8", "PSKREPORTER", -12, 1000));
    model.add_report (report_for ("K1ABC", "FN31", "20m", "FT8", "PSKREPORTER", -8, 1010));

    var points = model.get_heatmap_points_at (1010);

    assert_cmpuint (model.bucket_count (), CompareOperator.EQ, 1);
    assert_cmpint (points.size, CompareOperator.EQ, 1);
    assert_cmpuint (points[0].count, CompareOperator.EQ, 2);
    assert_cmpstr (points[0].grid, CompareOperator.EQ, "FN31");
    assert_cmpint (points[0].strongest_snr, CompareOperator.EQ, -8);
    assert_close (points[0].average_snr, -10.0, 0.0001);
    assert_cmpint ((int) points[0].latest_timestamp_unix, CompareOperator.EQ, 1010);
}

private void test_density_increases_weight () {
    var single = HeatmapModel.bucket_weight (-15, 1);
    var dense = HeatmapModel.bucket_weight (-15, 6);

    assert_true (dense > single);
}

private void test_age_decreases_weight () throws Error {
    var model = new HeatmapModel ();
    model.max_age_seconds = 100;
    model.add_report (report_for ("K1ABC", "FN31", "20m", "FT8", "PSKREPORTER", -10, 1000));

    var fresh = model.get_heatmap_points_at (1000);
    var stale = model.get_heatmap_points_at (1050);

    assert_cmpint (fresh.size, CompareOperator.EQ, 1);
    assert_cmpint (stale.size, CompareOperator.EQ, 1);
    assert_true (stale[0].weight < fresh[0].weight);
    assert_close (stale[0].weight, fresh[0].weight * 0.5, 0.0001);
}

private void test_expiration_of_old_reports () throws Error {
    var model = new HeatmapModel ();

    model.add_report (report_for ("K1ABC", "FN31", "20m", "FT8", "PSKREPORTER", -10, 1000));
    model.add_report (report_for ("K2ABC", "FN31", "20m", "FT8", "PSKREPORTER", -10, 2000));
    model.expire_reports_before (1500);

    var points = model.get_heatmap_points_at (2000);

    assert_cmpuint (model.bucket_count (), CompareOperator.EQ, 1);
    assert_cmpint (points.size, CompareOperator.EQ, 1);
    assert_true (points[0].bucket_key.has_prefix ("K2ABC|"));
}

private void test_partial_expiration_recomputes_bucket () throws Error {
    var model = new HeatmapModel ();

    model.add_report (report_for ("K1ABC", "FN31", "20m", "FT8", "PSKREPORTER", -20, 1000));
    model.add_report (report_for ("K1ABC", "FN31", "20m", "FT8", "PSKREPORTER", -5, 2000));
    model.expire_reports_before (1500);

    var points = model.get_heatmap_points_at (2000);

    assert_cmpuint (model.bucket_count (), CompareOperator.EQ, 1);
    assert_cmpint (points.size, CompareOperator.EQ, 1);
    assert_cmpuint (points[0].count, CompareOperator.EQ, 1);
    assert_cmpint (points[0].strongest_snr, CompareOperator.EQ, -5);
}

private void test_filters_by_band_mode_source () throws Error {
    var model = new HeatmapModel ();

    model.add_report (report_for ("K1ABC", "FN31", "20m", "FT8", "PSKREPORTER", -10, 1000));
    model.add_report (report_for ("K2ABC", "FN31", "40m", "FT8", "PSKREPORTER", -10, 1000));
    model.add_report (report_for ("K3ABC", "FN31", "20m", "CW", "PSKREPORTER", -10, 1000));
    model.add_report (report_for ("K4ABC", "FN31", "20m", "FT8", "LOCAL", -10, 1000));

    model.band_filter = "20m";
    assert_cmpint (model.get_heatmap_points_at (1000).size, CompareOperator.EQ, 3);

    model.mode_filter = "FT8";
    assert_cmpint (model.get_heatmap_points_at (1000).size, CompareOperator.EQ, 2);

    model.source_filter = "PSKREPORTER";
    var points = model.get_heatmap_points_at (1000);

    assert_cmpint (points.size, CompareOperator.EQ, 1);
    assert_true (points[0].bucket_key.has_prefix ("K1ABC|"));
}

private void test_bucket_key_normalization () throws Error {
    var report = report_for (" k1abc ", "fn31pr12", "20m", "ft8", "pskreporter", -10, 1000);
    var key = new SignalReportBucketKey (report);

    assert_cmpstr (key.stable_id, CompareOperator.EQ, "K1ABC|FN31|20M|FT8|PSKREPORTER");
}

private void test_bucket_grid_precision_deduplication () throws Error {
    var model = new HeatmapModel ();

    model.add_report (report_for ("K1ABC", "FN31", "20m", "FT8", "PSKREPORTER", -15, 1000));
    model.add_report (report_for ("K1ABC", "FN31pr", "20m", "FT8", "PSKREPORTER", -10, 1010));
    model.add_report (report_for ("K1ABC", "FN31pr12", "20m", "FT8", "PSKREPORTER", -5, 1020));

    var points = model.get_heatmap_points_at (1020);

    assert_cmpuint (model.bucket_count (), CompareOperator.EQ, 1);
    assert_cmpint (points.size, CompareOperator.EQ, 1);
    assert_cmpuint (points[0].count, CompareOperator.EQ, 3);
    assert_cmpstr (points[0].grid, CompareOperator.EQ, "FN31");
    assert_close (points[0].average_snr, -10.0, 0.0001);
    assert_true (points[0].bucket_key.has_prefix ("K1ABC|FN31|"));
}

private void test_bucket_statistics () throws Error {
    var bucket = new SignalReportBucket (
        new SignalReportBucketKey (report_for ("K1ABC", "FN31", "20m", "FT8", "PSKREPORTER", -15, 1000))
    );

    bucket.add_report (report_for ("K1ABC", "FN31", "20m", "FT8", "PSKREPORTER", -15, 1000));
    bucket.add_report (report_for ("K1ABC", "FN31", "20m", "FT8", "PSKREPORTER", -5, 1010));

    assert_cmpuint (bucket.count, CompareOperator.EQ, 2);
    assert_cmpint (bucket.strongest_snr, CompareOperator.EQ, -5);
    assert_close (bucket.average_snr, -10.0, 0.0001);
    assert_cmpint ((int) bucket.latest_timestamp_unix, CompareOperator.EQ, 1010);
}

private void test_bucket_retains_bounded_time_slices () throws Error {
    var model = new HeatmapModel ();

    for (var index = 0; index < 310; index++) {
        model.add_report (report_for (
            "K1ABC",
            "FN31",
            "20m",
            "FT8",
            "PSKREPORTER",
            -10,
            1000 + (index * 30)
        ));
    }

    var points = model.get_heatmap_points_at (10270);

    assert_cmpint (points.size, CompareOperator.EQ, 1);
    assert_cmpuint (points[0].count, CompareOperator.EQ, 300);
}

private void test_batch_add_emits_once () throws Error {
    var model = new HeatmapModel ();
    var reports = new ArrayList<SignalReport> ();
    uint changed_count = 0;

    model.changed.connect (() => {
        changed_count++;
    });

    reports.add (report_for ("K1ABC", "FN31", "20m", "FT8", "PSKREPORTER", -15, 1000));
    reports.add (report_for ("K2ABC", "FM18", "20m", "FT8", "PSKREPORTER", -5, 1010));
    model.add_reports (reports);

    assert_cmpuint (changed_count, CompareOperator.EQ, 1);
    assert_cmpuint (model.bucket_count (), CompareOperator.EQ, 2);
}

private void test_psk_reporter_decode_payload () throws Error {
    var payload = bytes_from_string ("{\"sq\":12345,\"f\":14074000,\"md\":\"FT8\",\"rp\":-12,\"t\":1704067200,\"sc\":\"K0VCZ\",\"rc\":\"VK2XYZ\",\"sl\":\"DM14\",\"rl\":\"QF56\",\"sa\":\"US\",\"ra\":\"AU\",\"b\":\"20m\"}");
    var report = PskReporterDecoder.decode_payload (
        "pskr/filter/v2/20m/FT8/K0VCZ/VK2XYZ/rx/12345",
        payload
    );

    assert_cmpstr (report.call, CompareOperator.EQ, "VK2XYZ");
    assert_cmpstr (report.grid, CompareOperator.EQ, "QF56");
    assert_cmpstr (report.band, CompareOperator.EQ, "20M");
    assert_cmpstr (report.mode, CompareOperator.EQ, "FT8");
    assert_cmpint (report.snr, CompareOperator.EQ, -12);
    assert_cmpint ((int) report.timestamp_unix, CompareOperator.EQ, 1704067200);
    assert_cmpstr (report.source, CompareOperator.EQ, "PSKREPORTER");
    assert_cmpstr (report.reporter, CompareOperator.EQ, "VK2XYZ");
}

private void test_psk_reporter_decode_grid10_payload () throws Error {
    var payload = bytes_from_string ("{\"sq\":12345,\"f\":14074000,\"md\":\"FT8\",\"rp\":-12,\"t\":1704067200,\"sc\":\"K0VCZ\",\"rc\":\"VK2XYZ\",\"sl\":\"DM14\",\"rl\":\"EM12tu08wq\",\"sa\":\"US\",\"ra\":\"US\",\"b\":\"20m\"}");
    var report = PskReporterDecoder.decode_payload (
        "pskr/filter/v2/20m/FT8/K0VCZ/VK2XYZ/rx/12345",
        payload
    );

    assert_cmpstr (report.grid, CompareOperator.EQ, "EM12TU08WQ");
}

private void test_psk_reporter_decode_rejects_missing_grid () {
    var payload = bytes_from_string ("{\"f\":14074000,\"md\":\"FT8\",\"rp\":-12,\"t\":1704067200,\"sc\":\"K0VCZ\",\"rc\":\"VK2XYZ\"}");

    try {
        PskReporterDecoder.decode_payload (
            "pskr/filter/v2/20m/FT8/K0VCZ/VK2XYZ/rx/12345",
            payload
        );
        error ("Expected missing grid to fail");
    } catch (Error err) {
        assert_true (err is PskReporterDecodeError);
    }
}

private void test_psk_reporter_decode_rejects_non_string_required_field () {
    var payload = bytes_from_string ("{\"f\":14074000,\"md\":\"FT8\",\"rp\":-12,\"t\":1704067200,\"sc\":\"K0VCZ\",\"rc\":123,\"rl\":\"QF56\"}");

    try {
        PskReporterDecoder.decode_payload (
            "pskr/filter/v2/20m/FT8/K0VCZ/VK2XYZ/rx/12345",
            payload
        );
        error ("Expected non-string receiver callsign to fail");
    } catch (Error err) {
        assert_true (err is PskReporterDecodeError);
    }
}

private void test_psk_reporter_xml_parse_payload () throws Error {
    var payload = bytes_from_string (
        "<?xml version=\"1.0\"?>" +
        "<receptionReports>" +
        "<receptionReport receiverCallsign=\"VK2XYZ\" receiverLocator=\"QF56ab12\" " +
        "senderCallsign=\"K0VCZ\" senderLocator=\"DM79\" frequency=\"014074000\" " +
        "flowStartSeconds=\"01704067200\" mode=\"FT8\" isSender=\"1\" " +
        "receiverDXCC=\"Australia\" receiverDXCCCode=\"150\" sNR=\"-09\"/>" +
        "<receptionReport receiverCallsign=\"BAD\" receiverLocator=\"NOPE\" " +
        "senderCallsign=\"K0VCZ\" frequency=\"14074000\" flowStartSeconds=\"1704067200\" " +
        "mode=\"FT8\" sNR=\"-9\"/>" +
        "</receptionReports>"
    );

    var reports = PskReporterClient.parse_reception_reports (payload);

    assert_cmpint (reports.size, CompareOperator.EQ, 1);
    assert_cmpstr (reports[0].call, CompareOperator.EQ, "VK2XYZ");
    assert_cmpstr (reports[0].grid, CompareOperator.EQ, "QF56AB12");
    assert_cmpstr (reports[0].band, CompareOperator.EQ, "20M");
    assert_cmpstr (reports[0].mode, CompareOperator.EQ, "FT8");
    assert_cmpint (reports[0].snr, CompareOperator.EQ, -9);
    assert_cmpint ((int) reports[0].timestamp_unix, CompareOperator.EQ, 1704067200);
    assert_cmpstr (reports[0].reporter, CompareOperator.EQ, "K0VCZ");
    assert_cmpstr (reports[0].dxcc, CompareOperator.EQ, "150");
    assert_cmpstr (reports[0].country, CompareOperator.EQ, "Australia");
}

private void test_psk_reporter_xml_rejects_partial_numeric_values () throws Error {
    var payload = bytes_from_string (
        "<?xml version=\"1.0\"?>" +
        "<receptionReports>" +
        "<receptionReport receiverCallsign=\"VK2XYZ\" receiverLocator=\"QF56ab12\" " +
        "senderCallsign=\"K0VCZ\" senderLocator=\"DM79\" frequency=\"14074000\" " +
        "flowStartSeconds=\"1704067200\" mode=\"FT8\" isSender=\"1\" " +
        "receiverDXCC=\"Australia\" receiverDXCCCode=\"150\" sNR=\"-9dB\"/>" +
        "</receptionReports>"
    );

    var reports = PskReporterClient.parse_reception_reports (payload);

    assert_cmpint (reports.size, CompareOperator.EQ, 0);
}

private void test_psk_reporter_cache_round_trip () throws Error {
    var cache_path = Path.build_filename (
        Environment.get_tmp_dir (),
        "artemis-psk-reporter-cache-%s.ini".printf (Uuid.string_random ())
    );
    var cache = new PskReporterReportCache (cache_path, 250);
    var reports = new ArrayList<SignalReport> ();

    reports.add (report_for ("VK2XYZ", "QF56ab12", "20m", "FT8", "PSKREPORTER", -9, 1704067200));
    cache.store_reports (reports, "k0vcz", new DateTime.now_utc ().to_unix ());

    var loaded = cache.get_reports (" K0VCZ ");

    assert_nonnull (loaded);
    assert_cmpint (loaded.size, CompareOperator.EQ, 1);
    assert_cmpstr (loaded[0].call, CompareOperator.EQ, "VK2XYZ");
    assert_cmpstr (loaded[0].grid, CompareOperator.EQ, "QF56AB12");

    FileUtils.remove (cache_path);
}

private void test_psk_reporter_cache_expiration () throws Error {
    var cache_path = Path.build_filename (
        Environment.get_tmp_dir (),
        "artemis-psk-reporter-cache-%s.ini".printf (Uuid.string_random ())
    );
    var cache = new PskReporterReportCache (cache_path, 1);
    var reports = new ArrayList<SignalReport> ();

    reports.add (report_for ("VK2XYZ", "QF56", "20m", "FT8", "PSKREPORTER", -9, 1704067200));
    cache.store_reports (reports, "k0vcz", new DateTime.now_utc ().to_unix () - 10);

    assert_null (cache.get_reports ("K0VCZ"));

    FileUtils.remove (cache_path);
}

public int main (string[] args) {
    Test.init (ref args);

    Test.add_func ("/heatmap-model/snr-weight-clamping", test_snr_weight_clamping);
    Test.add_func ("/heatmap-model/invalid-grid-rejection", test_invalid_grid_rejection);
    Test.add_func ("/heatmap-model/valid-grid-center-conversion", () => {
        try {
            test_valid_grid_center_conversion ();
        } catch (Error err) {
            error ("Unexpected error: %s", err.message);
        }
    });
    Test.add_func ("/heatmap-model/bucket-deduplication", () => {
        try {
            test_bucket_deduplication ();
        } catch (Error err) {
            error ("Unexpected error: %s", err.message);
        }
    });
    Test.add_func ("/heatmap-model/density-increases-weight", test_density_increases_weight);
    Test.add_func ("/heatmap-model/age-decreases-weight", () => {
        try {
            test_age_decreases_weight ();
        } catch (Error err) {
            error ("Unexpected error: %s", err.message);
        }
    });
    Test.add_func ("/heatmap-model/expiration", () => {
        try {
            test_expiration_of_old_reports ();
        } catch (Error err) {
            error ("Unexpected error: %s", err.message);
        }
    });
    Test.add_func ("/heatmap-model/partial-expiration-recomputes-bucket", () => {
        try {
            test_partial_expiration_recomputes_bucket ();
        } catch (Error err) {
            error ("Unexpected error: %s", err.message);
        }
    });
    Test.add_func ("/heatmap-model/filters", () => {
        try {
            test_filters_by_band_mode_source ();
        } catch (Error err) {
            error ("Unexpected error: %s", err.message);
        }
    });
    Test.add_func ("/heatmap-model/bucket-key-normalization", () => {
        try {
            test_bucket_key_normalization ();
        } catch (Error err) {
            error ("Unexpected error: %s", err.message);
        }
    });
    Test.add_func ("/heatmap-model/bucket-grid-precision-deduplication", () => {
        try {
            test_bucket_grid_precision_deduplication ();
        } catch (Error err) {
            error ("Unexpected error: %s", err.message);
        }
    });
    Test.add_func ("/heatmap-model/bucket-statistics", () => {
        try {
            test_bucket_statistics ();
        } catch (Error err) {
            error ("Unexpected error: %s", err.message);
        }
    });
    Test.add_func ("/heatmap-model/bucket-retains-bounded-time-slices", () => {
        try {
            test_bucket_retains_bounded_time_slices ();
        } catch (Error err) {
            error ("Unexpected error: %s", err.message);
        }
    });
    Test.add_func ("/heatmap-model/batch-add-emits-once", () => {
        try {
            test_batch_add_emits_once ();
        } catch (Error err) {
            error ("Unexpected error: %s", err.message);
        }
    });
    Test.add_func ("/heatmap-model/psk-reporter-decode-payload", () => {
        try {
            test_psk_reporter_decode_payload ();
        } catch (Error err) {
            error ("Unexpected error: %s", err.message);
        }
    });
    Test.add_func ("/heatmap-model/psk-reporter-decode-grid10-payload", () => {
        try {
            test_psk_reporter_decode_grid10_payload ();
        } catch (Error err) {
            error ("Unexpected error: %s", err.message);
        }
    });
    Test.add_func ("/heatmap-model/psk-reporter-decode-rejects-missing-grid",
        test_psk_reporter_decode_rejects_missing_grid);
    Test.add_func ("/heatmap-model/psk-reporter-decode-rejects-non-string-required-field",
        test_psk_reporter_decode_rejects_non_string_required_field);
    Test.add_func ("/heatmap-model/psk-reporter-xml-parse-payload", () => {
        try {
            test_psk_reporter_xml_parse_payload ();
        } catch (Error err) {
            error ("Unexpected error: %s", err.message);
        }
    });
    Test.add_func ("/heatmap-model/psk-reporter-xml-rejects-partial-numeric-values", () => {
        try {
            test_psk_reporter_xml_rejects_partial_numeric_values ();
        } catch (Error err) {
            error ("Unexpected error: %s", err.message);
        }
    });
    Test.add_func ("/heatmap-model/psk-reporter-cache-round-trip", () => {
        try {
            test_psk_reporter_cache_round_trip ();
        } catch (Error err) {
            error ("Unexpected error: %s", err.message);
        }
    });
    Test.add_func ("/heatmap-model/psk-reporter-cache-expiration", () => {
        try {
            test_psk_reporter_cache_expiration ();
        } catch (Error err) {
            error ("Unexpected error: %s", err.message);
        }
    });

    return Test.run ();
}
