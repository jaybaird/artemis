/* src/database.vala
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
using GLib;
using Sqlite;

const string[] DB_VERSIONS = {
    "version-001.sql"
};

static string iso8601_day_start (DateTime utc_any) {
    return utc_any.format ("%Y-%m-%dT00:00:00Z");
}

static string iso8601_next_day_start (DateTime utc_any) {
    DateTime next = utc_any.add_days (1);

    return next.format ("%Y-%m-%dT00:00:00Z");
}

static string? iso8601_from_borrowed_utc (DateTime? dt) {
    if (dt == null)
        return null;
    DateTime utc = dt.to_utc ();
    return utc.format ("%Y-%m-%dT%H:%M:%SZ");
}

static void bind_nullable_text (Sqlite.Statement st, int index, string? value) {
    if (is_empty_or_whitespace (value))
        st.bind_null (index);
    else
        st.bind_text (index, value);
}

public sealed class QsoRow : Object {
    public int64 id { get; construct; }
    public string? park_ref { get; construct; }
    public string? callsign { get; construct; }
    public string? mode { get; construct; }
    public double frequency_khz { get; construct; }
    public string? created_utc { get; construct; }
    public string? spotter { get; construct; }
    public string? spotter_comment { get; construct; }
    public string? activator_comment { get; construct; }
    public string? rst_sent { get; construct; }
    public string? rst_rcvd { get; construct; }
    public string? park_name { get; construct; }
    public bool local_adif_saved { get; construct; }
    public bool pota_spotted { get; construct; }
    public bool qrz_uploaded { get; construct; }
    public string? local_adif_error { get; construct; }
    public string? pota_error { get; construct; }
    public string? qrz_error { get; construct; }

    public QsoRow.from_statement (
        Sqlite.Statement st,
        bool includes_delivery_status = false,
        bool includes_rst = false
    ) {
        Object (
            id: st.column_int64 (0),
            park_ref: st.column_text (1),
            callsign: st.column_text (2),
            mode: (st.column_type (3) == Sqlite.NULL) ? null : st.column_text (3),
            frequency_khz: (st.column_type (4) == Sqlite.NULL) ? 0 : st.column_double (4),
            created_utc: st.column_text (5),
            spotter: (st.column_type (6) == Sqlite.NULL) ? null : st.column_text (6),
            spotter_comment: (st.column_type (7) == Sqlite.NULL) ? null : st.column_text (7),
            activator_comment: (st.column_type (8) == Sqlite.NULL) ? null : st.column_text (8),
            rst_sent: (!includes_rst || st.column_type (9) == Sqlite.NULL) ? null : st.column_text (9),
            rst_rcvd: (!includes_rst || st.column_type (10) == Sqlite.NULL) ? null : st.column_text (10),
            park_name: (st.column_type (11) == Sqlite.NULL) ? null : st.column_text (11),
            local_adif_saved: includes_delivery_status && st.column_int (12) != 0,
            pota_spotted: includes_delivery_status && st.column_int (13) != 0,
            qrz_uploaded: includes_delivery_status && st.column_int (14) != 0,
            local_adif_error: (!includes_delivery_status || st.column_type (15) == Sqlite.NULL) ?
                null : st.column_text (15),
            pota_error: (!includes_delivery_status || st.column_type (16) == Sqlite.NULL) ?
                null : st.column_text (16),
            qrz_error: (!includes_delivery_status || st.column_type (17) == Sqlite.NULL) ?
                null : st.column_text (17)
        );
    }
}

public sealed class ParkRow : Object {
    public int id { get; construct; }
    public string reference { get; construct; }
    public string? park_name { get; construct; }
    public string? location { get; construct; }

    public ParkRow (int id,
                    string reference,
                    string? park_name = null,
                    string? location = null) {
        Object (
            id: id,
            reference: reference,
            park_name: park_name,
            location: location
        );
    }

    public ParkRow.from_statement (Sqlite.Statement st) {
        int id = 0;
        string reference = st.column_text (0);

        Object (
            id: id,
            reference: reference,
            park_name: (st.column_type (1) == Sqlite.NULL) ? null : st.column_text (1),
            location: (st.column_type (2) == Sqlite.NULL) ? null : st.column_text (2)
        );
    }
} /* class ParkRow */

public sealed class HuntedParkRow : Object {
    public string reference { get; construct; }
    public string? park_name { get; construct; }
    public string? location { get; construct; }
    public string? first_qso_date { get; construct; }
    public int qso_count { get; construct; }
    public string? latest_qso_utc { get; construct; }
    public string? latest_callsign { get; construct; }
    public string? latest_mode { get; construct; }
    public double latest_frequency_khz { get; construct; }

    public HuntedParkRow.from_statement (Sqlite.Statement st) {
        Object (
            reference: st.column_text (0),
            park_name: (st.column_type (1) == Sqlite.NULL) ? null : st.column_text (1),
            location: (st.column_type (2) == Sqlite.NULL) ? null : st.column_text (2),
            first_qso_date: (st.column_type (3) == Sqlite.NULL) ? null : st.column_text (3),
            qso_count: st.column_int (4),
            latest_qso_utc: (st.column_type (5) == Sqlite.NULL) ? null : st.column_text (5),
            latest_callsign: (st.column_type (6) == Sqlite.NULL) ? null : st.column_text (6),
            latest_mode: (st.column_type (7) == Sqlite.NULL) ? null : st.column_text (7),
            latest_frequency_khz: (st.column_type (8) == Sqlite.NULL) ? 0.0 : st.column_double (8)
        );
    }
}

public enum LogbookSortDirection {
    ASC,
    DESC
}

public enum LogbookQsoSortColumn {
    DATE,
    ACTIVATOR,
    REFERENCE,
    PARK,
    BAND,
    MODE
}

public enum HuntedParkSortColumn {
    REFERENCE,
    PARK,
    LOCATION,
    QSOS,
    FIRST_QSO
}

public sealed class LogbookQsoPage : Object {
    public Gee.ArrayList<QsoRow> rows { get; construct; }
    public int total_count { get; construct; }

    public LogbookQsoPage (Gee.ArrayList<QsoRow> rows, int total_count) {
        Object (
            rows: rows,
            total_count: total_count
        );
    }
}

public sealed class HuntedParkPage : Object {
    public Gee.ArrayList<HuntedParkRow> rows { get; construct; }
    public int total_count { get; construct; }

    public HuntedParkPage (Gee.ArrayList<HuntedParkRow> rows, int total_count) {
        Object (
            rows: rows,
            total_count: total_count
        );
    }
}

public errordomain DatabaseError {
    DB_NOT_INITIALIZED,
    INVALID_ARGUMENT,
    SQLITE_FAILED
}

public sealed class SpotLogStatusSnapshot : Object {
    public HashSet<string> hunted_parks { get; private set; }
    public HashSet<string> hunted_today { get; private set; }
    public HashSet<string> hunted_park_bands { get; private set; }

    public SpotLogStatusSnapshot () {
        Object ();
    }

    construct {
        hunted_parks = new HashSet<string> ();
        hunted_today = new HashSet<string> ();
        hunted_park_bands = new HashSet<string> ();
    }

    public static string park_band_key (string park_ref, string band) {
        return "%s|%s".printf (park_ref, band);
    }
}

public class SpotDb : Object, QsoStore, ParkStore {
    private const int SCHEMA_VERSION_INITIAL = 1;
    private const int SCHEMA_VERSION_QSO_DELIVERY_STATUS = 2;
    private const int SCHEMA_VERSION_PARK_DETAILS = 3;
    private const int SCHEMA_VERSION_QSO_SIGNAL_REPORTS = 4;
    private const int SCHEMA_VERSION_CANONICAL_PARK_QSO_DATES = 5;
    private const int SCHEMA_VERSION_LATEST = SCHEMA_VERSION_CANONICAL_PARK_QSO_DATES;

    private Sqlite.Database? db = null;
    private string db_path = "";
    private int schema_version = 0;
    private Statement? is_park_hunted_stmt = null;
    private Statement? had_qso_on_utc_day_stmt = null;
    private Statement? had_qso_on_band_stmt = null;

    public int user_version {
        get { return schema_version; }
    }

    public bool has_qso_delivery_status {
        get { return schema_version >= SCHEMA_VERSION_QSO_DELIVERY_STATUS; }
    }

    public bool has_park_details {
        get { return schema_version >= SCHEMA_VERSION_PARK_DETAILS; }
    }

    public bool has_qso_signal_reports {
        get { return schema_version >= SCHEMA_VERSION_QSO_SIGNAL_REPORTS; }
    }

    public SpotDb () {}

