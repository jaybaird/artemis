/* src/wsjtx/wsjtx_logged_adif_handler.vala
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

namespace Artemis.Wsjtx {
    public sealed class LoggedAdifHandler : Object {
        private const int64 CQ_POTA_CACHE_SECONDS = 30 * 60;

        public LoggingService logging_service { get; construct; }
        public SpotLookup spot_lookup { get; construct; }
        public LoggingPreferences preferences { get; construct; }
        private Gee.HashMap<string, int64?> recent_cq_pota_callsigns = new Gee.HashMap<string, int64?> ();
        private Gee.HashSet<string> in_progress_logged_qso_keys = new Gee.HashSet<string> ();

        public signal void user_message (string message);

        public LoggedAdifHandler (
            LoggingService logging_service,
            SpotLookup spot_lookup,
            LoggingPreferences preferences
        ) {
            Object (
                logging_service: logging_service,
                spot_lookup: spot_lookup,
                preferences: preferences
            );
        }

        public void remember_cq_pota_decode (string decode_text, int64 now_seconds = -1) {
            prune_recent_cq_pota_callsigns (now_seconds);

            var callsign = cq_pota_callsign_from_decode (decode_text);
            if (callsign == "")
                return;

            recent_cq_pota_callsigns[callsign] = normalized_now_seconds (now_seconds);
        }

        public async bool handle (LoggedAdifPacket packet) {
            ParsedLoggedAdif? parsed = Artemis.Wsjtx.parse_logged_adif (
                packet.adif,
                preferences
            );
            if (parsed == null)
                return false;

            return yield handle_parsed (parsed, packet.adif, "Logged ADIF");
        }

        public async bool handle_qso_logged (QsoLoggedPacket packet) {
            ParsedLoggedAdif? parsed = Artemis.Wsjtx.parse_qso_logged (
                packet,
                preferences
            );
            if (parsed == null)
                return false;

            return yield handle_parsed (parsed, null, "QSO Logged");
        }

        private async bool handle_parsed (
            ParsedLoggedAdif parsed,
            string? source_adif,
            string source_name
        ) {
            prune_recent_cq_pota_callsigns ();

            var active_spot = spot_lookup.get_spot_for_callsign (parsed.call);
            var matched_live_spot = active_spot != null;
            var matched_recent_cq_pota = has_recent_cq_pota_callsign (parsed.call);
            if (!matched_live_spot && !matched_recent_cq_pota) {
                message (
                    "Skipping WSJT-X %s QSO for %s: no matching live spot or recent CQ POTA decode",
                    source_name,
                    parsed.call
                );
                return false;
            }

            var park_ref = active_spot != null ? active_spot.park_ref : "";
            var mode = parsed.mode != "" ? parsed.mode : active_spot != null ? active_spot.mode : "";
            var frequency_khz = parsed.frequency_khz > 0.0 ?
                parsed.frequency_khz :
                active_spot != null ? active_spot.frequency_khz : 0.0;
            var dedupe_key = logged_qso_key (parsed, park_ref, mode, frequency_khz);

            if (logging_service.has_completed_logged_adif (dedupe_key) ||
                in_progress_logged_qso_keys.contains (dedupe_key)) {
                message (
                    "Skipping WSJT-X %s QSO for %s: duplicate logged QSO",
                    source_name,
                    parsed.call
                );
                return false;
            }

            in_progress_logged_qso_keys.add (dedupe_key);

            if ((mode == "") || (frequency_khz <= 0.0) ||
                (parsed.station_callsign == "") || (parsed.spot_time == null)) {
                in_progress_logged_qso_keys.remove (dedupe_key);
                warning ("Skipping WSJT-X %s QSO for %s: QSO record missing required fields",
                    source_name,
                    parsed.call);
                return false;
            }

            var draft = new QsoDraft (
                parsed.call,
                park_ref,
                parsed.spot_time,
                frequency_khz,
                mode,
                parsed.station_callsign,
                parsed.comment,
                parsed.rst_sent,
                parsed.rst_rcvd
            );

            try {
                message (
                    "WSJT-X %s QRZ forwarding for %s @ %s: forward_wsjtx_qsos_to_qrz=%s",
                    source_name,
                    parsed.call,
                    park_ref,
                    preferences.forward_wsjtx_qsos_to_qrz.to_string ()
                );
                var qrz_adif = preferences.forward_wsjtx_qsos_to_qrz ?
                    build_qrz_adif (source_adif, parsed, active_spot) :
                    null;
                var result = yield logging_service.submit_qso_draft_with_qrz_mode (
                    draft,
                    park_ref != "",
                    preferences.forward_wsjtx_qsos_to_qrz ?
                        QrzUploadMode.ENABLED :
                        QrzUploadMode.DISABLED,
                    qrz_adif
                );
                logging_service.mark_logged_adif_completed (dedupe_key);
                in_progress_logged_qso_keys.remove (dedupe_key);
                if (result.local_saved && result.pota_posted)
                    user_message (_("WSJT-X QSO saved; POTA spot posted"));
                else if (result.local_saved)
                    user_message (_("WSJT-X QSO saved"));
                if (result.local_adif_error != null)
                    user_message (_("WSJT-X QSO saved locally; ADIF log failed"));
                if (result.pota_error != null)
                    user_message (_("WSJT-X QSO saved locally; POTA spot failed"));
                if (result.qrz_error != null)
                    user_message (_("WSJT-X QSO saved locally; QRZ upload failed"));
                return true;
            } catch (Error err) {
                warning ("Unable to auto spot WSJT-X %s POTA contact %s: %s",
                    source_name,
                    parsed.call,
                    err.message);
            }

            in_progress_logged_qso_keys.remove (dedupe_key);
            return false;
        }

        private bool has_recent_cq_pota_callsign (string callsign) {
            var normalized = normalize_callsign (callsign);
            return normalized != "" && recent_cq_pota_callsigns.has_key (normalized);
        }

        private void prune_recent_cq_pota_callsigns (int64 now_seconds = -1) {
            var now = normalized_now_seconds (now_seconds);
            var expired = new Gee.ArrayList<string> ();
            foreach (var entry in recent_cq_pota_callsigns.entries) {
                if (now - entry.value > CQ_POTA_CACHE_SECONDS)
                    expired.add (entry.key);
            }

            foreach (var callsign in expired)
                recent_cq_pota_callsigns.unset (callsign);
        }

        private static int64 normalized_now_seconds (int64 now_seconds) {
            if (now_seconds >= 0)
                return now_seconds;

            return GLib.get_monotonic_time () / 1000000;
        }

        private static string cq_pota_callsign_from_decode (string decode_text) {
            var normalized = decode_text.strip ().up ();
            if (normalized == "")
                return "";

            var tokens = new Gee.ArrayList<string> ();
            foreach (var token in normalized.split (" ")) {
                if (token != "")
                    tokens.add (token);
            }

            for (var i = 0; i + 2 < tokens.size; i++) {
                if (tokens[i] == "CQ" && tokens[i + 1] == "POTA")
                    return normalize_callsign (tokens[i + 2]);
            }

            return "";
        }

        private static string normalize_callsign (string callsign) {
            return callsign.strip ().up ();
        }

        private static string logged_qso_key (
            ParsedLoggedAdif parsed,
            string park_ref,
            string mode,
            double frequency_khz
        ) {
            var qso_time = parsed.spot_time != null ?
                parsed.spot_time.to_utc ().format ("%Y%m%d%H%M%S") :
                "";
            return "%s|%s|%s|%s|%s".printf (
                normalize_callsign (parsed.call),
                park_ref.strip ().up (),
                mode.strip ().up (),
                format_frequency_khz (frequency_khz),
                qso_time
            );
        }

        private static string build_qrz_adif (
            string? adif_text,
            ParsedLoggedAdif parsed,
            Spot? active_spot
        ) throws Artemis.Adif.Error {
            var normalized = (adif_text ?? "").strip ();
            if (!normalized.down ().contains ("<eor>"))
                normalized += "<eor>";

            Artemis.Adif.Document document;
            if (normalized != "<eor>") {
                document = Artemis.Adif.Parser.from_string (normalized);
                if (document.records.size == 0)
                    throw new Artemis.Adif.Error.INVALID_VALUE ("ADIF document has no QSO record");
            } else {
                document = new Artemis.Adif.Document ();
                document.records.add (new Artemis.Adif.Record ());
            }

            var record = document.records[0];
            set_record_field_if_missing (record, "CALL", parsed.call);
            set_record_field_if_missing (record, "STATION_CALLSIGN", parsed.station_callsign);
            set_record_field_if_missing (record, "MODE", parsed.mode);
            if (parsed.frequency_khz > 0.0) {
                set_record_field_if_missing (
                    record,
                    "FREQ",
                    format_frequency_mhz_from_khz (parsed.frequency_khz)
                );
            }
            if (has_text (parsed.comment))
                set_record_field_if_missing (record, "COMMENT", parsed.comment);

            if (parsed.spot_time != null) {
                var qso_time = parsed.spot_time.to_utc ();
                set_record_field_if_missing (record, "QSO_DATE", qso_time.format ("%Y%m%d"));
                set_record_field_if_missing (record, "TIME_ON", qso_time.format ("%H%M%S"));
            }

            var park_ref = active_spot != null ? active_spot.park_ref : "";
            var grid_square = active_spot != null ?
                first_non_empty (active_spot.grid6, active_spot.grid4) :
                "";
            if (has_text (grid_square))
                record.set ("GRIDSQUARE", grid_square);

            if (has_text (park_ref)) {
                set_record_field_if_missing (record, "SIG", "POTA");
                set_record_field_if_missing (record, "SIG_INFO", park_ref);
                set_record_field_if_missing (record, "POTA_REF", park_ref);
                set_record_field_if_missing (record, "NOTES", "POTA - %s".printf (park_ref));
            }

            return Artemis.Adif.Generator.to_string (document);
        }

        private static void set_record_field_if_missing (
            Artemis.Adif.Record record,
            string name,
            string value
        ) throws Artemis.Adif.Error {
            if (has_text (record.get (name)) || !has_text (value))
                return;

            record.set (name, value);
        }

    }
}
