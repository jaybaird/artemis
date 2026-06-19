/* src/space_weather_button.vala
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

public sealed class SpaceWeatherButton : Gtk.Box {
    private SpaceWeatherPopover popover;
    private Gtk.Label kp_badge_label;
    private Gtk.Widget storm_badge;

    public SpaceWeatherButton () {
        Object ();
    }

    construct {
        orientation = Gtk.Orientation.HORIZONTAL;
        append (build_button_face ());
        popover = new SpaceWeatherPopover ();

        show_loading ();
    }

    public Gtk.Popover create_popover () {
        return popover;
    }

    public void show_loading () {
        kp_badge_label.label = "…";
        kp_badge_label.add_css_class ("dim-label");
        storm_badge.visible = false;
        popover.show_loading ();
    }

    public void show_unavailable () {
        kp_badge_label.label = "—";
        kp_badge_label.add_css_class ("dim-label");
        storm_badge.visible = false;
        popover.show_unavailable ();
    }

    public void show_snapshot (SpaceWeatherSnapshot snapshot, bool refresh_failed = false) {
        if (refresh_failed)
            kp_badge_label.add_css_class ("dim-label");
        else
            kp_badge_label.remove_css_class ("dim-label");
        kp_badge_label.label = snapshot.has_kp () ? "%.1f".printf (snapshot.kp) : "—";
        storm_badge.visible = snapshot.is_storm_level ();
        popover.show_snapshot (snapshot, refresh_failed);
    }

    private Gtk.Widget build_button_face () {
        var overlay = new Gtk.Overlay () {
            width_request = 28,
            height_request = 28
        };
        overlay.add_css_class ("space-weather-button-face");

        var icon = new Gtk.Image.from_icon_name ("sun-outline-symbolic");
        overlay.set_child (icon);

        kp_badge_label = new Gtk.Label ("—") {
            halign = Gtk.Align.CENTER,
            valign = Gtk.Align.CENTER
        };
        kp_badge_label.add_css_class ("space-weather-kp-badge");
        overlay.add_overlay (kp_badge_label);

        storm_badge = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 0);
        storm_badge.visible = false;
        storm_badge.halign = Gtk.Align.END;
        storm_badge.valign = Gtk.Align.START;
        storm_badge.add_css_class ("toolbar-status-badge");
        storm_badge.add_css_class ("space-weather-storm-badge");
        overlay.add_overlay (storm_badge);

        return overlay;
    }
}
