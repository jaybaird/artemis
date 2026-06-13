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
using Adw;

private enum RefreshButtonState {
    PAUSE,
    RESUME,
    RELOADING
}

[GtkTemplate (ui = "/com/k0vcz/artemis/ui/main_window.ui")]
public sealed class AppWindow : Adw.ApplicationWindow {
    [GtkChild]
    private unowned Adw.ToastOverlay toast_overlay;

    [GtkChild]
    private unowned BandView band_view;

    //[GtkChild]
    //public unowned Gtk.Widget loading_spinner;

    [GtkChild]
    public unowned Gtk.SearchEntry search_entry;

    [GtkChild]
    private unowned Gtk.SearchBar search_bar;

    [GtkChild]
    private unowned Gtk.ToggleButton search_button;

    [GtkChild]
    private unowned Adw.ViewStack views;

    [GtkChild]
    private unowned Adw.HeaderBar main_header;

    [GtkChild]
    public unowned Gtk.Box map_container;

    [GtkChild]
    public unowned Gtk.Box list_container;

    [GtkChild]
    private unowned Gtk.ToggleButton refresh_toggle;

    [GtkChild]
    private unowned Adw.Clamp collapsed_sidebar_controls;

    [GtkChild]
    private unowned Gtk.Button header_add_spot_button;

    [GtkChild]
    private unowned Adw.OverlaySplitView sidebar_split;

    [GtkChild]
    private unowned Gtk.ToggleButton sidebar_toggle;

    [GtkChild]
    private unowned Adw.OverlaySplitView inspector_split;

    [GtkChild]
    private unowned Gtk.ToggleButton inspector_toggle;

    [GtkChild]
    private unowned Gtk.Widget alerts_badge;

    [GtkChild]
    private unowned StatusBar status_bar;

    [GtkChild]
    private unowned LeftSidebar left_sidebar;

    [GtkChild]
    private unowned SpotDetail spot_detail;

    [GtkChild]
    private unowned Gtk.Stack refresh_button_stack;

    [GtkChild]
    private unowned Adw.Spinner refresh_spinner;

    [GtkChild]
    private unowned Gtk.MenuButton space_weather_menu_button;

    [GtkChild]
    private unowned SpaceWeatherButton space_weather_button;

    private uint refresh_timer_id = 0;
    private int64 next_refresh_at_us = 0;
    private int64 next_clock_update_at_us = 0;
    private bool refresh_in_progress = false;

    private bool update_paused = false;
    private MapView? map_view = null;
    private SpotListView? list_view = null;
    private bool radio_connect_inflight = false;
    private uint auto_radio_start_id = 0;
    private Quark map_centered_spot_hash = BLANK_HASH;
    private string? pending_initial_band = null;
    private bool initial_band_applied = false;

    private ulong radio_status_handler = 0;
    private ulong radio_error_handler = 0;
    private ulong space_weather_changed_handler = 0;
    private bool syncing_inspector_toggle = false;
    private bool restoring_window_state = false;
    private Adw.TimedAnimation? search_margin_animation = null;

    private static Gee.HashSet<string> active_error_keys;
    private const int CONTENT_TOP_MARGIN = 48;
    private const int SEARCH_TOP_MARGIN = 96;
    private const uint SEARCH_MARGIN_ANIMATION_DURATION = 250;

    public AppWindow (Gtk.Application app) {
        Object (application: app);
    }

