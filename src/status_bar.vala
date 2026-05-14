/* src/status_bar.vala
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

[GtkTemplate (ui = "/com/k0vcz/artemis/ui/status_bar.ui")]
public sealed class StatusBar : Gtk.Box {
    [GtkChild]
    private unowned Gtk.Label status_bar_text;

    [GtkChild]
    private unowned Gtk.ProgressBar refresh_progress;

    [GtkChild]
    private unowned Gtk.Label current_time;

    public StatusBar () {
        Object ();
    }

    construct {
        refresh_progress.fraction = 0;
        refresh_progress.tooltip_text = "";
    }

    public void set_time (string time) {
        current_time.label = time;
    }

    public void set_filtered_text (uint filtered_count, uint total_visible) {
        var spots_text = ngettext (
            "%u spot",
            "%u spots",
            total_visible
        ).printf (total_visible);

        status_bar_text.label = "%s • %u filtered".printf (spots_text, filtered_count);
    }

    public void set_refresh_progress (double fraction) {
        refresh_progress.fraction = fraction;
    }

    public void set_refresh_tooltip (string tooltip) {
        refresh_progress.tooltip_text = tooltip;
    }

    public void set_paused (bool paused) {
        if (paused) {
            refresh_progress.tooltip_text = _("Updates Paused");
            refresh_progress.fraction = 0;
        } else {
            refresh_progress.tooltip_text = "";
        }
    }

}
