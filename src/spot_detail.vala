/* src/spot_detail.vala
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

[GtkTemplate (ui = "/com/k0vcz/artemis/ui/spot_detail.ui")]
public sealed class SpotDetail : Gtk.Box {
    [GtkChild]
    private unowned Gtk.Stack detail_stack;

    [GtkChild]
    private unowned Adw.Avatar detail_avatar;

    [GtkChild]
    private unowned Gtk.Label detail_callsign;

    [GtkChild]
    private unowned Gtk.Label detail_operator_name;

    [GtkChild]
    private unowned Gtk.Label detail_park_name;

    [GtkChild]
    private unowned Gtk.Box detail_badges;

    [GtkChild]
    private unowned Gtk.Label detail_frequency;

    [GtkChild]
    private unowned Gtk.Label detail_mode;

    [GtkChild]
    private unowned Gtk.Label detail_spot_count;

    [GtkChild]
    private unowned Gtk.Label detail_location;

    [GtkChild]
    private unowned Adw.ActionRow detail_grid_row;

    [GtkChild]
    private unowned Gtk.Label detail_grid;

    [GtkChild]
    private unowned Adw.ActionRow detail_distance_row;

    [GtkChild]
    private unowned Gtk.Label detail_distance;

    [GtkChild]
    private unowned Adw.ActionRow detail_bearing_row;

    [GtkChild]
    private unowned Gtk.Label detail_bearing;

    [GtkChild]
    private unowned Gtk.Label detail_spotter;

    [GtkChild]
    private unowned Gtk.Label detail_spot_time;

    [GtkChild]
    private unowned Adw.ActionRow detail_spotter_comment_row;

    [GtkChild]
    private unowned Adw.PreferencesGroup detail_activator_group;

    [GtkChild]
    private unowned Adw.ActionRow detail_activator_comment_row;

    [GtkChild]
    private unowned Gtk.Button detail_tune_button;

    [GtkChild]
    private unowned Gtk.Button detail_spot_button;

    [GtkChild]
    private unowned Gtk.Button detail_history_button;

    [GtkChild]
    private unowned Gtk.Button detail_park_button;

    private Spot? current_spot = null;
    private string? park_url = null;
    private ulong callsign_cache_handler = 0;

    public SpotDetail () {
        Object ();
    }

    construct {
        detail_tune_button.clicked.connect (on_tune_clicked);
        detail_spot_button.clicked.connect (on_spot_clicked);
        detail_history_button.clicked.connect (on_history_clicked);
        detail_park_button.clicked.connect (on_park_clicked);
    }

    public void set_spot (Spot? spot) {
        if (callsign_cache_handler != 0) {
            if (SignalHandler.is_connected (Application.callsign_cache, callsign_cache_handler))
                SignalHandler.disconnect (Application.callsign_cache, callsign_cache_handler);
            callsign_cache_handler = 0;
        }

        current_spot = spot;

        if (spot == null) {
            detail_stack.visible_child_name = "empty";
            return;
        }

        populate (spot);
        detail_stack.visible_child_name = "detail";

        fetch_avatar.begin ((obj, res) => { fetch_avatar.end (res); });
        callsign_cache_handler = Application.callsign_cache.entry_updated.connect ((cs) => {
            if (cs == spot.callsign)
                update_avatar_from_cache (cs);
        });
    }

    private void populate (Spot spot) {
        detail_avatar.text = spot.callsign;
        detail_callsign.label = "%s @ %s".printf (spot.callsign, spot.park_ref);
        var cached_activator = Application.callsign_cache.peek_callsign (spot.callsign);
        detail_operator_name.label = (cached_activator != null && cached_activator.name != "") ?
            cached_activator.name : "";
        detail_operator_name.visible = detail_operator_name.label != "";
        detail_park_name.label = spot.park_name;

        var badge_child = detail_badges.get_first_child ();
        while (badge_child != null) {
            var next = badge_child.get_next_sibling ();
            detail_badges.remove (badge_child);
            badge_child = next;
        }

        if (spot.is_new_park && Application.settings.get_boolean ("highlight-unhunted-parks")) {
            var badge = new Gtk.Image.from_icon_name ("starred-symbolic");
            badge.add_css_class ("unhunted");
            badge.tooltip_text = _("New park!");
            detail_badges.append (badge);
        }

        if (spot.was_hunted_today) {
            var badge = new Gtk.Image.from_icon_name ("bullseye-symbolic");
            badge.add_css_class ("hunted");
            badge.tooltip_text = _("Hunted today");
            detail_badges.append (badge);
        }

        detail_frequency.label = "%d kHz".printf (spot.frequency_khz);
        detail_mode.label = spot.mode;
        detail_spot_count.label = ngettext ("%d spot", "%d spots", spot.spot_count)
            .printf (spot.spot_count);

        Error err = null;
        var locations = spot.location_desc.split (",", -1);
        var loc_str = "";
        if (locations.length <= 2) {
            for (int i = 0; i < locations.length; i++) {
                var country = Application.spot_database.country_string_for_location (
                    locations[i], out err);
                loc_str += (i > 0 ? "\n" : "") + (country ?? spot.location_desc);
            }
        } else {
            loc_str = spot.location_desc;
        }
        detail_location.label = loc_str;

        var grid = ((spot.grid6 ?? "") != "") ? spot.grid6 : (spot.grid4 ?? "");
        detail_grid_row.visible = grid != "";
        detail_grid.label = grid;

        var has_location = Application.settings.get_string ("location") != "" && spot.distance >= 0;
        detail_distance_row.visible = has_location;
        detail_bearing_row.visible = has_location;
        if (has_location) {
            var use_metric = Application.settings.get_boolean ("use-metric");
            var unit = use_metric ? _("km") : _("mi");
            var dist = use_metric ? spot.distance : spot.distance * 0.6213712;
            detail_distance.label = "%'d %s".printf ((int)dist, unit);
            detail_bearing.label = "%d° %s".printf ((int)spot.bearing,
                bearing_to_compass (spot.bearing));
        }

        detail_spotter.label = spot.spotter;
        detail_spot_time.label = humanize_ago (spot.spot_time);

        var has_spotter_comment = (spot.spotter_comment ?? "").strip () != "";
        detail_spotter_comment_row.visible = has_spotter_comment;
        detail_spotter_comment_row.subtitle = has_spotter_comment ? spot.spotter_comment : "";

        var has_activator_comment = (spot.activator_comment ?? "").strip () != "";
        detail_activator_group.visible = has_activator_comment;
        detail_activator_comment_row.subtitle = has_activator_comment ? spot.activator_comment : "";

        var escaped = GLib.Uri.escape_string (spot.park_ref, null, false);
        park_url = @"http://pota.app/#/park/$escaped";
    }

    private async void fetch_avatar () {
        if (current_spot == null)
            return;
        var texture = yield Application.callsign_cache.get_avatar_for (current_spot.callsign);
        if (current_spot != null)
            detail_avatar.custom_image = texture;
    }

    private void update_avatar_from_cache (string callsign) {
        detail_avatar.custom_image = Application.callsign_cache.peek_avatar (callsign);
        var activator = Application.callsign_cache.peek_callsign (callsign);
        detail_operator_name.label = (activator != null && activator.name != "") ?
            activator.name : "";
        detail_operator_name.visible = detail_operator_name.label != "";
    }

    public void set_action_buttons_visible (bool visible) {
        detail_tune_button.visible = visible && Application.is_radio_configured;
        detail_tune_button.sensitive = visible && Application.radio_control.is_rig_connected;
        detail_spot_button.visible = visible;
    }

    private void on_tune_clicked () {
        if (current_spot == null)
            return;
        Application.radio_control.tune_to_spot (current_spot);
    }

    private void on_spot_clicked () {
        if (current_spot == null)
            return;
        new AddSpot.from_spot (current_spot).present (get_root ());
    }

    private void on_history_clicked () {
        var spot = current_spot;
        if (spot == null)
            return;
        var dlg = new SpotHistoryDialog (spot.callsign, spot.park_ref);
        dlg.show_loading (true);
        dlg.present (get_root ());
        Application.pota_client.fetch_spot_history.begin (spot.callsign, spot.park_ref, (
                obj, res) => {
            try {
                dlg.show_history (Application.pota_client.fetch_spot_history.end (res));
            } catch (Error e) {
                dlg.show_error (e.message);
            }
        });
    }

    private void on_park_clicked () {
        if (park_url == null)
            return;
#if ARTEMIS_UNIX
        new ParkDetailsView (park_url).present (get_root ());
#else
        GLib.AppInfo.launch_default_for_uri (park_url, null);
#endif
    }

    ~SpotDetail () {
        if (callsign_cache_handler != 0 &&
            SignalHandler.is_connected (Application.callsign_cache, callsign_cache_handler))
            SignalHandler.disconnect (Application.callsign_cache, callsign_cache_handler);
    }
}