    construct {
        var toggle_sidebar_action = new SimpleAction ("toggle-sidebar", null);
        toggle_sidebar_action.activate.connect (() => {
            set_sidebar_visible (!sidebar_split.show_sidebar);
        });
        add_action (toggle_sidebar_action);

        var search_action = new SimpleAction ("search", null);
        search_action.activate.connect (() => {
            search_bar.search_mode_enabled = true;
            search_entry.grab_focus ();
        });
        add_action (search_action);

        restore_window_state ();
        space_weather_menu_button.popover = space_weather_button.create_popover ();

        active_error_keys = new Gee.HashSet<string> ();
        left_sidebar.set_mode_visible (Application.is_radio_configured);
        if (Application.is_radio_configured) {
            queue_initial_radio_start ();
        }

        refresh_toggle.clicked.connect (on_refresh_button_clicked);
        header_add_spot_button.clicked.connect (on_add_button_clicked);

        left_sidebar.add_requested.connect (on_add_button_clicked);
        left_sidebar.sidebar_visibility_changed.connect ((visible) => {
            set_sidebar_visible (visible);
        });
        left_sidebar.power_clicked.connect (() => {
            if (radio_connect_inflight)
                return;
            if (Application.radio_control.is_rig_connected) {
                power_off_radio ();
            } else {
                start_radio ();
            }
        });
        search_bar.set_key_capture_widget (this);
        search_bar.bind_property (
            "search-mode-enabled",
            search_button,
            "active",
            BindingFlags.BIDIRECTIONAL | BindingFlags.SYNC_CREATE
        );
        search_bar.notify["search-mode-enabled"].connect (animate_search_content_margins);
        views.notify["visible-child-name"].connect (on_visible_view_changed);
        sync_alerts_badge ();
        Application.settings.changed["spot-alerts-enabled"].connect (sync_alerts_badge);

        Application.settings.changed["update-interval"].connect (() => {
            reset_refresh_schedule ();
        });

        Application.app.toast_requested.connect ((message) => {
            toast_overlay.add_toast (new Adw.Toast (message));
        });

        search_entry.search_changed.connect (() => {
            var text = search_entry.text.strip ();
            Application.state.current_search_text = text != "" ? text : null;
            refresh_spot_views ();
        });

        inspector_toggle.toggled.connect (() => {
            if (!syncing_inspector_toggle)
                set_inspector_visible (inspector_toggle.active);
        });
        sidebar_toggle.toggled.connect (() => {
            set_sidebar_visible (sidebar_toggle.active);
        });
        sidebar_split.notify["collapsed"].connect (update_collapsed_sidebar_controls);
        sidebar_split.notify["show-sidebar"].connect (update_collapsed_sidebar_controls);

        notify["default-width"].connect (save_window_geometry);
        notify["default-height"].connect (save_window_geometry);
        notify["maximized"].connect (save_window_maximized_state);

        Application.spot_repo.busy_changed.connect ((busy) => {
            set_refresh_button_state (
                busy
                    ? RefreshButtonState.RELOADING
                    : update_paused
                        ? RefreshButtonState.RESUME
                        : RefreshButtonState.PAUSE
            );
        });

        Application.spot_repo.refreshed.connect ((spots_updated) => {
            if (!initial_band_applied && Application.state.current_mode_filter == null) {
                var preferred_mode = Application.settings.get_string ("default-mode");
                if (preferred_mode != "" && preferred_mode != "All")
                    Application.state.current_mode_filter = preferred_mode;
            }

            if ((Application.state.current_mode_filter != null) &&
                !string_list_contains (
                    Application.spot_repo.mode_model,
                    Application.state.current_mode_filter
                )) {
                Application.state.current_mode_filter = null;
            }

            left_sidebar.update_bands (
                Application.spot_repo.band_counts,
                get_initial_sidebar_band ()
            );
            apply_initial_band_selection_if_needed ();
            left_sidebar.update_mode_model (
                Application.spot_repo.mode_model,
                Application.state.current_mode_filter
            );
            left_sidebar.update_program_model (
                Application.spot_repo.program_model,
                Application.state.current_program_filter
            );

            if (Application.state.current_spot_hash != BLANK_HASH &&
                !current_spot_matches_filters ()) {
                Application.state.current_spot_hash = BLANK_HASH;
            }

            if (!refresh_in_progress) {
                next_refresh_at_us = get_monotonic_time () + refresh_interval_us ();
                schedule_next_refresh_wake ();
            }

            update_refresh_status ();
            update_status_bar ();
        });

        Application.spot_repo.log_status_refreshed.connect (() => {
            band_view.bounce_filter ();
            if (list_view != null)
                list_view.bounce_filter ();
            if (map_view != null)
                map_view.bounce_filter ();

            spot_detail.set_spot (
                Application.spot_repo.get_spot (Application.state.current_spot_hash)
            );
            update_status_bar ();
        });

        Application.spot_repo.current_spot_changed.connect ((spot_hash) => {
            sync_selected_spot (spot_hash, true);
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

        pending_initial_band = Application.settings.get_string ("default-band");
        Application.state.current_band_filter = "All";
        Application.state.current_mode_filter = null;
        Application.state.current_program_filter = null;
        Application.state.current_search_text = null;
        band_view.set_band_filter (Application.state.current_band_filter);
        start_spot_updates ();

        left_sidebar.band_selected.connect ((band) => {
            set_current_band_filter (band);
        });

        left_sidebar.mode_changed.connect ((mode) => {
            Application.state.current_mode_filter = mode;
            refresh_spot_views ();
        });

        left_sidebar.program_changed.connect ((program) => {
            Application.state.current_program_filter = program;
            refresh_spot_views ();
        });

        left_sidebar.update_bands (
            Application.spot_repo.band_counts,
            get_initial_sidebar_band ()
        );
        left_sidebar.update_mode_model (
            Application.spot_repo.mode_model,
            Application.state.current_mode_filter
        );
        left_sidebar.update_program_model (
            Application.spot_repo.program_model,
            Application.state.current_program_filter
        );

        Application.app.radio_connection_state_changed.connect (() => {
            if (list_view != null)
                list_view.set_row_actions_visible (!inspector_split.show_sidebar);
        });

        on_visible_view_changed ();

        set_refresh_button_state (update_paused ? RefreshButtonState.RESUME : RefreshButtonState.PAUSE);

        set_sidebar_visible (true);
        update_collapsed_sidebar_controls ();
        set_inspector_visible (false);
        update_space_weather_view ();
        space_weather_changed_handler = Application.space_weather_service.changed.connect (
            update_space_weather_view
        );

        Application.settings.changed["hide-qrt"].connect (refresh_spot_views);
        Application.settings.changed["hide-hunted"].connect (refresh_spot_views);
        Application.settings.changed["hide-older-than"].connect (refresh_spot_views);
    }

    private void set_search_content_margin (int margin) {
        band_view.margin_top = margin;
        list_container.margin_top = margin;
        if (map_view != null)
            map_view.set_top_overlay_margin (margin);
    }

    private void sync_alerts_badge () {
        alerts_badge.visible = Application.settings.get_boolean ("spot-alerts-enabled");
    }

    public void open_map () {
        views.visible_child_name = "map";
    }

    private void on_visible_view_changed () {
        var visible_child_name = views.visible_child_name;

        if (visible_child_name == "list") {
            ensure_list_view ();
        } else if (visible_child_name == "map") {
            ensure_map_view ();
            if (map_view != null)
                map_view.set_active (true);
        }

        if (visible_child_name != "map" && map_view != null)
            map_view.set_active (false);

        spot_detail.set_action_buttons_visible (views.visible_child_name != "cards");
        spot_detail.set_open_map_button_visible (views.visible_child_name != "map");
    }

    private void ensure_list_view () {
        if (list_view != null)
            return;

        list_view = new SpotListView () {
            hexpand = true,
            vexpand = true
        };
        list_container.append (list_view);
        list_view.set_row_actions_visible (!inspector_split.show_sidebar);
        list_view.count_changed.connect (() => update_status_bar ());
        list_view.set_current_spot (Application.state.current_spot_hash);
        update_status_bar ();
    }

    private void ensure_map_view () {
        if (map_view != null)
            return;

        map_view = new MapView () {
            hexpand = true,
            vexpand = true
        };
        map_container.append (map_view);
        map_view.set_top_overlay_margin (band_view.margin_top);
        map_view.bounce_filter ();

        if (Application.state.current_spot_hash == BLANK_HASH)
            return;

        var spot = Application.spot_repo.get_spot (Application.state.current_spot_hash);
        if (spot != null) {
            map_view.go_to_spot (spot);
            map_centered_spot_hash = Application.state.current_spot_hash;
        }
    }

    private void animate_search_content_margins () {
        var target_margin = search_bar.search_mode_enabled ? SEARCH_TOP_MARGIN : CONTENT_TOP_MARGIN;
        var current_margin = band_view.margin_top;

        if (current_margin == target_margin)
            return;

        if (search_margin_animation != null)
            search_margin_animation.pause ();

        var target = new Adw.CallbackAnimationTarget ((value) => {
            set_search_content_margin ((int) Math.round (value));
        });

        search_margin_animation = new Adw.TimedAnimation (
            this,
            current_margin,
            target_margin,
            SEARCH_MARGIN_ANIMATION_DURATION,
            target
        );
        search_margin_animation.easing = Adw.Easing.EASE_OUT_CUBIC;
        search_margin_animation.done.connect (() => {
            set_search_content_margin (target_margin);
            search_margin_animation = null;
        });
        search_margin_animation.play ();
    }

    private void sync_selected_spot (Quark spot_hash, bool reveal_inspector) {
        var spot = Application.spot_repo.get_spot (spot_hash);
        spot_detail.set_spot (spot);

        if (spot == null) {
            map_centered_spot_hash = BLANK_HASH;
            band_view.set_current_spot (BLANK_HASH);
            if (list_view != null)
                list_view.set_current_spot (BLANK_HASH);
            return;
        }

        if (reveal_inspector)
            set_inspector_visible (true);

        if ((map_view != null) && (spot_hash != map_centered_spot_hash)) {
            map_view.go_to_spot (spot);
            map_centered_spot_hash = spot_hash;
        }

        band_view.set_current_spot (spot_hash);

        if (list_view != null)
            list_view.set_current_spot (spot_hash);
    }

    private void set_inspector_visible (bool visible) {
        if (visible == inspector_split.show_sidebar) {
            update_inspector_title_buttons (visible);
            syncing_inspector_toggle = true;
            inspector_toggle.active = visible;
            syncing_inspector_toggle = false;
            inspector_toggle.tooltip_text = visible ? _("Hide Inspector") : _("Show Inspector");
            if (list_view != null)
                list_view.set_row_actions_visible (!visible);
            return;
        }

        inspector_split.show_sidebar = visible;
        spot_detail.sensitive = visible;
        update_inspector_title_buttons (visible);

        syncing_inspector_toggle = true;
        inspector_toggle.active = visible;
        syncing_inspector_toggle = false;
        inspector_toggle.tooltip_text = visible ? _("Hide Inspector") : _("Show Inspector");
        if (list_view != null)
            list_view.set_row_actions_visible (!visible);
    }

    private void update_inspector_title_buttons (bool inspector_visible) {
        main_header.show_end_title_buttons = !inspector_visible;
        spot_detail.set_end_title_buttons_visible (inspector_visible);
    }

    private void set_sidebar_visible (bool visible) {
        left_sidebar.set_sidebar_visible_state (visible);

        if (visible == sidebar_split.show_sidebar) {
            sidebar_toggle.active = visible;
            sidebar_toggle.tooltip_text = visible ? _("Hide Sidebar") : _("Show Sidebar");
            update_collapsed_sidebar_controls ();
            return;
        }

        sidebar_split.show_sidebar = visible;
        sidebar_toggle.active = visible;
        sidebar_toggle.tooltip_text = visible ? _("Hide Sidebar") : _("Show Sidebar");
        update_collapsed_sidebar_controls ();
    }

    private void update_collapsed_sidebar_controls () {
        collapsed_sidebar_controls.visible = sidebar_split.collapsed ||
            !sidebar_split.show_sidebar;
    }

    private void update_status_bar () {
        var current_band = Application.state.current_band_filter ?? "All";
        int total_available = 0;
        if (current_band == "All") {
            total_available = (int)Application.spot_repo.store.get_n_items ();
        } else {
            total_available = Application.spot_repo.get_band_count (current_band);
        }

        int total_visible = count_visible_spots ();
        int filtered_count = total_available - total_visible;
        if (filtered_count < 0)
            filtered_count = 0;

        status_bar.set_filtered_text ((uint)filtered_count, (uint)total_visible);
    }

    private int count_visible_spots () {
        var current_band = Application.state.current_band_filter ?? "All";
        var count = 0;
        for (uint i = 0; i < Application.spot_repo.store.get_n_items (); i++) {
            var spot = Application.spot_repo.store.get_item (i) as Spot;
            if (spot != null && spot_matches_current_filters (spot, current_band))
                count++;
        }
        return count;
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
        if (Application.state.current_spot_hash == BLANK_HASH)
            return false;

        var spot = Application.spot_repo.get_spot (Application.state.current_spot_hash);
        if (spot == null)
            return false;

        return spot_matches_current_filters (
            spot,
            Application.state.current_band_filter ?? "All"
        );
    }

    private void restore_window_state () {
        restoring_window_state = true;

        var width = Application.settings.get_int ("window-width");
        var height = Application.settings.get_int ("window-height");
        set_default_size (width, height);

        if (Application.settings.get_boolean ("window-maximized"))
            maximize ();

        restoring_window_state = false;
    }

    private void save_window_geometry () {
        if (restoring_window_state || is_maximized ())
            return;

        Application.settings.set_int ("window-width", default_width);
        Application.settings.set_int ("window-height", default_height);
    }

    private void save_window_maximized_state () {
        if (restoring_window_state)
            return;

        Application.settings.set_boolean ("window-maximized", is_maximized ());
        if (!is_maximized ())
            save_window_geometry ();
    }

    private void refresh_spot_views () {
        bounce_map_filter_if_ready ();
        if (list_view != null)
            list_view.bounce_filter ();

        band_view.bounce_filter ();

        if (Application.state.current_spot_hash != BLANK_HASH &&
            !current_spot_matches_filters ()) {
            Application.state.current_spot_hash = BLANK_HASH;
        }

        update_status_bar ();
    }

    private void initial_update () {
        Application.spot_repo.update_spots.begin ((obj, res) => {
            Application.spot_repo.update_spots.end (res);
        });
    }

    private void reset_refresh_schedule () {
        cancel_refresh_timer ();

        var now = get_monotonic_time ();
        next_refresh_at_us = now + refresh_interval_us ();
        next_clock_update_at_us = next_clock_update_deadline_us ();
        update_clock_label ();
        update_refresh_status ();
        schedule_next_refresh_wake ();
    }

    private void start_spot_updates () {
        reset_refresh_schedule ();
        initial_update ();
    }

    private int64 refresh_interval_us () {
        return int64.max (
            1,
            Application.settings.get_int ("update-interval")
        ) * GLib.TimeSpan.SECOND;
    }

    private int64 next_clock_update_deadline_us () {
        var now_utc = new DateTime.now_utc ();
        var seconds_text = now_utc.format ("%S");
        var seconds = int.parse (seconds_text);
        return get_monotonic_time () + (60 - seconds) * GLib.TimeSpan.SECOND;
    }

    private void cancel_refresh_timer () {
        if (refresh_timer_id != 0) {
            Source.remove (refresh_timer_id);
            refresh_timer_id = 0;
        }
    }

    private void schedule_next_refresh_wake () {
        cancel_refresh_timer ();

        if (update_paused)
            return;

        var now = get_monotonic_time ();
        var next_status_at_us = next_refresh_status_deadline_us (now);
        var next_wake_at_us = int64.min (next_status_at_us, next_clock_update_at_us);
        var delay_us = int64.max (
            next_wake_at_us - now,
            100 * GLib.TimeSpan.MILLISECOND
        );

        refresh_timer_id = Timeout.add (
            (uint) int64.max (1, delay_us / GLib.TimeSpan.MILLISECOND),
            () => {
                refresh_timer_id = 0;
                on_refresh_timer ();
                return Source.REMOVE;
            }
        );
    }

    private int64 next_refresh_status_deadline_us (int64 now) {
        var remaining_seconds = seconds_until_refresh (now);
        if (remaining_seconds <= 10)
            return now + GLib.TimeSpan.SECOND;
        if (remaining_seconds <= 60)
            return now + 5 * GLib.TimeSpan.SECOND;

        var minute_boundary = next_refresh_at_us -
            ((remaining_seconds - 60) * GLib.TimeSpan.SECOND);
        return int64.min (now + 60 * GLib.TimeSpan.SECOND, minute_boundary);
    }

    private uint seconds_until_refresh (int64 now) {
        if (next_refresh_at_us <= now)
            return 0;

        return (uint) Math.ceil (
            (next_refresh_at_us - now) / (double) GLib.TimeSpan.SECOND
        );
    }

    private void on_refresh_timer () {
        var now = get_monotonic_time ();

        if (!update_paused && now >= next_refresh_at_us) {
            refresh_due.begin ();
            return;
        }

        if (now >= next_clock_update_at_us) {
            update_clock_label ();
            next_clock_update_at_us = next_clock_update_deadline_us ();
        }

        update_refresh_status ();
        schedule_next_refresh_wake ();
    }

    private async void refresh_due () {
        if (refresh_in_progress)
            return;

        refresh_in_progress = true;
        yield Application.spot_repo.update_spots ();

        var now = get_monotonic_time ();
        var interval_us = refresh_interval_us ();
        do {
            next_refresh_at_us += interval_us;
        } while (next_refresh_at_us <= now);

        sync_selected_spot (Application.state.current_spot_hash, false);
        update_clock_label ();
        next_clock_update_at_us = next_clock_update_deadline_us ();
        update_refresh_status ();
        refresh_in_progress = false;
        schedule_next_refresh_wake ();
    }

    private string get_initial_sidebar_band () {
        if (initial_band_applied)
            return Application.state.current_band_filter ?? "All";

        var preferred_band = pending_initial_band ?? "All";
        if (Application.spot_repo.band_counts.size == 0)
            return "All";
        if ((preferred_band != "All") &&
            !Application.spot_repo.band_counts.has_key (preferred_band))
            return "All";

        return preferred_band;
    }

    private void apply_initial_band_selection_if_needed () {
        if (initial_band_applied)
            return;

        var initial_band = get_initial_sidebar_band ();
        initial_band_applied = true;
        pending_initial_band = null;
        set_current_band_filter (initial_band);
    }

    private void set_current_band_filter (string band) {
        Application.state.current_band_filter = band;
        left_sidebar.set_selected_band (band);
        band_view.set_band_filter (band);
        if (map_view != null)
            map_view.set_band_filter (band);
        refresh_spot_views ();
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

    private void queue_initial_radio_start () {
        if (auto_radio_start_id != 0)
            return;

        auto_radio_start_id = Timeout.add (250, () => {
            auto_radio_start_id = 0;
            if (Application.is_radio_configured &&
                !Application.radio_control.is_rig_connected &&
                !radio_connect_inflight) {
                start_radio ();
            }
            return Source.REMOVE;
        });
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
                    left_sidebar.set_tx_active (false);
                    left_sidebar.set_rx_active (true);
                    disconnect_radio_handlers ();
                    radio_status_handler = Application.radio_control.radio_status.connect ((freq, mode, tx_active) => {
                        left_sidebar.set_tx_active (tx_active);
                        left_sidebar.set_rx_active (!tx_active);
                        left_sidebar.set_power_button_tooltip (_("Disconnect from radio"));
                        left_sidebar.set_power_button_text (_("Disconnect"));
                        left_sidebar.set_power_button_active (true);

                        if (freq > 0 && mode != 0) {
                            left_sidebar.set_mode_visible (true);
                            left_sidebar.set_vfo_animated (freq);
                            left_sidebar.set_mode_text (RadioControl.mode_string (mode));
                        } else {
                            left_sidebar.reset_vfo ();
                            left_sidebar.set_mode_visible (false);
                            left_sidebar.set_tx_active (tx_active);
                            left_sidebar.set_rx_active (!tx_active);
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

        status_bar.set_refresh_countdown (
            seconds_until_refresh (get_monotonic_time ())
        );
    }

    private void update_clock_label () {
        var now = new GLib.DateTime.now_utc ().format ("%R UTC");
        status_bar.set_time (now);
        spot_detail.update_local_time_row ();
    }

    private void update_space_weather_view () {
        var service = Application.space_weather_service;

        if (!service.has_snapshot ()) {
            if (service.loading) {
                space_weather_menu_button.sensitive = false;
                space_weather_button.show_loading ();
            } else {
                space_weather_menu_button.sensitive = true;
                space_weather_button.show_unavailable ();
            }
            return;
        }

        var snapshot = service.snapshot;
        if (snapshot == null)
            return;

        space_weather_menu_button.sensitive = !service.loading;
        space_weather_menu_button.tooltip_text = snapshot.secondary_text ();
        space_weather_button.show_snapshot (snapshot);
    }

    private void on_add_button_clicked () {
        AddSpot? add_spot = null;
        if (Application.radio_control.is_rig_connected && Application.radio_control.frequency > 0) {
            add_spot = new AddSpot.with_frequency (Application.radio_control.frequency);
        } else {
            add_spot = new AddSpot ();
        }
        add_spot.present (this);
    }

    private void set_refresh_button_state (RefreshButtonState state) {
    switch (state) {
        case RefreshButtonState.RELOADING:
            refresh_button_stack.visible_child = refresh_spinner;
            break;

        case RefreshButtonState.PAUSE:
            refresh_button_stack.visible_child = refresh_toggle;
            refresh_toggle.active = false;
            refresh_toggle.icon_name = "media-playback-pause-symbolic";
            refresh_toggle.tooltip_text = _("Pause");
            break;

        case RefreshButtonState.RESUME:
            refresh_button_stack.visible_child = refresh_toggle;
            refresh_toggle.active = true;
            refresh_toggle.icon_name = "arrow-circular-bottom-right-symbolic";
            refresh_toggle.tooltip_text = _("Resume");
            break;
    }
}

    private void on_refresh_button_clicked () {
        update_paused = !update_paused;
        if (update_paused) {
            cancel_refresh_timer ();
            Application.show_toast (_("Spot updates paused"));
        } else {
            var now = get_monotonic_time ();
            next_refresh_at_us = now + refresh_interval_us ();
            next_clock_update_at_us = next_clock_update_deadline_us ();
            Application.show_toast (_("Spot updates resumed"));
            Application.spot_repo.update_spots.begin ();
            schedule_next_refresh_wake ();
        }

        set_refresh_button_state (update_paused ? RefreshButtonState.RESUME : RefreshButtonState.PAUSE);

        update_refresh_status ();
    }

    ~AppWindow () {
        cancel_refresh_timer ();
        if (auto_radio_start_id != 0) {
            Source.remove (auto_radio_start_id);
            auto_radio_start_id = 0;
        }

        if (space_weather_changed_handler != 0) {
            SignalHandler.disconnect (Application.space_weather_service, space_weather_changed_handler);
            space_weather_changed_handler = 0;
        }

        disconnect_radio_handlers ();
    }
} /* class AppWindow */
