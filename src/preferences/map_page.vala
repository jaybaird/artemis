/* src/preferences/map_page.vala
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

[GtkTemplate (ui = "/com/k0vcz/artemis/ui/preferences/map_page.ui")]
public sealed class MapPreferencesPage : Adw.PreferencesPage {
    private const uint[] SIGNAL_REPORT_SPREAD_RADII = { 18, 28, 40 };

    [GtkChild]
    private unowned Adw.SpinRow row_signal_report_max_age;

    [GtkChild]
    private unowned Adw.ComboRow row_signal_report_spread;

    [GtkChild]
    private unowned Adw.SwitchRow row_signal_report_preload_history;

    public MapPreferencesPage () {
        Object ();
    }

    public void setup () {
        sync_signal_report_max_age ();
        row_signal_report_max_age.notify["value"].connect (() => {
            var seconds = (int) Math.round (row_signal_report_max_age.value) * 60;
            if (Application.settings.get_int ("signal-report-max-age-seconds") != seconds)
                Application.settings.set_int ("signal-report-max-age-seconds", seconds);
        });
        Application.settings.changed["signal-report-max-age-seconds"].connect (
            sync_signal_report_max_age
        );

        sync_signal_report_spread ();
        row_signal_report_spread.notify["selected"].connect (() => {
            var selected = row_signal_report_spread.selected;
            if (selected >= SIGNAL_REPORT_SPREAD_RADII.length)
                return;

            var radius = (int) SIGNAL_REPORT_SPREAD_RADII[selected];
            if (Application.settings.get_int ("signal-report-heatmap-radius") != radius)
                Application.settings.set_int ("signal-report-heatmap-radius", radius);
        });
        Application.settings.changed["signal-report-heatmap-radius"].connect (
            sync_signal_report_spread
        );

        Application.settings.bind (
            "signal-report-preload-history",
            row_signal_report_preload_history,
            "active",
            SettingsBindFlags.DEFAULT
        );
    }

    private void sync_signal_report_max_age () {
        var minutes = Application.settings.get_int ("signal-report-max-age-seconds") / 60.0;
        if (Math.fabs (row_signal_report_max_age.value - minutes) > 0.001)
            row_signal_report_max_age.value = minutes;
    }

    private void sync_signal_report_spread () {
        var radius = Application.settings.get_int ("signal-report-heatmap-radius");
        uint selected = 1;

        for (uint i = 0; i < SIGNAL_REPORT_SPREAD_RADII.length; i++) {
            if (SIGNAL_REPORT_SPREAD_RADII[i] == radius) {
                selected = i;
                break;
            }
        }

        if (row_signal_report_spread.selected != selected)
            row_signal_report_spread.selected = selected;
    }
}
