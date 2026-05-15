/* src/qrz_client.vala
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

public enum QrzLogbookError {
    INVALID_REQUEST,
    HTTP_FAILED,
    AUTH_FAILED,
    API_FAILED,
    PARSE_FAILED
}

public static GLib.Quark qrz_logbook_error_quark () {
    return GLib.Quark.from_string ("qrz-logbook-error");
}

public sealed class QrzClient : Object {
    private Soup.Session session;
    private const string QRZ_LOGBOOK_API_URL = "https://logbook.qrz.com/api";

    public QrzClient () {
        Object ();
    }

    construct {
        session = new Soup.Session ();
        session.timeout = 30;
        session.user_agent = "Artemis/%s".printf (Build.VERSION);
    }

    private static string encode_form_value (string value) {
        return GLib.Uri.escape_string (value, null, false);
    }

    private static string adif_field (string name, string value) {
        return "<%s:%u>%s".printf (name, value.length, value);
    }

    private static string format_frequency_mhz (double frequency_khz) {
        var formatted = "%.6f".printf (frequency_khz / 1000.0);

        while (formatted.has_suffix ("0")) {
            formatted = formatted.substring (0, formatted.length - 1);
        }
        if (formatted.has_suffix ("."))
            formatted = formatted.substring (0, formatted.length - 1);

        return formatted;
    }

    private static string? lookup_response_value (
        GLib.HashTable<string, string> params,
        string key
    ) {
        return params.lookup (key);
    }

    private static GLib.HashTable<string, string> parse_response_body (string body) {
        var params = new GLib.HashTable<string, string> (GLib.str_hash, GLib.str_equal);

        foreach (var chunk in body.split ("&")) {
            if (chunk == "")
                continue;

            int sep = chunk.index_of_char ('=');
            if (sep < 0)
                continue;

            var key = chunk.substring (0, sep).up ();
            var raw_value = chunk.substring (sep + 1);
            var value = GLib.Uri.unescape_string (raw_value.replace ("+", " "), null);

            params.insert (key, value ?? "");
        }

        return params;
    }

    private string build_adif_record (Spot spot) throws Error {
        var station_callsign = (spot.spotter ?? "").strip ();
        var contacted_callsign = (spot.callsign ?? "").strip ();
        var band = (spot.band ?? "").strip ();
        var mode = (spot.mode ?? "").strip ().up ();
        var park_ref = (spot.park_ref ?? "").strip ();

        if (station_callsign == "") {
            throw new Error (
                qrz_logbook_error_quark (),
                QrzLogbookError.INVALID_REQUEST,
                "Spotter callsign is required for QRZ upload"
            );
        }

        if (contacted_callsign == "") {
            throw new Error (
                qrz_logbook_error_quark (),
                QrzLogbookError.INVALID_REQUEST,
                "Activator callsign is required for QRZ upload"
            );
        }

        if ((band == "") || (band == "All") || (band == "Other")) {
            throw new Error (
                qrz_logbook_error_quark (),
                QrzLogbookError.INVALID_REQUEST,
                "A valid amateur band is required for QRZ upload"
            );
        }

        if (mode == "") {
            throw new Error (
                qrz_logbook_error_quark (),
                QrzLogbookError.INVALID_REQUEST,
                "Mode is required for QRZ upload"
            );
        }

        var qso_time = spot.spot_time.to_utc ();
        var adif = new StringBuilder ();
        adif.append (adif_field ("station_callsign", station_callsign));
        adif.append (adif_field ("call", contacted_callsign));
        adif.append (adif_field ("qso_date", qso_time.format ("%Y%m%d")));
        adif.append (adif_field ("time_on", qso_time.format ("%H%M")));
        adif.append (adif_field ("band", band));
        adif.append (adif_field ("mode", mode));

        if (spot.frequency_khz > 0)
            adif.append (adif_field ("freq", format_frequency_mhz (spot.frequency_khz)));

        if (park_ref != "") {
            adif.append (adif_field ("sig", "POTA"));
            adif.append (adif_field ("sig_info", park_ref));
            adif.append (adif_field ("POTARef", park_ref));
            adif.append (adif_field ("notes", "POTA - %s".printf (park_ref)));
        }

        if ((spot.rst_sent ?? "").strip () != "")
            adif.append (adif_field ("rst_sent", spot.rst_sent.strip ()));
        if ((spot.rst_rcvd ?? "").strip () != "")
            adif.append (adif_field ("rst_rcvd", spot.rst_rcvd.strip ()));

        var comment = (spot.spotter_comment ?? "").strip ();
        if (comment != "")
            adif.append (adif_field ("comment", comment));

        adif.append ("<eor>");

        return adif.str;
    }

    public async void upload_spot_qso (Spot spot) throws Error {
        var api_key = Application.settings.get_string ("qrz-api-key").strip ();
        if (api_key == "") {
            throw new Error (
                qrz_logbook_error_quark (),
                QrzLogbookError.INVALID_REQUEST,
                "QRZ API key is not configured"
            );
        }

        var form_body = "KEY=%s&ACTION=INSERT&ADIF=%s".printf (
            encode_form_value (api_key),
            encode_form_value (build_adif_record (spot))
        );

        var message = new Soup.Message ("POST", QRZ_LOGBOOK_API_URL);
        var bytes = new GLib.Bytes (form_body.data);
        message.set_request_body_from_bytes (
            "application/x-www-form-urlencoded",
            bytes
        );
        message.request_headers.replace ("Accept", "text/plain");
        message.request_headers.replace ("User-Agent", session.user_agent);

        var response = yield session.send_and_read_async (
            message,
            Priority.DEFAULT,
            null
        );

        if (message.status_code != Soup.Status.OK) {
            throw new Error (
                qrz_logbook_error_quark (),
                QrzLogbookError.HTTP_FAILED,
                "QRZ log upload failed: %u %s".printf (
                    message.status_code,
                    message.reason_phrase
                )
            );
        }

        var body = ((string)response.get_data ()).substring (
            0,
            (long)response.get_size ()
        ).strip ();
        var params = parse_response_body (body);
        var result = lookup_response_value (params, "RESULT");

        if ((result == null) || (result == "")) {
            throw new Error (
                qrz_logbook_error_quark (),
                QrzLogbookError.PARSE_FAILED,
                "QRZ log upload returned an unexpected response"
            );
        }

        if (result == "OK")
            return;

        var reason = lookup_response_value (params, "REASON");
        if ((reason == null) || (reason == "")) {
            reason = lookup_response_value (params, "DATA");
        }
        if ((reason == null) || (reason == "")) {
            reason = "Unknown QRZ API error";
        }

        if (result == "AUTH") {
            throw new Error (
                qrz_logbook_error_quark (),
                QrzLogbookError.AUTH_FAILED,
                reason
            );
        }

        throw new Error (
            qrz_logbook_error_quark (),
            QrzLogbookError.API_FAILED,
            reason
        );
    }
}
