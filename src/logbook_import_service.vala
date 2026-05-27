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
    public ParkStore park_store { get; construct; }

    public LogbookImportService (ParkStore park_store) {
        Object (park_store: park_store);
    }

    public LogbookImportResult import_pota_csv (File file) throws Error {
        if (file == null)
            throw new IOError.INVALID_ARGUMENT ("Import file is empty");

        var stream = file.read ();
        var data = new DataInputStream (stream);
        var line = data.read_line ();     // skip column titles
        var num_parks = 0;

        while ((line = data.read_line ()) != null) {
            var raw_columns = new ArrayList<string>.wrap (line.split (","));
            var columns = new ArrayList<string> ();
            foreach (var column in raw_columns)
                columns.add (strip_quotes (column));

            if (columns.size < 7) {
                throw new IOError.INVALID_DATA (
                    "CSV row has %d columns; expected at least 7".printf (columns.size)
                );
            }

            int qso_count = 0;
            unowned string unparsed;
            if (!int.try_parse (columns.get (6), out qso_count, out unparsed) ||
                unparsed != "") {
                throw new IOError.INVALID_DATA (
                    "CSV row has invalid QSO count '%s'".printf (columns.get (6))
                );
            }

            Error? error = null;
            park_store.add_park (
                columns.get (3),
                columns.get (4),
                columns.get (0),
                columns.get (1),
                columns.get (2),
                normalize_first_qso_date (columns.get (5)),
                qso_count,
                out error
            );
            if (error != null)
                throw new IOError.FAILED (error.message);

            num_parks++;
        }

        return new LogbookImportResult (num_parks);
    }

    private static string? normalize_first_qso_date (string value) throws Error {
        var trimmed = value.strip ();
        if (trimmed == "")
            return null;

        var parsed = new DateTime.from_iso8601 (trimmed, new TimeZone.utc ());
        if (parsed != null)
            return parsed.to_utc ().format ("%Y-%m-%dT%H:%M:%SZ");

        if (trimmed.length == 10 &&
            trimmed.get_char (4) == '-' &&
            trimmed.get_char (7) == '-') {
            int year = 0;
            int month = 0;
            int day = 0;
            unowned string unparsed;
            if (int.try_parse (trimmed.substring (0, 4), out year, out unparsed) &&
                unparsed == "" &&
                int.try_parse (trimmed.substring (5, 2), out month, out unparsed) &&
                unparsed == "" &&
                int.try_parse (trimmed.substring (8, 2), out day, out unparsed) &&
                unparsed == "") {
                var date = new DateTime.utc (year, month, day, 0, 0, 0);
                return date.format ("%Y-%m-%dT%H:%M:%SZ");
            }
        }

        throw new IOError.INVALID_DATA ("CSV row has invalid first QSO date '%s'".printf (value));
    }

    private static string strip_quotes (string s) {
        if (s.has_prefix ("\"") && s.has_suffix ("\"") && (s.length >= 2))
            return s.substring (1, s.length - 2);
        return s;
    }
}
