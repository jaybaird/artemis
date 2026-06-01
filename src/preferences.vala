/* src/preferences.vala
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

[GtkTemplate (ui = "/com/k0vcz/artemis/ui/preferences.ui")]
public sealed class PreferencesDialog : Adw.PreferencesDialog {
    [GtkChild]
    private unowned GeneralPreferencesPage general_page;

    [GtkChild]
    private unowned MapPreferencesPage map_page;

    [GtkChild]
    private unowned RadioPreferencesPage radio_page;

    [GtkChild]
    private unowned LoggingPreferencesPage logging_page;

    [GtkChild]
    private unowned WsjtxPreferencesPage wsjtx_page;

    public PreferencesDialog () {
        Object ();
    }

    construct {
        general_page.setup ();
        map_page.setup ();
        radio_page.setup ();
        logging_page.setup ();
        wsjtx_page.setup ();
    }
}
