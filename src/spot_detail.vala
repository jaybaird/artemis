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

public sealed class DetailFieldRow : Gtk.ListBoxRow {
    private Gtk.Label title_label;
    private Gtk.Label value_label;

    public string title {
        set {
            title_label.label = value;
        }
    }

    public string value {
        set {
            value_label.label = value;
        }
    }

    public bool value_visible {
        set {
            value_label.visible = value;
        }
    }

    public DetailFieldRow (string title, bool wrap = false, string? icon_name = null) {
        Object ();

        var box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 16) {
            margin_top = 10,
            margin_bottom = 10,
            margin_start = 12,
            margin_end = 12,
            hexpand = true
        };

        if (icon_name != null) {
            var icon = new Gtk.Image.from_icon_name (icon_name) {
                pixel_size = 16,
                valign = Gtk.Align.CENTER
            };
            icon.add_css_class ("dim-label");
            box.append (icon);
        }

        title_label = new Gtk.Label (title) {
            xalign = 0.0f,
            width_chars = 12
        };
        title_label.add_css_class ("caption");
        title_label.add_css_class ("dim-label");
        box.append (title_label);

        value_label = new Gtk.Label ("") {
            xalign = 1.0f,
            wrap = wrap,
            wrap_mode = Pango.WrapMode.WORD_CHAR,
            max_width_chars = wrap ? 28 : 18,
            ellipsize = wrap ? Pango.EllipsizeMode.NONE : Pango.EllipsizeMode.END,
            selectable = true,
            hexpand = true
        };
        value_label.justify = Gtk.Justification.RIGHT;
        value_label.add_css_class ("body");
        box.append (value_label);

        child = box;
    }

    public void add_value_css_class (string css_class) {
        value_label.add_css_class (css_class);
    }
}

public sealed class DetailTimePairRow : Gtk.ListBoxRow {
    private Gtk.Label title_label;
    private Gtk.Label first_value_label;
    private Gtk.Label second_value_label;

    public string title {
        set {
            title_label.label = value;
        }
    }

    public string first_value {
        set {
            first_value_label.label = value;
        }
    }

    public string second_value {
        set {
            second_value_label.label = value;
        }
    }

    public DetailTimePairRow (
        string title,
        string first_icon_name,
        string second_icon_name
    ) {
        Object ();

        var box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 16) {
            margin_top = 10,
            margin_bottom = 10,
            margin_start = 12,
            margin_end = 12,
            hexpand = true
        };

        title_label = new Gtk.Label (title) {
            xalign = 0.0f,
            width_chars = 12
        };
        title_label.add_css_class ("caption");
        title_label.add_css_class ("dim-label");
        box.append (title_label);

        var values_box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 12) {
            hexpand = true
        };
        values_box.halign = Gtk.Align.END;

        values_box.append (build_time_pair (first_icon_name, out first_value_label));
        values_box.append (build_time_pair (second_icon_name, out second_value_label));

        box.append (values_box);
        child = box;
    }

    private Gtk.Box build_time_pair (string icon_name, out Gtk.Label value_label) {
        var pair = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 4) {
            halign = Gtk.Align.END
        };

        var icon = new Gtk.Image.from_icon_name (icon_name) {
            valign = Gtk.Align.CENTER
        };
        icon.add_css_class ("detail-time-icon");
        icon.add_css_class ("dim-label");
        pair.append (icon);

        value_label = new Gtk.Label ("") {
            xalign = 1.0f,
            selectable = true
        };
        value_label.add_css_class ("body");
        pair.append (value_label);

        return pair;
    }
}

public sealed class DetailLinkRow : Gtk.ListBoxRow {
    private Gtk.Label title_label;

    public DetailLinkRow (string title) {
        Object ();
        activatable = true;

        var box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 12) {
            margin_top = 12,
            margin_bottom = 12,
            margin_start = 12,
            margin_end = 12
        };

        title_label = new Gtk.Label (title) {
            xalign = 0.0f,
            hexpand = true
        };
        title_label.add_css_class ("accent");
        box.append (title_label);

        var arrow = new Gtk.Image.from_icon_name ("go-next-symbolic");
        arrow.add_css_class ("dim-label");
        box.append (arrow);

        child = box;
    }
}

[GtkTemplate (ui = "/com/k0vcz/artemis/ui/spot_detail.ui")]
public sealed class SpotDetail : Gtk.Box {
    [GtkChild]
    private unowned Adw.HeaderBar detail_header;

