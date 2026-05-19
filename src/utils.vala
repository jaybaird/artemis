/* src/utils.vala
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

using GLib;
using Shumate;

public static inline uint clampi (uint v, uint min, uint max) {
    return (v < min) ? min : (max < v) ? max : v;
}

public static inline double clamp (double v, double min, double max) {
    return (v < min) ? min : (max < v) ? max : v;
}

public static T random_choice<T> (T[] array) {
    if (array.length == 0)
        critical ("Cannot choose from an empty array");
    return array[Random.int_range (0, array.length)];
}

public static Gee.ArrayList<T> to_array<T> (Gee.Iterator<T> iter) {
    var list = new Gee.ArrayList<T> ();

    while (iter.next ()) {
        list.add (iter.get ());
    }

    return list;
}

public static string format_vfo (double freq_khz) {
    uint64 freq_hz = (uint64)Math.round (freq_khz * 1000.0);
    uint64 mhz = freq_hz / 1000000;
    uint64 khz = (freq_hz / 1000) % 1000;
    uint64 hz = freq_hz % 1000;

    return "%lu.%03lu.%02lu".printf ((ulong)mhz, (ulong)khz, (ulong)(hz / 10));
}

public static int scaled_avatar_size (int base_size) {
    var settings = Gtk.Settings.get_default ();
    if (settings == null)
        return base_size;

    var font_desc = Pango.FontDescription.from_string (settings.gtk_font_name);
    var font_size = font_desc.get_size ();
    if (font_size <= 0)
        return base_size;

    var scale = (double) font_size / (10.0 * Pango.SCALE);
    return (int) Math.round (base_size * scale);
}

public async Gdk.Texture load_texture_from_bytes (GLib.Bytes bytes) throws Error {
    var loader = new Gly.Loader.for_bytes (bytes);
    var image = yield loader.load_async (null);
    var frame = yield image.next_frame_async (null);
    return GlyGtk4.frame_get_texture (frame);
}

public static string pota_profile_callsign (string callsign) {
    var stripped_callsign = callsign.strip ();
    var profile_callsign = "";

    foreach (var part in stripped_callsign.split ("/")) {
        var candidate = part.strip ();
        if (candidate.length > profile_callsign.length)
            profile_callsign = candidate;
    }

    return (profile_callsign != "") ? profile_callsign : stripped_callsign;
}

public sealed class SpotBadgeInfo : Object {
    public string icon_name { get; construct; }
    public string tooltip { get; construct; }
    public string css_class { get; construct; }

    public SpotBadgeInfo (string icon_name, string tooltip, string css_class) {
        Object (
            icon_name: icon_name,
            tooltip: tooltip,
            css_class: css_class
        );
    }
}

public static Gee.ArrayList<SpotBadgeInfo> collect_spot_badges (Spot spot) {
    var badges = new Gee.ArrayList<SpotBadgeInfo> ();

    if (spot.heard_recently) {
        badges.add (new SpotBadgeInfo (
            "headphones-symbolic",
            _("Heard recently"),
            "badge-heard-recently"
        ));
    }

    if (spot.is_new_park && Application.settings.get_boolean ("highlight-unhunted-parks")) {
        badges.add (new SpotBadgeInfo (
            "starred-symbolic",
            _("New park"),
            "badge-new-park"
        ));
    }

    if (spot.was_hunted_today) {
        badges.add (new SpotBadgeInfo (
            "verified-checkmark-symbolic",
            _("Hunted today"),
            "badge-hunted-today"
        ));
    } else if (!spot.is_new_park) {
        badges.add (new SpotBadgeInfo (
            "clock-alt-symbolic",
            _("Previously hunted"),
            "badge-previously-hunted"
        ));
    }

    if (spot.is_new_band) {
        badges.add (new SpotBadgeInfo (
            "sound-wave-add-symbolic",
            _("New band"),
            "badge-new-band"
        ));
    }

    return badges;
}

public static Gtk.Image create_spot_badge_image (SpotBadgeInfo badge) {
    var image = new Gtk.Image.from_icon_name (badge.icon_name);
    image.tooltip_text = badge.tooltip;
    image.add_css_class ("spot-badge");
    image.add_css_class (badge.css_class);
    return image;
}

public static void populate_spot_badges (Gtk.Box box, Spot spot) {
    var child = box.get_first_child ();
    while (child != null) {
        var next = child.get_next_sibling ();
        box.remove (child);
        child = next;
    }

    foreach (var badge in collect_spot_badges (spot))
        box.append (create_spot_badge_image (badge));
}

public static bool spot_matches_current_filters (Spot spot, string band_filter) {
    if (spot == null)
        return false;

    if ((band_filter != "All") && (spot.band != band_filter))
        return false;

    if (Application.settings.get_boolean ("hide-qrt") &&
        spot.activator_comment.down ().contains ("qrt"))
        return false;

    if (Application.settings.get_boolean ("hide-hunted") && spot.was_hunted_today)
        return false;

    var stale_minutes = Application.settings.get_int ("hide-older-than");
    var now = new DateTime.now_utc ();
    var expires = spot.spot_time.add_minutes (stale_minutes);
    if (now.compare (expires) > 0)
        return false;

    if ((Application.state.current_program_filter != null) &&
        !spot.park_ref.down ().has_prefix (Application.state.current_program_filter.down ()))
        return false;

    if ((Application.state.current_mode_filter != null) &&
        !spot.mode.down ().contains (Application.state.current_mode_filter.down ()))
        return false;

    if (Application.state.current_search_text != null) {
        var needle = Application.state.current_search_text.down ();
        if (!(spot.callsign.down ().contains (needle) ||
              spot.park_ref.down ().contains (needle) ||
              spot.park_name.down ().contains (needle))) {
            return false;
        }
    }

    return true;
}

namespace Distance {
    public errordomain MaidenheadError {
        TOO_SHORT,
    }

    public inline static double to_radians (double degrees) {
        return degrees * (Math.PI / 180.0);
    }

    // Convert radians to degrees
    public inline static double to_degrees (double radians) {
        return radians * (180.0 / Math.PI);
    }

    // Parse a Maidenhead locator to decimal degrees (approx center of square)
    public static Coordinate maidenhead_to_latlon (string grid) throws Error {
        if (grid.length < 4)
            throw new MaidenheadError.TOO_SHORT ("Grid locator %s is too short", grid);

        var loc = grid.ascii_down ();      // simplify handling
        double lon = (loc[0] - 'a') * 20.0 - 180.0;
        double lat = (loc[1] - 'a') * 10.0 - 90.0;

        lon += (loc[2] - '0') * 2.0;
        lat += (loc[3] - '0') * 1.0;

        if (loc.length >= 6) {
            lon += (loc[4] - 'a') * (5.0 / 60.0);
            lat += (loc[5] - 'a') * (2.5 / 60.0);
            // add half of subsquare to get center
            lon += 2.5 / 60.0;
            lat += 1.25 / 60.0;
        } else {
            // add half of square for center if no subsquare
            lon += 1.0;
            lat += 0.5;
        }

        return new Coordinate.full (lat, lon);
    }

    public static double haversine_distance_km (Coordinate a, Coordinate b) {
        return a.distance (b) / 1000.0;
    }

    // Initial bearing from point A to B
    public static double bearing (Coordinate a, Coordinate b) {
        double lat1 = to_radians (a.latitude);
        double lat2 = to_radians (b.latitude);
        double dlon = to_radians (b.longitude - a.longitude);

        double y = Math.sin (dlon) * Math.cos (lat2);
        double x = Math.cos (lat1) * Math.sin (lat2) - Math.sin (lat1) * Math.cos (
            lat2) * Math.cos (dlon);
        double brng = Math.atan2 (y, x);
        brng = to_degrees (brng);
        return (brng + 360) % 360;      // normalize 0–360°
    }
} /* namespace Distance */
