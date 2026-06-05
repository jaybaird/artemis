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

    private bool _selected = false;
    public bool selected {
        get { return _selected; }
        set {
            if (_selected != value) {
                _selected = value;
                if (selected) {
                    tune_button.remove_css_class ("flat");
                    spot_button.remove_css_class ("flat");
                    tune_button.add_css_class ("raised");
                    spot_button.add_css_class ("raised");
                    spot_button.add_css_class ("suggested-action");
                } else {
                    tune_button.remove_css_class ("raised");
                    spot_button.remove_css_class ("raised");
                    spot_button.remove_css_class ("suggested-action");
                    tune_button.add_css_class ("flat");
                    spot_button.add_css_class ("flat");
                }
            }
        }
    }
    private ulong callsign_cache_updated_handler = 0;
    private ulong radio_connection_state_handler = 0;
    private ulong heard_recently_notify_handler = 0;
    private ulong heard_reciprocally_notify_handler = 0;
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
        var grid = spot.grid ();
        grid_square.label = grid;
        grid_square.visible = grid != "";

        sync_band_dot_css (spot.band);
        frequency.label = "%s kHz".printf (format_frequency_khz (spot.frequency_khz));
        mode.label = spot.mode;
        time.label = humanize_ago (spot.spot_time);
        spot_count.label = spot.spot_count.to_string ("%'d");

        callsign_cache_updated_handler = Application.callsign_cache.entry_updated.connect ((updated_callsign) => {
            update_avatars_from_cache (updated_callsign);
        });
        start_avatar_fetch ();

        refresh_highlight ();

        heard_recently_notify_handler = spot.notify["heard-recently"].connect (() => {
            refresh_highlight ();
        });
        heard_reciprocally_notify_handler = spot.notify["heard-reciprocally"].connect (() => {
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
        if (heard_reciprocally_notify_handler != 0) {
            if (SignalHandler.is_connected (spot, heard_reciprocally_notify_handler))
                SignalHandler.disconnect (spot, heard_reciprocally_notify_handler);
            heard_reciprocally_notify_handler = 0;
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
