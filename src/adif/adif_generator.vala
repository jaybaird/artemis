/* src/adif/adif_generator.vala
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
    public sealed class Generator : Object {
        public static string to_string (Document document) throws Error {
            return new Generator ().generate_document (document);
        }

        public string generate_document (Document document) throws Error {
            if (document.records.size == 0) {
                throw new Error.INVALID_VALUE (
                    "ADIF documents must contain at least one record"
                );
            }

            var output = new StringBuilder ();
            bool has_header = document.header.text != "" || document.header.fields.size > 0;

            if (has_header) {
                output.append (document.header.text);
                append_fields (output, document.header.fields);
                output.append ("<EOH>");
                output.append_c ('\n');
            }

            for (int i = 0; i < document.records.size; i++) {
                append_fields (output, document.records[i].fields);
                output.append ("<EOR>");

                if (i + 1 < document.records.size)
                    output.append_c ('\n');
            }

            return output.str;
        }

        private void append_fields (
            StringBuilder output,
            Gee.List<Field> fields
        ) {
            foreach (Field field in fields)
                append_field (output, field);
        }

        private void append_field (StringBuilder output, Field field) {
            output.append_c ('<');
            output.append (field.name);
            output.append_c (':');
            output.append_printf ("%d", field.value.length);

            if (field.type_indicator != null) {
                output.append_c (':');
                output.append (field.type_indicator);
            }

            output.append_c ('>');
            output.append (field.value);
        }
    }
}
