/* src/local_adif_file.vala
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

public const string LOCAL_ADIF_DEFAULT_FILENAME = "artemis-log.adi";

public string resolve_local_adif_path (
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
            LOCAL_ADIF_DEFAULT_FILENAME
        );
    }

    return Path.build_filename (
        Environment.get_user_data_dir (),
        domain,
        LOCAL_ADIF_DEFAULT_FILENAME
    );
}

public void append_local_adif_text (
    string adif_text,
    string configured_path = "",
    string app_domain = ""
) throws Error {
    var path = resolve_local_adif_path (configured_path, app_domain);
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
