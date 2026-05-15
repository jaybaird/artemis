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
    public unowned Gtk.SearchEntry search_entry;

    [GtkChild]
    public unowned Gtk.Box map_container;

    [GtkChild]
    public unowned Gtk.Box list_container;

    [GtkChild]
    private unowned Gtk.ToggleButton refresh_toggle;

    [GtkChild]
    private unowned Gtk.Paned content_paned;

    [GtkChild]
    private unowned Gtk.ToggleButton inspector_toggle;

    [GtkChild]
    private unowned StatusBar status_bar;

    [GtkChild]
    private unowned LeftSidebar left_sidebar;

    [GtkChild]
    private unowned SpotDetail spot_detail;

    private uint timer_id = 0;

    private uint current_ticks = 0;
    private bool update_paused = false;
    private ArrayList<Adw.ViewStackPage> band_pages;
    private MapView map_view;
    private SpotListView list_view;
    private bool radio_connect_inflight = false;
    private Quark map_centered_spot_hash = BLANK_HASH;

    private ulong radio_status_handler = 0;
    private ulong radio_error_handler = 0;
    private bool syncing_inspector_toggle = false;

    private static Gee.HashSet<string> active_error_keys;

    public AppWindow (Gtk.Application app) {
        Object (application: app);
    }

    construct {
        active_error_keys = new Gee.HashSet<string> ();
        left_sidebar.set_mode_visible (Application.is_radio_configured);
        if (Application.is_radio_configured) {
            start_radio ();
        }
        left_sidebar.power_clicked.connect (() => {
            if (radio_connect_inflight)
                return;
            if (Application.radio_control.is_rig_connected) {
                power_off_radio ();
            } else {
                start_radio ();
            }
        });
        refresh_toggle.clicked.connect (on_refresh_button_clicked);

        search_entry.set_key_capture_widget (this);

        band_pages = new ArrayList<Adw.ViewStackPage> ();

        Application.settings.changed["update-interval"].connect (() => {
            setup_spot_updates ();
        });

        search_entry.search_changed.connect (() => {
            Application.current_search_text = search_entry.text;
            refresh_spot_views ();
        });

        inspector_toggle.toggled.connect (() => {
            if (!syncing_inspector_toggle)
                set_inspector_visible (inspector_toggle.active);
        });

        Application.spot_repo.busy_changed.connect ((busy) => {
            loading_spinner.visible = busy;
        });

        Application.spot_repo.refreshed.connect ((spots_updated) => {
            if ((Application.current_mode_filter != null) &&
                !string_list_contains (
                    Application.spot_repo.mode_model,
                    Application.current_mode_filter
                )) {
                Application.current_mode_filter = null;
            }

            left_sidebar.update_bands (
                Application.spot_repo.band_counts,
                Application.current_band_filter ?? "All"
            );
            left_sidebar.update_mode_model (
                Application.spot_repo.mode_model,
                Application.current_mode_filter
            );
            left_sidebar.update_program_model (
                Application.spot_repo.program_model,
                Application.current_program_filter
            );

            if (Application.current_spot_hash != BLANK_HASH &&
                !current_spot_matches_filters ()) {
                Application.current_spot_hash = BLANK_HASH;
            }

            current_ticks = 0;

            update_refresh_status ();
            update_status_bar ();
        });

        Application.spot_repo.current_spot_changed.connect (on_spot_selected);

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
            left_sidebar.set_selected_band (band_stack.visible_child_name);
            refresh_spot_views ();
        });

        left_sidebar.band_selected.connect ((band) => {
            band_stack.set_visible_child_name (band);
        });

        left_sidebar.mode_changed.connect ((mode) => {
            Application.current_mode_filter = mode;
            refresh_spot_views ();
        });

        left_sidebar.program_changed.connect ((program) => {
            Application.current_program_filter = program;
            refresh_spot_views ();
        });

        left_sidebar.update_bands (
            Application.spot_repo.band_counts,
            Application.current_band_filter ?? "All"
        );
        left_sidebar.update_mode_model (
            Application.spot_repo.mode_model,
            Application.current_mode_filter
        );
        left_sidebar.update_program_model (
            Application.spot_repo.program_model,
            Application.current_program_filter
        );

        map_view = new MapView () {
            hexpand = true,
            vexpand = true
        };
        map_container.append (map_view);

        list_view = new SpotListView () {
            hexpand = true,
            vexpand = true
        };
        list_container.append (list_view);
        Application.app.radio_connection_state_changed.connect (() => {
            list_view.set_row_actions_visible (content_paned.get_end_child () == null);
        });

        spot_detail.set_action_buttons_visible (true);
        set_inspector_visible (true);

        Application.settings.changed["hide-qrt"].connect (refresh_spot_views);
        Application.settings.changed["hide-hunted"].connect (refresh_spot_views);
        Application.settings.changed["hide-older-than"].connect (refresh_spot_views);

    }

    private void on_spot_selected (Quark spot_hash) {
        var spot = Application.spot_repo.get_spot (spot_hash);
        spot_detail.set_spot (spot);

        if (spot == null) {
            map_centered_spot_hash = BLANK_HASH;
            foreach (var page in band_pages) {
                var band_view = page.get_child () as BandView;
                band_view.set_current_spot (BLANK_HASH);
            }
            if (list_view != null)
                list_view.set_current_spot (BLANK_HASH);
            return;
        }

        if ((map_view != null) && (spot_hash != map_centered_spot_hash)) {
            map_view.go_to_spot (spot);
            map_centered_spot_hash = spot_hash;
        }

        sync_band_view_to_spot (spot_hash, spot);
        if (list_view != null)
            list_view.set_current_spot (spot_hash);
    }

    private void set_inspector_visible (bool visible) {
        if (visible) {
            if (content_paned.get_end_child () == null)
                content_paned.set_end_child (spot_detail);
        } else if (content_paned.get_end_child () != null) {
            content_paned.set_end_child (null);
        }

        syncing_inspector_toggle = true;
        inspector_toggle.active = visible;
        syncing_inspector_toggle = false;
        inspector_toggle.tooltip_text = visible ? _("Hide Inspector") : _("Show Inspector");
        if (list_view != null)
            list_view.set_row_actions_visible (!visible);
    }

    private void sync_band_view_to_spot (Quark spot_hash, Spot spot) {
        var band_view = band_stack.get_visible_child () as BandView;
        if (band_view != null)
            band_view.set_current_spot (spot_hash);
    }

    private void update_status_bar () {
        if (list_view == null)
            return;

        var current_band = Application.current_band_filter ?? "All";
        int total_available = 0;
        if (current_band == "All") {
            total_available = (int)Application.spot_repo.store.get_n_items ();
        } else {
            total_available = Application.spot_repo.get_band_count (current_band);
        }

        int total_visible = (int)list_view.get_n_items ();
        int filtered_count = total_available - total_visible;
        if (filtered_count < 0)
            filtered_count = 0;

        status_bar.set_filtered_text ((uint)filtered_count, (uint)total_visible);
    }

    private void bounce_map_filter_if_ready () {
        if (map_view != null)
            map_view.bounce_filter ();
    }

    private bool string_list_contains (Gtk.StringList model, string value) {
        for (uint i = 0; i < model.get_n_items (); i++) {
            if (model.get_string (i) == value)
                return true;
        }

        return false;
    }

    private bool current_spot_matches_filters () {
        if (Application.current_spot_hash == BLANK_HASH)
            return false;

        var spot = Application.spot_repo.get_spot (Application.current_spot_hash);
        if (spot == null)
            return false;

        return spot_matches_current_filters (
            spot,
            Application.current_band_filter ?? "All"
        );
    }

    private void refresh_spot_views () {
        bounce_map_filter_if_ready ();
        if (list_view != null)
            list_view.bounce_filter ();

        foreach (var page in band_pages) {
            var band_view = page.get_child () as BandView;
            band_view.bounce_filter ();
        }

        if (Application.current_spot_hash != BLANK_HASH &&
            !current_spot_matches_filters ()) {
            Application.current_spot_hash = BLANK_HASH;
        }

        update_status_bar ();
    }

    private void initial_update () {
        Application.spot_repo.update_spots.begin ((obj, res) => {
            Application.spot_repo.update_spots.end (res);
        });
    }

    private void setup_spot_updates () {
        if (timer_id != 0)
            Source.remove (timer_id);

        update_refresh_status ();

        timer_id = Timeout.add_seconds (1, () => {
            tick.begin ();
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

    private void power_off_radio () {
        radio_connect_inflight = false;
        disconnect_radio_handlers ();
        Application.radio_control.disconnect ().disown ();
        left_sidebar.reset_vfo ();
        left_sidebar.set_power_button_sensitive (true);
        left_sidebar.set_power_button_active (false);
        left_sidebar.set_power_button_text (_("Connect"));
        left_sidebar.set_mode_visible (false);
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
            model_id = Application.settings.get_string ("radio-connection-type") == "network" ?
                RadioControl.netrigctl_model_id () :
                Application.settings.get_int ("radio-model"),
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
        left_sidebar.set_power_button_sensitive (false);
        left_sidebar.set_power_button_text (_("Connecting…"));

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
                left_sidebar.set_power_button_sensitive (true);
                if (success) {
                    left_sidebar.set_power_button_active (true);
                    left_sidebar.set_power_button_text (_("Disconnect"));
                    disconnect_radio_handlers ();
                    radio_status_handler = Application.radio_control.radio_status.connect ((freq, mode) => {
                        if (freq > 0 && mode != 0) {
                            left_sidebar.set_mode_visible (true);
                            left_sidebar.set_vfo_animated (freq);
                            left_sidebar.set_mode_text (RadioControl.mode_string (mode));
                            left_sidebar.set_power_button_tooltip (_("Disconnect from radio"));
                            left_sidebar.set_power_button_text (_("Disconnect"));
                            left_sidebar.set_power_button_active (true);
                        } else {
                            left_sidebar.reset_vfo ();
                            left_sidebar.set_mode_visible (false);
                            left_sidebar.set_power_button_active (false);
                            left_sidebar.set_power_button_tooltip (_("Connect to radio"));
                            left_sidebar.set_power_button_text (_("Connect"));
                        }
                    });
                    radio_error_handler = Application.radio_control.radio_error.connect ((err) => {
                        left_sidebar.reset_vfo ();
                        left_sidebar.set_mode_visible (false);
                        left_sidebar.set_power_button_active (false);
                        left_sidebar.set_power_button_text (_("Connect"));
                    });
                } else {
                    disconnect_radio_handlers ();
                    left_sidebar.reset_vfo ();
                    left_sidebar.set_mode_visible (false);
                    left_sidebar.set_power_button_active (false);
                    left_sidebar.set_power_button_text (_("Connect"));
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

    private void update_refresh_status () {
        if (update_paused) {
            status_bar.set_paused (true);
            return;
        }

        var update_time = Application.settings.get_int ("update-interval");
        var seconds_remaining = update_time - current_ticks;
        status_bar.set_refresh_countdown (seconds_remaining);
    }


    private async void tick () {
        if (!update_paused) {
            current_ticks += 1;
            var update_time = Application.settings.get_int ("update-interval");
            if (current_ticks >= update_time) {
                current_ticks = current_ticks - update_time;
                yield Application.spot_repo.update_spots ();

                Idle.add (() => {
                    on_spot_selected (Application.current_spot_hash);
                    return Source.REMOVE;
                });
            }

            update_refresh_status ();
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
            current_ticks = 0;
            Application.spot_repo.update_spots.begin ();
        }
        refresh_toggle.active = update_paused;
        refresh_toggle.icon_name = update_paused
            ? "arrow-circular-bottom-right-symbolic"
            : "media-playback-pause-symbolic";
        refresh_toggle.tooltip_text = update_paused ? _("Resume") : _("Pause");
        update_refresh_status ();
    }

    ~AppWindow () {
        if (timer_id != 0)
            Source.remove (timer_id);

        disconnect_radio_handlers ();
    }
} /* class AppWindow */
