/* src/spot_history_dialog.vala
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

private Gtk.Widget create_spot_row (Json.Object spot_obj) {
    string spotter = spot_obj.get_string_member_with_default ("spotter", "");
    string frequency = spot_obj.get_string_member_with_default ("frequency", "");
    string mode = spot_obj.get_string_member_with_default ("mode", "");
    string spot_time = spot_obj.get_string_member_with_default ("spotTime", "");
    string comments = spot_obj.get_string_member_with_default ("comments", "");

    var dt = new DateTime.from_iso8601 (spot_time, new GLib.TimeZone.utc ());
    string spot_dt = dt != null ? dt.format ("%x %X UTC") : spot_time;

    var row = new Gtk.ListBoxRow () {
        margin_top = 6,
        margin_bottom = 6,
        margin_start = 6,
        margin_end = 6
    };
    row.add_css_class ("card");

    var main_box = new Gtk.Box (Gtk.Orientation.VERTICAL, 8) {
        margin_top = 12,
        margin_bottom = 12,
        margin_start = 12,
        margin_end = 12
    };
    row.set_child (main_box);

    if ((comments != null) && (comments.strip () != "")) {
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

    var spotter_label = new Gtk.Label (spotter) {
        xalign = 0
    };
    header_box.append (spotter_label);

    var freq_label = new Gtk.Label (@"$frequency kHz $mode") {
        xalign = 0,
        hexpand = true
    };
    header_box.append (freq_label);

    var time_label = new Gtk.Label (spot_dt) {
        xalign = 1
    };
    header_box.append (time_label);

    return row;
}

[GtkTemplate (ui = "/com/k0vcz/artemis/ui/spot_history_dialog.ui")]
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
        if (message != null)
            error_page.description = message;
        loading_page.visible = false;
        history_scroll.visible = false;
        error_page.visible = true;
    }

    public void show_history (Json.Node history_data) {
        history_list.remove_all ();

        if (history_data.get_node_type () != Json.NodeType.ARRAY) {
            show_error (_("Invalid response format from POTA API"));
            return;
        }

        var spots_array = history_data.get_array ();
        if (spots_array.get_length () == 0) {
            show_error (_("No spot history found"));
            return;
        }

        for (uint i = 0 ; i < spots_array.get_length () ; i++) {
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
