/* src/add_spot.vala
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

[GtkTemplate (ui = "/com/k0vcz/artemis/ui/add_spot_page.ui")]
public sealed class AddSpot : Adw.Dialog {
    [GtkChild] private unowned Adw.EntryRow activator_callsign;
    [GtkChild] private unowned Adw.EntryRow spotter_callsign;
    [GtkChild] private unowned Adw.EntryRow frequency;
    [GtkChild] private unowned Adw.ComboRow mode;
    [GtkChild] private unowned Adw.EntryRow park_ref;
    [GtkChild] private unowned Adw.ActionRow park_details_row;
    [GtkChild] private unowned Adw.EntryRow rst_sent;
    [GtkChild] private unowned Adw.EntryRow rst_received;
    [GtkChild] private unowned Adw.EntryRow spotter_comments;

    [GtkChild] private unowned Gtk.Button cancel_button;
    [GtkChild] private unowned Gtk.Button lookup_park_button;
    [GtkChild] private unowned Gtk.Button submit_button;

    public signal void qso_changed ();

    private bool park_lookup_in_progress = false;

    public AddSpot () {
        Object ();
    }

    public AddSpot.from_spot (Spot spot) {
        Object ();

        activator_callsign.text = spot.callsign;
        activator_callsign.editable = false;
        park_ref.text = spot.park_ref;
        park_ref.editable = false;
        Application.park_details_cache.seed (
            spot.park_ref,
            spot.park_name,
            spot.location_desc
        );
        set_park_details (spot.park_name);
        frequency.text = format_frequency_khz (spot.frequency_khz);
        select_mode (spot.mode);
        if ((spot.spotter_comment ?? "").strip () != "")
            spotter_comments.text = spot.spotter_comment;
    }

    public AddSpot.with_frequency (double frequency_khz) {
        Object ();

        frequency.text = format_frequency_khz (frequency_khz);
    }

    construct {
        var settings = Application.settings;
        spotter_callsign.text = settings.get_string ("callsign");
        spotter_comments.text = settings.get_string ("spot-message");
        select_mode (settings.get_string ("default-mode"));

        cancel_button.clicked.connect (() => {
            this.close ();
        });

        lookup_park_button.clicked.connect (() => lookup_park_details ());

        park_ref.changed.connect (() => {
            var cached_details = Application.park_details_cache.peek (park_ref.text);
            set_park_details (cached_details != null ? cached_details.name : null);
        });

        submit_button.clicked.connect (() => {
            submit_button.sensitive = false;

            var spot = build_spot (new DateTime.now_utc ());
            Application.logging_service.submit_spot_qso.begin (spot, true, (obj, res) => {
                try {
                    var result = Application.logging_service.submit_spot_qso.end (res);
                    this.close ();
                    qso_changed ();
                    Application.show_toast (_("QSO saved"));
                    if (result.pota_posted)
                        Application.show_toast (_("Spot posted"));
                    else if (result.pota_error != null)
                        Application.show_toast (_("QSO saved locally; POTA spot failed"));

                    if (result.qrz_uploaded)
                        Application.show_toast (_("Uploaded QSO to QRZ"));
                    else if (result.qrz_error != null)
                        present_qrz_error (result.qrz_error);
                } catch (Error err) {
                    submit_button.sensitive = true;
                    warning ("Unable to log QSO: %s", err.message);
                    present_logging_error (err.message);
                }
            });
        });
    }

    private void present_qrz_error (string message) {
        var alert = new Adw.AlertDialog (_("Unable to Upload to QRZ"), null);
        alert.format_body (_("The spot was submitted, but QRZ logging failed: %s"),
            message);
        alert.add_response ("ok", _("OK"));
        alert.set_default_response ("ok");
        alert.set_close_response ("ok");
        alert.present (Application.win);
    }

    private void present_logging_error (string message) {
        var alert = new Adw.AlertDialog (_("Unable to Log QSO"), null);
        alert.format_body ("%s", message);
        alert.add_response ("ok", _("OK"));
        alert.set_default_response ("ok");
        alert.set_close_response ("ok");
        alert.present (get_root ());
    }

    private void set_park_details (string? park_name) {
        var display_name = (park_name ?? "").strip ();
        park_details_row.subtitle = display_name;
        park_details_row.visible = display_name != "";
        update_lookup_park_button_state ();
    }

    private void update_lookup_park_button_state () {
        lookup_park_button.visible = park_ref.text.strip () != "" && !park_details_row.visible;
        if (!park_lookup_in_progress)
            lookup_park_button.sensitive = lookup_park_button.visible;
    }

    private Spot build_spot (DateTime spot_time) {
        string selected_mode = ((Gtk.StringList) mode.get_model ()).get_string (mode.selected);
        return new Spot.from_add_spot (
            activator_callsign.text,
            park_ref.text,
            spot_time,
            frequency.text,
            selected_mode,
            spotter_callsign.text,
            spotter_comments.text,
            rst_sent.text,
            rst_received.text
        );
    }

    private void lookup_park_details () {
        park_lookup_in_progress = true;
        lookup_park_button.sensitive = false;
        var reference = park_ref.text.strip ();

        Application.park_details_cache.get_details.begin (reference, (obj, res) => {
            try {
                var details = Application.park_details_cache.get_details.end (res);
                set_park_details (details.name);

                lookup_park_button.visible = false;
                Application.show_toast (_("Park details updated"));
            } catch (Error err) {
                present_logging_error (err.message);
            }
            park_lookup_in_progress = false;
            update_lookup_park_button_state ();
        });
    }

    private void select_mode (string mode_name) {
        var model = mode.get_model () as Gtk.StringList;
        if (model == null)
            return;

        var normalized_mode = strip_up (mode_name);
        for (uint i = 0 ; i < model.get_n_items () ; i++) {
            if (model.get_string (i).up () == normalized_mode) {
                mode.selected = i;
                return;
            }
        }
    }
}
