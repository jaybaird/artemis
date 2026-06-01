/* src/utils/spot_format.vala
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
        return _("%ld seconds ago").printf ((long) sec);
    if (min == 1)
        return _("a minute ago");
    if (min < 60)
        return _("%ld minutes ago").printf ((long) min);
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
        return _("%lds").printf ((long) sec);
    if (min < 60)
        return _("%ldm ago").printf ((long) min);
    return _("%ldh ago").printf ((long) hr);
}

public string bearing_to_compass (double bearing) {
    bearing = Math.fmod (bearing, 360.0);
    if (bearing < 0)
        bearing += 360.0;

    string[] directions = {
        _("N"),
        _("NE"),
        _("E"),
        _("SE"),
        _("S"),
        _("SW"),
        _("W"),
        _("NW")
    };
    int index = (int) Math.floor ((bearing + 22.5) / 45.0) % 8;
    return directions[index];
}