    [GtkChild]
    private unowned Gtk.Stack detail_stack;

    [GtkChild]
    private unowned Adw.Avatar detail_avatar;

    [GtkChild]
    private unowned Gtk.Label detail_callsign;

    [GtkChild]
    private unowned Gtk.Label detail_park_name;

    [GtkChild]
    private unowned Gtk.Box weather_summary_card;

    [GtkChild]
    private unowned Gtk.Image wx_conditions;

    [GtkChild]
    private unowned Gtk.Label wx_conditions_txt;

    [GtkChild]
    private unowned Gtk.Label wx_temp;

    [GtkChild]
    private unowned Gtk.Label wx_humidity;

    [GtkChild]
    private unowned Gtk.ListBox detail_activator_list;

    [GtkChild]
    private unowned Gtk.ListBox detail_operating_list;

    [GtkChild]
    private unowned Gtk.ListBox detail_location_list;

    [GtkChild]
    private unowned Gtk.ListBox detail_last_spot_list;

    [GtkChild]
    private unowned Gtk.Button detail_tune_button;

    [GtkChild]
    private unowned Gtk.Button detail_spot_button;

    private Spot? current_spot = null;
    private string? park_url = null;
    private string? activator_url = null;
    private ulong callsign_cache_handler = 0;
    private ulong pota_locations_handler = 0;
    private ulong radio_connected_handler = 0;
    private ulong radio_disconnected_handler = 0;
    private ulong radio_error_handler = 0;
    private uint weather_request_serial = 0;

    private DetailFieldRow detail_operator_name_row;
    private DetailFieldRow detail_operator_qth_row;
    private DetailFieldRow detail_operator_endorsements_row;
    private DetailLinkRow detail_activator_link_row;
    private DetailFieldRow detail_frequency_row;
    private DetailFieldRow detail_mode_row;
    private DetailFieldRow detail_spot_count_row;
    private DetailFieldRow detail_activator_comment_row;
    private DetailFieldRow detail_location_row;
    private DetailFieldRow detail_bearing_row;
    private DetailFieldRow detail_distance_row;
    private DetailFieldRow detail_grid_row;
    private DetailTimePairRow detail_sun_row;
    private DetailTimePairRow detail_moon_row;
    private DetailLinkRow detail_park_row;
    private DetailFieldRow detail_spotter_row;
    private DetailFieldRow detail_spot_time_row;
    private DetailFieldRow detail_spotter_comment_row;
    private DetailLinkRow detail_history_row;

    public SpotDetail () {
        Object ();
    }

    public void set_end_title_buttons_visible (bool visible) {
        detail_header.show_end_title_buttons = visible;
    }

    construct {
        build_detail_lists ();
        detail_tune_button.clicked.connect (on_tune_clicked);
        detail_spot_button.clicked.connect (on_spot_clicked);
        detail_last_spot_list.row_activated.connect ((row) => {
            if (row == detail_history_row)
                on_history_clicked ();
        });
        detail_location_list.row_activated.connect ((row) => {
            if (row == detail_park_row)
                on_park_clicked ();
        });
        detail_activator_list.row_activated.connect ((row) => {
            if (row == detail_activator_link_row)
                on_activator_clicked ();
        });
        pota_locations_handler = Application.pota_client.locations_updated.connect (() => {
            if (current_spot != null)
                populate (current_spot);
        });
        radio_connected_handler = Application.radio_control.radio_connected.connect (() => {
            update_tune_button_state ();
        });
        radio_disconnected_handler = Application.radio_control.radio_disconnected.connect (() => {
            update_tune_button_state ();
        });
        radio_error_handler = Application.radio_control.radio_error.connect ((err) => {
            update_tune_button_state ();
        });
    }

