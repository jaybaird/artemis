/* src/first_run_setup_dialog.vala
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

[GtkTemplate (ui = "/com/k0vcz/artemis/ui/first_run_setup_dialog.ui")]
public sealed class FirstRunSetupDialog : Adw.Dialog {
    [GtkChild]
    private unowned Adw.EntryRow callsign_row;

    [GtkChild]
    private unowned Adw.EntryRow location_row;

    [GtkChild]
    private unowned Adw.SwitchRow metric_row;

    [GtkChild]
    private unowned Gtk.Button skip_button;

    [GtkChild]
    private unowned Gtk.Button save_button;

    public signal void completed (
        bool save,
        string callsign,
        string location,
        bool use_metric
    );

    public FirstRunSetupDialog () {
        Object ();
    }

    construct {
        callsign_row.text = Application.settings.get_string ("callsign");
        location_row.text = Application.settings.get_string ("location");
        metric_row.active = Application.settings.get_boolean ("use-metric");

        skip_button.clicked.connect (() => complete (false));
        save_button.clicked.connect (() => complete (true));
    }

    private void complete (bool save) {
        completed (
            save,
            callsign_row.text.strip (),
            location_row.text.strip (),
            metric_row.active
        );
        force_close ();
    }
}
