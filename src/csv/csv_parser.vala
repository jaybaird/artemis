/* src/csv/csv_parser.vala
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

public errordomain CsvParseError {
    INVALID_CHARACTER,
    UNTERMINATED_QUOTE,
    INVALID_UTF8
}

private enum CsvParserState {
    START_FIELD,
    IN_UNQUOTED_FIELD,
    IN_QUOTED_FIELD,
    AFTER_QUOTE
}

public sealed class CsvParser : Object {
    public CsvParser () {
        Object ();
    }

    public ArrayList<ArrayList<string>> parse_bytes (uint8[] bytes) throws CsvParseError {
        return parse_buffer (bytes, bytes.length);
    }

    public ArrayList<ArrayList<string>> parse_file (File file) throws Error {
        var path = file.get_path ();
        if (path == null)
            throw new IOError.NOT_SUPPORTED ("CSV parsing requires a local file");

        return parse_path (path);
    }

    public ArrayList<ArrayList<string>> parse_path (string path) throws Error {
        var mapped = new MappedFile (path, false);
        var contents = mapped.get_contents ();
        return parse_mapped_contents (contents, mapped.get_length ());
    }

    private ArrayList<ArrayList<string>> parse_mapped_contents (
        char* contents,
        size_t length
    ) throws CsvParseError {
        unowned uint8[] bytes = (uint8[]) contents;
        bytes.length = (int) length;
        return parse_buffer (bytes, length);
    }

    private ArrayList<ArrayList<string>> parse_buffer (
        uint8[] bytes,
        size_t length
    ) throws CsvParseError {
        var rows = new ArrayList<ArrayList<string>> ();
        var row = new ArrayList<string> ();
        var field = new StringBuilder ();
        var state = CsvParserState.START_FIELD;
        var row_has_content = false;
        var last_token_was_delimiter = false;
        var line = 1;
        var column = 1;
        size_t i = has_utf8_bom (bytes, length) ? 3 : 0;

        while (i < length) {
            var b = bytes[i];
            var consumed_crlf = false;

            if (b == 0) {
                throw new CsvParseError.INVALID_CHARACTER (
                    "Invalid NUL byte at line %d, column %d".printf (line, column)
                );
            }

            switch (state) {
                case CsvParserState.START_FIELD:
                    if (b == '"') {
                        state = CsvParserState.IN_QUOTED_FIELD;
                        row_has_content = true;
                        last_token_was_delimiter = false;
                    } else if (b == ',') {
                        row.add ("");
                        row_has_content = true;
                        last_token_was_delimiter = true;
                    } else if (b == '\n') {
                        row.add ("");
                        rows.add (row);
                        row = new ArrayList<string> ();
                        row_has_content = false;
                        last_token_was_delimiter = false;
                    } else if (b == '\r') {
                        require_crlf (bytes, length, i, line, column);
                        row.add ("");
                        rows.add (row);
                        row = new ArrayList<string> ();
                        row_has_content = false;
                        last_token_was_delimiter = false;
                        i++;
                        consumed_crlf = true;
                    } else {
                        append_field_byte (field, b, line, column);
                        state = CsvParserState.IN_UNQUOTED_FIELD;
                        row_has_content = true;
                        last_token_was_delimiter = false;
                    }
                    break;

                case CsvParserState.IN_UNQUOTED_FIELD:
                    if (b == ',') {
                        row.add (finish_field (field, line, column));
                        state = CsvParserState.START_FIELD;
                        last_token_was_delimiter = true;
                    } else if (b == '\n') {
                        row.add (finish_field (field, line, column));
                        rows.add (row);
                        row = new ArrayList<string> ();
                        state = CsvParserState.START_FIELD;
                        row_has_content = false;
                        last_token_was_delimiter = false;
                    } else if (b == '\r') {
                        require_crlf (bytes, length, i, line, column);
                        row.add (finish_field (field, line, column));
                        rows.add (row);
                        row = new ArrayList<string> ();
                        state = CsvParserState.START_FIELD;
                        row_has_content = false;
                        last_token_was_delimiter = false;
                        i++;
                        consumed_crlf = true;
                    } else if (b == '"') {
                        throw new CsvParseError.INVALID_CHARACTER (
                            "Unexpected quote in unquoted field at line %d, column %d".printf (
                                line,
                                column
                            )
                        );
                    } else {
                        append_field_byte (field, b, line, column);
                    }
                    break;

                case CsvParserState.IN_QUOTED_FIELD:
                    if (b == '"') {
                        state = CsvParserState.AFTER_QUOTE;
                    } else if (b == '\r' && i + 1 < length && bytes[i + 1] == '\n') {
                        append_field_byte (field, b, line, column);
                        append_field_byte (field, bytes[i + 1], line, column + 1);
                        i++;
                        consumed_crlf = true;
                    } else {
                        append_field_byte (field, b, line, column);
                    }
                    break;

                case CsvParserState.AFTER_QUOTE:
                    if (b == '"') {
                        field.append_c ('"');
                        state = CsvParserState.IN_QUOTED_FIELD;
                    } else if (b == ',') {
                        row.add (finish_field (field, line, column));
                        state = CsvParserState.START_FIELD;
                        last_token_was_delimiter = true;
                    } else if (b == '\n') {
                        row.add (finish_field (field, line, column));
                        rows.add (row);
                        row = new ArrayList<string> ();
                        state = CsvParserState.START_FIELD;
                        row_has_content = false;
                        last_token_was_delimiter = false;
                    } else if (b == '\r') {
                        require_crlf (bytes, length, i, line, column);
                        row.add (finish_field (field, line, column));
                        rows.add (row);
                        row = new ArrayList<string> ();
                        state = CsvParserState.START_FIELD;
                        row_has_content = false;
                        last_token_was_delimiter = false;
                        i++;
                        consumed_crlf = true;
                    } else {
                        throw new CsvParseError.INVALID_CHARACTER (
                            "Unexpected character after closing quote at line %d, column %d".printf (
                                line,
                                column
                            )
                        );
                    }
                    break;
            }

            if (b == '\n' || consumed_crlf) {
                line++;
                column = 1;
            } else {
                column++;
            }
            i++;
        }

        if (state == CsvParserState.IN_QUOTED_FIELD) {
            throw new CsvParseError.UNTERMINATED_QUOTE (
                "Unterminated quoted field at line %d, column %d".printf (line, column)
            );
        }

        if (state == CsvParserState.AFTER_QUOTE) {
            row.add (finish_field (field, line, column));
            rows.add (row);
        } else if (state == CsvParserState.IN_UNQUOTED_FIELD) {
            row.add (finish_field (field, line, column));
            rows.add (row);
        } else if (row_has_content && last_token_was_delimiter) {
            row.add ("");
            rows.add (row);
        }

        return rows;
    }

    private static bool has_utf8_bom (uint8[] bytes, size_t length) {
        return length >= 3 && bytes[0] == 0xEF && bytes[1] == 0xBB && bytes[2] == 0xBF;
    }

    private static void require_crlf (
        uint8[] bytes,
        size_t length,
        size_t index,
        int line,
        int column
    ) throws CsvParseError {
        if (index + 1 >= length || bytes[index + 1] != '\n') {
            throw new CsvParseError.INVALID_CHARACTER (
                "Invalid carriage return at line %d, column %d".printf (line, column)
            );
        }
    }

    private static void append_field_byte (
        StringBuilder field,
        uint8 b,
        int line,
        int column
    ) throws CsvParseError {
        if (b == 0) {
            throw new CsvParseError.INVALID_CHARACTER (
                "Invalid NUL byte at line %d, column %d".printf (line, column)
            );
        }

        field.append_c ((char) b);
    }

    private static string finish_field (
        StringBuilder field,
        int line,
        int column
    ) throws CsvParseError {
        var value = field.str;
        if (!value.validate ()) {
            throw new CsvParseError.INVALID_UTF8 (
                "Invalid UTF-8 field ending near line %d, column %d".printf (
                    line,
                    column
                )
            );
        }

        field.truncate (0);
        return value;
    }

}
