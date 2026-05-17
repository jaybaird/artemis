/* src/adif/adif_types.vala
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
    public errordomain Error {
        INVALID_FORMAT,
        INVALID_VALUE
    }

    public sealed class Field : Object {
        public string name { get; construct; }

        public string value { get; set; }

        public string? type_indicator { get; construct; }

        public Field (string name, string value, string? type_indicator = null) throws Error {
            Object (
                name: normalize_field_name (name),
                value: value,
                type_indicator: normalize_type_indicator (type_indicator)
            );
        }
    }

    public sealed class Header : Object {
        public string text { get; set; default = ""; }
        public Gee.ArrayList<Field> fields { get; private set; }

        public Header () {
            fields = new Gee.ArrayList<Field> ();
        }

        public bool has_field (string name) {
            return lookup_index (name) >= 0;
        }

        public Field? get_field (string name) {
            int index = lookup_index (name);
            return index >= 0 ? fields[index] : null;
        }

        public new string? get (string name) {
            Field? field = get_field (name);
            return field != null ? field.value : null;
        }

        public new void set (string name, string value, string? type_indicator = null) throws Error {
            set_field (new Field (name, value, type_indicator));
        }

        public bool remove (string name) {
            int index = lookup_index (name);
            if (index < 0)
                return false;

            fields.remove_at (index);
            return true;
        }

        internal void add_field (Field field) throws Error {
            if (has_field (field.name)) {
                throw new Error.INVALID_FORMAT (
                    "Header field '%s' appears more than once".printf (field.name)
                );
            }

            fields.add (field);
        }

        private void set_field (Field field) {
            int index = lookup_index (field.name);
            if (index >= 0) {
                fields[index] = field;
                return;
            }

            fields.add (field);
        }

        private int lookup_index (string name) {
            string normalized;
            try {
                normalized = normalize_field_name (name);
            } catch (Error error) {
                return -1;
            }

            for (int i = 0; i < fields.size; i++) {
                if (fields[i].name == normalized)
                    return i;
            }

            return -1;
        }
    }

    public sealed class Record : Object {
        public Gee.ArrayList<Field> fields { get; private set; }

        public Record () {
            fields = new Gee.ArrayList<Field> ();
        }

        public bool has_field (string name) {
            return lookup_index (name) >= 0;
        }

        public Field? get_field (string name) {
            int index = lookup_index (name);
            return index >= 0 ? fields[index] : null;
        }

        public new string? get (string name) {
            Field? field = get_field (name);
            return field != null ? field.value : null;
        }

        public new void set (string name, string value, string? type_indicator = null) throws Error {
            set_field (new Field (name, value, type_indicator));
        }

        public bool remove (string name) {
            int index = lookup_index (name);
            if (index < 0)
                return false;

            fields.remove_at (index);
            return true;
        }

        internal void add_field (Field field) throws Error {
            if (has_field (field.name)) {
                throw new Error.INVALID_FORMAT (
                    "Record field '%s' appears more than once".printf (field.name)
                );
            }

            fields.add (field);
        }

        private void set_field (Field field) {
            int index = lookup_index (field.name);
            if (index >= 0) {
                fields[index] = field;
                return;
            }

            fields.add (field);
        }

        private int lookup_index (string name) {
            string normalized;
            try {
                normalized = normalize_field_name (name);
            } catch (Error error) {
                return -1;
            }

            for (int i = 0; i < fields.size; i++) {
                if (fields[i].name == normalized)
                    return i;
            }

            return -1;
        }
    }

    public sealed class Document : Object {
        public Header header { get; construct; }
        public Gee.ArrayList<Record> records { get; private set; }

        public Document () {
            Object (header: new Header ());
        }

        construct {
            records = new Gee.ArrayList<Record> ();
        }
    }

    internal string normalize_field_name (string name) throws Error {
        string normalized = name.strip ().up ();
        if (normalized == "") {
            throw new Error.INVALID_VALUE ("ADIF field names must not be empty");
        }

        if (normalized.index_of_char (':') >= 0 ||
            normalized.index_of_char ('<') >= 0 ||
            normalized.index_of_char ('>') >= 0) {
            throw new Error.INVALID_VALUE (
                "ADIF field name '%s' contains reserved characters".printf (name)
            );
        }

        return normalized;
    }

    internal string? normalize_type_indicator (string? indicator) throws Error {
        if (indicator == null)
            return null;

        string normalized = indicator.strip ().up ();
        if (normalized == "")
            return null;

        if (normalized.index_of_char (':') >= 0 ||
            normalized.index_of_char ('<') >= 0 ||
            normalized.index_of_char ('>') >= 0) {
            throw new Error.INVALID_VALUE (
                "ADIF type indicator '%s' contains reserved characters".printf (indicator)
            );
        }

        return normalized;
    }
}
