public bool contains_text_case_insensitive (string? haystack, string? needle)
{
    if ((haystack == null) || (needle == null) || (needle.length == 0))
        return true;
    if (haystack.length == 0)
        return false;

    return haystack.ascii_down ().contains (needle.ascii_down ());
}

private SpotCard create_spot_card (Spot spot)
{
    return new SpotCard.from_spot (spot);
}

[GtkTemplate (ui = "/com/k0vcz/artemis/ui/band_view.ui")]
public sealed class BandView : Gtk.Box {
    public string band_label { get; construct; }
    public string icon_name { get; construct; }
    [GtkChild]
    public unowned Gtk.FlowBox band_spot_cards;

    public unowned Adw.ViewStackPage? page;

    private Gtk.Filter filter;
    private Gtk.CustomSorter sorter;
    private Gtk.FilterListModel filtered;
    private Gtk.SortListModel sorted;

    private bool just_selected = false;

    private StatusPage status_page;

    public SpotRepo spot_repo { get; construct; }
    public BandView (SpotRepo repo, string band_label, string icon)
    {
        Object (
            spot_repo: repo,
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

            if ((band_label != "All") && (spot.band != band_label) )
                return false;

            if (settings.get_boolean ("hide-qrt") &&
                spot.activator_comment.down ().contains ("qrt"))
                return false;

            if (settings.get_boolean ("hide-hunted") && spot.was_hunted_today)
                return false;

            var stale_minutes = settings.get_int ("hide-older-than");
            var now = new DateTime.now_utc ();
            var expires = spot.spot_time.add_minutes (stale_minutes);
            if (now.compare (expires) > 0)
                return false;

            if ((Application.current_program_filter != null) && (Application.
                                                                 current_program_filter
                                                                 != _
                                                                     ("All")) &&
                !spot.park_ref.down ().has_prefix (Application.
                    current_program_filter.down
                        ()))
                return false;

            if ((Application.current_mode_filter != null) && (Application.
                                                              current_mode_filter
                                                              != _ (
                                                                  "All")) &&
                !spot.mode.down ().contains (Application.current_mode_filter.
                    down ()))
                return false;

            if (Application.current_search_text != null)
            {
                var needle = Application.current_search_text.down ();
                if (!(spot.callsign.down ().contains (needle) ||
                      spot.park_ref.down ().contains (needle) ||
                      spot.park_name.down ().contains (needle)))
                    return false;
            }

            return true;
        });

        filtered = new Gtk.FilterListModel (Application.spot_repo.store,
            filter);

        sorter = new Gtk.CustomSorter ((itemA, itemB) => {
            var spotA = itemA as Spot;
            var spotB = itemB as Spot;

            if ((spotA == null) || (spotB == null) )
                return Gtk.Ordering.EQUAL;

            var current_hash = Application.current_spot_hash;
            if ((spotA.hash == current_hash) && (spotB.hash != current_hash))
                return Gtk.Ordering.SMALLER;
            if ((spotB.hash == current_hash) && (spotA.hash != current_hash))
                return Gtk.Ordering.LARGER;

            int cmp = spotA.spot_time.compare (spotB.spot_time);
            if (cmp > 0)
                return Gtk.Ordering.SMALLER;
            else if (cmp < 0)
                return Gtk.Ordering.LARGER;
            else
                return Gtk.Ordering.EQUAL;
        });
        sorted = new Gtk.SortListModel (filtered, sorter);

        status_page = new StatusPage (icon_name, band_label, _ (
            "There are no spots currently on %s.").printf (band_label));
        status_page.visible = false;

        this.append (status_page);

        band_spot_cards.bind_model (
            sorted,
            (Gtk.FlowBoxCreateWidgetFunc)create_spot_card
            );
        band_spot_cards.child_activated.connect ( (child) => {
            var spot_card = child.get_child () as SpotCard;
            if ((spot_card != null) &&
                !just_selected &&
                (spot_card.spot.hash == Application.current_spot_hash))
            {
                Application.current_spot_hash = 0;
                band_spot_cards.unselect_all ();
            }
            if (just_selected)
            {
                Idle.add ( () => {
                    just_selected = false;
                    return Source.REMOVE;
                });
            }
        });
        band_spot_cards.selected_children_changed.connect (() => {
            var selected = band_spot_cards.get_selected_children ();
            if ((selected != null) && (selected.length () > 0))
            {
                var child = selected.nth_data (0) as Gtk.FlowBoxChild;
                var spot_card = child.get_child () as SpotCard;
                if (spot_card != null)
                {
                    var spot_hash = spot_card.spot.hash;
                    if (spot_hash != Application.current_spot_hash)
                    {
                        Application.current_spot_hash = spot_hash;
                        just_selected = true;
                    }
                }
            }
        });

        sorted.items_changed.connect ( (position, removed, added) => {
            var items = sorted.get_n_items ();
            band_spot_cards.visible = (items > 0);
            status_page.visible = (items == 0);

            if (page != null)
                page.badge_number = sorted.get_n_items ();
        });

        var items = sorted.get_n_items ();
        band_spot_cards.visible = (items > 0);
        status_page.visible = (items == 0);

        if (page != null)
            page.badge_number = sorted.get_n_items ();

        Application.map_window.notify["map_window"].connect (() => {
        });

        settings.changed["hide-qrt"].connect (bounce_filter);
        settings.changed["hide-hunted"].connect (bounce_filter);
        settings.changed["hide-older-than"].connect (bounce_filter);
        settings.changed["use-metric"].connect (_refresh_cards);
        settings.changed["highlight-unhunted-parks"].connect (_refresh_cards);
    }

    public void set_current_spot (Quark spot_hash)
    {
        Gtk.FlowBoxChild? selected_child = null;
        for (var child = band_spot_cards.get_first_child (); child != null;
             child = child.get_next_sibling ())
        {
            var fbchild = child as Gtk.FlowBoxChild;
            if (fbchild == null) continue;

            var spot_card = fbchild.get_child () as SpotCard;
            if ((spot_card != null) && (spot_card.spot.hash == spot_hash))
            {
                selected_child = fbchild;
                break;
            }
        }

        sorter.changed (Gtk.SorterChange.DIFFERENT);

        Idle.add ( () => {
            if (selected_child != null)
                band_spot_cards.select_child (selected_child);

            return Source.REMOVE;
        });
    }

    private void _refresh_cards ()
    {
        for (var child = band_spot_cards.get_first_child (); child != null;
             child = child.get_next_sibling ())
        {
            var fbchild = child as Gtk.FlowBoxChild;
            if (fbchild == null) continue;

            var spot_card = fbchild.get_child () as SpotCard;
            if (spot_card != null)
                spot_card.refresh_highlight ();
        }
    }

    public uint get_n_items ()
    {
        return sorted.get_n_items ();
    }

    public void bounce_filter (string? key = null)
    {
        filter.changed (Gtk.FilterChange.DIFFERENT);
    }
} /* class BandView */