    private void build_detail_lists () {
        detail_operator_name_row = new DetailFieldRow (_("Activator Name"), true);
        detail_operator_qth_row = new DetailFieldRow (_("QTH"), true);
        detail_operator_endorsements_row = new DetailFieldRow (_("Endorsements"), true);
        detail_activator_link_row = new DetailLinkRow (_("View Activator Details"));
        detail_activator_list.append (detail_operator_name_row);
        detail_activator_list.append (detail_operator_qth_row);
        detail_activator_list.append (detail_operator_endorsements_row);
        detail_activator_list.append (detail_activator_link_row);

        detail_frequency_row = new DetailFieldRow (_("Frequency"));
        detail_frequency_row.add_value_css_class ("numeric");
        detail_mode_row = new DetailFieldRow (_("Mode"));
        detail_spot_count_row = new DetailFieldRow (_("Spots"));
        detail_spot_count_row.add_value_css_class ("numeric");
        detail_activator_comment_row = new DetailFieldRow (_("Activator Comments"), true);
        detail_operating_list.append (detail_frequency_row);
        detail_operating_list.append (detail_mode_row);
        detail_operating_list.append (detail_spot_count_row);
        detail_operating_list.append (detail_activator_comment_row);

        detail_location_row = new DetailFieldRow (_("Location"), true);
        detail_bearing_row = new DetailFieldRow (_("Direction"));
        detail_distance_row = new DetailFieldRow (_("Distance"));
        detail_grid_row = new DetailFieldRow (_("Coordinates"));
        detail_grid_row.add_value_css_class ("numeric");
        detail_sun_row = new DetailTimePairRow (
            _("Sun"),
            "daytime-sunrise-symbolic",
            "daytime-sunset-symbolic"
        );
        detail_moon_row = new DetailTimePairRow (
            _("Moon"),
            "moonrise-symbolic",
            "moonset-symbolic"
        );
        detail_park_row = new DetailLinkRow (_("View Park Details"));
        detail_location_list.append (detail_location_row);
        detail_location_list.append (detail_bearing_row);
        detail_location_list.append (detail_distance_row);
        detail_location_list.append (detail_grid_row);
        detail_location_list.append (detail_sun_row);
        detail_location_list.append (detail_moon_row);
        detail_location_list.append (detail_park_row);

        detail_spotter_row = new DetailFieldRow (_("Spotter"));
        detail_spot_time_row = new DetailFieldRow (_("Time"));
        detail_spotter_comment_row = new DetailFieldRow (_("Comment"), true);
        detail_history_row = new DetailLinkRow (_("View Spot History"));
        detail_last_spot_list.append (detail_spotter_row);
        detail_last_spot_list.append (detail_spot_time_row);
        detail_last_spot_list.append (detail_spotter_comment_row);
        detail_last_spot_list.append (detail_history_row);
    }

    public void set_spot (Spot? spot) {
        if (callsign_cache_handler != 0) {
            if (SignalHandler.is_connected (Application.callsign_cache, callsign_cache_handler))
                SignalHandler.disconnect (Application.callsign_cache, callsign_cache_handler);
            callsign_cache_handler = 0;
        }

        current_spot = spot;

        if (spot == null) {
            weather_request_serial++;
            detail_stack.visible_child_name = "empty";
            return;
        }

        populate (spot);
        detail_stack.visible_child_name = "detail";

        fetch_avatar.begin ((obj, res) => { fetch_avatar.end (res); });
        load_weather.begin (spot, weather_request_serial);
        callsign_cache_handler = Application.callsign_cache.entry_updated.connect ((cs) => {
            if (cs == spot.callsign)
                update_avatar_from_cache (cs);
        });
    }