    public bool init (out Error? error = null) {
        error = null;
        // build paths
        string data_dir = Environment.get_user_data_dir ();
        string app_dir = Path.build_filename (data_dir, "artemis");
        if (GLib.DirUtils.create_with_parents (app_dir, 0700) != 0) {
            critical ("Failed to create app dir %s: %s", app_dir, strerror (
                errno)
                );
            error = new DatabaseError.SQLITE_FAILED ("Failed to create app directory: %s".printf (strerror (errno))
                );
            return false;
        }

        db_path = Path.build_filename (app_dir, "spots.db");
        bool db_existed = FileUtils.test (db_path, FileTest.EXISTS);

        int rc = Database.open (db_path, out db);
        if (rc != Sqlite.OK) {
            critical ("Cannot open DB at %s: %s", db_path, db.errmsg ());
            error = new DatabaseError.SQLITE_FAILED ("Cannot open database: %s".printf (db.errmsg ()));
            db = null;
            return false;
        }

        const string PRAGMAS =
            """
            PRAGMA journal_mode=WAL;
            PRAGMA synchronous=NORMAL;
            PRAGMA foreign_keys=ON;
            PRAGMA busy_timeout=3000;
        """;
        if (db.exec (PRAGMAS) != Sqlite.OK) {
            error = new DatabaseError.SQLITE_FAILED ("Failed to set database pragmas: %s".printf (db.errmsg ()));
            db = null;
            return false;
        }

        Error? schema_error;
        if (!spot_db_init_schema (db_existed, out schema_error)) {
            error = schema_error;
            db = null;
            return false;
        }

        message ("DB opened: %s (schema version %d)", db_path, schema_version);
        return true;
    } /* init */

    /* ----- schema ----- */
    private bool spot_db_init_schema (bool db_existed, out Error? error) {
        error = null;

        int detected_version = read_user_version (out error);
        if (error != null)
            return false;

        if (!db_existed && detected_version == 0) {
            if (!create_latest_schema (out error))
                return false;
            if (!set_user_version (SCHEMA_VERSION_LATEST, out error))
                return false;
            schema_version = SCHEMA_VERSION_LATEST;
            return true;
        }

        if (detected_version > SCHEMA_VERSION_LATEST) {
            error = new DatabaseError.SQLITE_FAILED (
                "Database schema version %d is newer than this Trailwave build supports (%d)".printf (
                    detected_version,
                    SCHEMA_VERSION_LATEST
                )
            );
            return false;
        }

        schema_version = detected_version;
        if (schema_version < SCHEMA_VERSION_INITIAL)
            schema_version = SCHEMA_VERSION_INITIAL;

        if (schema_version < SCHEMA_VERSION_LATEST &&
            !migrate_schema (schema_version, SCHEMA_VERSION_LATEST, out error)) {
            return false;
        }

        return true;
    }

    private bool create_latest_schema (out Error? error) {
        error = null;

        try {
            string schema_sql = (string)GLib.resources_lookup_data (
                "/com/k0vcz/artemis/sql/version-001.sql",
                GLib.ResourceLookupFlags.NONE
            ).get_data ();
            if (db.exec (schema_sql) != Sqlite.OK) {
                error = new DatabaseError.SQLITE_FAILED ("Failed to create database schema: %s".printf (db.errmsg ())
                );
                return false;
            }
        } catch (Error e) {
            error = e;
            return false;
        }

        return true;
    }

    private int read_user_version (out Error? error) {
        error = null;

        Statement st;
        if (db.prepare_v2 ("PRAGMA user_version;", -1, out st) != Sqlite.OK) {
            error = new DatabaseError.SQLITE_FAILED ("Failed to read database schema version: %s".printf (db.errmsg ()));
            return 0;
        }

        if (st.step () == Sqlite.ROW)
            return st.column_int (0);

        return 0;
    }

    private bool set_user_version (int version, out Error? error) {
        error = null;

        if (db.exec ("PRAGMA user_version = %d;".printf (version)) != Sqlite.OK) {
            error = new DatabaseError.SQLITE_FAILED ("Failed to set database schema version: %s".printf (db.errmsg ()));
            return false;
        }

        schema_version = version;
        return true;
    }

    private bool migrate_schema (int from_version, int to_version, out Error? error) {
        error = null;

        string backup_path;
        if (!backup_database_for_migration (from_version, to_version, out backup_path, out error))
            return false;

        message ("Backed up DB before migration: %s", backup_path);

        if (db.exec ("BEGIN IMMEDIATE;") != Sqlite.OK) {
            error = new DatabaseError.SQLITE_FAILED ("BEGIN migration transaction failed: %s".printf (db.errmsg ()));
            return false;
        }

        int current_version = from_version;
        bool ok = true;

        if (current_version < SCHEMA_VERSION_QSO_DELIVERY_STATUS) {
            ok = migrate_to_qso_delivery_status (out error);
            if (ok) {
                current_version = SCHEMA_VERSION_QSO_DELIVERY_STATUS;
                ok = set_user_version (current_version, out error);
            }
        }
        if (ok && current_version < SCHEMA_VERSION_PARK_DETAILS) {
            ok = migrate_to_park_details (out error);
            if (ok) {
                current_version = SCHEMA_VERSION_PARK_DETAILS;
                ok = set_user_version (current_version, out error);
            }
        }
        if (ok && current_version < SCHEMA_VERSION_QSO_SIGNAL_REPORTS) {
            ok = migrate_to_qso_signal_reports (out error);
            if (ok) {
                current_version = SCHEMA_VERSION_QSO_SIGNAL_REPORTS;
                ok = set_user_version (current_version, out error);
            }
        }
        if (ok && current_version < SCHEMA_VERSION_CANONICAL_PARK_QSO_DATES) {
            ok = migrate_to_canonical_park_qso_dates (out error);
            if (ok) {
                current_version = SCHEMA_VERSION_CANONICAL_PARK_QSO_DATES;
                ok = set_user_version (current_version, out error);
            }
        }

        if (!ok) {
            db.exec ("ROLLBACK;");
            schema_version = from_version;
            return false;
        }

        if (db.exec ("COMMIT;") != Sqlite.OK) {
            db.exec ("ROLLBACK;");
            schema_version = from_version;
            error = new DatabaseError.SQLITE_FAILED ("COMMIT migration transaction failed: %s".printf (db.errmsg ()));
            return false;
        }

        schema_version = current_version;
        return true;
    }

    private bool migrate_to_park_details (out Error? error) {
        error = null;

        var columns = load_park_columns (out error);
        if (error != null)
            return false;

        if (!add_park_column_if_missing (
            columns,
            "park_name",
            "ALTER TABLE parks ADD COLUMN park_name TEXT;",
            out error
        )) {
            return false;
        }
        if (!add_park_column_if_missing (
            columns,
            "location",
            "ALTER TABLE parks ADD COLUMN location TEXT;",
            out error
        )) {
            return false;
        }

        return true;
    }

    private bool backup_database_for_migration (
        int from_version,
        int to_version,
        out string backup_path,
        out Error? error
    ) {
        error = null;
        backup_path = "";

        var timestamp = new DateTime.now_utc ().format ("%Y%m%dT%H%M%SZ");
        backup_path = "%s.backup-v%d-to-v%d-%s-%s".printf (
            db_path,
            from_version,
            to_version,
            timestamp,
            Uuid.string_random ()
        );

        Sqlite.Database backup_db;
        int rc = Sqlite.Database.open (backup_path, out backup_db);
        if (rc != Sqlite.OK) {
            error = new DatabaseError.SQLITE_FAILED ("Failed to open migration backup database: SQLite error %d".printf (rc));
            return false;
        }

        var backup = new Sqlite.Backup (backup_db, "main", db, "main");
        rc = backup.step (-1);
        if (rc != Sqlite.DONE) {
            error = new DatabaseError.SQLITE_FAILED ("Failed to back up database before migration: %s".printf (
                backup_db.errmsg ()
            ));
            return false;
        }

        return true;
    }

