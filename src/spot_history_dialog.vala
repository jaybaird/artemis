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

[GtkTemplate (ui = "/com/k0vcz/artemis/ui/spot_history_row.ui")]
private sealed class SpotHistoryRow : Gtk.ListBoxRow {
    [GtkChild]
    private unowned Gtk.Label comment_label;
    [GtkChild]
    private unowned Gtk.Label spotter_label;
    [GtkChild]
    private unowned Gtk.Label frequency_label;
    [GtkChild]
    private unowned Gtk.Label time_label;

    public SpotHistoryRow (Json.Object spot_obj) {
        Object ();

        string spotter = spot_obj.get_string_member_with_default ("spotter", "");
        string frequency = spot_obj.get_string_member_with_default ("frequency", "");
        string mode = spot_obj.get_string_member_with_default ("mode", "");
        string spot_time = spot_obj.get_string_member_with_default ("spotTime", "");
        string comments = spot_obj.get_string_member_with_default ("comments", "");

        var dt = new DateTime.from_iso8601 (spot_time, new GLib.TimeZone.utc ());
        string spot_dt = dt != null ? dt.format ("%x %X UTC") : spot_time;

        comment_label.visible = comments.strip () != "";
        comment_label.label = comments;
        spotter_label.label = spotter;
        frequency_label.label = @"$frequency kHz $mode";
        time_label.label = spot_dt;
    }
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
                history_list.append (new SpotHistoryRow (spot_obj));
            }
        }

        loading_page.visible = false;
        history_scroll.visible = true;
        error_page.visible = false;
    }
}
