/* src/preferences/general_page.vala
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

[GtkTemplate (ui = "/com/k0vcz/artemis/ui/preferences/general_page.ui")]
public sealed class GeneralPreferencesPage : Adw.PreferencesPage {
    [GtkChild]
    private unowned Adw.EntryRow row_callsign;

    [GtkChild]
    private unowned Adw.EntryRow row_location;

    [GtkChild]
    private unowned Adw.EntryRow row_spot_message;

    [GtkChild]
    private unowned Adw.SpinRow row_update_interval;

    [GtkChild]
    private unowned Adw.ComboRow row_default_band;

    [GtkChild]
    private unowned Adw.ComboRow row_default_mode;

    [GtkChild]
    private unowned Adw.SwitchRow row_auto_open_inspector;

    [GtkChild]
    private unowned Adw.SwitchRow row_use_metric;

    [GtkChild]
    private unowned Adw.SwitchRow row_show_scale;

    [GtkChild]
    private unowned Adw.SwitchRow row_hide_qrt;

    [GtkChild]
    private unowned Adw.SwitchRow row_hide_hunted;

    [GtkChild]
    private unowned Adw.SpinRow row_hide_older_than;

    [GtkChild]
    private unowned Adw.SwitchRow row_highlight_unhunted;

    public GeneralPreferencesPage () {
        Object ();
    }

    public void setup () {
        Application.settings.bind ("callsign", row_callsign, "text", SettingsBindFlags.DEFAULT);
        Application.settings.bind ("location", row_location, "text", SettingsBindFlags.DEFAULT);
        Application.settings.bind ("spot-message", row_spot_message, "text", SettingsBindFlags.DEFAULT);
        Application.settings.bind ("update-interval", row_update_interval, "value",
            SettingsBindFlags.DEFAULT);

        bind_combo_to_string_setting ("default-band", row_default_band);
        bind_combo_to_string_setting ("default-mode", row_default_mode);

        Application.settings.bind ("auto-open-inspector", row_auto_open_inspector, "active",
            SettingsBindFlags.DEFAULT);
        Application.settings.bind ("use-metric", row_use_metric, "active",
            SettingsBindFlags.DEFAULT);
        Application.settings.bind ("show-map-scale", row_show_scale, "active",
            SettingsBindFlags.DEFAULT);
        Application.settings.bind ("hide-qrt", row_hide_qrt, "active",
            SettingsBindFlags.DEFAULT);
        Application.settings.bind ("hide-hunted", row_hide_hunted, "active",
            SettingsBindFlags.DEFAULT);
        Application.settings.bind ("hide-older-than", row_hide_older_than, "value",
            SettingsBindFlags.DEFAULT);
        Application.settings.bind ("highlight-unhunted-parks", row_highlight_unhunted,
            "active", SettingsBindFlags.DEFAULT);
    }

    private void bind_combo_to_string_setting (string setting_key, Adw.ComboRow combo_row) {
        var model = combo_row.model as Gtk.StringList;
        if (model == null)
            return;

        var current_value = Application.settings.get_string (setting_key).up ();
        for (uint i = 0; i < model.get_n_items (); i++) {
            if (model.get_string (i).up () == current_value) {
                combo_row.selected = i;
                break;
            }
        }

        combo_row.notify["selected"].connect (() => {
            var selected_text = model.get_string (combo_row.selected);
            if (selected_text != null)
                Application.settings.set_string (setting_key, selected_text);
        });

        Application.settings.changed[setting_key].connect (() => {
            var value = Application.settings.get_string (setting_key).up ();
            for (uint i = 0; i < model.get_n_items (); i++) {
                if (model.get_string (i).up () == value) {
                    combo_row.selected = i;
                    break;
                }
            }
        });
    }
}
