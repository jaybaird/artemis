/* src/local_adif_log.vala
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

public interface LocalAdifWriter : Object {
    public abstract void append_spot_qso (Spot spot, string configured_path = "") throws Error;
}

public sealed class FileLocalAdifWriter : Object, LocalAdifWriter {
    public void append_spot_qso (Spot spot, string configured_path = "") throws Error {
        append_local_adif_text (
            Artemis.Adif.spot_qso_to_string (spot),
            configured_path,
            Build.DOMAIN
        );
    }

    public static string resolve_path (string configured_path = "") {
        return resolve_local_adif_path (configured_path, Build.DOMAIN);
    }
}
