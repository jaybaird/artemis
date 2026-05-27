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
    private unowned Gtk.TextBuffer keyword_buffer;

    private bool syncing_keywords = false;

    public AlertsWindow (Gtk.Application app) {
        Object (application: app);
    }

    construct {
        Application.settings.bind (
            "spot-alerts-enabled",
            enabled_row,
            "active",
            SettingsBindFlags.DEFAULT
        );

        load_keywords ();
        keyword_buffer.changed.connect (store_keywords);
        Application.settings.changed["spot-alert-keywords"].connect (() => {
            if (!syncing_keywords)
                load_keywords ();
        });
    }

    private void load_keywords () {
        syncing_keywords = true;
        keyword_buffer.text = string.joinv ("\n", Application.settings.get_strv (
            "spot-alert-keywords"
        ));
        syncing_keywords = false;
    }

    private void store_keywords () {
        if (syncing_keywords)
            return;

        Gtk.TextIter start;
        Gtk.TextIter end;
        keyword_buffer.get_bounds (out start, out end);
        var text = keyword_buffer.get_text (start, end, false);
        string[] keywords = {};
        foreach (var line in text.split ("\n")) {
            var keyword = line.strip ();
            if (keyword != "")
                keywords += keyword;
        }

        syncing_keywords = true;
        Application.settings.set_strv ("spot-alert-keywords", keywords);
        syncing_keywords = false;
    }
}
