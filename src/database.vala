using Gee;
using GLib;
using Sqlite;

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

public sealed class QsoRow : Object {
    public int64 id;
    public string ? park_ref;
    public string ? callsign;
    public string ? mode;
    public int frequency_khz;
    public string ? created_utc;
    public string ? spotter;
    public string ? spotter_comment;
    public string ? activator_comment;
}

public sealed class ParkRow : Object {
    public int id { get; construct; }
    public string reference { get; construct; }
    public string name { get; construct; }
    public string location_desc { get; construct; }
    public double latitude { get; construct; }
    public double longitude { get; construct; }
    public ParkRow (int id,
                    string reference,
                    string name,
                    string location_desc,
                    double latitude,
                    double longitude) {
        Object (
            id: id,
            reference: reference,
            name: name,
            location_desc: location_desc,
            latitude: latitude,
            longitude: longitude
            );
    }
} /* class ParkRow */

public enum DatabaseError {
    DB_NOT_INITIALIZED,
    INVALID_ARGUMENT,
    SQLITE_FAILED
}

public static GLib.Quark spot_db_error_quark () {
    return GLib.Quark.from_string ("spot-db-error");
}

public class SpotDb : Object {
    private Sqlite.Database? db = null;

    public SpotDb () {}

    private bool init (out Error? error) {
        error = null;
        // build paths
        string data_dir = Environment.get_user_data_dir ();
        string app_dir = Path.build_filename (data_dir, "artemis");
        if (GLib.DirUtils.create_with_parents (app_dir, 0700) != 0) {
            critical ("Failed to create app dir %s: %s", app_dir, strerror (
                errno)
                );
            error = new Error (spot_db_error_quark (), DatabaseError.
                SQLITE_FAILED
                , "Failed to create app directory: %s".printf (strerror (errno))
                );
            return false;
        }

        string db_path = Path.build_filename (app_dir, "spots.db");

        int rc = Database.open (db_path, out db);
        if (rc != Sqlite.OK) {
            critical ("Cannot open DB at %s: %s", db_path, db.errmsg ());
            error = new Error (spot_db_error_quark (), DatabaseError.
                SQLITE_FAILED
                , "Cannot open database: %s".printf (db.errmsg ()));
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
            error = new Error (spot_db_error_quark (), DatabaseError.
                SQLITE_FAILED
                , "Failed to set database pragmas: %s".printf (db.errmsg ()));
            db = null;
            return false;
        }

        Error? schema_error;
        if (!spot_db_init_schema (out schema_error)) {
            error = schema_error;
            db = null;
            return false;
        }

        message ("DB opened: %s", db_path);
        return true;
    } /* init */

    /* ----- schema ----- */
    private bool spot_db_init_schema (out Error? error) {
        error = null;
        const string SCHEMA = """
        CREATE TABLE IF NOT EXISTS parks (
          reference TEXT PRIMARY KEY,
          park_name TEXT,
          dx_entity TEXT,
          location  TEXT,
          hasc      TEXT,
          first_qso_date DATETIME,
          qso_count INTEGER NOT NULL DEFAULT 0
        );

        CREATE TABLE IF NOT EXISTS qsos (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          park_ref TEXT NOT NULL,
          callsign TEXT NOT NULL,
          mode TEXT,
          frequency_khz INTEGER,
          created_utc DATETIME NOT NULL,
          spotter TEXT,
          spotter_comment TEXT,
          activator_comment TEXT,
          FOREIGN KEY(park_ref) REFERENCES parks(reference) ON DELETE CASCADE
        );

        CREATE INDEX IF NOT EXISTS idx_qsos_park_ref ON qsos(park_ref);
        CREATE INDEX IF NOT EXISTS idx_qsos_created  ON qsos(created_utc);

        CREATE TRIGGER IF NOT EXISTS trg_qsos_ai
        AFTER INSERT ON qsos
        FOR EACH ROW BEGIN
          UPDATE parks
            SET qso_count = qso_count + 1,
                first_qso_date = CASE
                    WHEN first_qso_date IS NULL THEN NEW.created_utc
                    WHEN NEW.created_utc < first_qso_date THEN NEW.created_utc
                    ELSE first_qso_date
                END
          WHERE reference = NEW.park_ref;
        END;

        CREATE TRIGGER IF NOT EXISTS trg_qsos_ad
        AFTER DELETE ON qsos
        FOR EACH ROW BEGIN
          UPDATE parks
            SET qso_count = CASE WHEN qso_count > 0 THEN qso_count - 1 ELSE 0 END,
                first_qso_date = (SELECT MIN(created_utc) FROM qsos WHERE park_ref = OLD.park_ref)
          WHERE reference = OLD.park_ref;
        END;""";
        if (db.exec (SCHEMA) != Sqlite.OK) {
            error = new Error (spot_db_error_quark (), DatabaseError.
                SQLITE_FAILED
                , "Failed to create database schema: %s".printf (db.errmsg ()));
            return false;
        }

        return true;
    }

