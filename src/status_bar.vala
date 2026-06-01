/* src/status_bar.vala
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

[GtkTemplate (ui = "/com/k0vcz/artemis/ui/status_bar.ui")]
public sealed class StatusBar : Gtk.Box {
    [GtkChild]
    private unowned Gtk.Label status_bar_text;

    [GtkChild]
    private unowned Gtk.Label refresh_status;

    [GtkChild]
    private unowned Gtk.Label current_time;

    [GtkChild]
    private unowned Adw.SplitButton notification_button;

    [GtkChild]
    private unowned Gtk.Button clear_notifications_button;

    [GtkChild]
    private unowned Gtk.Label notification_empty_label;

    [GtkChild]
    private unowned Gtk.ListBox notification_list;

    public StatusBar () {
        Object ();
    }

    construct {
        notification_button.clicked.connect (() => {
            notification_button.popup ();
        });
        clear_notifications_button.clicked.connect (() => {
            if (Application.app != null)
                Application.app.clear_notification_history ();
        });

        if (Application.app != null) {
            Application.app.notification_history_changed.connect (
                rebuild_notification_history
            );
        }
        rebuild_notification_history ();
    }

    public void set_time (string time) {
        current_time.label = time;
    }

    public void set_filtered_text (uint filtered_count, uint total_visible) {
        var spots_text = ngettext (
            "%u spot",
            "%u spots",
            total_visible
        ).printf (total_visible);

        status_bar_text.label = "%s • %u filtered".printf (spots_text, filtered_count);
    }

    public void set_refresh_countdown (uint seconds_remaining) {
        if (seconds_remaining > 60) {
            var time_str = new DateTime.now_utc ().add_seconds ((double)seconds_remaining).format ("%R");
            refresh_status.label = _("Refreshes at %s").printf (time_str);
            return;
        }

        refresh_status.label = _("Refreshes in %us").printf (seconds_remaining);
    }

    public void set_paused (bool paused) {
        if (paused) {
            refresh_status.label = _("Paused");
        }
    }

    private void rebuild_notification_history () {
        while (notification_list.get_first_child () != null)
            notification_list.remove (notification_list.get_first_child ());

        if (Application.app == null) {
            notification_empty_label.visible = true;
            notification_list.visible = false;
            return;
        }

        var history = Application.app.get_notification_history ();
        var count = history.get_n_items ();
        notification_empty_label.visible = count == 0;
        notification_list.visible = count > 0;

        for (int i = (int) count - 1; i >= 0; i--) {
            var notification = history.get_item ((uint) i) as AppNotification;
            if (notification == null)
                continue;

            notification_list.append (notification_row (notification));
        }
    }

    private Gtk.Widget notification_row (AppNotification notification) {
        var row = new Gtk.ListBoxRow ();
        var box = new Gtk.Box (Gtk.Orientation.VERTICAL, 2) {
            margin_top = 8,
            margin_bottom = 8,
            margin_start = 10,
            margin_end = 10
        };

        var time_label = new Gtk.Label (notification.timestamp.format ("%R")) {
            xalign = 0.0f
        };
        time_label.add_css_class ("caption");
        time_label.add_css_class ("numeric");
        time_label.add_css_class ("dim-label");

        var message_label = new Gtk.Label (notification.message) {
            xalign = 0.0f,
            wrap = true,
            wrap_mode = Pango.WrapMode.WORD_CHAR
        };

        box.append (time_label);
        box.append (message_label);
        row.child = box;
        return row;
    }

}
