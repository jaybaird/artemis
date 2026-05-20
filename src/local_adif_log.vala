/* src/local_adif_log.vala
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
