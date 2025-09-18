/* spot_card.vala
 *
 * Copyright 2025 Unknown
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

using WebKit;

private string humanize_ago(GLib.DateTime dt) {
    var now = new GLib.DateTime.now_utc();
    int64 span_us = now.difference(dt);

    if (span_us < 0) {
        return _("in the future");
    }

    int64 sec = span_us / GLib.TimeSpan.SECOND;
    int64 min = span_us / GLib.TimeSpan.MINUTE;

    if (sec < 5)  return _("just now");
    if (sec < 60) return _("%ld seconds ago").printf((long)sec);
    if (min == 1) return _("a minute ago");
    if (min < 60) return _("%ld minutes ago").printf((long)min);
    return _("more than an hour ago");
}

public sealed class AddSpot : Adw.Dialog {
    private Adw.EntryRow activator_callsign;
    private Adw.EntryRow spotter_callsign;
    private Adw.EntryRow frequency;
    private Adw.ComboRow mode;
    private Adw.EntryRow park_ref;
    private Adw.EntryRow rst_sent;
    private Adw.EntryRow rst_received;
    private Adw.EntryRow spotter_comments;

    private Gtk.Button cancel_button;
    private Gtk.Button submit_button;

    public AddSpot() {
        Object();
    }

    public AddSpot.from_spot (Spot spot) {
        Object();

        activator_callsign.text = spot.callsign;
        activator_callsign.editable = false;
        park_ref.text = spot.park_ref;
        park_ref.editable = false;
    }

    construct {
        Gtk.Builder builder = new Gtk.Builder.from_resource("/com/k0vcz/artemis/ui/add_spot_page.ui");

        var content = builder.get_object("add_spot_content") as Gtk.Widget;
        this.set_child(content);

        activator_callsign = builder.get_object("activator_callsign") as Adw.EntryRow;
        spotter_callsign = builder.get_object("spotter_callsign") as Adw.EntryRow;
        frequency = builder.get_object("frequency") as Adw.EntryRow;
        mode = builder.get_object("mode") as Adw.ComboRow;
        park_ref = builder.get_object("park_ref") as Adw.EntryRow;
        rst_sent = builder.get_object("rst_sent") as Adw.EntryRow;
        rst_received = builder.get_object("rst_received") as Adw.EntryRow;
        spotter_comments = builder.get_object("spotter_comments") as Adw.EntryRow;

        var settings = new GLib.Settings ("com.k0vcz.artemis");
        spotter_callsign.text = settings.get_string("callsign");
        spotter_comments.text = settings.get_string("spot-message");

        cancel_button = builder.get_object("cancel_button") as Gtk.Button;
        cancel_button.clicked.connect(() => {
            this.close();
        });

        submit_button = builder.get_object("submit_button") as Gtk.Button;
        submit_button.clicked.connect(() => {
            this.close();
        });
    }
}

[GtkTemplate(ui = "/com/k0vcz/artemis/ui/spot_card.ui")]
public sealed class SpotCard : Gtk.Box {
    [GtkChild]
    public unowned Adw.Avatar activator_avatar;

    [GtkChild]
    public unowned Gtk.Label title;

    [GtkChild]
    public unowned Gtk.Label park_label;

    [GtkChild]
    public unowned Gtk.Image corner_image;

    [GtkChild]
    public unowned Gtk.Label location_desc;

    [GtkChild]
    public unowned Gtk.Label frequency;

    [GtkChild]
    public unowned Gtk.Label mode;

    [GtkChild]
    public unowned Adw.Avatar hunter_avatar;

    [GtkChild]
    public unowned Gtk.Label hunter_callsign;

    [GtkChild]
    public unowned Gtk.Label time;

    [GtkChild]
    public unowned Gtk.Label spots;



    [GtkChild]
    public unowned Gtk.Button history_button;

    [GtkChild]
    public unowned Gtk.Button logbook_button;

    [GtkChild]
    public unowned Gtk.Button park_details_button;

    [GtkChild]
    public unowned Gtk.Button tune_button;

    [GtkChild]
    public unowned Gtk.Button spot_button;

    public string park_url { get; private set; }
    public string callsign { get; private set; }
    public string park_ref { get; private set; } 

    public SpotCard () {
        Object ();
    }

    public SpotCard.from_spot(Spot spot) {
        Object ();

        var escaped_park_ref = GLib.Uri.escape_string (spot.park_ref, null, false);
        park_url = @"http://pota.app/#/park/$escaped_park_ref";
        callsign = spot.callsign;
        park_ref = spot.park_ref;

        title.label = "%s @ %s".printf(spot.callsign, spot.park_ref);
        park_label.label = spot.park_name;
        location_desc.label = spot.location_desc;
        frequency.label = "%d kHz".printf(spot.frequency_khz);
        mode.label = spot.mode;
        hunter_callsign.label = spot.spotter;
        spots.label = "%d".printf(spot.spot_count);

        time.label = humanize_ago(spot.spot_time);
    }

    [GtkCallback]
    private void on_history_button_clicked() {
        var client = new PotaClient ();
        var spot_history = new SpotHistoryDialog(callsign, park_ref);
        
        spot_history.show_loading (true);
        spot_history.present(this.get_root ());
        
        client.fetch_spot_history.begin(callsign, park_ref, (obj, res) => {
            try {
                var history = client.fetch_spot_history.end (res);
                spot_history.show_history (history);
            } catch (Error err) {
                spot_history.show_error(err.message);
            }
        });
    }

    [GtkCallback]
    private void on_park_details_button_clicked() {
        var park_details = new ParkDetailsView(park_url);
        park_details.present(this.get_root ());
    }

    [GtkCallback]
    private void on_tune_button_clicked() {
        print("Tune button clicked\n");
    }

    [GtkCallback]
    private void on_spot_button_clicked() {
        print("Spot button clicked\n");
    }
}

private Gtk.Widget create_spot_row (Json.Object spot_obj) {
    string spotter    = spot_obj.get_string_member_with_default ("spotter", "");
    string frequency  = spot_obj.get_string_member_with_default ("frequency", "");
    string mode       = spot_obj.get_string_member_with_default ("mode", "");
    string spot_time  = spot_obj.get_string_member_with_default ("spotTime", "");
    string comments   = spot_obj.get_string_member_with_default ("comments", "");

    var dt = new DateTime.from_iso8601 (spot_time, new GLib.TimeZone.utc ());
    string spot_dt = dt != null ? dt.format ("%x %X UTC") : spot_time;

    // Main row
    var row = new Gtk.ListBoxRow () {
        margin_top = 6,
        margin_bottom = 6,
        margin_start = 6,
        margin_end = 6
    };
    row.add_css_class ("card");

    // Main content box
    var main_box = new Gtk.Box (Gtk.Orientation.VERTICAL, 8) {
        margin_top = 12,
        margin_bottom = 12,
        margin_start = 12,
        margin_end = 12
    };
    row.set_child (main_box);

    if (comments != null && comments.strip () != "") {
        var comment_label = new Gtk.Label (comments) { 
            xalign = 0,
            wrap = true,
            wrap_mode = Pango.WrapMode.WORD_CHAR,
            margin_top = 4
        };
        comment_label.add_css_class ("title-4");
        main_box.append (comment_label);
    }
    var header_box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 12);
    main_box.append (header_box);

    var spotter_label = new Gtk.Label (spotter) { xalign = 0 };
    header_box.append (spotter_label);

    var freq_label = new Gtk.Label (@"$frequency kHz $mode") { xalign = 0, hexpand = true };
    header_box.append (freq_label);

    var time_label = new Gtk.Label (spot_dt) { xalign = 1 };
    header_box.append (time_label);

    return row;
}

[GtkTemplate(ui = "/com/k0vcz/artemis/ui/spot_history_dialog.ui")]
public class SpotHistoryDialog : Adw.Dialog {
    [GtkChild]
    public unowned Adw.WindowTitle title_widget;
    [GtkChild]
    public unowned Adw.StatusPage loading_page;
    [GtkChild]
    public unowned Gtk.ScrolledWindow history_scroll;
    [GtkChild]
    public unowned Gtk.ListBox history_list;
    [GtkChild]
    public unowned Adw.StatusPage error_page;

    public SpotHistoryDialog (string callsign, string park_ref) {
        Object ();
        title_widget.title = @"$callsign @ $park_ref";
    }

    public void show_loading (bool loading) {
        loading_page.visible = true;
        history_scroll.visible = false;
        error_page.visible = false;
    }

    public void show_error (string? message) {
        if (message != null) {
            error_page.description = message;
        }
        loading_page.visible = false;
        history_scroll.visible = false;
        error_page.visible = true;
    }

    public void show_history (Json.Node history_data) {
        history_list.remove_all ();

        if (history_data.get_node_type() != Json.NodeType.ARRAY) {
            show_error (_("Invalid response format from POTA API"));
            return;
        }

        var spots_array = history_data.get_array ();
        if (spots_array.get_length () == 0) {
            show_error (_("No spot history found"));
            return;
        }

        for (uint i = 0; i < spots_array.get_length (); i++) {
            var spot_obj = spots_array.get_object_element (i);
            if (spot_obj != null) {
                var row = create_spot_row (spot_obj);
                history_list.append (row);
            }
        }

        loading_page.visible = false;
        history_scroll.visible = true;
        error_page.visible = false;
    }
}

public class ParkDetailsView : Adw.Dialog {
    private WebKit.WebView webview;
    private Adw.WindowTitle title_widget;

    public ParkDetailsView (string url) {
        Object (
            content_width: 800,
            content_height: 600
        );

        var toolbar_view = new Adw.ToolbarView ();


        var headerbar = new Adw.HeaderBar ();
        title_widget = new Adw.WindowTitle (_("Park Details"), "");
        headerbar.set_title_widget (title_widget);

        toolbar_view.add_top_bar (headerbar);

        var scrolled = new Gtk.ScrolledWindow () {
            hexpand = true,
            vexpand = true
        };

        webview = new WebKit.WebView ();
        webview.load_uri (url);

        scrolled.set_child (webview);
        toolbar_view.set_content (scrolled);

        // Set main child
        this.set_child (toolbar_view);
    }
}