    private bool migrate_to_qso_delivery_status (out Error? error) {
        error = null;

        var columns = load_qso_columns (out error);
        if (error != null)
            return false;

        if (!add_qso_column_if_missing (
            columns,
            "local_adif_saved",
            "ALTER TABLE qsos ADD COLUMN local_adif_saved INTEGER NOT NULL DEFAULT 0;",
            out error
        )) {
            return false;
        }
        if (!add_qso_column_if_missing (
            columns,
            "pota_spotted",
            "ALTER TABLE qsos ADD COLUMN pota_spotted INTEGER NOT NULL DEFAULT 0;",
            out error
        )) {
            return false;
        }
        if (!add_qso_column_if_missing (
            columns,
            "qrz_uploaded",
            "ALTER TABLE qsos ADD COLUMN qrz_uploaded INTEGER NOT NULL DEFAULT 0;",
            out error
        )) {
            return false;
        }
        if (!add_qso_column_if_missing (
            columns,
            "local_adif_error",
            "ALTER TABLE qsos ADD COLUMN local_adif_error TEXT;",
            out error
        )) {
            return false;
        }
        if (!add_qso_column_if_missing (
            columns,
            "pota_error",
            "ALTER TABLE qsos ADD COLUMN pota_error TEXT;",
            out error
        )) {
            return false;
        }
        if (!add_qso_column_if_missing (
            columns,
            "qrz_error",
            "ALTER TABLE qsos ADD COLUMN qrz_error TEXT;",
            out error
        )) {
            return false;
        }

        return true;
    }

    private bool migrate_to_qso_signal_reports (out Error? error) {
        error = null;

        var columns = load_qso_columns (out error);
        if (error != null)
            return false;

        if (!add_qso_column_if_missing (
            columns,
            "rst_sent",
            "ALTER TABLE qsos ADD COLUMN rst_sent TEXT;",
            out error
        )) {
            return false;
        }
        if (!add_qso_column_if_missing (
            columns,
            "rst_rcvd",
            "ALTER TABLE qsos ADD COLUMN rst_rcvd TEXT;",
            out error
        )) {
            return false;
        }

        return true;
    }

    private bool migrate_to_canonical_park_qso_dates (out Error? error) {
        error = null;

        const string SQL =
            """
            UPDATE parks
            SET first_qso_date = strftime('%Y-%m-%dT%H:%M:%SZ', first_qso_date)
            WHERE first_qso_date IS NOT NULL
              AND trim(first_qso_date) != ''
              AND strftime('%Y-%m-%dT%H:%M:%SZ', first_qso_date) IS NOT NULL;
            """;

        if (db.exec (SQL) != Sqlite.OK) {
            error = new DatabaseError.SQLITE_FAILED (
                "Failed to canonicalize park first QSO dates: %s".printf (db.errmsg ())
            );
            return false;
        }

        return true;
    }

    private HashSet<string> load_qso_columns (out Error? error) {
        error = null;
        var columns = new HashSet<string> ();

        Statement st;
        if (db.prepare_v2 ("PRAGMA table_info(qsos);", -1, out st) != Sqlite.OK) {
            error = new DatabaseError.SQLITE_FAILED ("Failed to inspect QSO schema: %s".printf (db.errmsg ()));
            return columns;
        }

        while (st.step () == Sqlite.ROW) {
            var column_name = st.column_text (1);
            if (column_name != null)
                columns.add (column_name);
        }

        return columns;
    }

    private HashSet<string> load_park_columns (out Error? error) {
        error = null;
        var columns = new HashSet<string> ();

        Statement st;
        if (db.prepare_v2 ("PRAGMA table_info(parks);", -1, out st) != Sqlite.OK) {
            error = new DatabaseError.SQLITE_FAILED ("Failed to inspect park schema: %s".printf (db.errmsg ()));
            return columns;
        }

        while (st.step () == Sqlite.ROW) {
            var column_name = st.column_text (1);
            if (column_name != null)
                columns.add (column_name);
        }

        return columns;
    }

    private bool add_qso_column_if_missing (
        HashSet<string> columns,
        string column_name,
        string sql,
        out Error? error
    ) {
        error = null;
        if (columns.contains (column_name))
            return true;

        if (db.exec (sql) != Sqlite.OK) {
            error = new DatabaseError.SQLITE_FAILED ("Failed to add QSO column %s: %s".printf (
                column_name,
                db.errmsg ()
            ));
            return false;
        }

        columns.add (column_name);
        return true;
    }

    private bool add_park_column_if_missing (
        HashSet<string> columns,
        string column_name,
        string sql,
        out Error? error
    ) {
        error = null;
        if (columns.contains (column_name))
            return true;

        if (db.exec (sql) != Sqlite.OK) {
            error = new DatabaseError.SQLITE_FAILED ("Failed to add park column %s: %s".printf (
                column_name,
                db.errmsg ()
            ));
            return false;
        }

        columns.add (column_name);
        return true;
    }

    private string qso_select_columns (string alias = "q") {
        var prefix = alias == "" ? "" : "%s.".printf (alias);
        var park_name_column = has_park_details ? "p.park_name" : "NULL";
        var rst_columns = has_qso_signal_reports ?
            "%srst_sent, %srst_rcvd".printf (prefix, prefix) :
            "NULL, NULL";
        var delivery_columns = has_qso_delivery_status ?
            "%slocal_adif_saved, %spota_spotted, %sqrz_uploaded, %slocal_adif_error, %spota_error, %sqrz_error".printf (
                prefix,
                prefix,
                prefix,
                prefix,
                prefix,
                prefix
            ) :
            "0, 0, 0, NULL, NULL, NULL";

        return "%sid, %spark_ref, %scallsign, %smode, %sfrequency_khz, %screated_utc, %sspotter, %sspotter_comment, %sactivator_comment, %s, %s, %s".printf (
            prefix,
            prefix,
            prefix,
            prefix,
            prefix,
            prefix,
            prefix,
            prefix,
            prefix,
            rst_columns,
            park_name_column,
            delivery_columns
        );
    }

    private string qso_park_join_sql () {
        return has_park_details ? "LEFT JOIN parks p ON p.reference = q.park_ref" : "";
    }

    private string qso_band_sql () {
        return """
            CASE
                WHEN q.frequency_khz >= 1800 AND q.frequency_khz < 2000 THEN '160m'
                WHEN q.frequency_khz >= 3500 AND q.frequency_khz < 4100 THEN '80m'
                WHEN q.frequency_khz >= 5250 AND q.frequency_khz < 5450 THEN '60m'
                WHEN q.frequency_khz >= 7000 AND q.frequency_khz < 7300 THEN '40m'
                WHEN q.frequency_khz >= 10100 AND q.frequency_khz < 10150 THEN '30m'
                WHEN q.frequency_khz >= 14000 AND q.frequency_khz < 14350 THEN '20m'
                WHEN q.frequency_khz >= 18068 AND q.frequency_khz < 18168 THEN '17m'
                WHEN q.frequency_khz >= 21000 AND q.frequency_khz < 21450 THEN '15m'
                WHEN q.frequency_khz >= 24890 AND q.frequency_khz < 24990 THEN '12m'
                WHEN q.frequency_khz >= 28000 AND q.frequency_khz < 29700 THEN '10m'
                WHEN q.frequency_khz >= 50000 AND q.frequency_khz < 54000 THEN '6m'
                WHEN q.frequency_khz >= 144000 AND q.frequency_khz < 148000 THEN '2m'
                WHEN q.frequency_khz >= 420000 AND q.frequency_khz < 450000 THEN '70cm'
                ELSE 'Other'
            END
        """;
    }

    private string sql_sort_direction (LogbookSortDirection direction) {
        return direction == LogbookSortDirection.ASC ? "ASC" : "DESC";
    }

    private string qso_order_by_sql (
        LogbookQsoSortColumn column,
        LogbookSortDirection direction
    ) {
        var dir = sql_sort_direction (direction);

        switch (column) {
            case LogbookQsoSortColumn.DATE:
                return "q.created_utc %s, q.id %s".printf (dir, dir);
            case LogbookQsoSortColumn.ACTIVATOR:
                return "q.callsign COLLATE NOCASE %s, q.created_utc DESC, q.id DESC".printf (dir);
            case LogbookQsoSortColumn.REFERENCE:
                return "q.park_ref COLLATE NOCASE %s, q.created_utc DESC, q.id DESC".printf (dir);
            case LogbookQsoSortColumn.PARK:
                return "%s COLLATE NOCASE %s, q.created_utc DESC, q.id DESC".printf (
                    has_park_details ? "p.park_name" : "q.park_ref",
                    dir
                );
            case LogbookQsoSortColumn.BAND:
                return "q.frequency_khz %s, q.created_utc DESC, q.id DESC".printf (dir);
            case LogbookQsoSortColumn.MODE:
                return "q.mode COLLATE NOCASE %s, q.created_utc DESC, q.id DESC".printf (dir);
            default:
                return "q.created_utc DESC, q.id DESC";
        }
    }

