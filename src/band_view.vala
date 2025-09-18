public bool contains_text_case_insensitive(string? haystack, string? needle) {
    if (haystack == null || needle == null || needle.length == 0)
        return true;
    if (haystack.length == 0)
        return false;

    return haystack.ascii_down().contains(needle.ascii_down());
}

private SpotCard create_spot_card(Spot spot) {
  return new SpotCard.from_spot(spot);
}

[GtkTemplate(ui = "/com/k0vcz/artemis/ui/band_view.ui")]
public sealed class BandView : Gtk.Box {
  public string band_label { get; construct; }
  public string icon_name { get; construct; }

  [GtkChild]
  public unowned Gtk.FlowBox band_spot_cards;

  private Gtk.Filter filter;
  private Gtk.FilterListModel filtered;
  private Gtk.SortListModel sorted;

  private string? current_search_text;
  private string? current_mode_filter;

  private StatusPage status_page;

  public SpotRepo spot_repo { get; construct; }

  public BandView (SpotRepo repo, string band_label, string icon) {
    Object (
      spot_repo: repo,
      band_label: band_label,
      icon_name: icon
    );
  }

  construct {
    filter = new Gtk.CustomFilter ((item) => {
      return true;
    });
    filtered = new Gtk.FilterListModel(spot_repo.get_model (), filter);
    var sorter = new Gtk.CustomSorter ((spotA, spotB) => {
      return 0;
    });
    sorted = new Gtk.SortListModel (filtered, sorter);
    
    status_page = new StatusPage (icon_name, band_label, _("There are no spots currently on %s.").printf(band_label));
    status_page.visible = false;

    this.append (status_page);

    band_spot_cards.bind_model(
      sorted,
      (Gtk.FlowBoxCreateWidgetFunc)create_spot_card
    );

    sorted.items_changed.connect( (position, removed, added) => {
      var items = sorted.get_n_items ();
      debug("Band %s: items_changed - position: %u, removed: %u, added: %u, total items: %u", band_label, position, removed, added, items);
      band_spot_cards.visible = (items > 0);
      status_page.visible = (items == 0);
    });

    spot_repo.get_model().items_changed.connect( (position, removed, added) => {
      var items = spot_repo.get_model().get_n_items();
      debug("SpotRepo model for band %s: items_changed - position: %u, removed: %u, added: %u, total items: %u", band_label, position, removed, added, items);
    });
  }
}