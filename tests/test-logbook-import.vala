/* tests/test-logbook-import.vala
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

private sealed class FakeParkStore : Object, ParkStore {
    public int add_count { get; private set; default = 0; }
    public string last_reference { get; private set; default = ""; }
    public string? last_first_qso_date { get; private set; default = null; }
    public int last_qso_count { get; private set; default = 0; }
    public bool fail_next { get; set; default = false; }

    public bool add_park (
        string reference,
        string? park_name,
        string? dx_entity,
        string? location,
        string? hasc,
        string? first_qso_date,
        int qso_count,
        out Error? error
    ) {
        if (fail_next) {
            error = new IOError.FAILED ("database failed");
            return false;
        }

        error = null;
        add_count++;
        last_reference = reference;
        last_first_qso_date = first_qso_date;
        last_qso_count = qso_count;
        return true;
    }
}

private File write_temp_csv (string contents) throws Error {
    var path = Path.build_filename (
        Environment.get_tmp_dir (),
        "artemis-test-logbook-%s.csv".printf (Uuid.string_random ())
    );
    FileUtils.set_contents (path, contents, contents.length);
    return File.new_for_path (path);
}

private void test_import_valid_csv () {
    try {
        var store = new FakeParkStore ();
        var service = new LogbookImportService (store);
        var file = write_temp_csv (
            "DX Entity,Location,HASC,Reference,Park Name,First QSO Date,QSOs\n" +
            "\"United States\",\"Minnesota\",\"US.MN\",\"US-1234\",\"Test Park\",\"2025-01-02\",\"3\"\n"
        );

        var result = service.import_pota_csv (file);

        assert (result.imported_count == 1);
        assert (store.add_count == 1);
        assert (store.last_reference == "US-1234");
        assert (store.last_first_qso_date == "2025-01-02T00:00:00Z");
        assert (store.last_qso_count == 3);
    } catch (Error err) {
        assert_not_reached ();
    }
}

private void test_import_rejects_invalid_qso_count () {
    try {
        var store = new FakeParkStore ();
        var service = new LogbookImportService (store);
        var file = write_temp_csv (
            "DX Entity,Location,HASC,Reference,Park Name,First QSO Date,QSOs\n" +
            "United States,Minnesota,US.MN,US-1234,Test Park,2025-01-02,not-a-number\n"
        );

        service.import_pota_csv (file);
        assert_not_reached ();
    } catch (IOError.INVALID_DATA err) {
        assert (err.message.contains ("invalid QSOs"));
    } catch (Error err) {
        assert_not_reached ();
    }
}

private void test_import_surfaces_park_store_error () {
    try {
        var store = new FakeParkStore ();
        store.fail_next = true;
        var service = new LogbookImportService (store);
        var file = write_temp_csv (
            "DX Entity,Location,HASC,Reference,Park Name,First QSO Date,QSOs\n" +
            "United States,Minnesota,US.MN,US-1234,Test Park,2025-01-02,3\n"
        );

        service.import_pota_csv (file);
        assert_not_reached ();
    } catch (IOError.FAILED err) {
        assert (err.message.contains ("database failed"));
    } catch (Error err) {
        assert_not_reached ();
    }
}

private void test_import_empty_body_returns_zero () {
    try {
        var store = new FakeParkStore ();
        var service = new LogbookImportService (store);
        var file = write_temp_csv (
            "DX Entity,Location,HASC,Reference,Park Name,First QSO Date,QSOs\n"
        );

        var result = service.import_pota_csv (file);

        assert (result.imported_count == 0);
        assert (store.add_count == 0);
    } catch (Error err) {
        assert_not_reached ();
    }
}

private void test_import_rejects_invalid_first_qso_date () {
    try {
        var store = new FakeParkStore ();
        var service = new LogbookImportService (store);
        var file = write_temp_csv (
            "DX Entity,Location,HASC,Reference,Park Name,First QSO Date,QSOs\n" +
            "United States,Minnesota,US.MN,US-1234,Test Park,not-a-date,3\n"
        );

        service.import_pota_csv (file);
        assert_not_reached ();
    } catch (IOError.INVALID_DATA err) {
        assert (err.message.contains ("invalid first QSO date"));
    } catch (Error err) {
        assert_not_reached ();
    }
}

private void test_import_rejects_wrong_column_count () {
    try {
        var store = new FakeParkStore ();
        var service = new LogbookImportService (store);
        var file = write_temp_csv (
            "DX Entity,Location,HASC,Reference,Park Name,First QSO Date,QSOs\n" +
            "United States,Minnesota,US.MN,US-1234\n"
        );

        service.import_pota_csv (file);
        assert_not_reached ();
    } catch (IOError.INVALID_DATA err) {
        assert (err.message.contains ("expected 7"));
    } catch (Error err) {
        assert_not_reached ();
    }
}

private void test_import_rejects_invalid_header () {
    try {
        var store = new FakeParkStore ();
        var service = new LogbookImportService (store);
        var file = write_temp_csv (
            "DX Entity,Location,HASC,Reference,Park Name,First QSO Date,QSO Count\n"
        );

        service.import_pota_csv (file);
        assert_not_reached ();
    } catch (IOError.INVALID_DATA err) {
        assert (err.message.contains ("expected 'QSOs'"));
    } catch (Error err) {
        assert_not_reached ();
    }
}

public int main (string[] args) {
    Test.init (ref args);

    Test.add_func ("/logbook-import/valid-csv", test_import_valid_csv);
    Test.add_func ("/logbook-import/rejects-invalid-qso-count",
        test_import_rejects_invalid_qso_count);
    Test.add_func ("/logbook-import/surfaces-park-store-error",
        test_import_surfaces_park_store_error);
    Test.add_func ("/logbook-import/empty-body-returns-zero",
        test_import_empty_body_returns_zero);
    Test.add_func ("/logbook-import/rejects-invalid-first-qso-date",
        test_import_rejects_invalid_first_qso_date);
    Test.add_func ("/logbook-import/rejects-wrong-column-count",
        test_import_rejects_wrong_column_count);
    Test.add_func ("/logbook-import/rejects-invalid-header",
        test_import_rejects_invalid_header);

    return Test.run ();
}