    private string hunted_park_order_by_sql (
        HuntedParkSortColumn column,
        LogbookSortDirection direction
    ) {
        var dir = sql_sort_direction (direction);

        switch (column) {
            case HuntedParkSortColumn.REFERENCE:
                return "p.reference COLLATE NOCASE %s".printf (dir);
            case HuntedParkSortColumn.PARK:
                return "%s COLLATE NOCASE %s, p.reference ASC".printf (
                    has_park_details ? "p.park_name" : "p.reference",
                    dir
                );
            case HuntedParkSortColumn.LOCATION:
                return "%s COLLATE NOCASE %s, p.reference ASC".printf (
                    has_park_details ? "p.location" : "p.reference",
                    dir
                );
            case HuntedParkSortColumn.QSOS:
                return "p.qso_count %s, p.reference ASC".printf (dir);
            case HuntedParkSortColumn.FIRST_QSO:
                return "p.first_qso_date %s, p.reference ASC".printf (dir);
            default:
                return "p.reference ASC";
        }
    }

    private string like_pattern (string search_text) {
        return "%%%s%%".printf (search_text.strip ());
    }

    private bool bind_qso_search_terms (
        Statement st,
        int start_index,
        string pattern,
        out Error? error
    ) {
        error = null;

        st.bind_text (start_index, pattern);
        st.bind_text (start_index + 1, pattern);
        st.bind_text (start_index + 2, pattern);
        st.bind_text (start_index + 3, pattern);
        st.bind_text (start_index + 4, pattern);
        st.bind_text (start_index + 5, pattern);

        return true;
    }

    private bool bind_park_search_terms (
        Statement st,
        int start_index,
        string pattern,
        out Error? error
    ) {
        error = null;

        st.bind_text (start_index, pattern);
        st.bind_text (start_index + 1, pattern);
        st.bind_text (start_index + 2, pattern);

        return true;
    }

    private int count_rows (string sql, string? search_pattern, bool is_park_search, out Error? error) {
        error = null;

        Statement st;
        if (db.prepare_v2 (sql, -1, out st) != Sqlite.OK) {
            error = new DatabaseError.SQLITE_FAILED ("Failed to prepare count query: %s".printf (db.errmsg ()));
            return 0;
        }

        if (search_pattern != null) {
            Error? bind_error;
            if (is_park_search)
                bind_park_search_terms (st, 1, search_pattern, out bind_error);
            else
                bind_qso_search_terms (st, 1, search_pattern, out bind_error);
            if (bind_error != null) {
                error = bind_error;
                return 0;
            }
        }

        if (st.step () != Sqlite.ROW) {
            error = new DatabaseError.SQLITE_FAILED ("Count query returned no rows");
            return 0;
        }

        return st.column_int (0);
    }

    public bool add_qso_from_spot (
        Spot spot,
        out bool inserted,
        out Error ? error
    ) {
        inserted = false;
        error = null;

        if (db == null) {
            error = new DatabaseError.DB_NOT_INITIALIZED ("DB not initialized");
            return false;
        }

        if (spot == null) {
            error = new DatabaseError.INVALID_ARGUMENT ("Spot is null");
            return false;
        }

        if ((spot.park_ref == null) || (spot.callsign == null) || (spot.
                                                                   spot_time
                                                                   == null)) {
            error = new DatabaseError.INVALID_ARGUMENT ("Required spot fields are null");
            return false;
        }

        if (db.exec ("BEGIN IMMEDIATE;") != Sqlite.OK) {
            error = new DatabaseError.SQLITE_FAILED ("BEGIN transaction failed: %s".printf (db.
                    errmsg ()));
            return false;
        }

        Sqlite.Statement st;
        string park_sql = has_park_details ?
            """
            INSERT INTO parks(reference, park_name, location) VALUES(?, ?, ?)
            ON CONFLICT(reference) DO UPDATE SET
                park_name = CASE
                    WHEN excluded.park_name IS NOT NULL AND excluded.park_name != ''
                    THEN excluded.park_name
                    ELSE parks.park_name
                END,
                location = CASE
                    WHEN excluded.location IS NOT NULL AND excluded.location != ''
                    THEN excluded.location
                    ELSE parks.location
                END;
            """ :
            """
            INSERT INTO parks(reference) VALUES(?)
            ON CONFLICT(reference) DO NOTHING;
            """;
        if (db.prepare_v2 (park_sql, -1, out st) != Sqlite.OK) {
            db.exec ("ROLLBACK;");
            error = new DatabaseError.SQLITE_FAILED ("Failed to prepare park insert: %s".printf (
                    db
                    .errmsg ()));
            return false;
        }
        st.bind_text (1, spot.park_ref);
        if (has_park_details) {
            bind_nullable_text (st, 2, spot.park_name);
            bind_nullable_text (st, 3, spot.location_desc);
        }

        if (st.step () != Sqlite.DONE) {
            db.exec ("ROLLBACK;");
            error = new DatabaseError.SQLITE_FAILED ("Park insert failed: %s".printf (db.errmsg ()
                    ))
            ;
            return false;
        }

        var created_utc = iso8601_from_borrowed_utc (spot.spot_time);
        const string QSO_SQL =
            """
            INSERT INTO qsos(
            park_ref, callsign, mode, frequency_khz, created_utc,
            spotter, spotter_comment, activator_comment, rst_sent, rst_rcvd
            )
            SELECT ?, ?, ?, ?, ?, ?, ?, ?, ?, ?
            WHERE NOT EXISTS (
                SELECT 1
                FROM qsos
                WHERE park_ref = ?
                  AND callsign = ?
                  AND IFNULL(mode, '') = IFNULL(?, '')
                  AND ABS(IFNULL(frequency_khz, 0) - ?) < 0.0005
                  AND created_utc = ?
                  AND IFNULL(spotter, '') = IFNULL(?, '')
            );
            """;
        if (db.prepare_v2 (QSO_SQL, -1, out st) != Sqlite.OK) {
            db.exec ("ROLLBACK;");
            error = new DatabaseError.SQLITE_FAILED ("Failed to prepare QSO insert: %s".printf (
                db.errmsg ()));
            return false;
        }

        st.bind_text (1, spot.park_ref);
        st.bind_text (2, spot.callsign);
        st.bind_text (3, spot.mode);
        st.bind_double (4, spot.frequency_khz);
        st.bind_text (5, created_utc);
        st.bind_text (6, spot.spotter);
        st.bind_text (7, spot.spotter_comment);
        st.bind_text (8, spot.activator_comment);
        bind_nullable_text (st, 9, spot.rst_sent);
        bind_nullable_text (st, 10, spot.rst_rcvd);
        st.bind_text (11, spot.park_ref);
        st.bind_text (12, spot.callsign);
        st.bind_text (13, spot.mode);
        st.bind_double (14, spot.frequency_khz);
        st.bind_text (15, created_utc);
        st.bind_text (16, spot.spotter);

        if (st.step () != Sqlite.DONE) {
            db.exec ("ROLLBACK;");
            error = new DatabaseError.SQLITE_FAILED ("QSO insert failed: %s".printf (db.errmsg
                        ()));
            return false;
        }
        inserted = db.changes () > 0;

        if (db.exec ("COMMIT;") != Sqlite.OK) {
            db.exec ("ROLLBACK;");
            inserted = false;
            error = new DatabaseError.SQLITE_FAILED ("COMMIT failed: %s".printf (db.errmsg ()));
            return false;
        }

        return true;
    } /* add_qso_from_spot */

    public bool update_qso_delivery_status (
        Spot spot,
        bool local_adif_saved,
        bool pota_posted,
        bool qrz_uploaded,
        string? local_adif_error,
        string? pota_error,
        string? qrz_error,
        out Error? error
    ) {
        error = null;

        if (!has_qso_delivery_status)
            return true;

        if (db == null) {
            error = new DatabaseError.DB_NOT_INITIALIZED ("DB not initialized");
            return false;
        }

        if ((spot == null) || (spot.park_ref == null) || (spot.callsign == null) ||
            (spot.spot_time == null)) {
            error = new DatabaseError.INVALID_ARGUMENT ("Required spot fields are null");
            return false;
        }

        var created_utc = iso8601_from_borrowed_utc (spot.spot_time);
        const string SQL =
            """
            UPDATE qsos
            SET local_adif_saved = ?,
                pota_spotted = ?,
                qrz_uploaded = ?,
                local_adif_error = ?,
                pota_error = ?,
                qrz_error = ?
            WHERE id = (
                SELECT id
                FROM qsos
                WHERE park_ref = ?
                  AND callsign = ?
                  AND IFNULL(mode, '') = IFNULL(?, '')
                  AND ABS(IFNULL(frequency_khz, 0) - ?) < 0.0005
                  AND created_utc = ?
                  AND IFNULL(spotter, '') = IFNULL(?, '')
                ORDER BY id DESC
                LIMIT 1
            );
            """;

        Statement st;
        if (db.prepare_v2 (SQL, -1, out st) != Sqlite.OK) {
            error = new DatabaseError.SQLITE_FAILED ("Failed to prepare QSO delivery status update: %s".printf (
                db.errmsg ()
            ));
            return false;
        }

        st.bind_int (1, local_adif_saved ? 1 : 0);
        st.bind_int (2, pota_posted ? 1 : 0);
        st.bind_int (3, qrz_uploaded ? 1 : 0);
        bind_nullable_text (st, 4, local_adif_error);
        bind_nullable_text (st, 5, pota_error);
        bind_nullable_text (st, 6, qrz_error);
        st.bind_text (7, spot.park_ref);
        st.bind_text (8, spot.callsign);
        st.bind_text (9, spot.mode);
        st.bind_double (10, spot.frequency_khz);
        st.bind_text (11, created_utc);
        st.bind_text (12, spot.spotter);

        if (st.step () != Sqlite.DONE) {
            error = new DatabaseError.SQLITE_FAILED ("QSO delivery status update failed: %s".printf (db.errmsg ()));
            return false;
        }

        return true;
    }

