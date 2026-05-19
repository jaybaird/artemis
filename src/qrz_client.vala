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

        if ((result == null) || (result == "")) {
            throw new QrzLogbookError.PARSE_FAILED (
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
            throw new QrzLogbookError.AUTH_FAILED (reason);
        }

        throw new QrzLogbookError.API_FAILED (reason);
    }

    private string build_adif_record (Spot spot) throws Error {
        var station_callsign = (spot.spotter ?? "").strip ();
        var contacted_callsign = (spot.callsign ?? "").strip ();
        var band = (spot.band ?? "").strip ();
        var mode = (spot.mode ?? "").strip ().up ();
        var park_ref = (spot.park_ref ?? "").strip ();

        if (station_callsign == "") {
            throw new QrzLogbookError.INVALID_REQUEST (
                "Spotter callsign is required for QRZ upload"
            );
        }

        if (contacted_callsign == "") {
            throw new QrzLogbookError.INVALID_REQUEST (
                "Activator callsign is required for QRZ upload"
            );
        }

        if ((band == "") || (band == "All") || (band == "Other")) {
            throw new QrzLogbookError.INVALID_REQUEST (
                "A valid amateur band is required for QRZ upload"
            );
        }

        if (mode == "") {
            throw new QrzLogbookError.INVALID_REQUEST ("Mode is required for QRZ upload");
        }

        var qso_time = spot.spot_time.to_utc ();
        var document = new Artemis.Adif.Document ();
        var record = new Artemis.Adif.Record ();
        record.set ("STATION_CALLSIGN", station_callsign);
        record.set ("CALL", contacted_callsign);
        record.set ("QSO_DATE", qso_time.format ("%Y%m%d"));
        record.set ("TIME_ON", qso_time.format ("%H%M"));
        record.set ("BAND", band);
        record.set ("MODE", mode);

        if (spot.frequency_khz > 0)
            record.set ("FREQ", format_frequency_mhz (spot.frequency_khz));

        if (park_ref != "") {
            record.set ("SIG", "POTA");
            record.set ("SIG_INFO", park_ref);
            record.set ("POTA_REF", park_ref);
            record.set ("NOTES", "POTA - %s".printf (park_ref));
        }

        if ((spot.rst_sent ?? "").strip () != "")
            record.set ("RST_SENT", spot.rst_sent.strip ());
        if ((spot.rst_rcvd ?? "").strip () != "")
            record.set ("RST_RCVD", spot.rst_rcvd.strip ());

        var comment = (spot.spotter_comment ?? "").strip ();
        if (comment != "")
            record.set ("COMMENT", comment);

        document.records.add (record);
        return Artemis.Adif.Generator.to_string (document);
    }

    public async void upload_spot_qso (Spot spot) throws Error {
        yield upload_adif_payload (build_adif_record (spot));
    }

    public async void upload_adif_record (string adif) throws Error {
        yield upload_adif_payload (adif);
    }
}
