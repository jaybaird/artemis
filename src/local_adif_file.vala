/* src/local_adif_file.vala
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

namespace Artemis.LocalAdif {
    public const string DEFAULT_FILENAME = "artemis-log.adi";

    public string resolve_path (
        string configured_path = "",
        string app_domain = ""
    ) {
        var stripped = configured_path.strip ();
        if (stripped != "")
            return stripped;

        var domain = app_domain.strip ();
        if (domain == "") {
            return Path.build_filename (
                Environment.get_user_data_dir (),
                DEFAULT_FILENAME
            );
        }

        return Path.build_filename (
            Environment.get_user_data_dir (),
            domain,
            DEFAULT_FILENAME
        );
    }

    public void append_text (
        string adif_text,
        string configured_path = "",
        string app_domain = ""
    ) throws Error {
        var path = resolve_path (configured_path, app_domain);
        var file = File.new_for_path (path);
        var parent = file.get_parent ();
        if ((parent != null) && !parent.query_exists ())
            parent.make_directory_with_parents ();

        FileOutputStream stream;
        try {
            stream = file.append_to (FileCreateFlags.NONE);
        } catch (IOError.NOT_FOUND error) {
            stream = file.create (FileCreateFlags.NONE);
        }

        var output = new DataOutputStream (stream);
        output.put_string (adif_text);
        output.put_string ("\n");
        output.close ();
    }
}