    private void populate (Spot spot) {
        weather_request_serial++;
        detail_avatar.text = spot.callsign;
        detail_callsign.label = "%s @ %s".printf (spot.callsign, spot.park_ref);
        var cached_activator = Application.callsign_cache.peek_callsign (spot.callsign);
        update_activator_profile (cached_activator);
        detail_park_name.label = spot.park_name;
        set_weather_loading ();

        detail_frequency_row.value = "%s kHz".printf (
            format_frequency_khz (spot.frequency_khz)
        );
        detail_mode_row.value = spot.mode;
        detail_spot_count_row.value = ngettext ("%d spot", "%d spots", spot.spot_count)
            .printf (spot.spot_count);

        var locations = spot.location_desc.split (",", -1);
        var loc_str = "";
        if (locations.length <= 2) {
            for (int i = 0; i < locations.length; i++) {
                string location_key = locations[i].strip ();
                var location = Application.pota_client.lookup_location (location_key);
                string display = location != null ? location.to_string () : location_key;
                loc_str += (i > 0 ? "\n" : "") + display;
            }
        } else {
            loc_str = spot.location_desc;
        }
        detail_location_row.value = loc_str;

        detail_grid_row.visible = spot.coordinate != null;
        if (spot.coordinate != null) {
            detail_grid_row.value = "%.4f, %.4f".printf (
                spot.coordinate.latitude,
                spot.coordinate.longitude
            );
            var now = new DateTime.now_utc ();
            var sun_times = Astronomy.sun_rise_set_times (now, spot.coordinate);
            var moon_times = Astronomy.moon_rise_set_times (now, spot.coordinate);

            detail_sun_row.visible = (sun_times.rise != null) || (sun_times.set != null);
            detail_sun_row.first_value = format_time_label (sun_times.rise);
            detail_sun_row.second_value = format_time_label (sun_times.set);

            detail_moon_row.visible = (moon_times.rise != null) || (moon_times.set != null);
            detail_moon_row.first_value = format_time_label (moon_times.rise);
            detail_moon_row.second_value = format_time_label (moon_times.set);
        } else {
            detail_grid_row.value = "";
            detail_sun_row.visible = false;
            detail_sun_row.first_value = "";
            detail_sun_row.second_value = "";
            detail_moon_row.visible = false;
            detail_moon_row.first_value = "";
            detail_moon_row.second_value = "";
        }

        var has_location = Application.settings.get_string ("location") != "" && spot.distance >= 0;
        detail_distance_row.visible = has_location;
        detail_bearing_row.visible = has_location;
        if (has_location) {
            var use_metric = Application.settings.get_boolean ("use-metric");
            var unit = use_metric ? _("km") : _("mi");
            var dist = use_metric ? spot.distance : spot.distance * 0.6213712;
            detail_distance_row.value = "%'d %s".printf ((int)dist, unit);
            detail_bearing_row.value = "%d° %s".printf ((int)spot.bearing,
                bearing_to_compass (spot.bearing));
        }

        detail_spotter_row.value = spot.spotter;
        detail_spot_time_row.value = humanize_ago (spot.spot_time);

        var has_spotter_comment = (spot.spotter_comment ?? "").strip () != "";
        detail_spotter_comment_row.visible = has_spotter_comment;
        detail_spotter_comment_row.value = has_spotter_comment ? spot.spotter_comment : "";

        detail_activator_comment_row.visible = (spot.activator_comment ?? "").strip () != "";
        detail_activator_comment_row.value = detail_activator_comment_row.visible ?
            spot.activator_comment : "";

        var escaped = GLib.Uri.escape_string (spot.park_ref, null, false);
        park_url = @"https://pota.app/#/park/$escaped";
        var escaped_callsign = GLib.Uri.escape_string (
            pota_profile_callsign (spot.callsign),
            null,
            false
        );
        activator_url = @"https://pota.app/#/profile/$escaped_callsign";
    }

    private string format_time_label (DateTime? time) {
        if (time == null)
            return "—";

        return time.to_utc ().format ("%H:%M UTC");
    }

    private string weather_temperature_label (double temperature) {
        var unit = Application.settings.get_boolean ("use-metric") ? "C" : "F";
        return "%.0f°%s".printf (temperature, unit);
    }

    private unowned string weather_icon_name (WeatherData data) {
        switch (data.icon_code) {
            case "01d":
                return "sun-outline-symbolic";
            case "01n":
                return "moon-outline-symbolic";
            case "02d":
            case "03d":
                return "few-clouds-outline-symbolic";
            case "02n":
            case "03n":
                return "moon-clouds-outline-symbolic";
            case "04d":
            case "04n":
                return "clouds-outline-symbolic";
            case "09d":
            case "09n":
                return "rain-scattered-outline-symbolic";
            case "10d":
            case "10n":
                return "rain-outline-symbolic";
            case "11d":
            case "11n":
                return "storm-outline-symbolic";
            case "13d":
            case "13n":
                return "snow-outline-symbolic";
            case "50d":
            case "50n":
                return "fog-symbolic";
            default:
                var condition = data.condition.down ();
                if (condition.contains ("thunder"))
                    return "storm-outline-symbolic";
                if (condition.contains ("snow") || condition.contains ("sleet"))
                    return "snow-outline-symbolic";
                if (condition.contains ("rain") || condition.contains ("drizzle"))
                    return "rain-outline-symbolic";
                if (condition.contains ("fog") || condition.contains ("mist") ||
                    condition.contains ("haze") || condition.contains ("smoke")) {
                    return "fog-symbolic";
                }
                if (condition.contains ("wind"))
                    return "windy-symbolic";
                if (condition.contains ("cloud"))
                    return "clouds-outline-symbolic";
                return "sun-outline-symbolic";
        }
    }

