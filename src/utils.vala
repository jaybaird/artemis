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
    var filter = new SpotFilterState (
        band_filter,
        Application.state.current_mode_filter,
        Application.state.current_program_filter,
        Application.state.current_search_text,
        Application.settings.get_boolean ("hide-qrt"),
        Application.settings.get_boolean ("hide-hunted"),
        Application.settings.get_int ("hide-older-than")
    );
    var snapshot = new SpotFilterSnapshot (
        spot.callsign,
        spot.park_ref,
        spot.park_name,
        spot.activator_comment,
        spot.band,
        spot.mode,
        spot.spot_time,
        spot.was_hunted_today
    );
    return spot_matches_filter (snapshot, filter);
}

public static Gdk.RGBA rgba (double red, double green, double blue, double alpha) {
    var color = Gdk.RGBA ();
    color.red = (float) red;
    color.green = (float) green;
    color.blue = (float) blue;
    color.alpha = (float) alpha;
    return color;
}