    public bool update_qso_from_spot (int64 qso_id, Spot spot, out Error? error) {
        error = null;

        if (db == null) {
            error = new DatabaseError.DB_NOT_INITIALIZED ("DB not initialized");
            return false;
        }

        if (qso_id <= 0) {
            error = new DatabaseError.INVALID_ARGUMENT ("QSO id is invalid");
            return false;
        }
        if ((spot == null) || (spot.park_ref == null) || (spot.callsign == null) ||
            (spot.spot_time == null)) {
            error = new DatabaseError.INVALID_ARGUMENT ("Required spot fields are null");
            return false;
        }

        var created_utc = iso8601_from_borrowed_utc (spot.spot_time);

        if (db.exec ("BEGIN IMMEDIATE;") != Sqlite.OK) {
            error = new DatabaseError.SQLITE_FAILED ("BEGIN QSO update transaction failed: %s".printf (db.errmsg ()));
            return false;
        }

        Statement st;
        string park_sql = has_park_details ?
            """
            INSERT INTO parks(reference, park_name, location) VALUES(?, ?, ?)
            ON CONFLICT(reference) DO UPDATE SET
                park_name = CASE
                    WHEN excluded.park_name IS NOT NULL AND excluded.park_name != ''
                    THEN excluded.park_name
                    ELSE parks.park_name
                END,
                location = CASE
                    WHEN excluded.location IS NOT NULL AND excluded.location != ''
                    THEN excluded.location
                    ELSE parks.location
                END;
            """ :
            """
            INSERT INTO parks(reference) VALUES(?)
            ON CONFLICT(reference) DO NOTHING;
            """;
        if (db.prepare_v2 (park_sql, -1, out st) != Sqlite.OK) {
            db.exec ("ROLLBACK;");
            error = new DatabaseError.SQLITE_FAILED ("Failed to prepare QSO update park upsert: %s".printf (db.errmsg ()));
            return false;
        }
        st.bind_text (1, spot.park_ref);
        if (has_park_details) {
            bind_nullable_text (st, 2, spot.park_name);
            bind_nullable_text (st, 3, spot.location_desc);
        }
        if (st.step () != Sqlite.DONE) {
            db.exec ("ROLLBACK;");
            error = new DatabaseError.SQLITE_FAILED ("QSO update park upsert failed: %s".printf (db.errmsg ()));
            return false;
        }

        const string OLD_PARK_SQL = "SELECT park_ref FROM qsos WHERE id = ?;";
        string? old_park_ref = null;
        if (db.prepare_v2 (OLD_PARK_SQL, -1, out st) != Sqlite.OK) {
            db.exec ("ROLLBACK;");
            error = new DatabaseError.SQLITE_FAILED ("Failed to prepare QSO old park lookup: %s".printf (db.errmsg ()));
            return false;
        }
        st.bind_int64 (1, qso_id);
        if (st.step () == Sqlite.ROW)
            old_park_ref = st.column_text (0);

        const string QSO_SQL =
            """
            UPDATE qsos
            SET park_ref = ?,
                callsign = ?,
                mode = ?,
                frequency_khz = ?,
                created_utc = ?,
                spotter = ?,
                spotter_comment = ?,
                activator_comment = ?,
                rst_sent = ?,
                rst_rcvd = ?
            WHERE id = ?;
            """;
        if (db.prepare_v2 (QSO_SQL, -1, out st) != Sqlite.OK) {
            db.exec ("ROLLBACK;");
            error = new DatabaseError.SQLITE_FAILED ("Failed to prepare QSO update: %s".printf (db.errmsg ()));
            return false;
        }
        st.bind_text (1, spot.park_ref);
        st.bind_text (2, spot.callsign);
        st.bind_text (3, spot.mode);
        st.bind_double (4, spot.frequency_khz);
        st.bind_text (5, created_utc);
        st.bind_text (6, spot.spotter);
        st.bind_text (7, spot.spotter_comment);
        st.bind_text (8, spot.activator_comment);
        bind_nullable_text (st, 9, spot.rst_sent);
        bind_nullable_text (st, 10, spot.rst_rcvd);
        st.bind_int64 (11, qso_id);
        if (st.step () != Sqlite.DONE) {
            db.exec ("ROLLBACK;");
            error = new DatabaseError.SQLITE_FAILED ("QSO update failed: %s".printf (db.errmsg ()));
            return false;
        }

        if (has_text (old_park_ref) &&
            !refresh_park_qso_summary (old_park_ref, out error)) {
            db.exec ("ROLLBACK;");
            return false;
        }
        if (has_text (spot.park_ref) &&
            !refresh_park_qso_summary (spot.park_ref, out error)) {
            db.exec ("ROLLBACK;");
            return false;
        }

        if (db.exec ("COMMIT;") != Sqlite.OK) {
            db.exec ("ROLLBACK;");
            error = new DatabaseError.SQLITE_FAILED ("COMMIT QSO update failed: %s".printf (db.errmsg ()));
            return false;
        }

        return true;
    }

    public bool delete_qso (int64 qso_id, out Error? error) {
        error = null;

        if (db == null) {
            error = new DatabaseError.DB_NOT_INITIALIZED ("DB not initialized");
            return false;
        }

        if (qso_id <= 0) {
            error = new DatabaseError.INVALID_ARGUMENT ("QSO id is invalid");
            return false;
        }

        if (db.exec ("BEGIN IMMEDIATE;") != Sqlite.OK) {
            error = new DatabaseError.SQLITE_FAILED ("BEGIN QSO delete transaction failed: %s".printf (db.errmsg ()));
            return false;
        }

        Statement st;
        const string OLD_PARK_SQL = "SELECT park_ref FROM qsos WHERE id = ?;";
        string? old_park_ref = null;
        if (db.prepare_v2 (OLD_PARK_SQL, -1, out st) != Sqlite.OK) {
            db.exec ("ROLLBACK;");
            error = new DatabaseError.SQLITE_FAILED ("Failed to prepare QSO delete park lookup: %s".printf (db.errmsg ()));
            return false;
        }
        st.bind_int64 (1, qso_id);
        if (st.step () == Sqlite.ROW)
            old_park_ref = st.column_text (0);

        if (old_park_ref == null) {
            db.exec ("ROLLBACK;");
            error = new DatabaseError.INVALID_ARGUMENT ("QSO does not exist");
            return false;
        }

        const string DELETE_SQL = "DELETE FROM qsos WHERE id = ?;";
        if (db.prepare_v2 (DELETE_SQL, -1, out st) != Sqlite.OK) {
            db.exec ("ROLLBACK;");
            error = new DatabaseError.SQLITE_FAILED ("Failed to prepare QSO delete: %s".printf (db.errmsg ()));
            return false;
        }
        st.bind_int64 (1, qso_id);
        if (st.step () != Sqlite.DONE) {
            db.exec ("ROLLBACK;");
            error = new DatabaseError.SQLITE_FAILED ("QSO delete failed: %s".printf (db.errmsg ()));
            return false;
        }

        if (!refresh_park_qso_summary (old_park_ref, out error)) {
            db.exec ("ROLLBACK;");
            return false;
        }

        if (db.exec ("COMMIT;") != Sqlite.OK) {
            db.exec ("ROLLBACK;");
            error = new DatabaseError.SQLITE_FAILED ("COMMIT QSO delete failed: %s".printf (db.errmsg ()));
            return false;
        }

        return true;
    }

