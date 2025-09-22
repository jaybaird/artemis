[GtkTemplate(ui = "/com/k0vcz/artemis/ui/status_page.ui")]
public sealed class StatusPage : Gtk.Box {
    public string icon_name { get; construct; }
    public string title { get; construct; }
    public string description { get; construct; }
    [GtkChild]
    public unowned Gtk.Image status_icon;
    [GtkChild]
    public unowned Gtk.Label status_title;
    [GtkChild]
    public unowned Gtk.Label status_body;

    public StatusPage (string icon_name, string title, string description)
    {
        Object(
            icon_name: icon_name,
            title: title,
            description: description
            );
    }

    construct {
        status_title.label = title;
        status_body.label = description;
        status_icon.set_from_icon_name(icon_name);
    }
} /* class StatusPage */
