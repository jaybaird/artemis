/* src/wsjtx/wsjtx_logged_adif_handler.vala
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

namespace Artemis.Wsjtx {
    public sealed class LoggedAdifHandler : Object {
        public LoggingService logging_service { get; construct; }
        public SpotRepo spot_repo { get; construct; }
        public LoggingPreferences preferences { get; construct; }

        public signal void user_message (string message);

        public LoggedAdifHandler (
            LoggingService logging_service,
            SpotRepo spot_repo,
            LoggingPreferences preferences
        ) {
            Object (
                logging_service: logging_service,
                spot_repo: spot_repo,
                preferences: preferences
            );
        }

        public async void handle (LoggedAdifPacket packet) {
            ParsedLoggedAdif? parsed = Artemis.Wsjtx.parse_logged_adif (
                packet.adif,
                preferences
            );
            if (parsed == null)
                return;

            var active_spot = spot_repo.get_spot_for_callsign (parsed.call);
            var park_ref = active_spot != null ? active_spot.park_ref : "";
            var mode = parsed.mode != "" ? parsed.mode : active_spot != null ? active_spot.mode : "";
            var frequency_khz = parsed.frequency_khz > 0.0 ?
                parsed.frequency_khz :
                active_spot != null ? active_spot.frequency_khz : 0.0;
            var dedupe_key = "%s|%s|%s".printf (
                parsed.dedupe_key,
                park_ref,
                mode
            );

            if (logging_service.has_completed_logged_adif (dedupe_key))
                return;

            if ((mode == "") || (frequency_khz <= 0.0) ||
                (parsed.station_callsign == "") || (parsed.spot_time == null)) {
                warning ("Skipping WSJT-X logged QSO for %s: ADIF record missing required fields",
                    parsed.call);
                return;
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
                var result = yield logging_service.submit_qso_draft (
                    draft,
                    park_ref != ""
                );
                logging_service.mark_logged_adif_completed (dedupe_key);
                if (result.local_adif_error != null)
                    user_message (_("WSJT-X QSO saved locally; ADIF log failed"));
                if (result.pota_error != null)
                    user_message (_("WSJT-X QSO saved locally; POTA spot failed"));
                if (result.qrz_error != null)
                    user_message (_("WSJT-X QSO saved locally; QRZ upload failed"));
            } catch (Error err) {
                warning ("Unable to auto spot WSJT-X POTA contact %s: %s",
                    parsed.call,
                    err.message);
            }
        }

    }
}