    private void set_weather_loading () {
        weather_summary_card.visible = false;
        wx_conditions.icon_name = "clouds-outline-symbolic";
        wx_conditions_txt.label = _("Loading weather…");
        wx_temp.label = "—";
        wx_humidity.label = "—";
    }

    private void set_weather_unavailable () {
        weather_summary_card.visible = false;
    }

    private void apply_weather (WeatherData data) {
        weather_summary_card.visible = true;
        wx_conditions.icon_name = weather_icon_name (data);
        wx_conditions_txt.label = data.condition;
        wx_temp.label = weather_temperature_label (data.temperature);
        wx_humidity.label = _("%d%%").printf (data.relative_humidity);
    }

    private async void load_weather (Spot spot, uint request_serial) {
        try {
            var fetched = yield Application.weather_cache.get_weather_for_spot (spot);
            if ((current_spot == spot) && (weather_request_serial == request_serial))
                apply_weather (fetched);
        } catch (Error err) {
            warning ("Failed to load weather for %s: %s", spot.park_ref, err.message);
            if ((current_spot == spot) && (weather_request_serial == request_serial))
                set_weather_unavailable ();
        }
    }

    private async void fetch_avatar () {
        if (current_spot == null)
            return;

        var callsign = current_spot.callsign;
        var texture = yield Application.callsign_cache.get_avatar_for (callsign);
        if ((current_spot != null) && (current_spot.callsign == callsign))
            detail_avatar.custom_image = texture;
    }

    private void update_avatar_from_cache (string callsign) {
        detail_avatar.custom_image = Application.callsign_cache.peek_avatar (callsign);
        var activator = Application.callsign_cache.peek_callsign (callsign);
        update_activator_profile (activator);
    }

    private void update_activator_profile (Activator? activator) {
        detail_operator_name_row.value = ((activator != null) && (activator.name != "")) ?
            activator.name : "—";
        detail_operator_qth_row.value = ((activator != null) && (activator.qth != "")) ?
            activator.qth : "—";

        if (activator != null) {
            detail_operator_endorsements_row.value = activator.endorsements.to_string ();
        } else {
            detail_operator_endorsements_row.value = "—";
        }
    }

    public void set_action_buttons_visible (bool visible) {
        detail_tune_button.visible = visible && Application.is_radio_configured;
        detail_spot_button.visible = visible;
        update_tune_button_state ();
    }

    private void update_tune_button_state () {
        detail_tune_button.sensitive = detail_tune_button.visible &&
            Application.radio_control.is_rig_connected;
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
        var parent = get_root () as Gtk.Window;
        if (parent == null)
            return;
#if ARTEMIS_UNIX
        new ParkDetailsView (parent, _("Park Details"), park_url).present ();
#else
        GLib.AppInfo.launch_default_for_uri (park_url, null);
#endif
    }

    private void on_activator_clicked () {
        if (activator_url == null)
            return;
#if ARTEMIS_UNIX
        var parent = get_root () as Gtk.Window;
        if (parent == null)
            return;
        new ParkDetailsView (parent, _("Activator Details"), activator_url).present ();
#else
        GLib.AppInfo.launch_default_for_uri (activator_url, null);
#endif
    }

    ~SpotDetail () {
        if (callsign_cache_handler != 0 &&
            SignalHandler.is_connected (Application.callsign_cache, callsign_cache_handler))
            SignalHandler.disconnect (Application.callsign_cache, callsign_cache_handler);
        if (pota_locations_handler != 0 &&
            SignalHandler.is_connected (Application.pota_client, pota_locations_handler))
            SignalHandler.disconnect (Application.pota_client, pota_locations_handler);
        if (radio_connected_handler != 0 &&
            SignalHandler.is_connected (Application.radio_control, radio_connected_handler))
            SignalHandler.disconnect (Application.radio_control, radio_connected_handler);
        if (radio_disconnected_handler != 0 &&
            SignalHandler.is_connected (Application.radio_control, radio_disconnected_handler))
            SignalHandler.disconnect (Application.radio_control, radio_disconnected_handler);
        if (radio_error_handler != 0 &&
            SignalHandler.is_connected (Application.radio_control, radio_error_handler))
            SignalHandler.disconnect (Application.radio_control, radio_error_handler);
    }
}