    public bool add_qso_from_spot (Spot spot, out Error ? error) {
        error = null;

        if (db == null) {
            error = new Error (spot_db_error_quark (), DatabaseError.
                DB_NOT_INITIALIZED, "DB not initialized");
            return false;
        }

        if (spot == null) {
            error = new Error (spot_db_error_quark (), DatabaseError.
                INVALID_ARGUMENT, "Spot is null");
            return false;
        }

        if ((spot.park_ref == null) || (spot.callsign == null) || (spot.
                                                                   spot_time
                                                                   == null)) {
            error = new Error (spot_db_error_quark (), DatabaseError.
                INVALID_ARGUMENT, "Required spot fields are null");
            return false;
        }

        if (db.exec ("BEGIN IMMEDIATE;") != Sqlite.OK) {
            error = new Error (spot_db_error_quark (), DatabaseError.
                SQLITE_FAILED, "BEGIN transaction failed: %s".printf (db.
                    errmsg ()));
            return false;
        }

        Sqlite.Statement st;
        const string PARK_SQL =
            """
            INSERT INTO parks(reference, park_name, location) VALUES(?, ?, ?)
            ON CONFLICT(reference) DO UPDATE SET
            park_name = COALESCE(excluded.park_name, parks.park_name),
            location  = COALESCE(excluded.location,  parks.location);
            """;
        if (db.prepare_v2 (PARK_SQL, -1, out st) != Sqlite.OK) {
            db.exec ("ROLLBACK;");
            error = new Error (spot_db_error_quark (), DatabaseError.
                SQLITE_FAILED, "Failed to prepare park insert: %s".printf (
                    db
                    .errmsg ()));
            return false;
        }
        st.bind_text (1, spot.park_ref);
        if (spot.park_name != null)
            st.bind_text (2, spot.park_name);
        else
            st.bind_null (2);
        if (spot.location_desc != null)
            st.bind_text (3, spot.location_desc);
        else
            st.bind_null (3);

        if (st.step () != Sqlite.DONE) {
            db.exec ("ROLLBACK;");
            error = new Error (spot_db_error_quark (), DatabaseError.
                SQLITE_FAILED, "Park insert failed: %s".printf (db.errmsg ()
                    ))
            ;
            return false;
        }

        const string QSO_SQL =
            """
            INSERT INTO qsos(
            park_ref, callsign, mode, frequency_khz, created_utc,
            spotter, spotter_comment, activator_comment
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?);
            """;
        db.prepare_v2 (QSO_SQL, -1, out st);

        st.bind_text (1, spot.park_ref);
        st.bind_text (2, spot.callsign);
        st.bind_text (3, spot.mode);
        st.bind_int (4, spot.frequency_khz);
        st.bind_text (5, iso8601_from_borrowed_utc (spot.spot_time));
        st.bind_text (6, spot.spotter);
        st.bind_text (7, spot.spotter_comment);
        st.bind_text (8, spot.activator_comment);

        if (st.step () != Sqlite.DONE) {
            db.exec ("ROLLBACK;");
            error = new Error (spot_db_error_quark (), DatabaseError.
                SQLITE_FAILED, "QSO insert failed: %s".printf (db.errmsg
                        ()));
            return false;
        }

        if (db.exec ("COMMIT;") != Sqlite.OK) {
            db.exec ("ROLLBACK;");
            error = new Error (spot_db_error_quark (), DatabaseError.
                SQLITE_FAILED, "COMMIT failed: %s".printf (db.errmsg ()));
            return false;
        }

        return true;
    } /* add_qso_from_spot */

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
            error = new Error (spot_db_error_quark (), DatabaseError.
                DB_NOT_INITIALIZED, "DB not initialized");
            return false;
        }
        if ((reference == null) || (reference.strip () == "")) {
            error = new Error (spot_db_error_quark (), DatabaseError.
                INVALID_ARGUMENT, "Park reference cannot be empty");
            return false;
        }

        const string SQL =
            """
        INSERT OR REPLACE INTO parks(reference, park_name, dx_entity, location, hasc, first_qso_date, qso_count)
        VALUES(?, ?, ?, ?, ?, ?, ?);
        """;

        Statement st;
        if (db.prepare_v2 (SQL, -1, out st) != Sqlite.OK) {
            error = new Error (spot_db_error_quark (), DatabaseError.
                SQLITE_FAILED
                , "Failed to prepare add park query: %s".printf (db.errmsg ()));
            return false;
        }
        st.bind_text (1, reference);
        st.bind_text (2, park_name != null ? park_name : "");
        st.bind_text (3, dx_entity != null ? dx_entity : "");
        st.bind_text (4, location != null ? location : "");
        st.bind_text (5, hasc != null ? hasc : "");
        st.bind_text (6, first_qso_date);
        st.bind_int (7, qso_count >= 0 ? qso_count : 0);
        if (st.step () != Sqlite.DONE) {
            error = new Error (spot_db_error_quark (), DatabaseError.
                SQLITE_FAILED
                , "Failed to execute add park query: %s".printf (db.errmsg ()));
            return false;
        }
        return true;
    } /* add_park */

    /* ----- is park hunted ----- */
    public bool is_park_hunted (string park_reference, out Error? error) {
        error = null;
        if (db == null) {
            error = new Error (spot_db_error_quark (), DatabaseError.
                DB_NOT_INITIALIZED, "DB not initialized");
            return false;
        }
        if ((park_reference == null) || (park_reference.strip () == "")) {
            error = new Error (spot_db_error_quark (), DatabaseError.
                INVALID_ARGUMENT, "Park reference cannot be empty");
            return false;
        }

        const string SQL =
            "SELECT qso_count FROM parks WHERE reference = ? AND qso_count > 0;";
        Statement st;
        if (db.prepare_v2 (SQL, -1, out st) != Sqlite.OK) {
            error = new Error (spot_db_error_quark (), DatabaseError.
                SQLITE_FAILED
                , "Failed to prepare park hunted query: %s".printf (db.errmsg ()
                    ))
            ;
            return false;
        }
        st.bind_text (1, park_reference);
        var rc = st.step ();
        bool hunted = (rc == Sqlite.ROW);
        return hunted;
    }

    /* ----- helpers to read rows from a prepared statement ----- */
    private ParkRow park_row_from_stmt (Sqlite.Statement st) {
        int id = st.column_int (0);
        string reference = st.column_text (1);
        string name = st.column_text (2);
        string location_desc = st.column_text (3);
        double latitude = st.column_double (4);
        double longitude = st.column_double (5);

        return new ParkRow (id, reference, name, location_desc, latitude,
            longitude);
    }

    private QsoRow qso_row_from_stmt (Statement st) {
        var r = new QsoRow ();

        r.id = st.column_int64 (0);
        r.park_ref = st.column_text (1);
        r.callsign = st.column_text (2);
        r.mode = (st.column_type (3) == Sqlite.NULL) ? null : st.column_text (3);
        r.frequency_khz = (st.column_type (4) == Sqlite.NULL) ? 0 : st.
            column_int (4);
        r.created_utc = st.column_text (5);
        r.spotter = (st.column_type (6) == Sqlite.NULL) ? null : st.
            column_text (6);
        r.spotter_comment = (st.column_type (7) == Sqlite.NULL) ? null : st.
            column_text (7);
        r.activator_comment = (st.column_type (8) == Sqlite.NULL) ? null : st
            .column_text (8);
        return r;
    }

    public ParkRow ? get_park_by_ref (string park_ref, out Error? error) {
        error = null;

        if (db == null) {
            error = new Error (spot_db_error_quark (),
                DatabaseError.DB_NOT_INITIALIZED,
                "DB not initialized");
            return null;
        }

        if ((park_ref == null) || (park_ref.strip () == "")) {
            error = new Error (spot_db_error_quark (),
                DatabaseError.INVALID_ARGUMENT,
                "Park reference cannot be empty");
            return null;
        }

        const string SQL =
            """
            SELECT id, reference, name, location_desc, latitude, longitude
            FROM parks
            WHERE reference = ?
            LIMIT 1;
        """;

        Statement st;
        if (db.prepare_v2 (SQL, -1, out st) != Sqlite.OK) {
            error = new Error (spot_db_error_quark (),
                DatabaseError.SQLITE_FAILED,
                "Failed to prepare get_park_by_ref query: %s".printf (db.errmsg
                        ()));
            return null;
        }

        st.bind_text (1, park_ref);

        if (st.step () == Sqlite.ROW)
            return park_row_from_stmt (st);

        // No row found
        return null;
    } /* get_park_by_ref */

    public Gee.ArrayList<QsoRow> latest_qso_per_park (out Error ? error) {
        error = null;
        var rows = new Gee.ArrayList<QsoRow> ();
        if (db == null) {
            error = new Error (spot_db_error_quark (), DatabaseError.
                DB_NOT_INITIALIZED, "DB not initialized");
            return rows;
        }

        const string SQL =
            """
          SELECT q.id, q.park_ref, q.callsign, q.mode, q.frequency_khz,
                q.created_utc, q.spotter, q.spotter_comment, q.activator_comment
          FROM qsos q
          JOIN (
            SELECT park_ref, MAX(created_utc) AS maxc
            FROM qsos
            GROUP BY park_ref
          ) t
            ON q.park_ref = t.park_ref AND q.created_utc = t.maxc
          ORDER BY q.created_utc DESC;
          """;

        Statement st;
        if (db.prepare_v2 (SQL, -1, out st) != Sqlite.OK) {
            error = new Error (spot_db_error_quark (), DatabaseError.
                SQLITE_FAILED
                , "Failed to prepare latest_qso_per_park query: %s".printf (db.
                    errmsg ()));
            return rows;
        }
        while (st.step () == Sqlite.ROW) {
            rows.add (qso_row_from_stmt (st));
        }
        return rows;
    }

    public Gee.ArrayList<QsoRow> latest_qsos (int limit, out Error? error) {
        error = null;
        var rows = new Gee.ArrayList<QsoRow> ();
        if (db == null) {
            error = new Error (spot_db_error_quark (), DatabaseError.
                DB_NOT_INITIALIZED, "DB not initialized");
            return rows;
        }
        if (limit <= 0)
            limit = 50;

        const string SQL =
            """
          SELECT id, park_ref, callsign, mode, frequency_khz, created_utc,
                spotter, spotter_comment, activator_comment
          FROM qsos
          ORDER BY created_utc DESC
          LIMIT ?;
          """;

        Statement st;
        if (db.prepare_v2 (SQL, -1, out st) != Sqlite.OK) {
            error = new Error (spot_db_error_quark (), DatabaseError.
                SQLITE_FAILED
                , "Failed to prepare latest_qsos query: %s".printf (db.errmsg ()
                    ))
            ;
            return rows;
        }
        st.bind_int (1, limit);
        while (st.step () == Sqlite.ROW) {
            rows.add (qso_row_from_stmt (st));
        }
        return rows;
    }

    public ArrayList<QsoRow> ? all_qsos_for_park (string park_ref, out Error? error) {
        var list = new ArrayList<QsoRow> ();

        error = null;
        if (db == null) {
            error = new Error (spot_db_error_quark (), DatabaseError.
                DB_NOT_INITIALIZED, "DB not initialized");
            return null;
        }
        if ((park_ref == null) || (park_ref.strip () == "")) {
            error = new Error (spot_db_error_quark (), DatabaseError.
                INVALID_ARGUMENT, "Park reference cannot be empty");
            return null;
        }

        const string SQL =
            """
        SELECT id, park_ref, callsign, mode, frequency_khz, created_utc,
              spotter, spotter_comment, activator_comment
        FROM qsos
        WHERE park_ref = ?
        ORDER BY created_utc DESC;
        """;

        Statement st;
        if (db.prepare_v2 (SQL, -1, out st) != Sqlite.OK) {
            error = new Error (spot_db_error_quark (), DatabaseError.
                SQLITE_FAILED
                , "Failed to prepare latest_qso_for_park query: %s".printf (db.
                    errmsg ()));
            return null;
        }
        st.bind_text (1, park_ref);

        while (st.step () == Sqlite.ROW) {
            var row = qso_row_from_stmt (st);
            list.add (row);
        }
        return list;
    } /* all_qsos_for_park */

    public QsoRow ? latest_qso_for_park (string park_ref, out Error ? error) {
        error = null;
        if (db == null) {
            error = new Error (spot_db_error_quark (), DatabaseError.
                DB_NOT_INITIALIZED, "DB not initialized");
            return null;
        }
        if ((park_ref == null) || (park_ref.strip () == "")) {
            error = new Error (spot_db_error_quark (), DatabaseError.
                INVALID_ARGUMENT, "Park reference cannot be empty");
            return null;
        }

        const string SQL =
            """
        SELECT id, park_ref, callsign, mode, frequency_khz, created_utc,
              spotter, spotter_comment, activator_comment
        FROM qsos
        WHERE park_ref = ?
        ORDER BY created_utc DESC
        LIMIT 1;
        """;

        Statement st;
        if (db.prepare_v2 (SQL, -1, out st) != Sqlite.OK) {
            error = new Error (spot_db_error_quark (), DatabaseError.
                SQLITE_FAILED
                , "Failed to prepare latest_qso_for_park query: %s".printf (db.
                    errmsg ()));
            return null;
        }
        st.bind_text (1, park_ref);
        QsoRow ? row = null;
        if (st.step () == Sqlite.ROW)
            row = qso_row_from_stmt (st);
        return row;
    } /* latest_qso_for_park */

    public bool had_qso_with_park_on_utc_day (string park_ref, DateTime
        utc_when_in_day, out Error ? error) {
        error = null;
        if (db == null) {
            error = new Error (spot_db_error_quark (), DatabaseError.
                DB_NOT_INITIALIZED, "DB not initialized");
            return false;
        }

        if ((park_ref == null) || (park_ref.strip () == "")) {
            error = new Error (spot_db_error_quark (), DatabaseError.
                INVALID_ARGUMENT, "Park reference cannot be empty");
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

        Statement st;
        if (db.prepare_v2 (SQL, -1, out st) != Sqlite.OK) {
            error = new Error (spot_db_error_quark (), DatabaseError.
                SQLITE_FAILED
                , "Failed to prepare had_qso_with_park_on_utc_day query: %s".
                printf (db.errmsg ()));
            return false;
        }
        st.bind_text (1, park_ref);
        st.bind_text (2, start_iso);
        st.bind_text (3, next_iso);
        bool exists = false;
        if (st.step () == Sqlite.ROW)
            exists = st.column_int (0) != 0;
        return exists;
    } /* had_qso_with_park_on_utc_day */

} /* class SpotDb */
