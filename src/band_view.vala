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
    private uint sync_selection_idle_id = 0;
    private Quark pending_selection_hash = BLANK_HASH;

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

            var band_filter = Application.state.current_band_filter ?? "All";
            return spot_matches_current_filters (spot, band_filter);
        });

        filtered = new Gtk.FilterListModel (Application.spot_repo.store, filter);

        sorter = new Gtk.CustomSorter ((item_a, item_b) => {
            var spot_a = item_a as Spot;
            var spot_b = item_b as Spot;

            if ((spot_a == null) || (spot_b == null))
                return Gtk.Ordering.EQUAL;

            int cmp = spot_a.spot_time.compare (spot_b.spot_time);
            if (cmp > 0)
                return Gtk.Ordering.SMALLER;
            else if (cmp < 0)
                return Gtk.Ordering.LARGER;
            else
                return Gtk.Ordering.EQUAL;
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
                Application.state.current_spot_hash = BLANK_HASH;
                band_spot_cards.unselect_all ();
            }
            if (just_selected) {
                Idle.add (() => {
                    just_selected = false;
                    return Source.REMOVE;
                });
            }
        });
        band_spot_cards.selected_children_changed.connect (() => {
            for (var child = band_spot_cards.get_first_child ();
                     child != null;
                     child = child.get_next_sibling ()) {
                var flow_child = child as Gtk.FlowBoxChild;
                if (flow_child == null)
                    continue;

                var spot_card = flow_child.get_child () as SpotCard;
                spot_card.selected = false;
            }

            var selected = band_spot_cards.get_selected_children ();
            if ((selected != null) && (selected.length () > 0)) {
                var child = selected.nth_data (0) as Gtk.FlowBoxChild;
                var spot_card = child.get_child () as SpotCard;
                if (spot_card != null) {
                    var spot_hash = spot_card.spot.hash;
                    if (spot_hash != Application.state.current_spot_hash) {
                        Application.state.current_spot_hash = spot_hash;
                        just_selected = true;
                        spot_card.selected = true;
                    }
                }
            }
        });

        sorted.items_changed.connect ((position, removed, added) => {
            update_visible_state ();
            count_changed (sorted.get_n_items ());
        });

        update_visible_state ();

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
                band_spot_cards.unselect_all ();
                return Source.REMOVE;
            }

            for (var child = band_spot_cards.get_first_child () ; child != null
                 ;
                 child = child.get_next_sibling ()) {
                var fbchild = child as Gtk.FlowBoxChild;
                if (fbchild == null)
                    continue;

                var spot_card = fbchild.get_child () as SpotCard;
                if ((spot_card != null) && (spot_card.spot.hash == current_hash)) {
                    band_spot_cards.select_child (fbchild);
                    Idle.add (() => {
                        scroll_to_child (fbchild);
                        return Source.REMOVE;
                    });
                    return Source.REMOVE;
                }
            }

            band_spot_cards.unselect_all ();
            return Source.REMOVE;
        });
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

    public uint get_n_items () {
        return sorted.get_n_items ();
    }

    public void set_band_filter (string band) {
        band_label = band;
        icon_name = @"band-$band";
        bounce_filter ();
        update_visible_state ();
    }

    public void bounce_filter (string? key = null) {
        filter.changed (Gtk.FilterChange.DIFFERENT);
    }

    private void update_visible_state () {
        var items = sorted.get_n_items ();
        var band = Application.state.current_band_filter ?? "All";
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
} /* class BandView */
