/* src/logging_service.vala
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

public errordomain LoggingError {
    INVALID_CONTACT,
    LOCAL_SAVE_FAILED,
    REMOTE_FAILED
}

public enum QrzUploadMode {
    DEFAULT,
    ENABLED,
    DISABLED
}

public interface QsoStore : Object {
    public abstract bool add_qso_from_spot (
        Spot spot,
        out bool inserted,
        out Error? error
    );
    public abstract bool update_qso_delivery_status (
        Spot spot,
        bool local_adif_saved,
        bool pota_posted,
        bool qrz_uploaded,
        string? local_adif_error,
        string? pota_error,
        string? qrz_error,
        out Error? error
    );
}

public interface PotaSpotPoster : Object {
    public abstract async void post_spot (
        string activator,
        string spotter,
        string reference,
        string frequency,
        string mode,
        string comment
    ) throws Error;
}

public interface QrzQsoUploader : Object {
    public abstract async void upload_spot_qso (Spot spot) throws Error;
    public abstract async void upload_adif_record (string adif) throws Error;
}

[Compact (opaque=true)]
public class QsoDraft {
    public string callsign { get; }
    public string park_ref { get; }
    public DateTime spot_time { get; }
    public double frequency_khz { get; }
    public string mode { get; }
    public string spotter { get; }
    public string spotter_comment { get; }
    public string rst_sent { get; }
    public string rst_rcvd { get; }

    public QsoDraft (
        string callsign,
        string park_ref,
        DateTime spot_time,
        double frequency_khz,
        string mode,
        string spotter,
        string spotter_comment,
        string rst_sent,
        string rst_rcvd
    ) {
        _callsign = callsign;
        _park_ref = park_ref;
        _spot_time = spot_time;
        _frequency_khz = frequency_khz;
        _mode = mode;
        _spotter = spotter;
        _spotter_comment = spotter_comment;
        _rst_sent = rst_sent;
        _rst_rcvd = rst_rcvd;
    }

    public QsoDraft.from_user_input (
        string callsign,
        string park_ref,
        DateTime spot_time,
        string frequency_text,
        string mode,
        string spotter,
        string spotter_comment,
        string rst_sent,
        string rst_rcvd
    ) {
        _callsign = callsign;
        _park_ref = park_ref;
        _spot_time = spot_time;
        _frequency_khz = parse_khz_or_zero (frequency_text);
        _mode = mode;
        _spotter = spotter;
        _spotter_comment = spotter_comment;
        _rst_sent = rst_sent;
        _rst_rcvd = rst_rcvd;
    }

    public Spot to_spot () {
        return new Spot.from_add_spot (
            callsign,
            park_ref,
            spot_time,
            format_frequency_khz (frequency_khz),
            mode,
            spotter,
            spotter_comment,
            rst_sent,
            rst_rcvd
        );
    }
}

[Compact (opaque=true)]
public class LoggingResult {
    public bool local_saved { get; }
    public bool local_adif_saved { get; }
    public bool pota_posted { get; }
    public bool qrz_uploaded { get; }
    public string? local_adif_error { get; }
    public string? pota_error { get; }
    public string? qrz_error { get; }

    public LoggingResult (
        bool local_saved,
        bool local_adif_saved,
        bool pota_posted,
        bool qrz_uploaded,
        string? local_adif_error = null,
        string? pota_error = null,
        string? qrz_error = null
    ) {
        _local_saved = local_saved;
        _local_adif_saved = local_adif_saved;
        _pota_posted = pota_posted;
        _qrz_uploaded = qrz_uploaded;
        _local_adif_error = local_adif_error;
        _pota_error = pota_error;
        _qrz_error = qrz_error;
    }
}

public sealed class LoggingService : Object {
    private Gee.HashSet<string> completed_logged_adif_keys = new Gee.HashSet<string> ();

    public signal void qso_changed ();
    public signal void qso_added (Spot spot);

    public QsoStore qso_store { get; construct; }
    public PotaSpotPoster pota_poster { get; construct; }
    public QrzQsoUploader qrz_uploader { get; construct; }
    public LocalAdifWriter local_adif_writer { get; construct; }
    public LoggingPreferences preferences { get; construct; }

    public LoggingService (
        QsoStore qso_store,
        PotaSpotPoster pota_poster,
        QrzQsoUploader qrz_uploader,
        LocalAdifWriter local_adif_writer,
        LoggingPreferences preferences
    ) {
        Object (
            qso_store: qso_store,
            pota_poster: pota_poster,
            qrz_uploader: qrz_uploader,
            local_adif_writer: local_adif_writer,
            preferences: preferences
        );
    }

    public async LoggingResult submit_qso_draft (
        QsoDraft draft,
        bool post_to_pota = true
    ) throws Error {
        return yield submit_qso_draft_with_qrz_mode (
            draft,
            post_to_pota,
            QrzUploadMode.DEFAULT
        );
    }

    public async LoggingResult submit_qso_draft_with_qrz_mode (
        QsoDraft draft,
        bool post_to_pota,
        QrzUploadMode qrz_upload_mode,
        string? qrz_adif = null
    ) throws Error {
        if (draft == null)
            throw new LoggingError.INVALID_CONTACT ("QSO is empty");

        return yield submit_spot_qso_with_qrz_mode (
            draft.to_spot (),
            post_to_pota,
            qrz_upload_mode,
            qrz_adif
        );
    }

    public async LoggingResult submit_spot_qso (
        Spot spot, bool post_to_pota = true
    ) throws Error {
        return yield submit_spot_qso_with_qrz_mode (
            spot,
            post_to_pota,
            QrzUploadMode.DEFAULT
        );
    }

    public async LoggingResult submit_spot_qso_with_qrz_mode (
        Spot spot,
        bool post_to_pota,
        QrzUploadMode qrz_upload_mode,
        string? qrz_adif = null
    ) throws Error {
        validate_spot_qso (spot);

        Error? db_error = null;
        bool inserted = false;
        if (!qso_store.add_qso_from_spot (spot, out inserted, out db_error)) {
            throw new LoggingError.LOCAL_SAVE_FAILED (
                db_error != null ? db_error.message : "Unable to save QSO locally"
            );
        }

        if (!inserted) {
            message (
                "Skipping QRZ upload for %s @ %s: QSO already exists locally",
                spot.callsign,
                spot.park_ref
            );
            return new LoggingResult (
                false,
                false,
                false,
                false
            );
        }

        qso_changed ();
        qso_added (spot);

        bool pota_posted = false;
        bool qrz_uploaded = false;
        bool local_adif_saved = false;
        string? local_adif_error = null;
        string? pota_error = null;
        string? qrz_error = null;

        if (preferences.enable_local_adif_log) {
            try {
                local_adif_writer.append_spot_qso (spot, preferences.local_adif_log_path);
                local_adif_saved = true;
            } catch (Error err) {
                local_adif_error = err.message;
                warning ("Unable to save QSO to local ADIF log: %s", err.message);
            }
        }

        if (post_to_pota && spot.park_ref.strip () != "") {
            try {
                yield pota_poster.post_spot (
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

        var upload_to_qrz = should_upload_to_qrz (qrz_upload_mode);
        message (
            "QRZ upload decision for %s @ %s: mode=%s global_enabled=%s wsjtx_forward=%s api_key_configured=%s upload=%s source=%s",
            spot.callsign,
            spot.park_ref,
            qrz_upload_mode.to_string (),
            preferences.enable_qrz_logging.to_string (),
            preferences.forward_wsjtx_qsos_to_qrz.to_string (),
            (preferences.qrz_api_key != "").to_string (),
            upload_to_qrz.to_string (),
            has_text (qrz_adif) ? "adif" : "spot"
        );

        if (upload_to_qrz) {
            try {
                if (has_text (qrz_adif)) {
                    message (
                        "Uploading ADIF QSO to QRZ for %s @ %s",
                        spot.callsign,
                        spot.park_ref
                    );
                    yield qrz_uploader.upload_adif_record (qrz_adif);
                } else {
                    message (
                        "Uploading spot QSO to QRZ for %s @ %s",
                        spot.callsign,
                        spot.park_ref
                    );
                    yield qrz_uploader.upload_spot_qso (spot);
                }
                qrz_uploaded = true;
            } catch (Error err) {
                qrz_error = err.message;
                warning ("Unable to upload QSO to QRZ: %s", err.message);
            }
        }

        var result = new LoggingResult (
            true,
            local_adif_saved,
            pota_posted,
            qrz_uploaded,
            local_adif_error,
            pota_error,
            qrz_error
        );

        Error? status_error = null;
        if (!qso_store.update_qso_delivery_status (
            spot,
            result.local_adif_saved,
            result.pota_posted,
            result.qrz_uploaded,
            result.local_adif_error,
            result.pota_error,
            result.qrz_error,
            out status_error
        )) {
            warning (
                "Unable to update QSO delivery status: %s",
                status_error != null ? status_error.message : "unknown error"
            );
        }

        return result;
    }

    private bool should_upload_to_qrz (QrzUploadMode mode) {
        if (preferences.qrz_api_key == "")
            return false;

        switch (mode) {
            case QrzUploadMode.ENABLED:
                return true;
            case QrzUploadMode.DISABLED:
                return false;
            case QrzUploadMode.DEFAULT:
            default:
                return preferences.enable_qrz_logging;
        }
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
        if (is_empty_or_whitespace (spot.callsign)) {
            throw new LoggingError.INVALID_CONTACT ("Activator callsign is required");
        }
        if (is_empty_or_whitespace (spot.spotter)) {
            throw new LoggingError.INVALID_CONTACT ("Your callsign is required");
        }
        if (is_empty_or_whitespace (spot.mode)) {
            throw new LoggingError.INVALID_CONTACT ("Mode is required");
        }
        if (spot.frequency_khz <= 0.0) {
            throw new LoggingError.INVALID_CONTACT ("Frequency is required");
        }
    }
}
