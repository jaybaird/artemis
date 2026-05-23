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
    private ulong heard_recently_notify_handler = 0;

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
        time_label.label = humanize_ago_compact (spot.spot_time);
        tune_button.clicked.connect (() => {
            Application.state.current_spot_hash = spot.hash;
            Application.radio_control.tune_to_spot (spot);
        });
        spot_button.clicked.connect (() => {
            Application.state.current_spot_hash = spot.hash;
            new AddSpot.from_spot (spot).present (get_root ());
        });
    }

    ~SpotListRow () {
        if (heard_recently_notify_handler != 0) {
            if (SignalHandler.is_connected (spot, heard_recently_notify_handler))
                SignalHandler.disconnect (spot, heard_recently_notify_handler);
            heard_recently_notify_handler = 0;
        }
    }

    public void set_actions_visible (bool visible) {
        tune_button.visible = visible && Application.is_radio_configured;
        tune_button.sensitive = Application.radio_control.is_rig_connected;
        spot_button.visible = visible;
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
            if ((spot_a == null) || (spot_b == null))
                return Gtk.Ordering.EQUAL;

            var cmp = spot_a.spot_time.compare (spot_b.spot_time);
            if (cmp > 0)
                return Gtk.Ordering.SMALLER;
            if (cmp < 0)
                return Gtk.Ordering.LARGER;
            return Gtk.Ordering.EQUAL;
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

        var settings = Application.settings;
        settings.changed["hide-qrt"].connect (bounce_filter);
        settings.changed["hide-hunted"].connect (bounce_filter);
        settings.changed["hide-older-than"].connect (bounce_filter);

        update_visible_state ();
    }

    private void update_visible_state () {
        var items = sorted.get_n_items ();
        scroll_window.visible = items > 0;
        status_page.visible = items == 0;
    }

    public void bounce_filter () {
        filter.changed (Gtk.FilterChange.DIFFERENT);
    }

    public uint get_n_items () {
        return sorted.get_n_items ();
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
}
