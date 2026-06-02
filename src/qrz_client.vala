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

public errordomain QrzLogbookError {
    INVALID_REQUEST,
    HTTP_FAILED,
    AUTH_FAILED,
    API_FAILED,
    PARSE_FAILED
}

public sealed class QrzClient : Object, QrzQsoUploader {
    private Soup.Session session;
    private const string QRZ_LOGBOOK_API_URL = "https://logbook.qrz.com/api";

    public QrzClient () {
        Object ();
    }

    construct {
        session = new Soup.Session () {
            timeout = 30,
            user_agent = Build.USER_AGENT
        };
    }

    private static string encode_form_value (string value) {
        return GLib.Uri.escape_string (value, null, false);
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

    private static bool is_duplicate_upload_reason (string reason) {
        return reason.down ().contains ("duplicate");
    }

    private async void upload_adif_payload (string adif) throws Error {
        var api_key = Application.settings.get_string ("qrz-api-key").strip ();
        if (api_key == "") {
            throw new QrzLogbookError.INVALID_REQUEST ("QRZ API key is not configured");
        }

        var normalized_adif = adif.strip ();
        if (normalized_adif == "") {
            throw new QrzLogbookError.INVALID_REQUEST ("ADIF record is required for QRZ upload");
        }

        if (!normalized_adif.down ().contains ("<eor>"))
            normalized_adif += "<eor>";

        try {
            var document = Artemis.Adif.Parser.from_string (normalized_adif);
            normalized_adif = Artemis.Adif.Generator.to_string (document);
        } catch (Artemis.Adif.Error error) {
            throw new QrzLogbookError.INVALID_REQUEST (
                "Invalid ADIF record for QRZ upload: %s".printf (error.message)
            );
        }

        message (
            "QRZ HTTP upload starting: api_key_configured=%s adif_length=%d",
            (api_key != "").to_string (),
            normalized_adif.length
        );

        var form_body = "KEY=%s&ACTION=INSERT&ADIF=%s".printf (
            encode_form_value (api_key),
            encode_form_value (normalized_adif)
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
            throw new QrzLogbookError.HTTP_FAILED (
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

        if (is_empty_or_whitespace (result)) {
            throw new QrzLogbookError.PARSE_FAILED (
                "QRZ log upload returned an unexpected response"
            );
        }

        if (result == "OK")
            return;

        var reason = lookup_response_value (params, "REASON");
        if (is_empty_or_whitespace (reason)) {
            reason = lookup_response_value (params, "DATA");
        }
        if (is_empty_or_whitespace (reason)) {
            reason = "Unknown QRZ API error";
        }

        if (result == "AUTH") {
            throw new QrzLogbookError.AUTH_FAILED (reason);
        }

        if (is_duplicate_upload_reason (reason))
            return;

        throw new QrzLogbookError.API_FAILED (reason);
    }

    public async void upload_spot_qso (Spot spot) throws Error {
        message (
            "QrzClient.upload_spot_qso called for %s @ %s",
            spot != null ? spot.callsign : "(null)",
            spot != null ? spot.park_ref : "(null)"
        );
        try {
            yield upload_adif_payload (Artemis.Adif.spot_qso_to_string (spot));
        } catch (Artemis.Adif.Error error) {
            throw new QrzLogbookError.INVALID_REQUEST (
                "Invalid QSO for QRZ upload: %s".printf (error.message)
            );
        }
    }

    public async void upload_adif_record (string adif) throws Error {
        message (
            "QrzClient.upload_adif_record called: adif_length=%d",
            adif.length
        );
        yield upload_adif_payload (adif);
    }
}
