/* src/preferences/logging_page.vala
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

[GtkTemplate (ui = "/com/k0vcz/artemis/ui/preferences/logging_page.ui")]
public sealed class LoggingPreferencesPage : Adw.PreferencesPage {
    [GtkChild]
    private unowned Adw.SwitchRow row_enable_logging;

    [GtkChild]
    private unowned Adw.SwitchRow row_enable_local_adif_log;

    [GtkChild]
    private unowned Adw.ActionRow row_local_adif_log_path;

    [GtkChild]
    private unowned Adw.PasswordEntryRow row_qrz_api_key;

    [GtkChild]
    private unowned Adw.ActionRow import_file_row;

    [GtkChild]
    private unowned Adw.ButtonRow import_log;

    private File? logbook_csv = null;

    public LoggingPreferencesPage () {
        Object ();
    }

    public void setup () {
        Application.settings.bind ("enable-logging", row_enable_logging, "active",
            SettingsBindFlags.DEFAULT);
        Application.settings.bind ("enable-local-adif-log", row_enable_local_adif_log,
            "active", SettingsBindFlags.DEFAULT);
        Application.settings.bind ("qrz-api-key", row_qrz_api_key, "text",
            SettingsBindFlags.DEFAULT);

        sync_local_adif_log_path_row ();
        Application.settings.changed["local-adif-log-path"].connect (() => {
            sync_local_adif_log_path_row ();
        });

        row_local_adif_log_path.activated.connect (on_choose_local_adif_log_path);
        import_file_row.activated.connect (on_import_file);
        import_log.activated.connect (do_import_file);
    }

    private void sync_local_adif_log_path_row () {
        row_local_adif_log_path.subtitle = FileLocalAdifWriter.resolve_path (
            Application.settings.get_string ("local-adif-log-path")
        );
    }

    private void do_import_file () {
        if (logbook_csv == null)
            return;

        string description;

        try {
            var result = Application.logbook_import_service.import_pota_csv (logbook_csv);
            description = ngettext ("Successfully imported one park",
                "Succesfully imported %d parks",
                result.imported_count
            ).printf (result.imported_count);
        } catch (Error err) {
            description = _(
                "Unable to import hunted parks. Please check your CSV file and try again.");
            warning ("Unable to import hunted parks: %s", err.message);
        }

        import_file_row.subtitle = "";
        logbook_csv = null;
        import_log.remove_css_class ("suggested-action");

        var alert = new Adw.AlertDialog (_("Import Parks"), description);
        alert.add_response ("ok", _("Ok"));
        alert.set_response_appearance ("ok", Adw.ResponseAppearance.SUGGESTED);
        alert.set_default_response ("ok");
        alert.set_close_response ("ok");
        alert.present (get_root ());
    }

    private void on_import_file () {
        var file_dialog = new Gtk.FileDialog ();
        file_dialog.title = _("Select Logbook CSV File");

        var csv_filter = new Gtk.FileFilter ();
        csv_filter.name = _("CSV Files");
        csv_filter.add_mime_type ("text/csv");
        csv_filter.add_pattern ("*.csv");

        var filter_list = new GLib.ListStore (typeof (Gtk.FileFilter));
        filter_list.append (csv_filter);
        file_dialog.filters = filter_list;

        file_dialog.open.begin (get_root () as Gtk.Window, null, (obj, res) => {
            try {
                var file = file_dialog.open.end (res);
                if (file != null) {
                    logbook_csv = file;
                    import_file_row.subtitle = file.get_basename ();
                    import_log.add_css_class ("suggested-action");
                }
            } catch (Error e) {
                warning ("Failed to select file: %s", e.message);
            }
        });
    }

    private void on_choose_local_adif_log_path () {
        var file_dialog = new Gtk.FileDialog ();
        var current_path = FileLocalAdifWriter.resolve_path (
            Application.settings.get_string ("local-adif-log-path")
        );
        var current_file = File.new_for_path (current_path);
        var parent = current_file.get_parent ();

        file_dialog.title = _("Choose ADIF Log File");
        file_dialog.initial_name = current_file.get_basename ();
        if (parent != null)
            file_dialog.initial_folder = parent;

        var adif_filter = new Gtk.FileFilter ();
        adif_filter.name = _("ADIF Files");
        adif_filter.add_pattern ("*.adi");
        adif_filter.add_pattern ("*.adif");

        var filter_list = new GLib.ListStore (typeof (Gtk.FileFilter));
        filter_list.append (adif_filter);
        file_dialog.filters = filter_list;

        file_dialog.save.begin (get_root () as Gtk.Window, null, (obj, res) => {
            try {
                var file = file_dialog.save.end (res);
                if (file == null)
                    return;

                var path = file.get_path ();
                if ((path != null) && path.strip () != "")
                    Application.settings.set_string ("local-adif-log-path", path);
            } catch (Error e) {
                warning ("Failed to select ADIF log file: %s", e.message);
            }
        });
    }
}
