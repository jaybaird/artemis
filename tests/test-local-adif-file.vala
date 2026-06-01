/* tests/test-local-adif-file.vala
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

private const string TEST_DOMAIN = "com.k0vcz.Artemis";
private string test_data_root;

private string temp_path (string suffix) {
    return Path.build_filename (
        Environment.get_tmp_dir (),
        "artemis-local-adif-%s-%s".printf (suffix, Uuid.string_random ())
    );
}

private void test_resolve_path_uses_configured_path () {
    var configured = "  /tmp/custom-artemis-log.adi  ";
    assert (Artemis.LocalAdif.resolve_path (configured, TEST_DOMAIN) == "/tmp/custom-artemis-log.adi");
}

private void test_resolve_path_uses_default_location () {
    var expected = Path.build_filename (
        Environment.get_user_data_dir (),
        TEST_DOMAIN,
        Artemis.LocalAdif.DEFAULT_FILENAME
    );
    assert (Artemis.LocalAdif.DEFAULT_FILENAME == "artemis-log.adi");
    assert (Artemis.LocalAdif.resolve_path ("", TEST_DOMAIN) == expected);
}

private void test_append_text_uses_default_location_for_empty_path () {
    try {
        var expected = Path.build_filename (
            test_data_root,
            TEST_DOMAIN,
            Artemis.LocalAdif.DEFAULT_FILENAME
        );

        Artemis.LocalAdif.append_text ("DEFAULT-PATH<eor>", "", TEST_DOMAIN);

        string read_back;
        assert (FileUtils.get_contents (expected, out read_back));
        assert (read_back == "DEFAULT-PATH<eor>\n");
    } catch (Error err) {
        warning ("%s", err.message);
        assert_not_reached ();
    }
}

private void test_append_text_creates_and_appends () {
    try {
        var path = temp_path ("append");
        var contents = "BEGIN-ADIF<eor>";

        Artemis.LocalAdif.append_text (contents, path, TEST_DOMAIN);

        string read_back;
        assert (FileUtils.get_contents (path, out read_back));
        assert (read_back == contents + "\n");

        Artemis.LocalAdif.append_text ("SECOND-RECORD<eor>", path, TEST_DOMAIN);
        assert (FileUtils.get_contents (path, out read_back));
        assert (read_back == contents + "\nSECOND-RECORD<eor>\n");
    } catch (Error err) {
        warning ("%s", err.message);
        assert_not_reached ();
    }
}

private void test_append_text_creates_parent_directories () {
    try {
        var nested_path = Path.build_filename (
            temp_path ("nested"),
            "deep",
            "log.adi"
        );

        Artemis.LocalAdif.append_text ("NESTED-RECORD<eor>", nested_path, TEST_DOMAIN);

        string read_back;
        assert (FileUtils.get_contents (nested_path, out read_back));
        assert (read_back == "NESTED-RECORD<eor>\n");
    } catch (Error err) {
        warning ("%s", err.message);
        assert_not_reached ();
    }
}

public int main (string[] args) {
    test_data_root = temp_path ("xdg-data");
    Environment.set_variable ("XDG_DATA_HOME", test_data_root, true);

    Test.init (ref args);

    Test.add_func ("/local-adif-file/resolve-path-uses-configured-path",
        test_resolve_path_uses_configured_path);
    Test.add_func ("/local-adif-file/resolve-path-uses-default-location",
        test_resolve_path_uses_default_location);
    Test.add_func ("/local-adif-file/append-text-uses-default-location-for-empty-path",
        test_append_text_uses_default_location_for_empty_path);
    Test.add_func ("/local-adif-file/append-text-creates-and-appends",
        test_append_text_creates_and_appends);
    Test.add_func ("/local-adif-file/append-text-creates-parent-directories",
        test_append_text_creates_parent_directories);

    return Test.run ();
}
