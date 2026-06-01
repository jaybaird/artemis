/* tests/test-wsjtx-logged-adif.vala
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

private sealed class FakeLoggingPreferences : Object, LoggingPreferences {
    public bool qrz_enabled = false;
    public bool forward_wsjtx_qrz = false;
    public string api_key = "";

    public bool enable_qrz_logging {
        get { return qrz_enabled; }
    }

    public bool forward_wsjtx_qsos_to_qrz {
        get { return forward_wsjtx_qrz; }
    }

    public string qrz_api_key {
        owned get { return api_key; }
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

public interface LocalAdifWriter : Object {
    public abstract void append_spot_qso (Spot spot, string configured_path = "") throws Error;
}

private FakeLoggingPreferences preferences () {
    return new FakeLoggingPreferences ();
}

public class Spot : Object {
    public string callsign { get; construct; }
    public string park_ref { get; construct; }
    public string mode { get; construct; }
    public double frequency_khz { get; construct; }
    public DateTime spot_time { get; construct; }
    public string spotter { get; construct; }
    public string spotter_comment { get; construct; }
    public string? rst_sent { get; construct; }
    public string? rst_rcvd { get; construct; }

    public string band {
        owned get { return "20m"; }
    }

    public Spot.from_add_spot (
        string callsign,
        string park_ref,
        DateTime spot_time,
        string frequency_khz,
        string mode,
        string spotter,
        string spotter_comment,
        string rst_sent,
        string rst_rcvd
    ) {
        Object (
            callsign: callsign,
            park_ref: park_ref,
            spot_time: spot_time,
            frequency_khz: parse_khz_or_zero (frequency_khz),
            mode: mode,
            spotter: spotter,
            spotter_comment: spotter_comment,
            rst_sent: rst_sent,
            rst_rcvd: rst_rcvd
        );
    }

    public Spot.with_values (
        string callsign,
        string park_ref,
        string mode,
        double frequency_khz,
        DateTime spot_time,
        string spotter = "K0VCZ"
    ) {
        Object (
            callsign: callsign,
            park_ref: park_ref,
            mode: mode,
            frequency_khz: frequency_khz,
            spot_time: spot_time,
            spotter: spotter,
            spotter_comment: ""
        );
    }
}

private sealed class FakeSpotLookup : Object, Artemis.Wsjtx.SpotLookup {
    public Spot? spot = null;

    public Spot? get_spot_for_callsign (string callsign) {
        if (spot == null)
            return null;

        return spot.callsign == callsign.strip ().up () ? spot : null;
    }
}

private sealed class FakeQsoStore : Object, QsoStore {
    public int saved_count = 0;
    public Spot? last_spot = null;

    public bool add_qso_from_spot (Spot spot, out Error? error) {
        error = null;
        saved_count++;
        last_spot = spot;
        return true;
    }

    public bool update_qso_delivery_status (
        Spot spot,
        bool local_adif_saved,
        bool pota_posted,
        bool qrz_uploaded,
        string? local_adif_error,
        string? pota_error,
        string? qrz_error,
        out Error? error
    ) {
        error = null;
        return true;
    }
}

private sealed class FakePotaPoster : Object, PotaSpotPoster {
    public int post_count = 0;

    public async void post_spot (
        string activator,
        string spotter,
        string reference,
        string frequency,
        string mode,
        string comment
    ) throws Error {
        post_count++;
    }
}

private sealed class FakeQrzUploader : Object, QrzQsoUploader {
    public int upload_count = 0;
    public string last_adif = "";

    public async void upload_spot_qso (Spot spot) throws Error {
        upload_count++;
    }

    public async void upload_adif_record (string adif) throws Error {
        upload_count++;
        last_adif = adif;
    }
}

private sealed class FakeLocalAdifWriter : Object, LocalAdifWriter {
    public int append_count = 0;

    public void append_spot_qso (Spot spot, string configured_path = "") throws Error {
        append_count++;
    }
}

private sealed class HandlerFixture {
    public FakeLoggingPreferences preferences;
    public FakeSpotLookup spot_lookup;
    public FakeQsoStore qso_store;
    public FakePotaPoster pota_poster;
    public FakeQrzUploader qrz_uploader;
    public FakeLocalAdifWriter adif_writer;
    public LoggingService logging_service;
    public Artemis.Wsjtx.LoggedAdifHandler handler;

    public HandlerFixture () {
        preferences = new FakeLoggingPreferences ();
        spot_lookup = new FakeSpotLookup ();
        qso_store = new FakeQsoStore ();
        pota_poster = new FakePotaPoster ();
        qrz_uploader = new FakeQrzUploader ();
        adif_writer = new FakeLocalAdifWriter ();
        logging_service = new LoggingService (
            qso_store,
            pota_poster,
            qrz_uploader,
            adif_writer,
            preferences
        );
        handler = new Artemis.Wsjtx.LoggedAdifHandler (
            logging_service,
            spot_lookup,
            preferences
        );
    }
}

private Artemis.Wsjtx.LoggedAdifPacket logged_adif_packet (string call = "K1ABC") {
    Artemis.Wsjtx.LoggedAdifPacket packet = {};
    packet.adif = "<CALL:%d>%s<MODE:3>FT8<FREQ:6>14.074<QSO_DATE:8>20260519<TIME_ON:6>153000<EOR>".printf (
        call.length,
        call
    );
    return packet;
}

private bool run_handler (Artemis.Wsjtx.LoggedAdifHandler handler, Artemis.Wsjtx.LoggedAdifPacket packet) {
    var loop = new MainLoop ();
    var handled = false;
    handler.handle.begin (packet, (obj, res) => {
        handled = handler.handle.end (res);
        loop.quit ();
    });
    loop.run ();
    return handled;
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

private void test_handler_skips_non_pota_qso () {
    var fixture = new HandlerFixture ();

    assert (!run_handler (fixture.handler, logged_adif_packet ()));
    assert (fixture.qso_store.saved_count == 0);
    assert (fixture.adif_writer.append_count == 0);
    assert (fixture.pota_poster.post_count == 0);
    assert (fixture.qrz_uploader.upload_count == 0);
}

private void test_handler_logs_matching_spot () {
    var fixture = new HandlerFixture ();
    fixture.spot_lookup.spot = new Spot.with_values (
        "K1ABC",
        "US-0001",
        "FT8",
        14074.0,
        new DateTime.from_iso8601 ("2026-05-19T15:30:00Z", new TimeZone.utc ())
    );

    assert (run_handler (fixture.handler, logged_adif_packet ()));
    assert (fixture.qso_store.saved_count == 1);
    assert (fixture.qso_store.last_spot.park_ref == "US-0001");
    assert (fixture.adif_writer.append_count == 1);
    assert (fixture.pota_poster.post_count == 1);
}

private void test_handler_logs_recent_cq_pota_without_park () {
    var fixture = new HandlerFixture ();
    fixture.handler.remember_cq_pota_decode ("153000 -10 0.1 700 ~ CQ  POTA  K1ABC DM33");

    assert (run_handler (fixture.handler, logged_adif_packet ()));
    assert (fixture.qso_store.saved_count == 1);
    assert (fixture.qso_store.last_spot.park_ref == "");
    assert (fixture.adif_writer.append_count == 1);
    assert (fixture.pota_poster.post_count == 0);
}

private void test_handler_ignores_expired_cq_pota () {
    var fixture = new HandlerFixture ();
    fixture.handler.remember_cq_pota_decode ("CQ POTA K1ABC", 0);

    assert (!run_handler (fixture.handler, logged_adif_packet ()));
    assert (fixture.qso_store.saved_count == 0);
}

private void test_handler_respects_wsjtx_qrz_toggle () {
    var fixture = new HandlerFixture ();
    fixture.preferences.api_key = "test-key";
    fixture.preferences.qrz_enabled = true;
    fixture.preferences.forward_wsjtx_qrz = false;
    fixture.handler.remember_cq_pota_decode ("CQ POTA K1ABC");

    assert (run_handler (fixture.handler, logged_adif_packet ()));
    assert (fixture.qrz_uploader.upload_count == 0);

    fixture = new HandlerFixture ();
    fixture.preferences.api_key = "test-key";
    fixture.preferences.qrz_enabled = false;
    fixture.preferences.forward_wsjtx_qrz = true;
    fixture.handler.remember_cq_pota_decode ("CQ POTA K1ABC");

    assert (run_handler (fixture.handler, logged_adif_packet ()));
    assert (fixture.qrz_uploader.upload_count == 1);
}

private void test_handler_uploads_original_wsjtx_adif_comment_to_qrz () {
    var fixture = new HandlerFixture ();
    fixture.preferences.api_key = "test-key";
    fixture.preferences.forward_wsjtx_qrz = true;
    fixture.spot_lookup.spot = new Spot.with_values (
        "K1ABC",
        "US-0001",
        "FT8",
        14074.0,
        new DateTime.from_iso8601 ("2026-05-19T15:30:00Z", new TimeZone.utc ())
    );

    Artemis.Wsjtx.LoggedAdifPacket packet = {};
    packet.adif = "<CALL:5>K1ABC<MODE:3>FT8<FREQ:6>14.074<QSO_DATE:8>20260519<TIME_ON:6>153000<COMMENT:15>from wsjt-x log<EOR>";

    assert (run_handler (fixture.handler, packet));
    assert (fixture.qrz_uploader.upload_count == 1);
    assert (fixture.qrz_uploader.last_adif.contains ("<COMMENT:15>from wsjt-x log"));
    assert (fixture.qrz_uploader.last_adif.contains ("<POTA_REF:7>US-0001"));
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
    Test.add_func ("/wsjtx-logged-adif/handler-skips-non-pota-qso",
        test_handler_skips_non_pota_qso);
    Test.add_func ("/wsjtx-logged-adif/handler-logs-matching-spot",
        test_handler_logs_matching_spot);
    Test.add_func ("/wsjtx-logged-adif/handler-logs-recent-cq-pota-without-park",
        test_handler_logs_recent_cq_pota_without_park);
    Test.add_func ("/wsjtx-logged-adif/handler-ignores-expired-cq-pota",
        test_handler_ignores_expired_cq_pota);
    Test.add_func ("/wsjtx-logged-adif/handler-respects-wsjtx-qrz-toggle",
        test_handler_respects_wsjtx_qrz_toggle);
    Test.add_func ("/wsjtx-logged-adif/handler-uploads-original-wsjtx-adif-comment-to-qrz",
        test_handler_uploads_original_wsjtx_adif_comment_to_qrz);

    return Test.run ();
}
