/* tests/test-csv-parser.vala
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

private Gee.ArrayList<Gee.ArrayList<string>> parse_text (string text) throws CsvParseError {
    var parser = new CsvParser ();
    uint8[] bytes = text.data;
    return parser.parse_bytes (bytes);
}

private File write_temp_csv (string contents) throws Error {
    var path = Path.build_filename (
        Environment.get_tmp_dir (),
        "artemis-test-csv-%s.csv".printf (Uuid.string_random ())
    );
    FileUtils.set_contents (path, contents, contents.length);
    return File.new_for_path (path);
}

private void test_parse_simple_quoted_row () {
    try {
        var rows = parse_text ("\"a\",\"b\",\"c\"\n");
        assert (rows.size == 1);
        assert (rows[0].size == 3);
        assert (rows[0][0] == "a");
        assert (rows[0][1] == "b");
        assert (rows[0][2] == "c");
    } catch (Error err) {
        assert_not_reached ();
    }
}

private void test_parse_quoted_comma () {
    try {
        var rows = parse_text ("a,\"b,c\",d\n");
        assert (rows[0][1] == "b,c");
    } catch (Error err) {
        assert_not_reached ();
    }
}

private void test_parse_escaped_quote () {
    try {
        var rows = parse_text ("\"a \"\"quoted\"\" value\"\n");
        assert (rows[0][0] == "a \"quoted\" value");
    } catch (Error err) {
        assert_not_reached ();
    }
}

private void test_parse_empty_field () {
    try {
        var rows = parse_text ("a,,c\n");
        assert (rows[0].size == 3);
        assert (rows[0][1] == "");
    } catch (Error err) {
        assert_not_reached ();
    }
}

private void test_parse_trailing_empty_field () {
    try {
        var rows = parse_text ("a,b,\n");
        assert (rows[0].size == 3);
        assert (rows[0][2] == "");
    } catch (Error err) {
        assert_not_reached ();
    }
}

private void test_parse_crlf () {
    try {
        var rows = parse_text ("a,b\r\nc,d\r\n");
        assert (rows.size == 2);
        assert (rows[0][1] == "b");
        assert (rows[1][0] == "c");
    } catch (Error err) {
        assert_not_reached ();
    }
}

private void test_parse_final_row_without_newline () {
    try {
        var rows = parse_text ("a,b\nc,d");
        assert (rows.size == 2);
        assert (rows[1][1] == "d");
    } catch (Error err) {
        assert_not_reached ();
    }
}

private void test_parse_quoted_multiline_field () {
    try {
        var rows = parse_text ("a,\"line one\nline two\",c\n");
        assert (rows.size == 1);
        assert (rows[0][1] == "line one\nline two");
    } catch (Error err) {
        assert_not_reached ();
    }
}

private void test_parse_bom_and_utf8_file () {
    try {
        var parser = new CsvParser ();
        var file = write_temp_csv (
            "\xEF\xBB\xBF" +
            "\"alpha\",\"Québec\",\"value, with comma\"\n"
        );

        var rows = parser.parse_file (file);
        assert (rows.size == 1);
        assert (rows[0].size == 3);
        assert (rows[0][1] == "Québec");
        assert (rows[0][2] == "value, with comma");
    } catch (Error err) {
        warning ("%s", err.message);
        assert_not_reached ();
    }
}

private void test_rejects_unterminated_quote () {
    try {
        parse_text ("a,\"b");
        assert_not_reached ();
    } catch (CsvParseError.UNTERMINATED_QUOTE err) {
        assert (err.message.contains ("Unterminated"));
    } catch (Error err) {
        assert_not_reached ();
    }
}

private void test_rejects_unexpected_quote_in_unquoted_field () {
    try {
        parse_text ("a,b\"c,d\n");
        assert_not_reached ();
    } catch (CsvParseError.INVALID_CHARACTER err) {
        assert (err.message.contains ("Unexpected quote"));
    } catch (Error err) {
        assert_not_reached ();
    }
}

private void test_rejects_character_after_closing_quote () {
    try {
        parse_text ("\"a\" b,c\n");
        assert_not_reached ();
    } catch (CsvParseError.INVALID_CHARACTER err) {
        assert (err.message.contains ("after closing quote"));
    } catch (Error err) {
        assert_not_reached ();
    }
}

private void test_rejects_invalid_utf8 () {
    try {
        var parser = new CsvParser ();
        uint8[] bytes = { 'a', ',', 0xff, '\n' };
        parser.parse_bytes (bytes);
        assert_not_reached ();
    } catch (CsvParseError.INVALID_UTF8 err) {
        assert (err.message.contains ("Invalid UTF-8"));
    } catch (Error err) {
        assert_not_reached ();
    }
}

public int main (string[] args) {
    Test.init (ref args);

    Test.add_func ("/csv-parser/simple-quoted-row", test_parse_simple_quoted_row);
    Test.add_func ("/csv-parser/quoted-comma", test_parse_quoted_comma);
    Test.add_func ("/csv-parser/escaped-quote", test_parse_escaped_quote);
    Test.add_func ("/csv-parser/empty-field", test_parse_empty_field);
    Test.add_func ("/csv-parser/trailing-empty-field", test_parse_trailing_empty_field);
    Test.add_func ("/csv-parser/crlf", test_parse_crlf);
    Test.add_func ("/csv-parser/final-row-without-newline", test_parse_final_row_without_newline);
    Test.add_func ("/csv-parser/quoted-multiline-field", test_parse_quoted_multiline_field);
    Test.add_func ("/csv-parser/bom-and-utf8-file", test_parse_bom_and_utf8_file);
    Test.add_func ("/csv-parser/rejects-unterminated-quote", test_rejects_unterminated_quote);
    Test.add_func ("/csv-parser/rejects-unexpected-quote-in-unquoted-field",
        test_rejects_unexpected_quote_in_unquoted_field);
    Test.add_func ("/csv-parser/rejects-character-after-closing-quote",
        test_rejects_character_after_closing_quote);
    Test.add_func ("/csv-parser/rejects-invalid-utf8", test_rejects_invalid_utf8);

    return Test.run ();
}
