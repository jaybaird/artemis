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

    private Gtk.Filter filter;
    private Gtk.FilterListModel filtered;
    private Gtk.SortListModel sorted;

    private string? _current_program_filter = null;
    public string? current_program_filter {
        get {
            return _current_program_filter;
        } set {
            if (_current_program_filter == value) return;
            _current_program_filter = value;
            _bounce_filter ();
        }
    }
    private string? _current_search_text = null;
    public string? current_search_text {
        get {
            return _current_search_text;
        } set {
            if (_current_search_text == value)
                return;
            _current_search_text = value;
            _bounce_filter ();
        }
    }
    private string? _current_mode_filter = null;
    public string? current_mode_filter {
        get {
            return _current_mode_filter;
        } set {
            if (_current_mode_filter == value)
                return;
            _current_mode_filter = value;
            _bounce_filter ();
        }
    }
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

            if ((current_program_filter != null) && (current_program_filter != _
                                                         ("All")) &&
                !spot.park_ref.down ().has_prefix (current_program_filter.down
                        ()))
                return false;

            if ((current_mode_filter != null) && (current_mode_filter != _ (
                "All")) &&
                !spot.mode.down ().contains (current_mode_filter.down ()))
                return false;

            if (current_search_text != null)
            {
                var needle = current_search_text.down ();
                if (!(spot.callsign.down ().contains (needle) ||
                      spot.park_ref.down ().contains (needle) ||
                      spot.park_name.down ().contains (needle)))
                    return false;
            }

            return true;
        });

        filtered = new Gtk.FilterListModel (Application.spot_repo.store,
            filter);
        var sorter = new Gtk.CustomSorter ((itemA, itemB) => {
            var spotA = itemA as Spot;
            var spotB = itemB as Spot;

            if ((spotA == null) || (spotB == null) )
                return Gtk.Ordering.EQUAL;

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

        sorted.items_changed.connect ( (position, removed, added) => {
            var items = sorted.get_n_items ();
            band_spot_cards.visible = (items > 0);
            status_page.visible = (items == 0);
        });

        var items = sorted.get_n_items ();
        band_spot_cards.visible = (items > 0);
        status_page.visible = (items == 0);

        Application.map_window.notify["map_window"].connect (() => {
        });

        settings.changed["hide-qrt"].connect (_bounce_filter);
        settings.changed["hide-hunted"].connect (_bounce_filter);
        settings.changed["hide-older-than"].connect (_bounce_filter);
        settings.changed["use-metric"].connect (_refresh_cards);
        settings.changed["highlight-unhunted-parks"].connect (_refresh_cards);
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

    private void _bounce_filter (string? key = null)
    {
        filter.changed (Gtk.FilterChange.DIFFERENT);
    }
} /* class BandView */
