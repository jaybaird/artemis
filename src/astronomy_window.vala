/* src/astronomy_window.vala
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

[GtkTemplate (ui = "/com/k0vcz/artemis/ui/astronomy_window.ui")]
public sealed class AstronomyWindow : Adw.Window {
    private const string HAMQSL_OVERVIEW_URL = "https://www.hamqsl.com/solar101vhfpic.php";

    [GtkChild]
    private unowned Gtk.Label updated_label;

    [GtkChild]
    private unowned Gtk.Label error_label;

    [GtkChild]
    private unowned Gtk.Picture propagation_picture;

    [GtkChild]
    private unowned Gtk.ListBox alerts_list;

    private Soup.Session image_session;

    public AstronomyWindow (Gtk.Application app) {
        Object (application: app);
    }

    construct {
        image_session = new Soup.Session ();
        image_session.timeout = 30;
        image_session.user_agent = "Artemis/%s".printf (Build.VERSION);

        Application.solar_conditions.updated.connect (render_state);

        refresh_picture.begin (
            propagation_picture,
            HAMQSL_OVERVIEW_URL,
            _("Unable to load the HamQSL propagation image")
        );
        render_state ();
    }

    private async void refresh_picture (
        Gtk.Picture picture,
        string url,
        string failure_message
    ) {
        try {
            var message = new Soup.Message ("GET", url);
            var bytes = yield image_session.send_and_read_async (
                message,
                GLib.Priority.DEFAULT,
                null
            );

            if (message.status_code != Soup.Status.OK) {
                throw new IOError.FAILED (
                    "%s: %u %s".printf (
                        failure_message,
                        message.status_code,
                        message.reason_phrase
                    )
                );
            }

            picture.paintable = yield load_texture_from_bytes (bytes);
        } catch (Error e) {
            warning ("%s: %s", failure_message, e.message);
        }
    }

    private void render_state () {
        var model = Application.solar_conditions.model;

        if (model.last_updated != null) {
            updated_label.label = @"Last updated: $(model.last_updated.to_local ().format ("%Y-%m-%d %H:%M %Z"))";
        } else if (model.refreshing) {
            updated_label.label = _("Loading solar conditions…");
        } else {
            updated_label.label = _("No solar data loaded yet");
        }

        error_label.visible = (model.error_message ?? "").strip () != "";
        error_label.label = error_label.visible ? model.error_message : "";

        rebuild_alerts_list (model);
    }

    private void clear_list_box (Gtk.ListBox list) {
        Gtk.Widget? child = list.get_first_child ();
        while (child != null) {
            var next = child.get_next_sibling ();
            list.remove (child);
            child = next;
        }
    }

    private void rebuild_alerts_list (SolarConditionsModel model) {
        clear_list_box (alerts_list);

        if (model.alerts.size == 0) {
            alerts_list.append (detail_row (_("Notices"), _("No NOAA alerts in the last 24 hours")));
            return;
        }

        foreach (var alert in model.alerts) {
            var row = new DetailFieldRow (alert.issue_time_text, true);
            row.value = alert.summary;
            alerts_list.append (row);
        }
    }

    private DetailFieldRow detail_row (string title, string value) {
        var row = new DetailFieldRow (title, true);
        row.value = value;
        return row;
    }
}
