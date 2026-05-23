/* src/spot_card.vala
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

public string humanize_ago (GLib.DateTime dt) {
    var now = new GLib.DateTime.now_utc ();
    int64 span_us = now.difference (dt);

    if (span_us < 0)
        return _("in the future");

    int64 sec = span_us / GLib.TimeSpan.SECOND;
    int64 min = span_us / GLib.TimeSpan.MINUTE;

    if (sec < 5)
        return _("just now");
    if (sec < 60)
        return _("%ld seconds ago").printf ((long)sec);
    if (min == 1)
        return _("a minute ago");
    if (min < 60)
        return _("%ld minutes ago").printf ((long)min);
    return _("more than an hour ago");
}

public string humanize_ago_compact (GLib.DateTime dt) {
    var now = new GLib.DateTime.now_utc ();
    int64 span_us = now.difference (dt);

    if (span_us < 0)
        return _("now");

    int64 sec = span_us / GLib.TimeSpan.SECOND;
    int64 min = span_us / GLib.TimeSpan.MINUTE;
    int64 hr = span_us / GLib.TimeSpan.HOUR;

    if (sec < 60)
        return _("%lds").printf ((long)sec);
    if (min < 60)
        return _("%ldm ago").printf ((long)min);
    return _("%ldh ago").printf ((long)hr);
}

public string bearing_to_compass (double bearing) {
    bearing = Math.fmod (bearing, 360.0);
    if (bearing < 0)
        bearing += 360.0;

    string[] directions = { _("N"), _("NE"), _("E"), _("SE"), _("S"), _(
        "SW"), _("W"), _("NW") };
    int index = (int)Math.floor ((bearing + 22.5) / 45.0) % 8;
    return directions[index];
}

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
    [GtkChild] private unowned Gtk.Button retry_qrz_button;
    [GtkChild] private unowned Gtk.Button submit_button;

    public signal void qso_changed ();

    private int64 edit_qso_id = 0;
    private DateTime? edit_spot_time = null;
    private bool edit_local_adif_saved = false;
    private bool edit_pota_spotted = false;
    private bool edit_qrz_uploaded = false;
    private string? edit_local_adif_error = null;
    private string? edit_pota_error = null;
    private string? edit_qrz_error = null;
    private bool edit_missing_park_name = false;
    private bool park_lookup_in_progress = false;

    public AddSpot () {
        Object ();
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
    }

    public AddSpot.from_qso (QsoRow qso) {
        Object ();

        title = _("Edit QSO");
        submit_button.label = _("Save");

        edit_qso_id = qso.id;
        edit_spot_time = parse_qso_time (qso.created_utc) ?? new DateTime.now_utc ();
        edit_local_adif_saved = qso.local_adif_saved;
        edit_pota_spotted = qso.pota_spotted;
        edit_qrz_uploaded = qso.qrz_uploaded;
        edit_local_adif_error = qso.local_adif_error;
        edit_pota_error = qso.pota_error;
        edit_qrz_error = qso.qrz_error;
        edit_missing_park_name = (qso.park_name ?? "").strip () == "";

        activator_callsign.text = qso.callsign ?? "";
        spotter_callsign.text = qso.spotter ?? Application.settings.get_string ("callsign");
        park_ref.text = qso.park_ref ?? "";
        Application.park_details_cache.seed (park_ref.text, qso.park_name);
        set_park_details (qso.park_name);
        frequency.text = format_frequency_khz (qso.frequency_khz);
        spotter_comments.text = qso.spotter_comment ?? "";
        select_mode (qso.mode ?? Application.settings.get_string ("default-mode"));

        retry_qrz_button.visible = can_retry_qrz ();
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
        retry_qrz_button.clicked.connect (() => retry_qrz_upload ());

        park_ref.changed.connect (() => {
            var cached_details = Application.park_details_cache.peek (park_ref.text);
            set_park_details (cached_details != null ? cached_details.name : null);
        });

        submit_button.clicked.connect (() => {
            submit_button.sensitive = false;
            if (edit_qso_id > 0) {
                save_edited_qso ();
                return;
            }

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

    private bool can_retry_qrz () {
        return edit_qso_id > 0 &&
            !edit_qrz_uploaded &&
            (edit_qrz_error ?? "").strip () != "" &&
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

    private void save_edited_qso () {
        Error? error = null;
        var spot = build_spot (edit_spot_time ?? new DateTime.now_utc ());
        if (!Application.spot_database.update_qso_from_spot (edit_qso_id, spot, out error)) {
            submit_button.sensitive = true;
            present_logging_error (error != null ? error.message : _("Unable to save QSO"));
            return;
        }

        qso_changed ();
        Application.show_toast (_("QSO saved"));
        this.close ();
    }

    private void retry_qrz_upload () {
        retry_qrz_button.sensitive = false;
        submit_button.sensitive = false;

        var spot = build_spot (edit_spot_time ?? new DateTime.now_utc ());
        Error? save_error = null;
        if (!Application.spot_database.update_qso_from_spot (edit_qso_id, spot, out save_error)) {
            retry_qrz_button.sensitive = true;
            submit_button.sensitive = true;
            present_logging_error (save_error != null ? save_error.message : _("Unable to save QSO"));
            return;
        }

        Application.qrz_client.upload_spot_qso.begin (spot, (obj, res) => {
            try {
                Application.qrz_client.upload_spot_qso.end (res);
                edit_qrz_uploaded = true;
                edit_qrz_error = null;
                update_delivery_status (spot);
                retry_qrz_button.visible = false;
                qso_changed ();
                Application.show_toast (_("Uploaded QSO to QRZ"));
            } catch (Error err) {
                edit_qrz_error = err.message;
                update_delivery_status (spot);
                retry_qrz_button.sensitive = true;
                present_qrz_error (err.message);
            } finally {
                submit_button.sensitive = true;
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

                if (edit_qso_id > 0) {
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
                }

                lookup_park_button.visible = false;
                Application.show_toast (_("Park details updated"));
            } catch (Error err) {
                present_logging_error (err.message);
            }
            park_lookup_in_progress = false;
            update_lookup_park_button_state ();
        });
    }

    private void update_delivery_status (Spot spot) {
        Error? error = null;
        if (!Application.spot_database.update_qso_delivery_status (
            spot,
            edit_local_adif_saved,
            edit_pota_spotted,
            edit_qrz_uploaded,
            edit_local_adif_error,
            edit_pota_error,
            edit_qrz_error,
            out error
        )) {
            warning (
                "Unable to update QSO delivery status: %s",
                error != null ? error.message : "unknown error"
            );
        }
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
} /* class AddSpot */

