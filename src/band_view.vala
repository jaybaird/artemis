/* src/band_view.vala
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

public bool contains_text_case_insensitive (string? haystack, string? needle) {
    if ((haystack == null) || (needle == null) || (needle.length == 0))
        return true;
    if (haystack.length == 0)
        return false;

    return haystack.ascii_down ().contains (needle.ascii_down ());
}

private SpotCard create_spot_card (Spot spot) {
    return new SpotCard.from_spot (spot);
}

[GtkTemplate (ui = "/com/k0vcz/artemis/ui/band_view.ui")]
public sealed class BandView : Gtk.Box {
    public string band_label { get; set; default = "All"; }
    public string icon_name { get; set; default = "band-All"; }
    [GtkChild]
    public unowned Gtk.FlowBox band_spot_cards;

    [GtkChild]
    private unowned Gtk.ScrolledWindow spot_scroll_window;

    [GtkChild]
    public unowned Adw.StatusPage status_page;

    public signal void count_changed (uint count);

    private Gtk.Filter filter;
    private Gtk.CustomSorter sorter;
    private Gtk.FilterListModel filtered;
    private Gtk.SortListModel sorted;

    private bool just_selected = false;
    private SelectionSyncGuard selection_sync = new SelectionSyncGuard ();
    private uint sync_selection_idle_id = 0;
    private Quark pending_selection_hash = BLANK_HASH;
    private Gee.ArrayList<Spot> watched_spots = new Gee.ArrayList<Spot> ();
    private Gee.ArrayList<ulong> watched_not_heard_handlers = new Gee.ArrayList<ulong> ();
    private Gee.ArrayList<ulong> watched_hunted_handlers = new Gee.ArrayList<ulong> ();

    public BandView (string band_label, string icon) {
        Object (
            band_label: band_label,
            icon_name: icon
            );
    }

    construct {
        var settings = Application.settings;
        filter = new Gtk.CustomFilter ((item) => {
            var spot = item as Spot;
            if (spot == null)
                return false;

            var band_filter = Application.state.current_band_filter;
            return spot_matches_current_filters (spot, band_filter);
        });

        filtered = new Gtk.FilterListModel (Application.spot_repo.store, filter);

        sorter = new Gtk.CustomSorter ((item_a, item_b) => {
            var spot_a = item_a as Spot;
            var spot_b = item_b as Spot;
            return compare_spots_for_display (spot_a, spot_b);
        });
        sorted = new Gtk.SortListModel (filtered, sorter);

        band_spot_cards.bind_model (
            sorted,
            (Gtk.FlowBoxCreateWidgetFunc)create_spot_card
        );
        band_spot_cards.child_activated.connect ((child) => {
            var spot_card = child.get_child () as SpotCard;
            if ((spot_card != null) &&
                !just_selected &&
                (spot_card.spot.hash == Application.state.current_spot_hash)) {
                Application.state.clear_spot_selection ();
                select_current_child (null);
            }
            if (just_selected) {
                Idle.add (() => {
                    just_selected = false;
                    return Source.REMOVE;
                });
            }
        });
        band_spot_cards.selected_children_changed.connect (() => {
            if (selection_sync.should_ignore_changes)
                return;

            var selected = band_spot_cards.get_selected_children ();
            if ((selected != null) && (selected.length () > 0)) {
                var child = selected.nth_data (0) as Gtk.FlowBoxChild;
                var spot_card = child.get_child () as SpotCard;
                if (spot_card != null) {
                    var spot_hash = spot_card.spot.hash;
                    if (spot_hash != Application.state.current_spot_hash) {
                        Application.state.select_spot (spot_hash);
                        just_selected = true;
                    }
                    sync_card_selection (spot_hash);
                }
            } else {
                sync_card_selection (BLANK_HASH);
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
        Application.spot_repo.spots_replacing.connect (() => {
            begin_model_selection_sync ();
        });
        Application.spot_repo.spots_replaced.connect (() => {
            finish_model_selection_sync ();
        });

        update_visible_state ();
        reconnect_sort_watchers ();

        settings.changed["hide-qrt"].connect (bounce_filter);
        settings.changed["hide-hunted"].connect (bounce_filter);
        settings.changed["hide-older-than"].connect (bounce_filter);
        settings.changed["use-metric"].connect (_refresh_cards);
        settings.changed["highlight-unhunted-parks"].connect (_refresh_cards);
    }

    public void set_current_spot (Quark spot_hash) {
        pending_selection_hash = spot_hash;
        if (sync_selection_idle_id != 0)
            return;

        sync_selection_idle_id = Idle.add (() => {
            sync_selection_idle_id = 0;
            var current_hash = pending_selection_hash;

            if (current_hash == BLANK_HASH) {
                sync_card_selection (BLANK_HASH);
                select_current_child (null);
                return Source.REMOVE;
            }

            var selected_child = sync_card_selection (current_hash);
            if (selected_child != null) {
                select_current_child (selected_child);
                Idle.add (() => {
                    scroll_to_child (selected_child);
                    return Source.REMOVE;
                });
                return Source.REMOVE;
            }

            select_current_child (null);
            return Source.REMOVE;
        });
    }

    private void select_current_child (Gtk.FlowBoxChild? child) {
        selection_sync.run_programmatic_sync (() => {
            if (child != null)
                band_spot_cards.select_child (child);
            else
                band_spot_cards.unselect_all ();
        });
    }

    private Gtk.FlowBoxChild? sync_card_selection (Quark current_hash) {
        Gtk.FlowBoxChild? selected_child = null;

        for (var child = band_spot_cards.get_first_child ();
             child != null;
             child = child.get_next_sibling ()) {
            var flow_child = child as Gtk.FlowBoxChild;
            if (flow_child == null)
                continue;

            var spot_card = flow_child.get_child () as SpotCard;
            if (spot_card == null)
                continue;

            var is_selected = (
                current_hash != BLANK_HASH &&
                spot_card.spot.hash == current_hash
            );
            spot_card.selected = is_selected;

            if (is_selected)
                selected_child = flow_child;
        }

        return selected_child;
    }

    private void scroll_to_child (Gtk.Widget child) {
        Graphene.Rect bounds;
        if (!child.compute_bounds (band_spot_cards, out bounds))
            return;

        var adj = spot_scroll_window.vadjustment;
        var child_top = bounds.get_top_left ().y;
        var child_bottom = bounds.get_bottom_right ().y;

        if (child_top < adj.value)
            adj.value = child_top;
        else if (child_bottom > adj.value + adj.page_size)
            adj.value = child_bottom - adj.page_size;
    }

    private void _refresh_cards () {
        for (var child = band_spot_cards.get_first_child () ; child != null ;
             child = child.get_next_sibling ()) {
            var fbchild = child as Gtk.FlowBoxChild;
            if (fbchild == null)
                continue;

            var spot_card = fbchild.get_child () as SpotCard;
            if (spot_card != null)
                spot_card.refresh_highlight ();
        }
    }

    public void set_band_filter (string band) {
        band_label = band;
        icon_name = @"band-$band";
        bounce_filter ();
        update_visible_state ();
    }

    public void bounce_filter (string? key = null) {
        begin_model_selection_sync ();
        filter.changed (Gtk.FilterChange.DIFFERENT);
        finish_model_selection_sync ();
    }

    private void refresh_sorting () {
        begin_model_selection_sync ();
        sorter.changed (Gtk.SorterChange.DIFFERENT);
        finish_model_selection_sync ();
    }

    private void begin_model_selection_sync () {
        selection_sync.begin_model_sync ();
    }

    private void finish_model_selection_sync () {
        selection_sync.finish_model_sync (() => {
            set_current_spot (Application.state.current_spot_hash);
        });
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

    private void update_visible_state () {
        var items = sorted.get_n_items ();
        var band = Application.state.current_band_filter;
        band_label = band;
        icon_name = @"band-$band";

        band_spot_cards.visible = (items > 0);
        status_page.visible = (items == 0);
        status_page.title = band_label;
        status_page.icon_name = icon_name;

        if (items > 0)
            return;

        int raw_count = (band_label == "All")
            ? (int)Application.spot_repo.store.get_n_items ()
            : Application.spot_repo.get_band_count (band_label);
        if (raw_count > 0)
            status_page.description = _("No spots on %s match your current filters").printf (band_label);
        else
            status_page.description = _("There are no spots currently on %s").printf (band_label);
    }

    ~BandView () {
        if (sync_selection_idle_id != 0) {
            Source.remove (sync_selection_idle_id);
            sync_selection_idle_id = 0;
        }
        disconnect_sort_watchers ();
    }
} /* class BandView */
