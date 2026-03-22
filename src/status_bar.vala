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
    public unowned Gtk.ToggleButton radio_power_button;

    [GtkChild]
    public unowned Gtk.Label radio_vfo;

    [GtkChild]
    public unowned Gtk.Label radio_mode;

    [GtkChild]
    public unowned Gtk.Label status_bar_text;

    [GtkChild]
    public unowned Gtk.ProgressBar refresh_progress;

    [GtkChild]
    public unowned Gtk.Label current_time;

    [GtkChild]
    public unowned Gtk.ToggleButton refresh_button;

    private uint radio_vfo_anim_id = 0;
    private int64 radio_vfo_anim_started_at = 0;
    private bool has_displayed_radio_vfo = false;
    private int displayed_radio_vfo_khz = 0;
    private int radio_vfo_anim_start_khz = 0;
    private int radio_vfo_anim_target_khz = 0;

    public signal void refresh_clicked ();
    public signal void power_clicked ();

    public StatusBar () {
        Object ();
    }

    construct {
        refresh_progress.fraction = 0;
        refresh_progress.tooltip_text = "";
        refresh_button.clicked.connect (() => refresh_clicked ());
        radio_power_button.clicked.connect (() => power_clicked ());
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
            refresh_button.icon_name = "view-refresh-symbolic";
            refresh_button.tooltip_text = _("Refresh");
            refresh_progress.tooltip_text = _("Updates Paused");
            refresh_progress.fraction = 0;
        } else {
            refresh_button.icon_name = "media-playback-pause-symbolic";
            refresh_button.tooltip_text = _("Pause");
        }
    }

    public void set_mode_visible (bool visible) {
        radio_mode.visible = visible;
    }

    public void set_mode_text (string mode) {
        radio_mode.label = mode;
    }

    public void set_vfo_text (string text) {
        radio_vfo.label = text;
    }

    public void set_power_button_active (bool active) {
        radio_power_button.active = active;
    }

    public void set_power_button_sensitive (bool sensitive) {
        radio_power_button.sensitive = sensitive;
    }

    public void set_power_button_tooltip (string tooltip) {
        radio_power_button.tooltip_text = tooltip;
    }

    public void set_vfo_animated (int freq_khz) {
        if (!has_displayed_radio_vfo) {
            displayed_radio_vfo_khz = freq_khz;
            has_displayed_radio_vfo = true;
            radio_vfo.label = format_vfo ((float)freq_khz);
            return;
        }

        stop_vfo_animation ();

        radio_vfo_anim_start_khz = displayed_radio_vfo_khz;
        radio_vfo_anim_target_khz = freq_khz;
        if (radio_vfo_anim_start_khz == radio_vfo_anim_target_khz) {
            radio_vfo.label = format_vfo ((float)freq_khz);
            return;
        }

        radio_vfo_anim_started_at = get_monotonic_time ();
        radio_vfo_anim_id = Timeout.add (16, () => {
            const double DURATION_MS = 160.0;
            var elapsed_ms = (get_monotonic_time () - radio_vfo_anim_started_at) / 1000.0;
            var t = elapsed_ms / DURATION_MS;
            if (t > 1.0)
                t = 1.0;

            var eased_t = 1.0 - ((1.0 - t) * (1.0 - t));
            var interpolated = (double)radio_vfo_anim_start_khz +
                ((double)(radio_vfo_anim_target_khz - radio_vfo_anim_start_khz) * eased_t);
            displayed_radio_vfo_khz = (int)Math.round (interpolated);
            radio_vfo.label = format_vfo ((float)displayed_radio_vfo_khz);

            if (t >= 1.0) {
                displayed_radio_vfo_khz = radio_vfo_anim_target_khz;
                radio_vfo.label = format_vfo ((float)displayed_radio_vfo_khz);
                radio_vfo_anim_id = 0;
                return Source.REMOVE;
            }

            return Source.CONTINUE;
        });
    }

    public void stop_vfo_animation () {
        if (radio_vfo_anim_id != 0) {
            Source.remove (radio_vfo_anim_id);
            radio_vfo_anim_id = 0;
        }
    }

    public void reset_vfo () {
        stop_vfo_animation ();
        has_displayed_radio_vfo = false;
    }
}