[GtkTemplate (ui = "/com/k0vcz/artemis/ui/spot_card.ui")]
public sealed class SpotCard : Gtk.Box {
    [GtkChild]
    private unowned Adw.Avatar activator_avatar;

    [GtkChild]
    private unowned Gtk.Label title;

    [GtkChild]
    private unowned Gtk.Label park_label;

    [GtkChild]
    private unowned Gtk.Box badge_box;

    [GtkChild]
    private unowned Gtk.Label location_desc;

    [GtkChild]
    private unowned Gtk.Label grid_square;

    [GtkChild]
    private unowned Gtk.Image band_dot;

    [GtkChild]
    private unowned Gtk.Label frequency;

    [GtkChild]
    private unowned Gtk.Label mode;

    [GtkChild]
    private unowned Gtk.Label time;

    [GtkChild]
    private unowned Gtk.Label spot_count;

    [GtkChild]
    private unowned Gtk.Button tune_button;

    [GtkChild]
    private unowned Gtk.Button spot_button;

    public Spot spot { get; construct; }
    private ulong callsign_cache_updated_handler = 0;
    private ulong radio_connection_state_handler = 0;
    private ulong heard_recently_notify_handler = 0;
    private uint avatar_retry_id = 0;
    private uint avatar_fetch_attempt = 0;
    private bool disposed = false;

    private Gdk.Texture? activator_avatar_texture {
        set {
            if (value != null)
                activator_avatar.set_custom_image (value);
        }
    }

    private Activator? activator_info {
        set {
            if (value != null) {
                bool has_name = value.name != null && value.name.length > 0;
                bool has_qth = value.qth != null && value.qth.length > 0;

                if (has_name && has_qth)
                    activator_avatar.tooltip_text = "%s (%s)".printf (value.name, value.qth);
                else if (has_name)
                    activator_avatar.tooltip_text = value.name;
                else
                    activator_avatar.tooltip_text = null;
            } else {
                activator_avatar.tooltip_text = null;
            }
        }
    }

    public SpotCard () {
        Object ();
    }

    public SpotCard.from_spot (Spot spot) {
        Object (spot: spot);

        title.label = "%s @ %s".printf (spot.callsign, spot.park_ref);
        park_label.label = spot.park_name;
        location_desc.label = spot.location_desc;
        var grid = ((spot.grid6 ?? "") != "") ? spot.grid6 : (spot.grid4 ?? "");
        grid_square.label = grid;
        grid_square.visible = grid != "";

        sync_band_dot_css (spot.band);
        frequency.label = "%s kHz".printf (format_frequency_khz (spot.frequency_khz));
        mode.label = spot.mode;
        time.label = humanize_ago (spot.spot_time);
        spot_count.label = spot.spot_count.to_string ();

        callsign_cache_updated_handler = Application.callsign_cache.entry_updated.connect ((updated_callsign) => {
            update_avatars_from_cache (updated_callsign);
        });
        start_avatar_fetch ();

        refresh_highlight ();

        heard_recently_notify_handler = spot.notify["heard-recently"].connect (() => {
            refresh_highlight ();
        });

        update_tune_button_state ();
        tune_button.clicked.connect (on_tune_clicked);
        spot_button.clicked.connect (on_spot_clicked);

        radio_connection_state_handler = Application.app.radio_connection_state_changed.connect (() => {
            update_tune_button_state ();
        });
    }

