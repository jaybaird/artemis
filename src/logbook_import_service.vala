/* src/logbook_import_service.vala
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

using Gee;

public interface ParkStore : Object {
    public abstract bool add_park (
        string reference,
        string? park_name,
        string? dx_entity,
        string? location,
        string? hasc,
        string? first_qso_date,
        int qso_count,
        out Error? error
    );
}

[Compact (opaque=true)]
public class LogbookImportResult {
    public int imported_count { get; }

    public LogbookImportResult (int imported_count) {
        _imported_count = imported_count;
    }
}

public sealed class LogbookImportService : Object {
    private const int HUNTER_COLUMN_COUNT = 7;
    private const string[] HUNTER_HEADER = {
        "DX Entity",
        "Location",
        "HASC",
        "Reference",
        "Park Name",
        "First QSO Date",
        "QSOs"
    };

    public ParkStore park_store { get; construct; }

    public LogbookImportService (ParkStore park_store) {
        Object (park_store: park_store);
    }

    public LogbookImportResult import_pota_csv (File file) throws Error {
        if (file == null)
            throw new IOError.INVALID_ARGUMENT ("Import file is empty");

        var parser = new CsvParser ();
        return import_hunter_park_rows (parser.parse_file (file));
    }

    private LogbookImportResult import_hunter_park_rows (
        ArrayList<ArrayList<string>> rows
    ) throws Error {
        if (rows.size == 0)
            throw new IOError.INVALID_DATA ("CSV file is empty");

        validate_hunter_header (rows[0]);
        var num_parks = 0;
        for (var i = 1; i < rows.size; i++) {
            var row = rows[i];
            var csv_row = i + 1;
            if (row.size != HUNTER_COLUMN_COUNT) {
                throw new IOError.INVALID_DATA (
                    "CSV row %d has %d columns; expected %d".printf (
                        csv_row,
                        row.size,
                        HUNTER_COLUMN_COUNT
                    )
                );
            }

            Error? error = null;
            park_store.add_park (
                row[3],
                row[4],
                row[0],
                row[1],
                row[2],
                normalize_first_qso_date (normalize_optional_string (row[5])),
                parse_qsos (row[6], csv_row),
                out error
            );
            if (error != null)
                throw new IOError.FAILED (error.message);

            num_parks++;
        }

        return new LogbookImportResult (num_parks);
    }

    private static void validate_hunter_header (ArrayList<string> header) throws Error {
        if (header.size != HUNTER_COLUMN_COUNT) {
            throw new IOError.INVALID_DATA (
                "CSV header has %d columns; expected %d".printf (
                    header.size,
                    HUNTER_COLUMN_COUNT
                )
            );
        }

        for (var i = 0; i < HUNTER_COLUMN_COUNT; i++) {
            if (header[i] != HUNTER_HEADER[i]) {
                throw new IOError.INVALID_DATA (
                    "CSV header column %d is '%s'; expected '%s'".printf (
                        i + 1,
                        header[i],
                        HUNTER_HEADER[i]
                    )
                );
            }
        }
    }

    private static int parse_qsos (string value, int csv_row) throws Error {
        var qso_text = value.strip ();
        int qsos = 0;
        unowned string unparsed;
        if (!int.try_parse (qso_text, out qsos, out unparsed) || unparsed != "") {
            throw new IOError.INVALID_DATA (
                "CSV row %d has invalid QSOs value '%s'".printf (csv_row, value)
            );
        }

        return qsos;
    }

    private static string? normalize_first_qso_date (string? value) throws Error {
        var trimmed = (value ?? "").strip ();
        if (trimmed == "")
            return null;

        var parsed = new DateTime.from_iso8601 (trimmed, new TimeZone.utc ());
        if (parsed != null)
            return parsed.to_utc ().format ("%Y-%m-%dT%H:%M:%SZ");

        var date_only = parse_date_only_utc (trimmed);
        if (date_only != null)
            return date_only.format ("%Y-%m-%dT%H:%M:%SZ");

        throw new IOError.INVALID_DATA ("CSV row has invalid first QSO date '%s'".printf (value));
    }

    private static string? normalize_optional_string (string value) {
        var stripped = value.strip ();
        return stripped == "" ? null : stripped;
    }
}
