/* tests/test-local-adif-file.vala
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

private const string TEST_DOMAIN = "com.k0vcz.Artemis";

private string temp_path (string suffix) {
    return Path.build_filename (
        Environment.get_tmp_dir (),
        "artemis-local-adif-%s-%s".printf (suffix, Uuid.string_random ())
    );
}

private void test_resolve_path_uses_configured_path () {
    var configured = "  /tmp/custom-artemis-log.adi  ";
    assert (resolve_local_adif_path (configured, TEST_DOMAIN) == "/tmp/custom-artemis-log.adi");
}

private void test_resolve_path_uses_default_location () {
    var expected = Path.build_filename (
        Environment.get_user_data_dir (),
        TEST_DOMAIN,
        LOCAL_ADIF_DEFAULT_FILENAME
    );
    assert (resolve_local_adif_path ("", TEST_DOMAIN) == expected);
}

private void test_append_text_creates_and_appends () {
    try {
        var path = temp_path ("append");
        var contents = "BEGIN-ADIF<eor>";

        append_local_adif_text (contents, path, TEST_DOMAIN);

        string read_back;
        assert (FileUtils.get_contents (path, out read_back));
        assert (read_back == contents + "\n");

        append_local_adif_text ("SECOND-RECORD<eor>", path, TEST_DOMAIN);
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

        append_local_adif_text ("NESTED-RECORD<eor>", nested_path, TEST_DOMAIN);

        string read_back;
        assert (FileUtils.get_contents (nested_path, out read_back));
        assert (read_back == "NESTED-RECORD<eor>\n");
    } catch (Error err) {
        warning ("%s", err.message);
        assert_not_reached ();
    }
}

public int main (string[] args) {
    Test.init (ref args);

    Test.add_func ("/local-adif-file/resolve-path-uses-configured-path",
        test_resolve_path_uses_configured_path);
    Test.add_func ("/local-adif-file/resolve-path-uses-default-location",
        test_resolve_path_uses_default_location);
    Test.add_func ("/local-adif-file/append-text-creates-and-appends",
        test_append_text_creates_and_appends);
    Test.add_func ("/local-adif-file/append-text-creates-parent-directories",
        test_append_text_creates_parent_directories);

    return Test.run ();
}
