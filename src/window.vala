/* src/window.vala
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

[GtkTemplate (ui = "/com/k0vcz/artemis/ui/main_window.ui")]
public sealed class AppWindow : Gtk.Window {
    [GtkChild]
    public unowned Adw.ViewStack band_stack;

    [GtkChild]
    public unowned Gtk.Box loading_spinner;

    [GtkChild]
    public unowned Adw.ToastOverlay toast_overlay;

    [GtkChild]
    public unowned Gtk.SearchEntry search_entry;

    [GtkChild]
    public unowned Gtk.Box map_container;

    [GtkChild]
    public unowned Gtk.DropDown search_select;

    [GtkChild]
    public unowned Gtk.DropDown program_select;

    [GtkChild]
    public unowned Gtk.MenuButton filter_button;

    [GtkChild]
    private unowned StatusBar status_bar;

    [GtkChild]
    public unowned Gtk.Box left_pane;

    [GtkChild]
    public unowned Gtk.Box right_pane;

    private uint timer_id = 0;
    private uint progress_timer_id = 0;
    private int64 last_refresh_time = 0;

    private uint current_ticks = 0;
    private bool update_paused = false;
    private ArrayList<Adw.ViewStackPage> band_pages;
    private MapView map_view;
    private bool radio_connect_inflight = false;

    private ulong program_select_handler = 0;
    private ulong radio_status_handler = 0;
    private ulong radio_error_handler = 0;

    private static Gee.HashSet<string> active_error_keys;

    public AppWindow (Gtk.Application app) {
        Object (application: app);
    }

    construct {
        active_error_keys = new Gee.HashSet<string> ();
        status_bar.set_mode_visible (Application.is_radio_configured);
        if (Application.is_radio_configured) {
            start_radio ();
        } else {
            status_bar.set_vfo_text (_("Radio disconnected"));
        }
        status_bar.power_clicked.connect (() => {
            if (radio_connect_inflight)
                return;
            if (Application.radio_control.is_rig_connected) {
                power_off_radio ();
            } else {
                start_radio ();
            }
        });
        status_bar.refresh_clicked.connect (on_refresh_button_clicked);

        search_entry.set_key_capture_widget (this);

        band_pages = new ArrayList<Adw.ViewStackPage> ();

        Application.settings.changed["update-interval"].connect (() => {
            setup_spot_updates ();
        });

        search_entry.search_changed.connect (() => {
            Application.current_search_text = search_entry.text;

            bounce_map_filter_if_ready ();
            foreach (var page in band_pages) {
                var band_view = page.get_child () as BandView;
                band_view.bounce_filter ();
            }

            update_status_bar ();
        });

        Application.spot_repo.busy_changed.connect ((busy) => {
            loading_spinner.visible = busy;
            if (busy && (program_select_handler != 0)) {
                program_select.disconnect (program_select_handler);
                program_select_handler = 0;
            }
        });

        Application.spot_repo.refreshed.connect ((spots_updated) => {
            string toast_title = ngettext (
                "%u spot refreshed",
                "%u spots refreshed",
                spots_updated
                ).printf (spots_updated);

            var toast = new Adw.Toast (toast_title);
            toast.timeout = 5;
            toast_overlay.add_toast (toast);

            var idx = 0u;
            var model = program_select.get_model () as Gtk.StringList;
            for (uint i = 0 ; i < model.get_n_items () ; i++) {
                if (Application.current_program_filter == model.get_string (i)) {
                    idx = i;
                    break;
                }
            }
            program_select.set_selected (idx);
            if (program_select_handler == 0) {
                program_select_handler = program_select.notify["selected"].connect (
                    on_program_selected);
            }

            last_refresh_time = get_monotonic_time ();
            current_ticks = 0;

            update_status_bar ();
        });

        Application.spot_repo.current_spot_changed.connect ((spot_hash) => {
            var spot = Application.spot_repo.get_spot (spot_hash);
            if (spot == null)
                return;

            if (band_stack.get_visible_child_name () != "All")
                band_stack.set_visible_child_name (spot.band);

            var band_view = band_stack.get_visible_child () as BandView;
            if (band_view == null)
                return;
            band_view.set_current_spot (spot_hash);
        });

        Application.spot_repo.update_error.connect ((error) => {
            var error_key = "%s:%d".printf (error.domain.to_string (), error.code);
            if (active_error_keys.contains (error_key))
                return;

            var alert_dialog = new Adw.AlertDialog (_(
                "Unable to refresh spots"),
                null);
            alert_dialog.format_body (_(
                "Unable to refresh spots due to an error: %s"), error.message);
            alert_dialog.add_responses (
                "cancel", _("Cancel"),
                "retry", _("Retry")
                );
            alert_dialog.set_response_appearance ("retry", Adw.ResponseAppearance.SUGGESTED);
            alert_dialog.set_default_response ("cancel");
            alert_dialog.set_close_response ("cancel");

            active_error_keys.add (error_key);
            alert_dialog.choose.begin (this, null, (obj, res) => {
                active_error_keys.remove (error_key);
                try {
                    var response = alert_dialog.choose.end (res);
                    switch (response) {
                        case "retry":
                            Application.spot_repo.update_spots.begin ();
                            break;
                        case "cancel":
                        default:
                            break;
                    }
                } catch (Error e) {
                    warning ("Unable to alert user, dialog failed: %s", e.message);
                }
            });
        });

        setup_spot_updates ();
        build_band_stack ();

        band_stack.set_visible_child_name (Application.settings.get_string ("default-band"));
        Application.current_band_filter = band_stack.visible_child_name;
        Application.current_program_filter = null;
        Application.current_search_text = null;

        band_stack.notify["visible-child-name"].connect (() => {
            Application.current_band_filter = band_stack.visible_child_name;
            update_status_bar ();
            bounce_map_filter_if_ready ();
        });

        program_select.model = Application.spot_repo.program_model;

        search_select.notify["selected"].connect (() => {
            var idx = search_select.selected;
            if (idx == Gtk.INVALID_LIST_POSITION)
                return;

            var model = search_select.get_model () as Gtk.StringList;
            if (model != null) {
                string? mode = null;
                if (idx > 0)
                    mode = model.get_string (idx);

                Application.current_mode_filter = mode;

                bounce_map_filter_if_ready ();

                foreach (var page in band_pages) {
                    var band_view = page.get_child () as BandView;
                    band_view.bounce_filter ();
                }
            }

            update_filter_button_style ();
            update_status_bar ();
        });

        program_select_handler = program_select.notify["selected"].connect (on_program_selected);

        var model = search_select.get_model () as Gtk.StringList;
        if (model != null) {
            var default_mode = Application.settings.get_string ("default-mode");
            int idx = -1;

            for (uint i = 0 ; i < model.get_n_items () ; i++) {
                if (model.get_string (i) == default_mode) {
                    idx = (int)i;
                    break;
                }
            }

            if (idx >= 0)
                search_select.set_selected (idx);
            else
                search_select.set_selected (0);

            if ((search_select.selected != Gtk.INVALID_LIST_POSITION) &&
                (search_select.selected > 0)) {
                Application.current_mode_filter = model.get_string (search_select.selected);
            } else {
                Application.current_mode_filter = null;
            }
        }

        update_filter_button_style ();

        map_view = new MapView () {
            hexpand = true,
            vexpand = true
        };
        map_container.append (map_view);

    }

    private void update_status_bar () {
        var visible_page = band_stack.visible_child;
        var band_view = visible_page as BandView;
        if (band_view == null)
            return;

        int total_available = 0;
        if (band_view.band_label == "All") {
            total_available = (int)Application.spot_repo.store.get_n_items ();
        } else {
            total_available = Application.spot_repo.get_band_count (band_view.band_label);
        }

        int total_visible = (int)band_view.get_n_items ();
        int filtered_count = total_available - total_visible;
        if (filtered_count < 0)
            filtered_count = 0;

        status_bar.set_filtered_text ((uint)filtered_count, (uint)total_available);
    }

    private void bounce_map_filter_if_ready () {
        if (map_view != null)
            map_view.bounce_filter ();
    }

    private void initial_update () {
        Application.spot_repo.update_spots.begin ((obj, res) => {
            Application.spot_repo.update_spots.end (res);
        });
    }

    private void setup_spot_updates () {
        if (timer_id != 0)
            Source.remove (timer_id);

        if (progress_timer_id != 0)
            Source.remove (progress_timer_id);

        last_refresh_time = get_monotonic_time ();

        timer_id = Timeout.add_seconds (1, () => {
            tick.begin ();
            return Source.CONTINUE;
        });

        progress_timer_id = Timeout.add (100, () => {
            progress_tick ();
            return Source.CONTINUE;
        });

        initial_update ();
    }

    private void build_band_stack () {
        for (uint i = 0; i < RadioConstants.BANDS.length; i++) {
            var band = RadioConstants.BANDS[i];
            var band_view = new BandView (band, @"band-$band");

            var page = band_stack.add_titled_with_icon (band_view, band, band,
                @"band-$band");
            band_view.page = page;
            band_pages.add (page);

        }
    }

    private void update_filter_button_style () {
        bool mode_active = search_select.selected != Gtk.INVALID_LIST_POSITION &&
                           search_select.selected > 0;
        bool program_active = program_select.selected != Gtk.INVALID_LIST_POSITION &&
                              program_select.selected > 0;
        if (mode_active || program_active)
            filter_button.add_css_class ("accent");
        else
            filter_button.remove_css_class ("accent");
    }

    private void power_off_radio () {
        radio_connect_inflight = false;
        disconnect_radio_handlers ();
        Application.radio_control.disconnect ().disown ();
        status_bar.reset_vfo ();
        status_bar.set_power_button_sensitive (true);
        status_bar.set_power_button_active (false);
        status_bar.set_vfo_text (_("Radio disconnected"));
        status_bar.set_mode_visible (false);
    }

    private void disconnect_radio_handlers () {
        if (radio_status_handler != 0) {
            SignalHandler.disconnect (Application.radio_control, radio_status_handler);
            radio_status_handler = 0;
        }
        if (radio_error_handler != 0) {
            SignalHandler.disconnect (Application.radio_control, radio_error_handler);
            radio_error_handler = 0;
        }
    }

    private void start_radio () {
        if (radio_connect_inflight)
            return;

        var config = RadioConfiguration () {
            model_id = Application.settings.get_int ("radio-model"),
            connection_type = Application.settings.get_string ("radio-connection-type"),
            device_path = Application.settings.get_string ("radio-device"),
            network_host = Application.settings.get_string ("radio-network-host"),
            network_port = Application.settings.get_int ("radio-network-port"),
            baud_rate = Application.settings.get_int ("radio-baud-rate"),
            data_bits = Application.settings.get_int ("radio-data-bits"),
            stop_bits = Application.settings.get_int ("radio-stop-bits"),
            handshake = Application.settings.get_int ("radio-hardware-handshake")
        };

        radio_connect_inflight = true;
        status_bar.set_power_button_sensitive (false);
        status_bar.set_vfo_text (_("Connecting radio…"));

        var is_connected = Application.radio_control.connect (config);
        new Dex.Future.finally (is_connected, (result) => {
            var success = false;
            string? error_message = null;
            try {
                success = result.await_boolean ();
            } catch (Error err) {
                success = false;
                error_message = err.message;
                Application.radio_control.disconnect ().disown ();
            }

            Dex.Scheduler.get_default ().spawn (0, () => {
                radio_connect_inflight = false;
                status_bar.set_power_button_sensitive (true);
                if (success) {
                    status_bar.set_power_button_active (true);
                    status_bar.set_vfo_text (_("Radio connected"));
                    disconnect_radio_handlers ();
                    radio_status_handler = Application.radio_control.radio_status.connect ((freq, mode) => {
                        if (freq > 0 && mode != 0) {
                            status_bar.set_mode_visible (true);
                            status_bar.set_vfo_animated (freq);
                            status_bar.set_mode_text (RadioControl.mode_string (mode));
                            status_bar.set_power_button_tooltip (_("Disconnect from radio"));
                            status_bar.set_power_button_active (true);
                        } else {
                            status_bar.reset_vfo ();
                            status_bar.set_mode_visible (false);
                            status_bar.set_power_button_active (false);
                            status_bar.set_power_button_tooltip (_("Connect to radio"));
                            status_bar.set_vfo_text (_("Radio disconnected"));
                        }
                    });
                    radio_error_handler = Application.radio_control.radio_error.connect ((err) => {
                        status_bar.reset_vfo ();
                        status_bar.set_mode_visible (false);
                        status_bar.set_power_button_active (false);
                        status_bar.set_vfo_text (_("Radio disconnected"));
                    });
                } else {
                    disconnect_radio_handlers ();
                    status_bar.reset_vfo ();
                    status_bar.set_mode_visible (false);
                    status_bar.set_power_button_active (false);
                    status_bar.set_vfo_text (_("Radio disconnected"));
                    var message = _("Radio connection failed.");
                    if ((error_message != null) && (error_message != "")) {
                        message = error_message;
                    }
                    var alert = new Adw.AlertDialog (_("Radio Connection Failed"), message);
                    alert.add_response ("ok", _("OK"));
                    alert.set_default_response ("ok");
                    alert.set_close_response ("ok");
                    alert.present (this);
                }

                return null;
            }).disown ();

            return null;
        }).disown ();
    }

    private void progress_tick () {
        if (update_paused)
            return;
        var now = get_monotonic_time ();
        double elapsed = (now - last_refresh_time) / 1000000.0;
        var update_time = Application.settings.get_int ("update-interval");

        double fraction = elapsed / (double)update_time;
        if (fraction > 1.0)
            fraction = 1.0;

        status_bar.set_refresh_progress (fraction);
    }

    private async void tick () {
        if (!update_paused) {
            current_ticks += 1;
            var update_time = Application.settings.get_int ("update-interval");
            if (current_ticks >= update_time) {
                current_ticks = current_ticks - update_time;
                last_refresh_time = get_monotonic_time ();
                yield Application.spot_repo.update_spots ();

                Idle.add (() => {
                    foreach (var page in band_pages) {
                        var band_view = page.get_child () as BandView;
                        band_view.set_current_spot (Application.current_spot_hash);
                    }
                    return Source.REMOVE;
                });
            }

            var seconds_remaining = update_time - current_ticks;
            status_bar.set_refresh_tooltip (ngettext (
                "Spots will refresh in %u second",
                "Spots will refresh in %u seconds",
                seconds_remaining
            ).printf (seconds_remaining));
        }

        var now = new GLib.DateTime.now_utc ().format ("%H:%M:%S UTC");
        status_bar.set_time (now);
    } /* tick */

    [GtkCallback]
    private void on_add_button_clicked () {
        AddSpot? add_spot = null;
        if (Application.radio_control.is_rig_connected && Application.radio_control.frequency > 0) {
            add_spot = new AddSpot.with_frequency (Application.radio_control.frequency);
        } else {
            add_spot = new AddSpot ();
        }
        add_spot.present (this);
    }

    private void on_refresh_button_clicked () {
        update_paused = !update_paused;
        if (update_paused) {
            current_ticks = 0;
        } else {
            last_refresh_time = get_monotonic_time ();
            Application.spot_repo.update_spots.begin ();
        }
        status_bar.set_paused (update_paused);
    }

    private void on_program_selected () {
        var idx = program_select.selected;

        if (idx == Gtk.INVALID_LIST_POSITION)
            return;

        var model = program_select.get_model () as Gtk.StringList;
        if (model != null) {
            string ? program = null;
            if (idx > 0)
                program = model.get_string (idx);

            Application.current_program_filter = program;

            bounce_map_filter_if_ready ();

            foreach (var page in band_pages) {
                var band_view = page.get_child () as BandView;
                band_view.bounce_filter ();
            }
        }

        update_filter_button_style ();
        update_status_bar ();
    }

    ~AppWindow () {
        if (timer_id != 0)
            Source.remove (timer_id);

        if (progress_timer_id != 0)
            Source.remove (progress_timer_id);

        disconnect_radio_handlers ();
    }
} /* class AppWindow */
