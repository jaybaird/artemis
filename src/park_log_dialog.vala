/* src/park_log_dialog.vala
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

[GtkTemplate (ui = "/com/k0vcz/artemis/ui/park_log_dialog.ui")]
public class ParkLogDialog : Adw.Dialog {
    [GtkChild]
    public unowned Adw.WindowTitle title_widget;
    [GtkChild]
    public unowned Gtk.ScrolledWindow qso_scroll;
    [GtkChild]
    public unowned Gtk.ListBox qso_list;

    public string park_ref { get; construct; }

    public ParkLogDialog (Spot spot) {
        Object (
            park_ref: spot.park_ref
        );
        title_widget.title = "%s %s".printf (_("Park Logbook"), spot.park_ref);
    }

    construct {
        Error? error = null;
        var all_qsos = Application.spot_database.all_qsos_for_park (park_ref, out error);
        if (error != null) {
            qso_list.append (create_qso_message_row (error.message));
            qso_scroll.visible = true;
            return;
        }

        if (all_qsos == null || all_qsos.size == 0) {
            qso_list.append (create_qso_message_row (_("No QSOs logged for this park yet.")));
            qso_scroll.visible = true;
            return;
        }

        foreach (var qso in all_qsos)
            qso_list.append (create_qso_row (qso));

        qso_scroll.visible = true;
    }

    private Gtk.Widget create_qso_message_row (string message) {
        var row = new Gtk.ListBoxRow ();
        row.set_child (new Gtk.Label (message) {
            margin_top = 12,
            margin_bottom = 12,
            margin_start = 12,
            margin_end = 12,
            wrap = true,
            xalign = 0
        });
        return row;
    }

    private Gtk.Widget create_qso_row (QsoRow qso) {
        var row = new Gtk.ListBoxRow ();
        var box = new Gtk.Box (Gtk.Orientation.VERTICAL, 4) {
            margin_top = 10,
            margin_bottom = 10,
            margin_start = 12,
            margin_end = 12
        };

        var title = new Gtk.Label ("%s  %s  %s kHz".printf (
            qso.callsign ?? _("Unknown"),
            qso.mode ?? "",
            format_frequency_khz (qso.frequency_khz)
        )) {
            xalign = 0
        };
        title.add_css_class ("heading");
        box.append (title);

        var detail = new Gtk.Label ("%s  %s".printf (
            qso.created_utc ?? "",
            qso.spotter ?? ""
        )) {
            xalign = 0
        };
        detail.add_css_class ("caption");
        detail.add_css_class ("dim-label");
        box.append (detail);

        if ((qso.spotter_comment ?? "").strip () != "") {
            box.append (new Gtk.Label (qso.spotter_comment) {
                xalign = 0,
                wrap = true
            });
        }

        row.set_child (box);
        return row;
    }
}
