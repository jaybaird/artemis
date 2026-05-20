/* src/logbook_import_service.vala
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
                columns.get (5),
                qso_count,
                out error
            );
            if (error != null)
                throw new IOError.FAILED (error.message);

            num_parks++;
        }

        return new LogbookImportResult (num_parks);
    }

    private static string strip_quotes (string s) {
        if (s.has_prefix ("\"") && s.has_suffix ("\"") && (s.length >= 2))
            return s.substring (1, s.length - 2);
        return s;
    }
}
