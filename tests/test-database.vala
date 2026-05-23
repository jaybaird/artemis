/* tests/test-database.vala
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

public interface QsoStore : Object {
    public abstract bool add_qso_from_spot (Spot spot, out Error? error);
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

public class Spot : Object {
    public string callsign { get; construct; }
    public string park_ref { get; construct; }
    public string park_name { get; construct; }
    public string location_desc { get; construct; }
    public string? mode { get; construct; }
    public double frequency_khz { get; construct; }
    public DateTime? spot_time { get; construct; }
    public string? spotter { get; construct; }
    public string? spotter_comment { get; construct; }
    public string? activator_comment { get; construct; }

    public Spot (
        string callsign,
        string park_ref,
        string park_name,
        string location_desc,
        string mode,
        double frequency_khz,
        DateTime spot_time,
        string spotter
    ) {
        Object (
            callsign: callsign,
            park_ref: park_ref,
            park_name: park_name,
            location_desc: location_desc,
            mode: mode,
            frequency_khz: frequency_khz,
            spot_time: spot_time,
            spotter: spotter,
            spotter_comment: "",
            activator_comment: ""
        );
    }
}

public string band_from_khz (double khz) {
    double mhz = khz / 1000.0;

    if ((mhz >= 1.8) && (mhz < 2.0))
        return "160m";
    if ((mhz >= 3.5) && (mhz < 4.1))
        return "80m";
    if ((mhz >= 5.25) && (mhz < 5.45))
        return "60m";
    if ((mhz >= 7.0) && (mhz < 7.3))
        return "40m";
    if ((mhz >= 10.1) && (mhz < 10.15))
        return "30m";
    if ((mhz >= 14.0) && (mhz < 14.35))
        return "20m";
    if ((mhz >= 18.068) && (mhz < 18.168))
        return "17m";
    if ((mhz >= 21.0) && (mhz < 21.45))
        return "15m";
    if ((mhz >= 24.89) && (mhz < 24.99))
        return "12m";
    if ((mhz >= 28.0) && (mhz < 29.7))
        return "10m";
    if ((mhz >= 50.0) && (mhz < 54.0))
        return "6m";
    if ((mhz >= 144.0) && (mhz < 148.0))
        return "2m";
    if ((mhz >= 420.0) && (mhz < 450.0))
        return "70cm";

    return "Other";
}

private string test_data_root;

private string app_dir () {
    return Path.build_filename (Environment.get_user_data_dir (), "artemis");
}

private string db_path () {
    return Path.build_filename (app_dir (), "spots.db");
}

private void delete_tree (File file) throws Error {
    if (!file.query_exists ())
        return;

    if (file.query_file_type (FileQueryInfoFlags.NONE) == FileType.DIRECTORY) {
        var enumerator = file.enumerate_children (
            FileAttribute.STANDARD_NAME,
            FileQueryInfoFlags.NONE
        );
        FileInfo? info;
        while ((info = enumerator.next_file ()) != null)
            delete_tree (file.get_child (info.get_name ()));
    }

    file.delete ();
}

private void reset_database_dir () throws Error {
    delete_tree (File.new_for_path (app_dir ()));
    DirUtils.create_with_parents (app_dir (), 0700);
}

private Sqlite.Database open_raw_db () throws Error {
    Sqlite.Database db;
    var rc = Sqlite.Database.open (db_path (), out db);
    if (rc != Sqlite.OK)
        throw new IOError.FAILED ("Unable to open raw test database: SQLite error %d".printf (rc));
    return db;
}

private void exec_sql (Sqlite.Database db, string sql) throws Error {
    if (db.exec (sql) != Sqlite.OK)
        throw new IOError.FAILED ("SQLite exec failed: %s".printf (db.errmsg ()));
}

private int scalar_int (Sqlite.Database db, string sql) throws Error {
    Sqlite.Statement st;
    if (db.prepare_v2 (sql, -1, out st) != Sqlite.OK)
        throw new IOError.FAILED ("SQLite prepare failed: %s".printf (db.errmsg ()));
    if (st.step () != Sqlite.ROW)
        throw new IOError.FAILED ("SQLite query returned no rows");
    return st.column_int (0);
}

private bool column_exists (Sqlite.Database db, string table_name, string column_name) throws Error {
    Sqlite.Statement st;
    if (db.prepare_v2 ("PRAGMA table_info(%s);".printf (table_name), -1, out st) != Sqlite.OK)
        throw new IOError.FAILED ("SQLite table_info failed: %s".printf (db.errmsg ()));

    while (st.step () == Sqlite.ROW) {
        if (st.column_text (1) == column_name)
            return true;
    }
    return false;
}

private int count_migration_backups () throws Error {
    var dir = File.new_for_path (app_dir ());
    var enumerator = dir.enumerate_children (
        FileAttribute.STANDARD_NAME,
        FileQueryInfoFlags.NONE
    );

    var count = 0;
    FileInfo? info;
    while ((info = enumerator.next_file ()) != null) {
        var name = info.get_name ();
        if (name.has_prefix ("spots.db.backup-v1-to-v3-"))
            count++;
    }
    return count;
}

private void create_legacy_v1_database () throws Error {
    reset_database_dir ();
    var db = open_raw_db ();
    exec_sql (db, """
        CREATE TABLE parks(
          reference TEXT PRIMARY KEY,
          first_qso_date TEXT,
          qso_count INTEGER NOT NULL DEFAULT 0
        );
        CREATE TABLE qsos(
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          park_ref TEXT NOT NULL,
          callsign TEXT NOT NULL,
          mode TEXT,
          frequency_khz REAL,
          created_utc TEXT NOT NULL,
          spotter TEXT,
          spotter_comment TEXT,
          activator_comment TEXT
        );
        INSERT INTO parks(reference, first_qso_date, qso_count)
        VALUES('US-0001', '2026-01-02T03:04:05Z', 1);
        INSERT INTO qsos(
          park_ref, callsign, mode, frequency_khz, created_utc,
          spotter, spotter_comment, activator_comment
        )
        VALUES(
          'US-0001', 'K1ABC', 'CW', 14063, '2026-01-02T03:04:05Z',
          'K0VCZ', 'legacy comment', ''
        );
        PRAGMA user_version = 1;
    """);
}

private void test_database_creates_latest_schema () {
    try {
        reset_database_dir ();

        Error? error = null;
        var spot_db = new SpotDb ();
        assert (spot_db.init (out error));
        assert (error == null);
        assert (spot_db.user_version == 3);
        assert (spot_db.has_qso_delivery_status);
        assert (spot_db.has_park_details);

        var raw = open_raw_db ();
        assert (scalar_int (raw, "PRAGMA user_version;") == 3);
        assert (column_exists (raw, "qsos", "qrz_uploaded"));
        assert (column_exists (raw, "qsos", "qrz_error"));
        assert (column_exists (raw, "parks", "park_name"));
        assert (column_exists (raw, "parks", "location"));
    } catch (Error err) {
        warning ("%s", err.message);
        assert_not_reached ();
    }
}

private void test_database_migrates_v1_and_backups () {
    try {
        create_legacy_v1_database ();

        Error? error = null;
        var spot_db = new SpotDb ();
        assert (spot_db.init (out error));
        assert (error == null);
        assert (spot_db.user_version == 3);
        assert (spot_db.has_qso_delivery_status);
        assert (spot_db.has_park_details);
        assert (count_migration_backups () == 1);

        var raw = open_raw_db ();
        assert (scalar_int (raw, "PRAGMA user_version;") == 3);
        assert (column_exists (raw, "qsos", "local_adif_saved"));
        assert (column_exists (raw, "qsos", "qrz_error"));
        assert (column_exists (raw, "parks", "park_name"));
        assert (column_exists (raw, "parks", "location"));

        var rows = spot_db.latest_qsos (10, out error);
        assert (error == null);
        assert (rows.size == 1);
        assert (rows[0].callsign == "K1ABC");
        assert (!rows[0].qrz_uploaded);
        assert (rows[0].qrz_error == null);
    } catch (Error err) {
        warning ("%s", err.message);
        assert_not_reached ();
    }
}

private void test_database_park_details_lookup_uses_local_rows () {
    try {
        reset_database_dir ();

        Error? error = null;
        var spot_db = new SpotDb ();
        assert (spot_db.init (out error));
        assert (error == null);

        assert (spot_db.lookup_park_details ("US-1234", out error) == null);
        assert (error == null);

        assert (spot_db.add_park (
            "US-1234",
            "Test Park",
            null,
            "US-MN",
            null,
            "2026-02-03T04:05:06Z",
            2,
            out error
        ));
        assert (error == null);

        var details = spot_db.lookup_park_details ("us-1234", out error);
        assert (error == null);
        assert (details != null);
        assert (details.reference == "US-1234");
        assert (details.park_name == "Test Park");
        assert (details.location == "US-MN");
    } catch (Error err) {
        warning ("%s", err.message);
        assert_not_reached ();
    }
}

private void test_database_logbook_pages_search_and_sort () {
    try {
        reset_database_dir ();

        Error? error = null;
        var spot_db = new SpotDb ();
        assert (spot_db.init (out error));
        assert (error == null);

        var raw = open_raw_db ();
        exec_sql (raw, """
            INSERT INTO parks(reference, park_name, location, first_qso_date, qso_count)
            VALUES
              ('US-0001', 'Acadia', 'US-ME', '2026-01-02T00:00:00Z', 1),
              ('US-9999', 'Zenith Park', 'US-CA', '2026-03-04T00:00:00Z', 1);
            INSERT INTO qsos(
              park_ref, callsign, mode, frequency_khz, created_utc,
              spotter, spotter_comment, activator_comment,
              local_adif_saved, pota_spotted, qrz_uploaded,
              local_adif_error, pota_error, qrz_error
            )
            VALUES
              ('US-0001', 'K1ABC', 'CW', 14063, '2026-01-02T00:00:00Z',
               'K0VCZ', '', '', 1, 1, 0, NULL, NULL, 'QRZ failed'),
              ('US-9999', 'N9XYZ', 'SSB', 7250, '2026-03-04T00:00:00Z',
               'K0VCZ', '', '', 1, 0, 1, NULL, 'POTA failed', NULL);
        """);

        var qso_page = spot_db.load_qso_page (
            10,
            0,
            "20m",
            LogbookQsoSortColumn.DATE,
            LogbookSortDirection.DESC,
            out error
        );
        assert (error == null);
        assert (qso_page.total_count == 1);
        assert (qso_page.rows.size == 1);
        assert (qso_page.rows[0].callsign == "K1ABC");
        assert (qso_page.rows[0].qrz_error == "QRZ failed");

        var park_page = spot_db.load_hunted_park_page (
            10,
            0,
            "",
            HuntedParkSortColumn.FIRST_QSO,
            LogbookSortDirection.DESC,
            out error
        );
        assert (error == null);
        assert (park_page.total_count == 2);
        assert (park_page.rows.size == 2);
        assert (park_page.rows[0].reference == "US-9999");
        assert (park_page.rows[1].reference == "US-0001");
    } catch (Error err) {
        warning ("%s", err.message);
        assert_not_reached ();
    }
}

public int main (string[] args) {
    test_data_root = Path.build_filename (
        Environment.get_tmp_dir (),
        "artemis-db-test-%s".printf (Uuid.string_random ())
    );
    Environment.set_variable ("XDG_DATA_HOME", test_data_root, true);

    Test.init (ref args);

    Test.add_func ("/database/create-latest-schema", test_database_creates_latest_schema);
    Test.add_func ("/database/migrate-v1-and-backup", test_database_migrates_v1_and_backups);
    Test.add_func ("/database/local-park-details-lookup", test_database_park_details_lookup_uses_local_rows);
    Test.add_func ("/database/logbook-pages-search-and-sort", test_database_logbook_pages_search_and_sort);

    var result = Test.run ();

    try {
        delete_tree (File.new_for_path (test_data_root));
    } catch (Error err) {
        warning ("%s", err.message);
    }

    return result;
}
