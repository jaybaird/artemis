/* src/alerts_window.vala
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

[GtkTemplate (ui = "/com/k0vcz/artemis/ui/alerts_window.ui")]
public sealed class AlertsWindow : Adw.Window {
    [GtkChild]
    private unowned Adw.SwitchRow enabled_row;

    [GtkChild]
    private unowned Adw.PreferencesGroup keywords_group;

    [GtkChild]
    private unowned Gtk.Button add_keyword_button;

    [GtkChild]
    private unowned Gtk.Button cancel_button;

    [GtkChild]
    private unowned Gtk.Button save_button;

    private ArrayList<Adw.EntryRow> keyword_rows = new ArrayList<Adw.EntryRow> ();

    public AlertsWindow (Gtk.Application app) {
        Object (application: app);
    }

    construct {
        load_settings ();

        add_keyword_button.clicked.connect (() => add_keyword_row ("", true));

        cancel_button.clicked.connect (() => {
            load_settings ();
            close ();
        });

        save_button.clicked.connect (() => {
            save_settings ();
            close ();
        });
    }

    private void load_settings () {
        enabled_row.active = Application.settings.get_boolean ("spot-alerts-enabled");
        load_keywords ();
    }

    private void load_keywords () {
        clear_keyword_rows ();
        foreach (var keyword in Application.settings.get_strv ("spot-alert-keywords"))
            add_keyword_row (keyword);
    }

    private void save_settings () {
        Application.settings.set_boolean ("spot-alerts-enabled", enabled_row.active);
        Application.settings.set_strv ("spot-alert-keywords", collect_keywords ());
    }

    private void add_keyword_row (string keyword, bool focus = false) {
        var row = new Adw.EntryRow ();
        row.title = _("Keyword");
        row.text = keyword;

        var delete_button = new Gtk.Button.from_icon_name ("edit-delete-symbolic");
        delete_button.tooltip_text = _("Remove Keyword");
        delete_button.valign = Gtk.Align.CENTER;
        delete_button.add_css_class ("flat");
        row.add_suffix (delete_button);

        delete_button.clicked.connect (() => {
            keywords_group.remove (row);
            keyword_rows.remove (row);
        });

        keyword_rows.add (row);
        keywords_group.add (row);
        if (focus)
            row.grab_focus ();
    }

    private void clear_keyword_rows () {
        foreach (var row in keyword_rows)
            keywords_group.remove (row);
        keyword_rows.clear ();
    }

    private string[] collect_keywords () {
        string[] keywords = {};
        foreach (var row in keyword_rows) {
            var keyword = row.text.strip ();
            if (keyword != "")
                keywords += keyword;
        }

        return keywords;
    }
}