    private bool refresh_park_qso_summary (string park_ref, out Error? error) {
        error = null;

        if (is_empty_or_whitespace (park_ref))
            return true;

        const string SQL =
            """
            UPDATE parks
            SET qso_count = (
                    SELECT COUNT(*)
                    FROM qsos
                    WHERE park_ref = ?
                ),
                first_qso_date = (
                    SELECT MIN(created_utc)
                    FROM qsos
                    WHERE park_ref = ?
                )
            WHERE reference = ?;
            """;

        Statement st;
        if (db.prepare_v2 (SQL, -1, out st) != Sqlite.OK) {
            error = new DatabaseError.SQLITE_FAILED ("Failed to prepare park QSO summary refresh: %s".printf (db.errmsg ()));
            return false;
        }

        st.bind_text (1, park_ref);
        st.bind_text (2, park_ref);
        st.bind_text (3, park_ref);
        if (st.step () != Sqlite.DONE) {
            error = new DatabaseError.SQLITE_FAILED ("Park QSO summary refresh failed: %s".printf (db.errmsg ()));
            return false;
        }

        return true;
    }

    /* ----- add park ----- */
    public bool add_park (string reference,
        string ? park_name,
        string ? dx_entity,
        string ? location,
        string ? hasc,
        string ? first_qso_date,
        int qso_count,
        out Error ? error) {
        error = null;
        if (db == null) {
            error = new DatabaseError.DB_NOT_INITIALIZED ("DB not initialized");
            return false;
        }
        if (is_empty_or_whitespace (reference)) {
            error = new DatabaseError.INVALID_ARGUMENT ("Park reference cannot be empty");
            return false;
        }

        string sql = has_park_details ?
            """
        INSERT INTO parks(reference, park_name, location, first_qso_date, qso_count)
        VALUES(?, ?, ?, ?, ?)
        ON CONFLICT(reference) DO UPDATE SET
            park_name = COALESCE(excluded.park_name, parks.park_name),
            location = COALESCE(excluded.location, parks.location),
            first_qso_date = COALESCE(excluded.first_qso_date, parks.first_qso_date),
            qso_count = MAX(parks.qso_count, excluded.qso_count);
        """ :
            """
        INSERT INTO parks(reference, first_qso_date, qso_count)
        VALUES(?, ?, ?)
        ON CONFLICT(reference) DO UPDATE SET
            first_qso_date = COALESCE(excluded.first_qso_date, parks.first_qso_date),
            qso_count = MAX(parks.qso_count, excluded.qso_count);
        """;

        Statement st;
        if (db.prepare_v2 (sql, -1, out st) != Sqlite.OK) {
            error = new DatabaseError.SQLITE_FAILED ("Failed to prepare add park query: %s".printf (db.errmsg ()));
            return false;
        }
        st.bind_text (1, reference);
        int first_qso_index = 2;
        int qso_count_index = 3;
        if (has_park_details) {
            bind_nullable_text (st, 2, park_name);
            bind_nullable_text (st, 3, location);
            first_qso_index = 4;
            qso_count_index = 5;
        }
        if (has_text (first_qso_date))
            st.bind_text (first_qso_index, first_qso_date);
        else
            st.bind_null (first_qso_index);
        st.bind_int (qso_count_index, qso_count >= 0 ? qso_count : 0);
        if (st.step () != Sqlite.DONE) {
            error = new DatabaseError.SQLITE_FAILED ("Failed to execute add park query: %s".printf (db.errmsg ()));
            return false;
        }
        return true;
    } /* add_park */

    public ParkRow? lookup_park_details (string reference, out Error? error) {
        error = null;

        if (db == null) {
            error = new DatabaseError.DB_NOT_INITIALIZED ("DB not initialized");
            return null;
        }
        if (is_empty_or_whitespace (reference)) {
            error = new DatabaseError.INVALID_ARGUMENT ("Park reference cannot be empty");
            return null;
        }
        if (!has_park_details)
            return null;

        const string SQL =
            """
            SELECT reference, park_name, location
            FROM parks
            WHERE reference = ?
              AND park_name IS NOT NULL
              AND park_name != ''
            LIMIT 1;
            """;

        Statement st;
        if (db.prepare_v2 (SQL, -1, out st) != Sqlite.OK) {
            error = new DatabaseError.SQLITE_FAILED ("Failed to prepare park details lookup: %s".printf (db.errmsg ()));
            return null;
        }
        st.bind_text (1, strip_up (reference));

        if (st.step () != Sqlite.ROW)
            return null;

        return new ParkRow.from_statement (st);
    }

    /* ----- is park hunted ----- */
    public bool is_park_hunted (string park_reference, out Error? error) {
        error = null;
        if (db == null) {
            error = new DatabaseError.DB_NOT_INITIALIZED ("DB not initialized");
            return false;
        }
        if (is_empty_or_whitespace (park_reference)) {
            error = new DatabaseError.INVALID_ARGUMENT ("Park reference cannot be empty");
            return false;
        }

        const string SQL =
            "SELECT qso_count FROM parks WHERE reference = ? AND qso_count > 0;";
        if (is_park_hunted_stmt == null &&
            db.prepare_v2 (SQL, -1, out is_park_hunted_stmt) != Sqlite.OK) {
            error = new DatabaseError.SQLITE_FAILED ("Failed to prepare park hunted query: %s".printf (db.errmsg ()
                    ))
            ;
            return false;
        }
        unowned Statement st = is_park_hunted_stmt;
        st.reset ();
        st.clear_bindings ();
        st.bind_text (1, park_reference);
        var rc = st.step ();
        bool hunted = (rc == Sqlite.ROW);
        return hunted;
    }

    public SpotLogStatusSnapshot load_log_status_snapshot (
        DateTime utc_day,
        out Error? error
    ) {
        error = null;
        var snapshot = new SpotLogStatusSnapshot ();

        if (db == null) {
            error = new DatabaseError.DB_NOT_INITIALIZED ("DB not initialized");
            return snapshot;
        }

        if (!load_hunted_parks (snapshot, out error))
            return snapshot;
        if (!load_hunted_today (snapshot, utc_day, out error))
            return snapshot;
        if (!load_hunted_park_bands (snapshot, out error))
            return snapshot;

        return snapshot;
    }

    private bool load_hunted_parks (
        SpotLogStatusSnapshot snapshot,
        out Error? error
    ) {
        error = null;

        const string SQL =
            "SELECT reference FROM parks WHERE qso_count > 0;";

        Statement st;
        if (db.prepare_v2 (SQL, -1, out st) != Sqlite.OK) {
            error = new DatabaseError.SQLITE_FAILED ("Failed to prepare hunted parks snapshot query: %s".printf (
                db.errmsg ()));
            return false;
        }

        while (st.step () == Sqlite.ROW) {
            var park_ref = st.column_text (0);
            if (has_text (park_ref))
                snapshot.hunted_parks.add (park_ref);
        }

        return true;
    }

    private bool load_hunted_today (
        SpotLogStatusSnapshot snapshot,
        DateTime utc_day,
        out Error? error
    ) {
        error = null;

        DateTime utc = utc_day.to_utc ();
        string start_iso = iso8601_day_start (utc);
        string next_iso = iso8601_next_day_start (utc);

        const string SQL =
            """
          SELECT DISTINCT park_ref
          FROM qsos
          WHERE created_utc >= ? AND created_utc < ?;
          """;

        Statement st;
        if (db.prepare_v2 (SQL, -1, out st) != Sqlite.OK) {
            error = new DatabaseError.SQLITE_FAILED ("Failed to prepare hunted today snapshot query: %s".printf (
                db.errmsg ()));
            return false;
        }

        st.bind_text (1, start_iso);
        st.bind_text (2, next_iso);
        while (st.step () == Sqlite.ROW) {
            var park_ref = st.column_text (0);
            if (has_text (park_ref))
                snapshot.hunted_today.add (park_ref);
        }

        return true;
    }

    private bool load_hunted_park_bands (
        SpotLogStatusSnapshot snapshot,
        out Error? error
    ) {
        error = null;

        const string SQL =
            """
          SELECT DISTINCT park_ref, frequency_khz
          FROM qsos
          WHERE frequency_khz IS NOT NULL AND frequency_khz > 0;
          """;

        Statement st;
        if (db.prepare_v2 (SQL, -1, out st) != Sqlite.OK) {
            error = new DatabaseError.SQLITE_FAILED ("Failed to prepare hunted band snapshot query: %s".printf (
                db.errmsg ()));
            return false;
        }

        while (st.step () == Sqlite.ROW) {
            var park_ref = st.column_text (0);
            if (is_empty_or_whitespace (park_ref))
                continue;

            var band = band_from_khz (st.column_double (1));
            if (band == "Other")
                continue;

            snapshot.hunted_park_bands.add (
                SpotLogStatusSnapshot.park_band_key (park_ref, band)
            );
        }

        return true;
    }

