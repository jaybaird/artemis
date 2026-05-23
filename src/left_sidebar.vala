/* src/left_sidebar.vala
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

[GtkTemplate (ui = "/com/k0vcz/artemis/ui/band_button.ui")]
public sealed class BandButton : Gtk.Box {
    [GtkChild]
    private unowned BandStrip band_strip;

    [GtkChild]
    private unowned Gtk.Label band_name;

    [GtkChild]
    private unowned Gtk.Label count_label;

    public BandButton (string band, int count) {
        Object ();

        band_strip.band = band;
        band_name.label = band;
        count_label.label = count.to_string ();
    }
}

[GtkTemplate (ui = "/com/k0vcz/artemis/ui/left_sidebar.ui")]
public sealed class LeftSidebar : Gtk.Box {
    [GtkChild]
    private unowned Gtk.Button add_spot_button;

    [GtkChild]
    private unowned Gtk.ToggleButton sidebar_toggle;

    [GtkChild]
    private unowned Gtk.Box band_buttons_box;

    [GtkChild]
    private unowned Gtk.DropDown mode_select;

    [GtkChild]
    private unowned Gtk.DropDown program_select;

    [GtkChild]
    private unowned Gtk.ToggleButton radio_power_button;

    [GtkChild]
    private unowned Gtk.Label radio_vfo;

    [GtkChild]
    private unowned Gtk.Image tx_light;

    [GtkChild]
    private unowned Gtk.Image rx_light;

    [GtkChild]
    private unowned Gtk.Image data_light;

    [GtkChild]
    private unowned Gtk.Label radio_mode;

    private Gtk.ToggleButton? band_group_leader = null;
    private HashMap<string, Gtk.ToggleButton> band_buttons;
    private ulong mode_handler = 0;
    private ulong program_handler = 0;
    private ulong data_status_handler = 0;
    private bool syncing_mode_model = false;
    private bool syncing_program_model = false;

    private uint radio_vfo_anim_id = 0;
    private int64 radio_vfo_anim_started_at = 0;
    private bool has_displayed_radio_vfo = false;
    private double displayed_radio_vfo_khz = 0;
    private double radio_vfo_anim_start_khz = 0;
    private double radio_vfo_anim_target_khz = 0;

    public signal void band_selected (string band);
    public signal void mode_changed (string? mode);
    public signal void program_changed (string? program);
    public signal void power_clicked ();
    public signal void add_requested ();
    public signal void sidebar_visibility_changed (bool visible);

    public LeftSidebar () {
        Object ();
    }

    construct {
        band_buttons = new HashMap<string, Gtk.ToggleButton> ();

        add_spot_button.clicked.connect (() => add_requested ());
        sidebar_toggle.toggled.connect (() => {
            sidebar_visibility_changed (sidebar_toggle.active);
        });
        radio_power_button.clicked.connect (() => power_clicked ());

        mode_handler = mode_select.notify["selected"].connect (() => {
            if (syncing_mode_model)
                return;
            var idx = mode_select.selected;
            if (idx == Gtk.INVALID_LIST_POSITION)
                return;
            var model = mode_select.get_model () as Gtk.StringList;
            if (model == null)
                return;
            mode_changed (idx > 0 ? model.get_string (idx) : null);
        });

        program_handler = program_select.notify["selected"].connect (() => {
            if (syncing_program_model)
                return;
            var idx = program_select.selected;
            if (idx == Gtk.INVALID_LIST_POSITION)
                return;
            var model = program_select.get_model () as Gtk.StringList;
            if (model == null)
                return;
            program_changed (idx > 0 ? model.get_string (idx) : null);
        });

        data_status_handler = Application.wsjtx_session.status_changed.connect (() => {
            set_data_active (Application.wsjtx_session.connected);
        });
        set_data_active (Application.wsjtx_session.connected);
    }

    public void update_mode_model (Gtk.StringList model, string? current_filter) {
        syncing_mode_model = true;
        SignalHandler.block (mode_select, mode_handler);
        mode_select.model = model;

        uint selected = 0;
        if (current_filter != null) {
            for (uint i = 0; i < model.get_n_items (); i++) {
                if (model.get_string (i) == current_filter) {
                    selected = i;
                    break;
                }
            }
        }
        mode_select.selected = selected;
        SignalHandler.unblock (mode_select, mode_handler);
        syncing_mode_model = false;
    }

    public void update_program_model (Gtk.StringList model, string? current_filter) {
        syncing_program_model = true;
        SignalHandler.block (program_select, program_handler);
        program_select.model = model;

        uint selected = 0;
        if (current_filter != null) {
            for (uint i = 0; i < model.get_n_items (); i++) {
                if (model.get_string (i) == current_filter) {
                    selected = i;
                    break;
                }
            }
        }
        program_select.selected = selected;
        SignalHandler.unblock (program_select, program_handler);
        syncing_program_model = false;
    }

    public void set_selected_band (string band) {
        if (band_buttons.has_key (band))
            band_buttons[band].active = true;
    }

    public void update_bands (HashMap<string, int> band_counts, string selected_band) {
        var child = band_buttons_box.get_first_child ();
        while (child != null) {
            var next = child.get_next_sibling ();
            band_buttons_box.remove (child);
            child = next;
        }
        band_buttons.clear ();
        band_group_leader = null;

        foreach (var band in RadioConstants.BANDS) {
            int count = 0;
            if (band == "All") {
                foreach (var c in band_counts.values)
                    count += c;
            } else {
                count = band_counts.has_key (band) ? band_counts[band] : 0;
                if (count == 0)
                    continue;
            }

            var btn = make_band_button (band, count, band == selected_band);
            if (band_group_leader == null) {
                band_group_leader = btn;
            } else {
                btn.set_group (band_group_leader);
            }
            band_buttons[band] = btn;
            band_buttons_box.append (btn);
        }

        if (!band_buttons.has_key (selected_band) && band_group_leader != null)
            band_group_leader.active = true;
    }

    public void set_mode_visible (bool visible) {
        radio_mode.visible = visible;
    }

    public void set_mode_text (string mode) {
        radio_mode.label = mode;
    }

    public void set_tx_active (bool active) {
        if (active)
            tx_light.add_css_class ("active");
        else
            tx_light.remove_css_class ("active");
    }

    public void set_rx_active (bool active) {
        if (active)
            rx_light.add_css_class ("active");
        else
            rx_light.remove_css_class ("active");
    }

    public void set_data_active (bool active) {
        if (active) {
            data_light.add_css_class ("pulse-green");
            data_light.tooltip_text = _("WSJT-X connected…");
        } else {
            data_light.remove_css_class ("pulse-green");
            data_light.tooltip_text = "";
        }
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

    public void set_power_button_text (string text) {
        radio_power_button.label = text;
    }

    public void set_sidebar_visible_state (bool visible) {
        sidebar_toggle.active = visible;
        sidebar_toggle.tooltip_text = visible ? _("Hide Sidebar") : _("Show Sidebar");
    }

    public void set_vfo_animated (double freq_khz) {
        if (!has_displayed_radio_vfo) {
            displayed_radio_vfo_khz = freq_khz;
            has_displayed_radio_vfo = true;
            radio_vfo.label = format_vfo (freq_khz);
            return;
        }

        stop_vfo_animation ();

        radio_vfo_anim_start_khz = displayed_radio_vfo_khz;
        radio_vfo_anim_target_khz = freq_khz;
        if (Math.fabs (radio_vfo_anim_start_khz - radio_vfo_anim_target_khz) < 0.001) {
            displayed_radio_vfo_khz = freq_khz;
            radio_vfo.label = format_vfo (freq_khz);
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
            displayed_radio_vfo_khz = radio_vfo_anim_start_khz +
                ((radio_vfo_anim_target_khz - radio_vfo_anim_start_khz) * eased_t);
            radio_vfo.label = format_vfo (displayed_radio_vfo_khz);

            if (t >= 1.0) {
                displayed_radio_vfo_khz = radio_vfo_anim_target_khz;
                radio_vfo.label = format_vfo (displayed_radio_vfo_khz);
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
        radio_vfo.label = "";
        set_tx_active (false);
        set_rx_active (false);
    }

    private Gtk.ToggleButton make_band_button (string band, int count, bool active) {
        var btn = new Gtk.ToggleButton ();
        btn.child = new BandButton (band, count);
        btn.active = active;
        btn.add_css_class ("flat");
        btn.hexpand = true;

        btn.toggled.connect (() => {
            if (btn.active)
                band_selected (band);
        });

        return btn;
    }
}
