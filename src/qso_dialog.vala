/* src/qso_dialog.vala
 *
 * Copyright 2026 Jay Baird (K0VCZ)
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

[GtkTemplate (ui = "/com/k0vcz/artemis/ui/qso_dialog.ui")]
public sealed class QsoDialog : Adw.Dialog {
    [GtkChild] private unowned Adw.EntryRow activator_callsign;
    [GtkChild] private unowned Adw.EntryRow spotter_callsign;
    [GtkChild] private unowned Adw.EntryRow frequency;
    [GtkChild] private unowned Adw.ComboRow mode;
    [GtkChild] private unowned Adw.EntryRow park_ref;
    [GtkChild] private unowned Adw.ActionRow park_details_row;
    [GtkChild] private unowned Adw.EntryRow rst_sent;
    [GtkChild] private unowned Adw.EntryRow rst_received;
    [GtkChild] private unowned Adw.EntryRow spotter_comments;

    [GtkChild] private unowned Gtk.Button delete_button;
    [GtkChild] private unowned Gtk.Button cancel_button;
    [GtkChild] private unowned Gtk.Button lookup_park_button;
    [GtkChild] private unowned Gtk.Button retry_qrz_button;
    [GtkChild] private unowned Gtk.Button save_button;

    public signal void qso_changed ();

    private int64 qso_id = 0;
    private DateTime? qso_time = null;
    private bool local_adif_saved = false;
    private bool pota_spotted = false;
    private bool qrz_uploaded = false;
    private string? local_adif_error = null;
    private string? pota_error = null;
    private string? qrz_error = null;
    private bool park_lookup_in_progress = false;

    public QsoDialog (QsoRow qso) {
        Object ();

        qso_id = qso.id;
        qso_time = parse_qso_time (qso.created_utc) ?? new DateTime.now_utc ();
        local_adif_saved = qso.local_adif_saved;
        pota_spotted = qso.pota_spotted;
        qrz_uploaded = qso.qrz_uploaded;
        local_adif_error = qso.local_adif_error;
        pota_error = qso.pota_error;
        qrz_error = qso.qrz_error;

        activator_callsign.text = qso.callsign ?? "";
        spotter_callsign.text = qso.spotter ?? Application.settings.get_string ("callsign");
        park_ref.text = qso.park_ref ?? "";
        Application.park_details_cache.seed (park_ref.text, qso.park_name);
        set_park_details (qso.park_name);
        frequency.text = format_frequency_khz (qso.frequency_khz);
        spotter_comments.text = qso.spotter_comment ?? "";
        rst_sent.text = qso.rst_sent ?? "";
        rst_received.text = qso.rst_rcvd ?? "";
        select_mode (qso.mode ?? Application.settings.get_string ("default-mode"));

        retry_qrz_button.visible = can_retry_qrz ();
    }

    construct {
        cancel_button.clicked.connect (() => close ());
        lookup_park_button.clicked.connect (() => lookup_park_details ());
        retry_qrz_button.clicked.connect (() => retry_qrz_upload ());
        delete_button.clicked.connect (() => confirm_delete ());
        save_button.clicked.connect (() => save_qso ());

        park_ref.changed.connect (() => {
            var cached_details = Application.park_details_cache.peek (park_ref.text);
            set_park_details (cached_details != null ? cached_details.name : null);
        });
    }

    private bool can_retry_qrz () {
        return qso_id > 0 &&
            !qrz_uploaded &&
            (qrz_error ?? "").strip () != "" &&
            Application.logging_service.preferences.enable_qrz_logging &&
            Application.logging_service.preferences.qrz_api_key != "";
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

    private Spot build_spot () {
        string selected_mode = ((Gtk.StringList) mode.get_model ()).get_string (mode.selected);
        return new Spot.from_add_spot (
            activator_callsign.text,
            park_ref.text,
            qso_time ?? new DateTime.now_utc (),
            frequency.text,
            selected_mode,
            spotter_callsign.text,
            spotter_comments.text,
            rst_sent.text,
            rst_received.text
        );
    }

    private void save_qso () {
        save_button.sensitive = false;

        Error? error = null;
        if (!Application.spot_database.update_qso_from_spot (qso_id, build_spot (), out error)) {
            save_button.sensitive = true;
            present_error (_("Unable to Save QSO"), error != null ? error.message : _("Unable to save QSO"));
            return;
        }

        qso_changed ();
        Application.show_toast (_("QSO saved"));
        close ();
    }

    private void confirm_delete () {
        var alert = new Adw.AlertDialog (_("Delete QSO?"), null);
        alert.body = _("This removes the QSO from your local logbook.");
        alert.add_response ("cancel", _("Cancel"));
        alert.add_response ("delete", _("Delete"));
        alert.set_response_appearance ("delete", Adw.ResponseAppearance.DESTRUCTIVE);
        alert.set_default_response ("cancel");
        alert.set_close_response ("cancel");
        alert.response.connect ((response) => {
            if (response == "delete")
                delete_qso ();
        });
        alert.present (this);
    }

    private void delete_qso () {
        delete_button.sensitive = false;
        save_button.sensitive = false;

        Error? error = null;
        if (!Application.spot_database.delete_qso (qso_id, out error)) {
            delete_button.sensitive = true;
            save_button.sensitive = true;
            present_error (_("Unable to Delete QSO"), error != null ? error.message : _("Unable to delete QSO"));
            return;
        }

        qso_changed ();
        Application.show_toast (_("QSO deleted"));
        close ();
    }

    private void retry_qrz_upload () {
        retry_qrz_button.sensitive = false;
        save_button.sensitive = false;

        var spot = build_spot ();
        Error? save_error = null;
        if (!Application.spot_database.update_qso_from_spot (qso_id, spot, out save_error)) {
            retry_qrz_button.sensitive = true;
            save_button.sensitive = true;
            present_error (_("Unable to Save QSO"), save_error != null ? save_error.message : _("Unable to save QSO"));
            return;
        }

        Application.qrz_client.upload_spot_qso.begin (spot, (obj, res) => {
            try {
                Application.qrz_client.upload_spot_qso.end (res);
                qrz_uploaded = true;
                qrz_error = null;
                update_delivery_status (spot);
                retry_qrz_button.visible = false;
                qso_changed ();
                Application.show_toast (_("Uploaded QSO to QRZ"));
            } catch (Error err) {
                qrz_error = err.message;
                update_delivery_status (spot);
                retry_qrz_button.sensitive = true;
                present_qrz_error (err.message);
            } finally {
                save_button.sensitive = true;
            }
        });
    }

    private void lookup_park_details () {
        park_lookup_in_progress = true;
        lookup_park_button.sensitive = false;
        var reference = park_ref.text.strip ();

        Application.park_details_cache.get_details.begin (reference, (obj, res) => {
            try {
                var details = Application.park_details_cache.get_details.end (res);
                set_park_details (details.name);

                Error? db_error = null;
                if (!Application.spot_database.add_park (
                    details.reference,
                    details.name,
                    null,
                    details.location_desc,
                    null,
                    null,
                    0,
                    out db_error
                )) {
                    throw db_error ?? new IOError.FAILED ("Unable to save park details");
                }

                qso_changed ();
                lookup_park_button.visible = false;
                Application.show_toast (_("Park details updated"));
            } catch (Error err) {
                present_error (_("Unable to Lookup Park"), err.message);
            }
            park_lookup_in_progress = false;
            update_lookup_park_button_state ();
        });
    }

    private void update_delivery_status (Spot spot) {
        Error? error = null;
        if (!Application.spot_database.update_qso_delivery_status (
            spot,
            local_adif_saved,
            pota_spotted,
            qrz_uploaded,
            local_adif_error,
            pota_error,
            qrz_error,
            out error
        )) {
            warning (
                "Unable to update QSO delivery status: %s",
                error != null ? error.message : "unknown error"
            );
        }
    }

    private void present_qrz_error (string message) {
        var alert = new Adw.AlertDialog (_("Unable to Upload to QRZ"), null);
        alert.format_body (_("The QSO was saved, but QRZ logging failed: %s"), message);
        alert.add_response ("ok", _("OK"));
        alert.set_default_response ("ok");
        alert.set_close_response ("ok");
        alert.present (this);
    }

    private void present_error (string title, string message) {
        var alert = new Adw.AlertDialog (title, null);
        alert.format_body ("%s", message);
        alert.add_response ("ok", _("OK"));
        alert.set_default_response ("ok");
        alert.set_close_response ("ok");
        alert.present (this);
    }

    private void select_mode (string mode_name) {
        var model = mode.get_model () as Gtk.StringList;
        if (model == null)
            return;

        var normalized_mode = mode_name.strip ().up ();
        for (uint i = 0 ; i < model.get_n_items () ; i++) {
            if (model.get_string (i).up () == normalized_mode) {
                mode.selected = i;
                return;
            }
        }
    }

    private static DateTime? parse_qso_time (string? iso_utc) {
        if ((iso_utc ?? "").strip () == "")
            return null;
        return new DateTime.from_iso8601 (iso_utc, new TimeZone.utc ());
    }
}
