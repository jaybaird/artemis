/* src/adif/adif_parser.vala
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

namespace Artemis.Adif {
    public DateTime? parse_qso_datetime_utc (string qso_date, string time_on) {
        if ((qso_date.length != 8) || (time_on.length < 4))
            return null;

        int year;
        int month;
        int day;
        int hour;
        int minute;
        int second = 0;
        unowned string unparsed;

        if (!int.try_parse (qso_date.substring (0, 4), out year, out unparsed) ||
            (unparsed != "")) {
            return null;
        }
        if (!int.try_parse (qso_date.substring (4, 2), out month, out unparsed) ||
            (unparsed != "")) {
            return null;
        }
        if (!int.try_parse (qso_date.substring (6, 2), out day, out unparsed) ||
            (unparsed != "")) {
            return null;
        }
        if (!int.try_parse (time_on.substring (0, 2), out hour, out unparsed) ||
            (unparsed != "")) {
            return null;
        }
        if (!int.try_parse (time_on.substring (2, 2), out minute, out unparsed) ||
            (unparsed != "")) {
            return null;
        }
        if ((time_on.length >= 6) &&
            (!int.try_parse (time_on.substring (4, 2), out second, out unparsed) ||
             (unparsed != ""))) {
            return null;
        }

        return new DateTime.utc (year, month, day, hour, minute, (double) second);
    }

    public sealed class Parser : Object {
        public static Document from_string (string input) throws Error {
            return new Parser ().parse (input);
        }

        public Document parse (string input) throws Error {
            var document = new Document ();
            int position = 0;

            if (has_header (input))
                position = parse_header (input, document.header);

            parse_records (input, position, document);

            if (document.records.size == 0) {
                throw new Error.INVALID_FORMAT (
                    "ADIF input does not contain any complete records"
                );
            }

            return document;
        }

        private bool has_header (string input) throws Error {
            int position = 0;

            while (position < input.length) {
                int tag_start = input.index_of_char ('<', position);
                if (tag_start < 0)
                    return false;

                var tag = read_tag (input, tag_start);

                if (is_end_tag (tag.contents, "EOH"))
                    return true;

                if (is_end_tag (tag.contents, "EOR"))
                    return false;

                // If this is a data field, skip its payload so field values containing
                // '<' or '>' do not confuse header detection.
                if (tag.contents.index_of_char (':') > 0) {
                    Field field = parse_field (input, tag);
                    position = tag.next_position + field.value.length;
                } else {
                    position = tag.next_position;
                }
            }

            return false;
        }

        private int parse_header (string input, Header header) throws Error {
            var text = new StringBuilder ();
            int position = 0;

            while (position < input.length) {
                int tag_start = input.index_of_char ('<', position);
                if (tag_start < 0) {
                    throw new Error.INVALID_FORMAT (
                        "Header started with text but did not terminate with <EOH>"
                    );
                }

                if (tag_start > position)
                    text.append_len (input.substring (position), tag_start - position);

                var tag = read_tag (input, tag_start);
                if (is_end_tag (tag.contents, "EOH")) {
                    header.text = text.str;
                    return tag.next_position;
                }

                Field field = parse_field (input, tag);
                header.add_field (field);
                position = tag.next_position + field.value.length;
            }

            throw new Error.INVALID_FORMAT (
                "Header started with text but did not terminate with <EOH>"
            );
        }

        private void parse_records (
            string input,
            int position,
            Document document
        ) throws Error {
            Record? current_record = null;

            while (position < input.length) {
                int tag_start = input.index_of_char ('<', position);
                if (tag_start < 0)
                    break;

                var tag = read_tag (input, tag_start);

                if (is_end_tag (tag.contents, "EOH")) {
                    throw new Error.INVALID_FORMAT (
                        "Unexpected <EOH> after the ADIF header"
                    );
                }

                if (is_end_tag (tag.contents, "EOR")) {
                    if (current_record == null || current_record.fields.size == 0) {
                        throw new Error.INVALID_FORMAT (
                            "Encountered <EOR> without any preceding record fields"
                        );
                    }

                    document.records.add (current_record);
                    current_record = null;
                    position = tag.next_position;
                    continue;
                }

                Field field = parse_field (input, tag);
                if (current_record == null)
                    current_record = new Record ();

                current_record.add_field (field);
                position = tag.next_position + field.value.length;
            }

            if (current_record != null && current_record.fields.size > 0) {
                throw new Error.INVALID_FORMAT (
                    "Final ADIF record is missing its terminating <EOR> tag"
                );
            }
        }

        private Field parse_field (string input, Tag tag) throws Error {
            int first_colon = tag.contents.index_of_char (':');
            if (first_colon <= 0) {
                throw new Error.INVALID_FORMAT (
                    "Invalid ADIF data specifier <%s>".printf (tag.contents)
                );
            }

            string field_name = tag.contents.substring (0, first_colon);
            string remainder = tag.contents.substring (first_colon + 1);
            string? type_indicator = null;

            int second_colon = remainder.index_of_char (':');
            string length_text;
            if (second_colon >= 0) {
                length_text = remainder.substring (0, second_colon);
                type_indicator = remainder.substring (second_colon + 1);
            } else {
                length_text = remainder;
            }

            int data_length = parse_length (length_text, tag.contents);
            if (tag.next_position + data_length > input.length) {
                throw new Error.INVALID_FORMAT (
                    "Field '%s' declares %d bytes of data, but the input ends early".printf (
                        field_name,
                        data_length
                    )
                );
            }

            string value = input.substring (tag.next_position, data_length);
            return new Field (field_name, value, type_indicator);
        }

        private int parse_length (string text, string tag_contents) throws Error {
            string digits = text.strip ();
            if (digits == "") {
                throw new Error.INVALID_FORMAT (
                    "ADIF data specifier <%s> is missing a length".printf (tag_contents)
                );
            }

            for (int i = 0; i < digits.length; i++) {
                if (!digits[i].isdigit ()) {
                    throw new Error.INVALID_FORMAT (
                        "ADIF data specifier <%s> has a non-numeric length".printf (tag_contents)
                    );
                }
            }

            int length = int.parse (digits);
            if (length < 0) {
                throw new Error.INVALID_FORMAT (
                    "ADIF data specifier <%s> has a negative length".printf (tag_contents)
                );
            }

            return length;
        }

        private bool is_end_tag (string tag_contents, string expected) {
            return tag_contents.strip ().up () == expected;
        }

        private Tag read_tag (string input, int tag_start) throws Error {
            int tag_end = input.index_of_char ('>', tag_start);
            if (tag_end < 0) {
                throw new Error.INVALID_FORMAT (
                    "ADIF tag beginning at byte %d is missing its closing '>'".printf (tag_start)
                );
            }

            Tag tag = {};
            tag.contents = input.substring (tag_start + 1, tag_end - tag_start - 1);
            tag.next_position = tag_end + 1;
            return tag;
        }

        private struct Tag {
            public string contents;
            public int next_position;
        }
    }
}