    public ParkRow? get_park_by_ref (string park_ref, out Error? error) {
        error = null;

        if (db == null) {
            error = new DatabaseError.DB_NOT_INITIALIZED ("DB not initialized");
            return null;
        }

        if (is_empty_or_whitespace (park_ref)) {
            error = new DatabaseError.INVALID_ARGUMENT ("Park reference cannot be empty");
            return null;
        }

        const string SQL =
            """
            SELECT reference
            FROM parks
            WHERE reference = ?
            LIMIT 1;
        """;

        Statement st;
        if (db.prepare_v2 (SQL, -1, out st) != Sqlite.OK) {
            error = new DatabaseError.SQLITE_FAILED ("Failed to prepare get_park_by_ref query: %s".printf (db.errmsg
                        ()));
            return null;
        }

        st.bind_text (1, park_ref);

        if (st.step () == Sqlite.ROW)
            return new ParkRow.from_statement (st);

        // No row found
        return null;
    } /* get_park_by_ref */

    public Gee.ArrayList<QsoRow> latest_qso_per_park (out Error ? error) {
        error = null;
        var rows = new Gee.ArrayList<QsoRow> ();
        if (db == null) {
            error = new DatabaseError.DB_NOT_INITIALIZED ("DB not initialized");
            return rows;
        }

        string sql =
            """
          SELECT %s
          FROM qsos q
          %s
          JOIN (
            SELECT park_ref, MAX(created_utc) AS maxc
            FROM qsos
            WHERE park_ref != ''
            GROUP BY park_ref
          ) t
            ON q.park_ref = t.park_ref AND q.created_utc = t.maxc
          ORDER BY q.created_utc DESC;
          """.printf (qso_select_columns (), qso_park_join_sql ());

        Statement st;
        if (db.prepare_v2 (sql, -1, out st) != Sqlite.OK) {
            error = new DatabaseError.SQLITE_FAILED ("Failed to prepare latest_qso_per_park query: %s".printf (db.
                    errmsg ()));
            return rows;
        }
        while (st.step () == Sqlite.ROW) {
            rows.add (new QsoRow.from_statement (st, has_qso_delivery_status, has_qso_signal_reports));
        }
        return rows;
    }

    public Gee.ArrayList<QsoRow> latest_qsos (int limit, out Error? error) {
        error = null;
        var rows = new Gee.ArrayList<QsoRow> ();
        if (db == null) {
            error = new DatabaseError.DB_NOT_INITIALIZED ("DB not initialized");
            return rows;
        }
        if (limit <= 0)
            limit = 50;

        string sql =
            """
          SELECT %s
          FROM qsos q
          %s
          ORDER BY q.created_utc DESC
          LIMIT ?;
          """.printf (qso_select_columns (), qso_park_join_sql ());

        Statement st;
        if (db.prepare_v2 (sql, -1, out st) != Sqlite.OK) {
            error = new DatabaseError.SQLITE_FAILED ("Failed to prepare latest_qsos query: %s".printf (db.errmsg ()
                    ))
            ;
            return rows;
        }
        st.bind_int (1, limit);
        while (st.step () == Sqlite.ROW) {
            rows.add (new QsoRow.from_statement (st, has_qso_delivery_status, has_qso_signal_reports));
        }
        return rows;
    }

    public LogbookQsoPage load_qso_page (
        int limit,
        int offset,
        string search_text,
        LogbookQsoSortColumn sort_column,
        LogbookSortDirection sort_direction,
        out Error? error
    ) {
        error = null;
        var rows = new Gee.ArrayList<QsoRow> ();
        if (db == null) {
            error = new DatabaseError.DB_NOT_INITIALIZED ("DB not initialized");
            return new LogbookQsoPage (rows, 0);
        }
        if (limit <= 0)
            limit = 50;
        if (offset < 0)
            offset = 0;

        var trimmed_search = search_text.strip ();
        string search_sql = "";
        string? search_pattern = null;
        if (trimmed_search != "") {
            var park_name_expr = has_park_details ? "p.park_name" : "q.park_ref";
            search_sql = """
                WHERE q.callsign LIKE ? COLLATE NOCASE
                   OR q.park_ref LIKE ? COLLATE NOCASE
                   OR %s LIKE ? COLLATE NOCASE
                   OR q.mode LIKE ? COLLATE NOCASE
                   OR CAST(q.frequency_khz AS TEXT) LIKE ?
                   OR %s LIKE ? COLLATE NOCASE
            """.printf (park_name_expr, qso_band_sql ());
            search_pattern = like_pattern (trimmed_search);
        }

        string count_sql =
            """
            SELECT COUNT(*)
            FROM qsos q
            %s
            %s;
            """.printf (qso_park_join_sql (), search_sql);
        var total_count = count_rows (count_sql, search_pattern, false, out error);
        if (error != null)
            return new LogbookQsoPage (rows, 0);

        string sql =
            """
            SELECT %s
            FROM qsos q
            %s
            %s
            ORDER BY %s
            LIMIT ?
            OFFSET ?;
            """.printf (
                qso_select_columns (),
                qso_park_join_sql (),
                search_sql,
                qso_order_by_sql (sort_column, sort_direction)
            );

        Statement st;
        if (db.prepare_v2 (sql, -1, out st) != Sqlite.OK) {
            error = new DatabaseError.SQLITE_FAILED ("Failed to prepare logbook QSO page query: %s".printf (
                db.errmsg ()
            ));
            return new LogbookQsoPage (rows, total_count);
        }

        var bind_index = 1;
        if (search_pattern != null) {
            Error? bind_error;
            bind_qso_search_terms (st, bind_index, search_pattern, out bind_error);
            if (bind_error != null) {
                error = bind_error;
                return new LogbookQsoPage (rows, total_count);
            }
            bind_index += 6;
        }
        st.bind_int (bind_index++, limit);
        st.bind_int (bind_index, offset);

        while (st.step () == Sqlite.ROW)
            rows.add (new QsoRow.from_statement (st, has_qso_delivery_status, has_qso_signal_reports));

        return new LogbookQsoPage (rows, total_count);
    }

    public Gee.ArrayList<HuntedParkRow> hunted_parks (out Error? error) {
        error = null;
        var rows = new Gee.ArrayList<HuntedParkRow> ();
        if (db == null) {
            error = new DatabaseError.DB_NOT_INITIALIZED ("DB not initialized");
            return rows;
        }

        string sql = has_park_details ?
            """
            SELECT p.reference, p.park_name, p.location, p.first_qso_date, p.qso_count,
                   q.created_utc, q.callsign, q.mode, q.frequency_khz
            FROM parks p
            LEFT JOIN qsos q
              ON q.id = (
                SELECT id
                FROM qsos
                WHERE park_ref = p.reference
                ORDER BY created_utc DESC, id DESC
                LIMIT 1
              )
            WHERE p.qso_count > 0 AND p.reference != ''
            ORDER BY q.created_utc DESC, p.reference ASC;
            """ :
            """
            SELECT p.reference, NULL, NULL, p.first_qso_date, p.qso_count,
                   q.created_utc, q.callsign, q.mode, q.frequency_khz
            FROM parks p
            LEFT JOIN qsos q
              ON q.id = (
                SELECT id
                FROM qsos
                WHERE park_ref = p.reference
                ORDER BY created_utc DESC, id DESC
                LIMIT 1
              )
            WHERE p.qso_count > 0 AND p.reference != ''
            ORDER BY q.created_utc DESC, p.reference ASC;
            """;

        Statement st;
        if (db.prepare_v2 (sql, -1, out st) != Sqlite.OK) {
            error = new DatabaseError.SQLITE_FAILED ("Failed to prepare hunted parks query: %s".printf (db.errmsg ()));
            return rows;
        }

        while (st.step () == Sqlite.ROW)
            rows.add (new HuntedParkRow.from_statement (st));

        return rows;
    }

