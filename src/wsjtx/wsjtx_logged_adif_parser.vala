/* src/wsjtx/wsjtx_logged_adif_parser.vala
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

namespace Artemis.Wsjtx {
    public struct ParsedLoggedAdif {
        public string call;
        public string station_callsign;
        public string mode;
        public double frequency_khz;
        public string rst_sent;
        public string rst_rcvd;
        public string comment;
        public DateTime? spot_time;
        public string dedupe_key;
    }

    public static ParsedLoggedAdif? parse_logged_adif (
        string adif_text,
        LoggingPreferences preferences
    ) {
        string normalized = adif_text.strip ();
        if (normalized == "") {
            warning ("Unable to parse WSJT-X logged ADIF: ADIF text is empty");
            return null;
        }

        if (!normalized.down ().contains ("<eor>"))
            normalized += "<eor>";

        Artemis.Adif.Document document;
        try {
            document = Artemis.Adif.Parser.from_string (normalized);
        } catch (Artemis.Adif.Error error) {
            warning ("Unable to parse WSJT-X logged ADIF: %s", error.message);
            return null;
        }

        if (document.records.size == 0) {
            warning ("Unable to parse WSJT-X logged ADIF: no QSO records found");
            return null;
        }

        Artemis.Adif.Record record = document.records[0];

        var call = map_record_value (record, "CALL").up ();
        if (call == "") {
            warning ("Unable to parse WSJT-X logged ADIF: QSO record is missing CALL");
            return null;
        }

        var mode = map_record_value (record, "MODE").up ();
        var frequency_khz = parse_mhz_to_khz_or_zero (map_record_value (record, "FREQ"));
        var station_callsign = first_non_empty (
            map_record_value (record, "STATION_CALLSIGN"),
            preferences.station_callsign
        );
        var comment = first_non_empty (
            map_record_value (record, "COMMENT"),
            map_record_value (record, "NOTES"),
            preferences.spot_message
        );
        var qso_date = map_record_value (record, "QSO_DATE");
        var time_on = first_non_empty (
            map_record_value (record, "TIME_ON"),
            map_record_value (record, "TIME_OFF")
        );

        ParsedLoggedAdif parsed = {};
        parsed.call = call;
        parsed.station_callsign = station_callsign.up ();
        parsed.mode = mode;
        parsed.frequency_khz = frequency_khz;
        parsed.rst_sent = map_record_value (record, "RST_SENT");
        parsed.rst_rcvd = map_record_value (record, "RST_RCVD");
        parsed.comment = comment;
        parsed.spot_time = Artemis.Adif.parse_qso_datetime_utc (qso_date, time_on);
        parsed.dedupe_key = "%s|%s|%s|%s".printf (
            call,
            "",
            qso_date,
            time_on
        );

        return parsed;
    }

    public static ParsedLoggedAdif? parse_qso_logged (
        QsoLoggedPacket packet,
        LoggingPreferences preferences
    ) {
        var call = normalize_callsign (packet.dx_call);
        if (call == "") {
            warning ("Unable to parse WSJT-X QSO Logged packet: DX call is empty");
            return null;
        }

        var spot_time = qdatetime_to_utc (packet.time_on);
        if (spot_time == null)
            spot_time = qdatetime_to_utc (packet.time_off);

        var qso_date = spot_time != null ? spot_time.to_utc ().format ("%Y%m%d") : "";
        var time_on = spot_time != null ? spot_time.to_utc ().format ("%H%M%S") : "";
        var station_callsign = first_non_empty (
            packet.operator_call,
            packet.my_call,
            preferences.station_callsign
        );

        ParsedLoggedAdif parsed = {};
        parsed.call = call;
        parsed.station_callsign = station_callsign.up ();
        parsed.mode = strip_up (packet.mode);
        parsed.frequency_khz = (double) packet.tx_frequency_hz / 1000.0;
        parsed.rst_sent = packet.report_sent.strip ();
        parsed.rst_rcvd = packet.report_received.strip ();
        parsed.comment = first_non_empty (packet.comments, preferences.spot_message);
        parsed.spot_time = spot_time;
        parsed.dedupe_key = "%s|%s|%s|%s".printf (
            call,
            "",
            qso_date,
            time_on
        );

        return parsed;
    }

    private static string map_record_value (Artemis.Adif.Record record, string key) {
        var value = record.get (key);
        return value != null ? value.strip () : "";
    }

    private static string first_non_empty (string first, string second = "", string third = "") {
        if (first.strip () != "")
            return first.strip ();
        if (second.strip () != "")
            return second.strip ();
        return third.strip ();
    }

    private static DateTime? qdatetime_to_utc (WsjtxDateTime value) {
        if (value.julian_day <= 0)
            return null;

        int year;
        int month;
        int day;
        julian_day_to_gregorian (value.julian_day, out year, out month, out day);

        var hour = (int) (value.msecs_since_midnight / 3600000);
        var minute = (int) ((value.msecs_since_midnight / 60000) % 60);
        var second = (int) ((value.msecs_since_midnight / 1000) % 60);
        var millisecond = (int) (value.msecs_since_midnight % 1000);
        var datetime = new DateTime.utc (
            year,
            month,
            day,
            hour,
            minute,
            second + ((double) millisecond / 1000.0)
        );

        if (value.time_spec == 2)
            datetime = datetime.add_seconds (-value.utc_offset_seconds);

        return datetime;
    }

    private static void julian_day_to_gregorian (
        int64 julian_day,
        out int year,
        out int month,
        out int day
    ) {
        var l = julian_day + 68569;
        var n = (4 * l) / 146097;
        l = l - (146097 * n + 3) / 4;
        var i = (4000 * (l + 1)) / 1461001;
        l = l - (1461 * i) / 4 + 31;
        var j = (80 * l) / 2447;
        day = (int) (l - (2447 * j) / 80);
        l = j / 11;
        month = (int) (j + 2 - 12 * l);
        year = (int) (100 * (n - 49) + i + l);
    }
}
