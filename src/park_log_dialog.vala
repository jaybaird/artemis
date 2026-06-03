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

[GtkTemplate (ui = "/com/k0vcz/artemis/ui/park_log_message_row.ui")]
private sealed class ParkLogMessageRow : Gtk.ListBoxRow {
    [GtkChild]
    private unowned Gtk.Label message_label;

    public ParkLogMessageRow (string message) {
        Object ();
        message_label.label = message;
    }
}

[GtkTemplate (ui = "/com/k0vcz/artemis/ui/park_log_qso_row.ui")]
private sealed class ParkLogQsoRow : Gtk.ListBoxRow {
    [GtkChild]
    private unowned Gtk.Label title_label;
    [GtkChild]
    private unowned Gtk.Label detail_label;
    [GtkChild]
    private unowned Gtk.Label comment_label;

    public ParkLogQsoRow (QsoRow qso) {
        Object ();

        title_label.label = "%s  %s  %s kHz".printf (
            qso.callsign ?? _("Unknown"),
            qso.mode ?? "",
            format_frequency_khz (qso.frequency_khz)
        );

        detail_label.label = "%s  %s".printf (
            qso.created_utc ?? "",
            qso.spotter ?? ""
        );

        comment_label.visible = (qso.spotter_comment ?? "").strip () != "";
        comment_label.label = qso.spotter_comment ?? "";
    }
}

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
            qso_list.append (new ParkLogMessageRow (error.message));
            qso_scroll.visible = true;
            return;
        }

        if (all_qsos == null || all_qsos.size == 0) {
            qso_list.append (new ParkLogMessageRow (_("No QSOs logged for this park yet.")));
            qso_scroll.visible = true;
            return;
        }

        foreach (var qso in all_qsos)
            qso_list.append (new ParkLogQsoRow (qso));

        qso_scroll.visible = true;
    }
}
