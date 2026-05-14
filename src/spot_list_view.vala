public sealed class SpotListRow : Gtk.Box {
    public Spot spot { get; construct; }

    private BandStrip band_marker;
    private Gtk.Label callsign_label;
    private Gtk.Label park_label;
    private Gtk.Label location_label;
    private Gtk.Label frequency_label;
    private Gtk.Label mode_label;
    private Gtk.Box badge_box;
    private Gtk.Label time_label;

    public SpotListRow (Spot spot) {
        Object (spot: spot);
    }

    construct {
        orientation = Gtk.Orientation.HORIZONTAL;
        spacing = 12;
        margin_top = 6;
        margin_bottom = 6;
        margin_start = 8;
        margin_end = 12;

        band_marker = new BandStrip (spot.band) {
            width_request = 4,
            height_request = 34,
            valign = Gtk.Align.CENTER,
            margin_end = 4
        };
        append (band_marker);

        var text_box = new Gtk.Box (Gtk.Orientation.VERTICAL, 2) {
            hexpand = true,
            valign = Gtk.Align.CENTER
        };

        callsign_label = new Gtk.Label ("%s @ %s".printf (spot.callsign, spot.park_ref)) {
            hexpand = true,
            xalign = 0.0f,
            ellipsize = Pango.EllipsizeMode.END
        };
        callsign_label.add_css_class ("heading");
        text_box.append (callsign_label);

        park_label = new Gtk.Label (spot.park_name) {
            hexpand = true,
            xalign = 0.0f,
            ellipsize = Pango.EllipsizeMode.END
        };
        park_label.add_css_class ("dim-label");
        text_box.append (park_label);

        append (text_box);

        var trailing_box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 12) {
            halign = Gtk.Align.END,
            valign = Gtk.Align.CENTER,
            hexpand = false
        };

        location_label = new Gtk.Label (spot.location_desc) {
            xalign = 1.0f,
            justify = Gtk.Justification.RIGHT,
            ellipsize = Pango.EllipsizeMode.END
        };
        location_label.add_css_class ("dim-label");
        location_label.width_chars = 8;
        location_label.max_width_chars = 12;
        trailing_box.append (location_label);

        frequency_label = new Gtk.Label ("%d kHz".printf (spot.frequency_khz)) {
            xalign = 1.0f
        };
        frequency_label.add_css_class ("numeric");
        trailing_box.append (frequency_label);

        mode_label = new Gtk.Label (spot.mode) {
            xalign = 0.5f
        };
        mode_label.add_css_class ("pill");
        mode_label.add_css_class ("caption");
        trailing_box.append (mode_label);

        badge_box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 4) {
            valign = Gtk.Align.CENTER
        };
        populate_spot_badges (badge_box, spot);
        trailing_box.append (badge_box);

        time_label = new Gtk.Label (humanize_ago_compact (spot.spot_time)) {
            xalign = 1.0f
        };
        time_label.add_css_class ("dim-label");
        trailing_box.append (time_label);

        append (trailing_box);
    }
}

private Gtk.Widget create_spot_list_row (Object item) {
    var spot = item as Spot;
    if (spot == null)
        return new Gtk.Box (Gtk.Orientation.HORIZONTAL, 0);
    return new SpotListRow (spot);
}

public sealed class SpotListView : Gtk.Box {
    private const int BOTTOM_INSET = 72;

    private Gtk.ScrolledWindow scroll_window;
    private Gtk.ListBox spot_list;
    private Adw.StatusPage status_page;

    private Gtk.Filter filter;
    private Gtk.CustomSorter sorter;
    private Gtk.FilterListModel filtered;
    private Gtk.SortListModel sorted;
    private bool just_selected = false;

    public signal void count_changed (uint count);

    public SpotListView () {
        Object ();
    }

    construct {
        orientation = Gtk.Orientation.VERTICAL;
        hexpand = true;
        vexpand = true;

        scroll_window = new Gtk.ScrolledWindow () {
            hexpand = true,
            vexpand = true,
            hscrollbar_policy = Gtk.PolicyType.NEVER,
            margin_bottom = BOTTOM_INSET
        };

        spot_list = new Gtk.ListBox () {
            selection_mode = Gtk.SelectionMode.SINGLE
        };
        spot_list.add_css_class ("boxed-list");
        scroll_window.set_child (spot_list);
        append (scroll_window);

        status_page = new Adw.StatusPage () {
            visible = false,
            title = _("No Spots Match"),
            description = _("Adjust your filters to see more activations."),
            icon_name = "view-list-symbolic",
            hexpand = true,
            vexpand = true,
            margin_bottom = BOTTOM_INSET
        };
        append (status_page);

        filter = new Gtk.CustomFilter ((item) => {
            var spot = item as Spot;
            if (spot == null)
                return false;

            var band_filter = Application.current_band_filter ?? "All";
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

        spot_list.bind_model (sorted, create_spot_list_row);

        spot_list.row_activated.connect ((row) => {
            var list_row = row.get_child () as SpotListRow;
            if ((list_row != null) &&
                !just_selected &&
                (list_row.spot.hash == Application.current_spot_hash)) {
                Application.current_spot_hash = BLANK_HASH;
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

            if (list_row.spot.hash != Application.current_spot_hash) {
                Application.current_spot_hash = list_row.spot.hash;
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

    public void set_current_spot (Quark spot_hash) {
        Idle.add (() => {
            for (var child = spot_list.get_first_child (); child != null;
                 child = child.get_next_sibling ()) {
                var row = child as Gtk.ListBoxRow;
                if (row == null)
                    continue;

                var list_row = row.get_child () as SpotListRow;
                if (list_row == null)
                    continue;

                if (list_row.spot.hash == spot_hash) {
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