    private void update_tune_button_state () {
        tune_button.visible = Application.is_radio_configured;
        tune_button.sensitive = Application.radio_control.is_rig_connected;
    }

    private void sync_band_dot_css (string band) {
        foreach (var known_band in RadioConstants.BANDS) {
            band_dot.remove_css_class ("band-dot-%s".printf (known_band.down ()));
        }

        band_dot.add_css_class ("band-dot-%s".printf (band.down ()));
    }

    private void on_tune_clicked () {
        Application.state.current_spot_hash = spot.hash;
        Application.radio_control.tune_to_spot (spot);
    }

    private void on_spot_clicked () {
        new AddSpot.from_spot (spot).present (get_root ());
    }

    private void start_avatar_fetch () {
        fetch_avatars.begin ((obj, res) => {
            fetch_avatars.end (res);
        });
    }

    private void schedule_avatar_retry () {
        if (disposed || avatar_fetch_attempt >= 3 || avatar_retry_id != 0)
            return;

        avatar_fetch_attempt++;
        avatar_retry_id = Timeout.add_seconds (avatar_fetch_attempt, () => {
            avatar_retry_id = 0;
            if (!disposed)
                start_avatar_fetch ();
            return Source.REMOVE;
        });
    }

    private void cancel_avatar_retry () {
        if (avatar_retry_id != 0) {
            Source.remove (avatar_retry_id);
            avatar_retry_id = 0;
        }
    }

    private async void fetch_avatars () {
        var ava_activator = yield Application.callsign_cache.get_avatar_for (spot.callsign);
        if (disposed)
            return;

        activator_avatar_texture = ava_activator;
        if (ava_activator == null)
            schedule_avatar_retry ();
        else
            cancel_avatar_retry ();

        var activator = yield Application.callsign_cache.get_callsign (spot.callsign);
        if (disposed)
            return;

        activator_info = activator;
    } /* fetch_avatars */

    private void update_avatars_from_cache (string updated_callsign) {
        if (
            (updated_callsign == spot.callsign) ||
            (updated_callsign == pota_profile_callsign (spot.callsign))
        ) {
            var activator_image = Application.callsign_cache.peek_avatar (spot.callsign);
            activator_avatar_texture = activator_image;
            if (activator_image != null)
                cancel_avatar_retry ();

            var activator = Application.callsign_cache.peek_callsign (spot.callsign);
            activator_info = activator;
        }
    }

    ~SpotCard () {
        disposed = true;
        cancel_avatar_retry ();
        if (callsign_cache_updated_handler != 0) {
            if (SignalHandler.is_connected (Application.callsign_cache, callsign_cache_updated_handler))
                SignalHandler.disconnect (Application.callsign_cache, callsign_cache_updated_handler);
            callsign_cache_updated_handler = 0;
        }
        if (radio_connection_state_handler != 0) {
            if (SignalHandler.is_connected (Application.app, radio_connection_state_handler))
                SignalHandler.disconnect (Application.app, radio_connection_state_handler);
            radio_connection_state_handler = 0;
        }
        if (heard_recently_notify_handler != 0) {
            if (SignalHandler.is_connected (spot, heard_recently_notify_handler))
                SignalHandler.disconnect (spot, heard_recently_notify_handler);
            heard_recently_notify_handler = 0;
        }
    }

    public void refresh_highlight () {
        populate_spot_badges (badge_box, spot);

        this.remove_css_class ("dimmed");
        if (spot.was_hunted_today) {
            this.add_css_class ("dimmed");
        }

    } /* refresh_highlight */
} /* class SpotCard */

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
} /* class ParkLogDialog */

private Gtk.Widget create_spot_row (Json.Object spot_obj) {
    string spotter = spot_obj.get_string_member_with_default ("spotter", "");
    string frequency = spot_obj.get_string_member_with_default ("frequency", "")
    ;
    string mode = spot_obj.get_string_member_with_default ("mode", "");
    string spot_time = spot_obj.get_string_member_with_default ("spotTime", "");
    string comments = spot_obj.get_string_member_with_default ("comments", "");

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
        xalign = 0, hexpand = true
    };
    header_box.append (freq_label);

    var time_label = new Gtk.Label (spot_dt) {
        xalign = 1
    };
    header_box.append (time_label);

    return row;
} /* create_spot_row */

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
} /* class SpotHistoryDialog */
