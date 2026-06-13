 [GtkTemplate (ui = "/com/k0vcz/artemis/ui/spot_list_row.ui")]
public sealed class SpotListRow : Gtk.Box {
    public Spot spot { get; construct; }

    [GtkChild]
    private unowned BandStrip band_marker;
    [GtkChild]
    private unowned Gtk.Label callsign_label;
    [GtkChild]
    private unowned Gtk.Label park_label;
    [GtkChild]
    private unowned Gtk.Label location_label;
    [GtkChild]
    private unowned Gtk.Label frequency_label;
    [GtkChild]
    private unowned Gtk.Label mode_label;
    [GtkChild]
    private unowned Gtk.Box badge_box;
    [GtkChild]
    private unowned Gtk.Label time_label;
    [GtkChild]
    private unowned Gtk.Button tune_button;
    [GtkChild]
    private unowned Gtk.Button spot_button;
    [GtkChild]
    private unowned Gtk.Button not_heard_button;
    private ulong heard_recently_notify_handler = 0;
    private ulong heard_reciprocally_notify_handler = 0;
    private ulong not_heard_recently_notify_handler = 0;
    private ulong was_hunted_today_notify_handler = 0;

    public SpotListRow (Spot spot) {
        Object (spot: spot);
    }

    construct {
        band_marker.band = spot.band;
        callsign_label.label = "%s @ %s".printf (spot.callsign, spot.park_ref);
        park_label.label = spot.park_name;
        location_label.label = spot.location_desc;
        frequency_label.label = "%s kHz".printf (format_frequency_khz (spot.frequency_khz));
        mode_label.label = spot.mode;
        populate_spot_badges (badge_box, spot);
        heard_recently_notify_handler = spot.notify["heard-recently"].connect (() => {
            populate_spot_badges (badge_box, spot);
        });
        heard_reciprocally_notify_handler = spot.notify["heard-reciprocally"].connect (() => {
            populate_spot_badges (badge_box, spot);
        });
        not_heard_recently_notify_handler = spot.notify["not-heard-recently"].connect (() => {
            refresh_visual_state ();
        });
        was_hunted_today_notify_handler = spot.notify["was-hunted-today"].connect (() => {
            refresh_visual_state ();
        });
        time_label.label = humanize_ago_compact (spot.spot_time);
        tune_button.clicked.connect (() => {
            Application.state.current_spot_hash = spot.hash;
            Application.radio_control.tune_to_spot (spot);
        });
        spot_button.clicked.connect (() => {
            Application.state.current_spot_hash = spot.hash;
            new AddSpot.from_spot (spot).present (get_root ());
        });
        not_heard_button.clicked.connect (() => {
            Application.spot_repo.mark_spot_not_heard (spot);
        });
        refresh_visual_state ();
    }

    ~SpotListRow () {
        if (heard_recently_notify_handler != 0) {
            if (SignalHandler.is_connected (spot, heard_recently_notify_handler))
                SignalHandler.disconnect (spot, heard_recently_notify_handler);
            heard_recently_notify_handler = 0;
        }
        if (heard_reciprocally_notify_handler != 0) {
            if (SignalHandler.is_connected (spot, heard_reciprocally_notify_handler))
                SignalHandler.disconnect (spot, heard_reciprocally_notify_handler);
            heard_reciprocally_notify_handler = 0;
        }
        if (not_heard_recently_notify_handler != 0) {
            if (SignalHandler.is_connected (spot, not_heard_recently_notify_handler))
                SignalHandler.disconnect (spot, not_heard_recently_notify_handler);
            not_heard_recently_notify_handler = 0;
        }
        if (was_hunted_today_notify_handler != 0) {
            if (SignalHandler.is_connected (spot, was_hunted_today_notify_handler))
                SignalHandler.disconnect (spot, was_hunted_today_notify_handler);
            was_hunted_today_notify_handler = 0;
        }
    }

    public void set_actions_visible (bool visible) {
        tune_button.visible = visible && Application.is_radio_configured;
        tune_button.sensitive = Application.radio_control.is_rig_connected;
        spot_button.visible = visible;
        not_heard_button.visible = visible;
    }

    private void refresh_visual_state () {
        populate_spot_badges (badge_box, spot);
        remove_css_class ("spot-deprioritized");
        if (spot_is_greyed_out (spot))
            add_css_class ("spot-deprioritized");
    }
}

private Gtk.Widget create_spot_list_row (Object item) {
    var spot = item as Spot;
    if (spot == null)
        return new Gtk.Box (Gtk.Orientation.HORIZONTAL, 0);
    return new SpotListRow (spot);
}

 [GtkTemplate (ui = "/com/k0vcz/artemis/ui/spot_list_view.ui")]
public sealed class SpotListView : Gtk.Box {
    [GtkChild]
    private unowned Gtk.ScrolledWindow scroll_window;
    [GtkChild]
    private unowned Gtk.ListBox spot_list;
    [GtkChild]
    private unowned Adw.StatusPage status_page;

    private Gtk.Filter filter;
    private Gtk.CustomSorter sorter;
    private Gtk.FilterListModel filtered;
    private Gtk.SortListModel sorted;
    private bool just_selected = false;
    private bool row_actions_visible = false;
    private uint sync_selection_idle_id = 0;
    private Quark pending_selection_hash = BLANK_HASH;
    private Gee.ArrayList<Spot> watched_spots = new Gee.ArrayList<Spot> ();
    private Gee.ArrayList<ulong> watched_not_heard_handlers = new Gee.ArrayList<ulong> ();
    private Gee.ArrayList<ulong> watched_hunted_handlers = new Gee.ArrayList<ulong> ();

    public signal void count_changed (uint count);

    public SpotListView () {
        Object ();
    }

