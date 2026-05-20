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
        if (normalized == "")
            return null;

        if (!normalized.down ().contains ("<eor>"))
            normalized += "<eor>";

        Artemis.Adif.Document document;
        try {
            document = Artemis.Adif.Parser.from_string (normalized);
        } catch (Artemis.Adif.Error error) {
            warning ("Unable to parse WSJT-X logged ADIF: %s", error.message);
            return null;
        }

        if (document.records.size == 0)
            return null;

        Artemis.Adif.Record record = document.records[0];

        var call = map_record_value (record, "CALL").up ();
        if (call == "")
            return null;

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
}
