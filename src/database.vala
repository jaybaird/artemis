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

public sealed class QsoRow : Object {
    public int64 id { get; construct; }
    public string? park_ref { get; construct; }
    public string? callsign { get; construct; }
    public string? mode { get; construct; }
    public int frequency_khz { get; construct; }
    public string? created_utc { get; construct; }
    public string? spotter { get; construct; }
    public string? spotter_comment { get; construct; }
    public string? activator_comment { get; construct; }

    public QsoRow.from_statement (Sqlite.Statement st) {
        Object (
            id: st.column_int64 (0),
            park_ref: st.column_text (1),
            callsign: st.column_text (2),
            mode: (st.column_type (3) == Sqlite.NULL) ? null : st.column_text (3),
            frequency_khz: (st.column_type (4) == Sqlite.NULL) ? 0 : st.column_int (4),
            created_utc: st.column_text (5),
            spotter: (st.column_type (6) == Sqlite.NULL) ? null : st.column_text (6),
            spotter_comment: (st.column_type (7) == Sqlite.NULL) ? null : st.column_text (7),
            activator_comment: (st.column_type (8) == Sqlite.NULL) ? null : st.column_text (8)
        );
    }
}

public sealed class ParkRow : Object {
    public int id { get; construct; }
    public string reference { get; construct; }
    public ParkRow (int id,
                    string reference) {
        Object (
            id: id,
            reference: reference
        );
    }

    public ParkRow.from_statement (Sqlite.Statement st) {
        int id = st.column_int (0);
        string reference = st.column_text (1);

        Object (
            id: id,
            reference: reference
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

    public bool init (out Error? error = null) {
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
        try {
            string schema_sql = (string)GLib.resources_lookup_data (
                "/com/k0vcz/artemis/sql/version-001.sql",
                GLib.ResourceLookupFlags.NONE
            ).get_data ();
            if (db.exec (schema_sql) != Sqlite.OK) {
                error = new Error (
                    spot_db_error_quark (),
                    DatabaseError.SQLITE_FAILED,
                    "Failed to create database schema: %s".printf (db.errmsg ())
                );
                return false;
            }
        } catch (Error e) {
            error = e;
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
            INSERT INTO parks(reference) VALUES(?)
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

    public ParkRow? get_park_by_ref (string park_ref, out Error? error) {
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
            SELECT id, reference
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
            return new ParkRow.from_statement (st);

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
            rows.add (new QsoRow.from_statement (st));
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
            rows.add (new QsoRow.from_statement (st));
        }
        return rows;
    }

    public ArrayList<QsoRow>? all_qsos_for_park (string park_ref, out Error? error) {
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
            var row = new QsoRow.from_statement (st);
            list.add (row);
        }
        return list;
    } /* all_qsos_for_park */

    public QsoRow? latest_qso_for_park (string park_ref, out Error ? error) {
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
        QsoRow? row = null;
        if (st.step () == Sqlite.ROW)
            row = new QsoRow.from_statement (st);
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

    public string? country_string_for_location (string location, out Error? error) {
        error = null;
        if (db == null) {
            error = new Error (spot_db_error_quark (), DatabaseError.
                DB_NOT_INITIALIZED, "DB not initialized");
            return null;
        }

        if ((location == null) || (location.strip () == "")) {
            error = new Error (spot_db_error_quark (), DatabaseError.
                INVALID_ARGUMENT, "Location cannot be empty");
            return null;
        }

        const string SQL =
            """
            SELECT s.name, l.value
            FROM subdivision s
            JOIN list l ON s.country = l.id
            WHERE s.id = ?
            LIMIT 1;
            """;

        Statement st;
        if (db.prepare_v2 (SQL, -1, out st) != Sqlite.OK) {
            error = new Error (spot_db_error_quark (), DatabaseError.
                SQLITE_FAILED
                , "Failed to prepare country_string_for_location query: %s".
                printf (db.errmsg ()));
            return null;
        }
        st.bind_text (1, location);

        if (st.step () == Sqlite.ROW) {
            string subdivision_name = st.column_text (0);
            string country_name = st.column_text (1);
            return "%s, %s".printf (subdivision_name, country_name);
        }

        // No match found, return null
        return null;
    } /* country_string_for_location */

} /* class SpotDb */
