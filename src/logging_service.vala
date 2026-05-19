/* src/logging_service.vala
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

public errordomain LoggingError {
    INVALID_CONTACT,
    LOCAL_SAVE_FAILED,
    REMOTE_FAILED
}

public sealed class LoggingResult : Object {
    public bool local_saved { get; construct; }
    public bool pota_posted { get; construct; }
    public bool qrz_uploaded { get; construct; }
    public string? pota_error { get; construct; }
    public string? qrz_error { get; construct; }

    public LoggingResult (
        bool local_saved,
        bool pota_posted,
        bool qrz_uploaded,
        string? pota_error = null,
        string? qrz_error = null
    ) {
        Object (
            local_saved: local_saved,
            pota_posted: pota_posted,
            qrz_uploaded: qrz_uploaded,
            pota_error: pota_error,
            qrz_error: qrz_error
        );
    }
}

public sealed class LoggingService : Object {
    private Gee.HashSet<string> completed_logged_adif_keys = new Gee.HashSet<string> ();

    public async LoggingResult submit_spot_qso (Spot spot, bool post_to_pota = true) throws Error {
        validate_spot_qso (spot);

        Error? db_error = null;
        if (!Application.spot_database.add_qso_from_spot (spot, out db_error)) {
            throw new LoggingError.LOCAL_SAVE_FAILED (
                db_error != null ? db_error.message : "Unable to save QSO locally"
            );
        }

        bool pota_posted = false;
        bool qrz_uploaded = false;
        string? pota_error = null;
        string? qrz_error = null;

        if (post_to_pota && spot.park_ref.strip () != "") {
            try {
                yield Application.pota_client.post_spot (
                    spot.callsign,
                    spot.spotter,
                    spot.park_ref,
                    format_frequency_khz (spot.frequency_khz),
                    spot.mode,
                    spot.spotter_comment
                );
                pota_posted = true;
            } catch (Error err) {
                pota_error = err.message;
                warning ("Unable to post spot to POTA: %s", err.message);
            }
        }

        bool enable_logging = Application.settings.get_boolean ("enable-logging");
        string qrz_api_key = Application.settings.get_string ("qrz-api-key").strip ();
        if (enable_logging && qrz_api_key != "") {
            try {
                yield Application.qrz_client.upload_spot_qso (spot);
                qrz_uploaded = true;
            } catch (Error err) {
                qrz_error = err.message;
                warning ("Unable to upload QSO to QRZ: %s", err.message);
            }
        }

        return new LoggingResult (true, pota_posted, qrz_uploaded, pota_error, qrz_error);
    }

    public bool has_completed_logged_adif (string key) {
        return completed_logged_adif_keys.contains (key);
    }

    public void mark_logged_adif_completed (string key) {
        if (key != "")
            completed_logged_adif_keys.add (key);
    }

    private void validate_spot_qso (Spot spot) throws Error {
        if (spot == null) {
            throw new LoggingError.INVALID_CONTACT ("QSO is empty");
        }
        if (spot.callsign.strip () == "") {
            throw new LoggingError.INVALID_CONTACT ("Activator callsign is required");
        }
        if (spot.spotter.strip () == "") {
            throw new LoggingError.INVALID_CONTACT ("Your callsign is required");
        }
        if (spot.mode.strip () == "") {
            throw new LoggingError.INVALID_CONTACT ("Mode is required");
        }
        if (spot.frequency_khz <= 0.0) {
            throw new LoggingError.INVALID_CONTACT ("Frequency is required");
        }
    }
}