    public HuntedParkPage load_hunted_park_page (
        int limit,
        int offset,
        string search_text,
        HuntedParkSortColumn sort_column,
        LogbookSortDirection sort_direction,
        out Error? error
    ) {
        error = null;
        var rows = new Gee.ArrayList<HuntedParkRow> ();
        if (db == null) {
            error = new DatabaseError.DB_NOT_INITIALIZED ("DB not initialized");
            return new HuntedParkPage (rows, 0);
        }
        if (limit <= 0)
            limit = 50;
        if (offset < 0)
            offset = 0;

        var trimmed_search = search_text.strip ();
        string search_sql = "";
        string? search_pattern = null;
        if (trimmed_search != "") {
            search_sql = has_park_details ?
                """
                AND (
                    p.reference LIKE ? COLLATE NOCASE
                    OR p.park_name LIKE ? COLLATE NOCASE
                    OR p.location LIKE ? COLLATE NOCASE
                )
                """ :
                """
                AND (
                    p.reference LIKE ? COLLATE NOCASE
                    OR p.reference LIKE ? COLLATE NOCASE
                    OR p.reference LIKE ? COLLATE NOCASE
                )
                """;
            search_pattern = like_pattern (trimmed_search);
        }

        string count_sql =
            """
            SELECT COUNT(*)
            FROM parks p
            WHERE p.qso_count > 0 AND p.reference != ''
            %s;
            """.printf (search_sql);
        var total_count = count_rows (count_sql, search_pattern, true, out error);
        if (error != null)
            return new HuntedParkPage (rows, 0);

        string sql = has_park_details ?
            """
            SELECT p.reference, p.park_name, p.location, p.first_qso_date, p.qso_count,
                   q.created_utc, q.callsign, q.mode, q.frequency_khz
            FROM parks p
            LEFT JOIN qsos q
              ON q.id = (
                SELECT id
                FROM qsos
                WHERE park_ref = p.reference
                ORDER BY created_utc DESC, id DESC
                LIMIT 1
              )
            WHERE p.qso_count > 0 AND p.reference != ''
            %s
            ORDER BY %s
            LIMIT ?
            OFFSET ?;
            """.printf (search_sql, hunted_park_order_by_sql (sort_column, sort_direction)) :
            """
            SELECT p.reference, NULL, NULL, p.first_qso_date, p.qso_count,
                   q.created_utc, q.callsign, q.mode, q.frequency_khz
            FROM parks p
            LEFT JOIN qsos q
              ON q.id = (
                SELECT id
                FROM qsos
                WHERE park_ref = p.reference
                ORDER BY created_utc DESC, id DESC
                LIMIT 1
              )
            WHERE p.qso_count > 0 AND p.reference != ''
            %s
            ORDER BY %s
            LIMIT ?
            OFFSET ?;
            """.printf (search_sql, hunted_park_order_by_sql (sort_column, sort_direction));

        Statement st;
        if (db.prepare_v2 (sql, -1, out st) != Sqlite.OK) {
            error = new DatabaseError.SQLITE_FAILED ("Failed to prepare hunted parks page query: %s".printf (
                db.errmsg ()
            ));
            return new HuntedParkPage (rows, total_count);
        }

        var bind_index = 1;
        if (search_pattern != null) {
            Error? bind_error;
            bind_park_search_terms (st, bind_index, search_pattern, out bind_error);
            if (bind_error != null) {
                error = bind_error;
                return new HuntedParkPage (rows, total_count);
            }
            bind_index += 3;
        }
        st.bind_int (bind_index++, limit);
        st.bind_int (bind_index, offset);

        while (st.step () == Sqlite.ROW)
            rows.add (new HuntedParkRow.from_statement (st));

        return new HuntedParkPage (rows, total_count);
    }

    public ArrayList<QsoRow>? all_qsos_for_park (string park_ref, out Error? error) {
        var list = new ArrayList<QsoRow> ();

        error = null;
        if (db == null) {
            error = new DatabaseError.DB_NOT_INITIALIZED ("DB not initialized");
            return null;
        }
        if ((park_ref == null) || (park_ref.strip () == "")) {
            error = new DatabaseError.INVALID_ARGUMENT ("Park reference cannot be empty");
            return null;
        }

        string sql =
            """
        SELECT %s
        FROM qsos q
        %s
        WHERE q.park_ref = ?
        ORDER BY q.created_utc DESC;
        """.printf (qso_select_columns (), qso_park_join_sql ());

        Statement st;
        if (db.prepare_v2 (sql, -1, out st) != Sqlite.OK) {
            error = new DatabaseError.SQLITE_FAILED ("Failed to prepare latest_qso_for_park query: %s".printf (db.
                    errmsg ()));
            return null;
        }
        st.bind_text (1, park_ref);

        while (st.step () == Sqlite.ROW) {
            var row = new QsoRow.from_statement (st, has_qso_delivery_status, has_qso_signal_reports);
            list.add (row);
        }
        return list;
    } /* all_qsos_for_park */

    public QsoRow? latest_qso_for_park (string park_ref, out Error ? error) {
        error = null;
        if (db == null) {
            error = new DatabaseError.DB_NOT_INITIALIZED ("DB not initialized");
            return null;
        }
        if ((park_ref == null) || (park_ref.strip () == "")) {
            error = new DatabaseError.INVALID_ARGUMENT ("Park reference cannot be empty");
            return null;
        }

        string sql =
            """
        SELECT %s
        FROM qsos q
        %s
        WHERE q.park_ref = ?
        ORDER BY q.created_utc DESC
        LIMIT 1;
        """.printf (qso_select_columns (), qso_park_join_sql ());

        Statement st;
        if (db.prepare_v2 (sql, -1, out st) != Sqlite.OK) {
            error = new DatabaseError.SQLITE_FAILED ("Failed to prepare latest_qso_for_park query: %s".printf (db.
                    errmsg ()));
            return null;
        }
        st.bind_text (1, park_ref);
        QsoRow? row = null;
        if (st.step () == Sqlite.ROW)
            row = new QsoRow.from_statement (st, has_qso_delivery_status, has_qso_signal_reports);
        return row;
    } /* latest_qso_for_park */

    public bool had_qso_with_park_on_utc_day (string park_ref, DateTime
        utc_when_in_day, out Error ? error) {
        error = null;
        if (db == null) {
            error = new DatabaseError.DB_NOT_INITIALIZED ("DB not initialized");
            return false;
        }

        if ((park_ref == null) || (park_ref.strip () == "")) {
            error = new DatabaseError.INVALID_ARGUMENT ("Park reference cannot be empty");
            return false;
        }

        DateTime utc = utc_when_in_day.to_utc ();
        string start_iso = iso8601_day_start (utc);
        string next_iso = iso8601_next_day_start (utc);

        const string SQL =
            """
          SELECT EXISTS (
            SELECT 1
            FROM qsos
            WHERE park_ref = ? AND created_utc >= ? AND created_utc < ?
          );
          """;

        if (had_qso_on_utc_day_stmt == null &&
            db.prepare_v2 (SQL, -1, out had_qso_on_utc_day_stmt) != Sqlite.OK) {
            error = new DatabaseError.SQLITE_FAILED ("Failed to prepare had_qso_with_park_on_utc_day query: %s".
                printf (db.errmsg ()));
            return false;
        }
        unowned Statement st = had_qso_on_utc_day_stmt;
        st.reset ();
        st.clear_bindings ();
        st.bind_text (1, park_ref);
        st.bind_text (2, start_iso);
        st.bind_text (3, next_iso);
        bool exists = false;
        if (st.step () == Sqlite.ROW)
            exists = st.column_int (0) != 0;
        return exists;
    } /* had_qso_with_park_on_utc_day */

    public bool had_qso_with_park_on_band (string park_ref, string band, out Error? error) {
        error = null;
        if (db == null) {
            error = new DatabaseError.DB_NOT_INITIALIZED ("DB not initialized");
            return false;
        }

        if ((park_ref == null) || (park_ref.strip () == "")) {
            error = new DatabaseError.INVALID_ARGUMENT ("Park reference cannot be empty");
            return false;
        }

        int min_khz = 0;
        int max_khz = 0;
        if (!band_frequency_range_khz (band, out min_khz, out max_khz)) {
            error = new DatabaseError.INVALID_ARGUMENT ("Band %s does not map to a known frequency range".printf (band));
            return false;
        }

        const string SQL =
            """
          SELECT EXISTS (
            SELECT 1
            FROM qsos
            WHERE park_ref = ? AND frequency_khz >= ? AND frequency_khz < ?
          );
          """;

        if (had_qso_on_band_stmt == null &&
            db.prepare_v2 (SQL, -1, out had_qso_on_band_stmt) != Sqlite.OK) {
            error = new DatabaseError.SQLITE_FAILED ("Failed to prepare had_qso_with_park_on_band query: %s".printf (
                    db.errmsg ()));
            return false;
        }

        unowned Statement st = had_qso_on_band_stmt;
        st.reset ();
        st.clear_bindings ();
        st.bind_text (1, park_ref);
        st.bind_int (2, min_khz);
        st.bind_int (3, max_khz);

        bool exists = false;
        if (st.step () == Sqlite.ROW)
            exists = st.column_int (0) != 0;
        return exists;
    }

} /* class SpotDb */
