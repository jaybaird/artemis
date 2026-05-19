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
    [GtkChild] private unowned Adw.EntryRow rst_sent;
    [GtkChild] private unowned Adw.EntryRow rst_received;
    [GtkChild] private unowned Adw.EntryRow spotter_comments;

    [GtkChild] private unowned Gtk.Button cancel_button;
    [GtkChild] private unowned Gtk.Button submit_button;

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

    public AddSpot.from_spot (Spot spot) {
        Object ();

        activator_callsign.text = spot.callsign;
        activator_callsign.editable = false;
        park_ref.text = spot.park_ref;
        park_ref.editable = false;
        frequency.text = format_frequency_khz (spot.frequency_khz);
        select_mode (spot.mode);
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

        submit_button.clicked.connect (() => {
            bool enable_logging = Application.settings.get_boolean ("enable-logging");
            string qrz_api_key = Application.settings.get_string ("qrz-api-key").strip ();
            var spot = new Spot.from_add_spot (
                activator_callsign.text,
                park_ref.text,
                new DateTime.now_utc (),
                frequency.text,
                ((Gtk.StringList)mode.get_model ()).get_string (mode.selected),
                spotter_callsign.text,
                spotter_comments.text,
                rst_sent.text,
                rst_received.text);

            this.close ();

            Application.pota_client.post_spot.begin (spot, (obj, res) => {
                try {
                    Error? err = null;
                    Application.pota_client.post_spot.end (res);
                    Application.show_toast (_("Spot posted"));
                    Application.spot_database.add_qso_from_spot (spot, out err);
                    if (err != null) {
                        warning ("Unable to save qso: %s".printf (err.message));
                    }

                    if (enable_logging && (qrz_api_key != "")) {
                        Application.qrz_client.upload_spot_qso.begin (spot, (
                            qrz_obj,
                            qrz_res
                        ) => {
                            try {
                                Application.qrz_client.upload_spot_qso.end (qrz_res);
                                Application.show_toast (_("Uploaded QSO to QRZ"));
                            } catch (Error qrz_err) {
                                warning ("Unable to upload QSO to QRZ: %s",
                                    qrz_err.message);
                                present_qrz_error (qrz_err.message);
                            }
                        });
                    }
                } catch (Error err) {
                    var errmsg = err.message;
                    warning (@"Unable to post spot: $errmsg");
                }
            });
        });
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
    private unowned BandStrip band_strip;

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
    private ulong wsjtx_decode_handler = 0;
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

        band_strip.band = spot.band;
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

        wsjtx_decode_handler = Application.wsjtx_session.decode_received.connect ((decode) => {
            if (decode_matches_spot (decode))
                spot.mark_heard_recently ();
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

    private void on_tune_clicked () {
        Application.current_spot_hash = spot.hash;
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

    private bool decode_matches_spot (Artemis.Wsjtx.DecodePacket decode) {
        var decoded_text = decode.text.strip ().up ();
        var callsign = spot.callsign.strip ().up ();

        if ((decoded_text == "") || (callsign == ""))
            return false;

        return decoded_text.contains (callsign);
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
        if (wsjtx_decode_handler != 0) {
            if (SignalHandler.is_connected (Application.wsjtx_session, wsjtx_decode_handler))
                SignalHandler.disconnect (Application.wsjtx_session, wsjtx_decode_handler);
            wsjtx_decode_handler = 0;
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
    public unowned Gtk.ScrolledWindow qso_scroll;
    [GtkChild]
    public unowned Gtk.ListBox qso_list;

    public string park_ref { get; construct; }
    public ParkLogDialog (Spot spot) {
        Object (
            park_ref: spot.park_ref
        );
    }

    construct {
        Error error = null;
        var park = Application.spot_database.get_park_by_ref (park_ref, out error);
        var all_qsos = Application.spot_database.all_qsos_for_park (park_ref, out
            error);
        foreach (var qso in all_qsos) {
            // var row = create_qso_row (qso);
            // qso_list.append (row);
        }
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