    construct {
        filter = new Gtk.CustomFilter ((item) => {
            var spot = item as Spot;
            if (spot == null)
                return false;

            var band_filter = Application.state.current_band_filter ?? "All";
            return spot_matches_current_filters (spot, band_filter);
        });

        sorter = new Gtk.CustomSorter ((item_a, item_b) => {
            var spot_a = item_a as Spot;
            var spot_b = item_b as Spot;
            return compare_spots_for_display (spot_a, spot_b);
        });

        filtered = new Gtk.FilterListModel (Application.spot_repo.store, filter);
        sorted = new Gtk.SortListModel (filtered, sorter);

        spot_list.bind_model (sorted, (item) => {
            var row = create_spot_list_row (item);
            var spot_row = row as SpotListRow;
            if (spot_row != null)
                spot_row.set_actions_visible (row_actions_visible);
            return row;
        });

        spot_list.row_activated.connect ((row) => {
            var list_row = row.get_child () as SpotListRow;
            if ((list_row != null) &&
                !just_selected &&
                (list_row.spot.hash == Application.state.current_spot_hash)) {
                Application.state.current_spot_hash = BLANK_HASH;
                spot_list.unselect_all ();
            }
            if (just_selected) {
                Idle.add (() => {
                    just_selected = false;
                    return Source.REMOVE;
                });
            }
        });

        spot_list.selected_rows_changed.connect (() => {
            var row = spot_list.get_selected_row ();
            if (row == null)
                return;

            var list_row = row.get_child () as SpotListRow;
            if (list_row == null)
                return;

            if (list_row.spot.hash != Application.state.current_spot_hash) {
                Application.state.current_spot_hash = list_row.spot.hash;
                just_selected = true;
            }
        });

        sorted.items_changed.connect ((position, removed, added) => {
            update_visible_state ();
            count_changed (sorted.get_n_items ());
        });
        Application.spot_repo.store.items_changed.connect ((position, removed, added) => {
            reconnect_sort_watchers ();
            refresh_sorting ();
        });

        var settings = Application.settings;
        settings.changed["hide-qrt"].connect (bounce_filter);
        settings.changed["hide-hunted"].connect (bounce_filter);
        settings.changed["hide-older-than"].connect (bounce_filter);

        update_visible_state ();
        reconnect_sort_watchers ();
    }

    private void update_visible_state () {
        var items = sorted.get_n_items ();
        scroll_window.visible = items > 0;
        status_page.visible = items == 0;
    }

    public void bounce_filter () {
        filter.changed (Gtk.FilterChange.DIFFERENT);
    }

    private void refresh_sorting () {
        sorter.changed (Gtk.SorterChange.DIFFERENT);
    }

    private void reconnect_sort_watchers () {
        disconnect_sort_watchers ();

        for (uint i = 0; i < Application.spot_repo.store.get_n_items (); i++) {
            var spot = Application.spot_repo.store.get_item (i) as Spot;
            if (spot == null)
                continue;

            watched_spots.add (spot);
            watched_not_heard_handlers.add (spot.notify["not-heard-recently"].connect (() => {
                refresh_sorting ();
            }));
            watched_hunted_handlers.add (spot.notify["was-hunted-today"].connect (() => {
                refresh_sorting ();
            }));
        }
    }

    private void disconnect_sort_watchers () {
        for (int i = 0; i < watched_spots.size; i++) {
            var spot = watched_spots[i];
            var not_heard_handler = watched_not_heard_handlers[i];
            var hunted_handler = watched_hunted_handlers[i];
            if (SignalHandler.is_connected (spot, not_heard_handler))
                SignalHandler.disconnect (spot, not_heard_handler);
            if (SignalHandler.is_connected (spot, hunted_handler))
                SignalHandler.disconnect (spot, hunted_handler);
        }

        watched_spots.clear ();
        watched_not_heard_handlers.clear ();
        watched_hunted_handlers.clear ();
    }

    public void set_row_actions_visible (bool visible) {
        row_actions_visible = visible;

        for (var child = spot_list.get_first_child (); child != null;
             child = child.get_next_sibling ()) {
            var row = child as Gtk.ListBoxRow;
            if (row == null)
                continue;

            var list_row = row.get_child () as SpotListRow;
            if (list_row != null)
                list_row.set_actions_visible (visible);
        }
    }

    public void set_current_spot (Quark spot_hash) {
        pending_selection_hash = spot_hash;
        if (sync_selection_idle_id != 0)
            return;

        sync_selection_idle_id = Idle.add (() => {
            sync_selection_idle_id = 0;
            var current_hash = pending_selection_hash;

            for (var child = spot_list.get_first_child (); child != null;
                 child = child.get_next_sibling ()) {
                var row = child as Gtk.ListBoxRow;
                if (row == null)
                    continue;

                var list_row = row.get_child () as SpotListRow;
                if (list_row == null)
                    continue;

                if (list_row.spot.hash == current_hash) {
                    spot_list.select_row (row);
                    scroll_to_row (row);
                    return Source.REMOVE;
                }
            }

            spot_list.unselect_all ();
            return Source.REMOVE;
        });
    }

    private void scroll_to_row (Gtk.Widget row) {
        Graphene.Rect bounds;
        if (!row.compute_bounds (spot_list, out bounds))
            return;

        var adj = scroll_window.vadjustment;
        var row_top = bounds.get_top_left ().y;
        var row_bottom = bounds.get_bottom_right ().y;

        if (row_top < adj.value)
            adj.value = row_top;
        else if (row_bottom > adj.value + adj.page_size)
            adj.value = row_bottom - adj.page_size;
    }

    ~SpotListView () {
        disconnect_sort_watchers ();
    }
}
