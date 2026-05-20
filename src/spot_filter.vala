/* src/spot_filter.vala
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

[Compact]
public class SpotFilterSnapshot {
    public string callsign;
    public string park_ref;
    public string park_name;
    public string activator_comment;
    public string band;
    public string mode;
    public DateTime spot_time;
    public bool was_hunted_today;

    public SpotFilterSnapshot (
        string callsign,
        string park_ref,
        string park_name,
        string activator_comment,
        string band,
        string mode,
        DateTime spot_time,
        bool was_hunted_today
    ) {
        this.callsign = callsign;
        this.park_ref = park_ref;
        this.park_name = park_name;
        this.activator_comment = activator_comment;
        this.band = band;
        this.mode = mode;
        this.spot_time = spot_time;
        this.was_hunted_today = was_hunted_today;
    }

}

[Compact]
public class SpotFilterState {
    public string band;
    public string? mode;
    public string? program;
    public string? search_text;
    public bool hide_qrt;
    public bool hide_hunted;
    public int hide_older_than_minutes;
    public DateTime now_utc;

    public SpotFilterState (
        string band,
        string? mode,
        string? program,
        string? search_text,
        bool hide_qrt,
        bool hide_hunted,
        int hide_older_than_minutes,
        DateTime? now_utc = null
    ) {
        this.band = band;
        this.mode = mode;
        this.program = program;
        this.search_text = search_text;
        this.hide_qrt = hide_qrt;
        this.hide_hunted = hide_hunted;
        this.hide_older_than_minutes = hide_older_than_minutes;
        this.now_utc = now_utc ?? new DateTime.now_utc ();
    }
}

public static bool spot_matches_filter (SpotFilterSnapshot spot, SpotFilterState filter) {
    if ((spot == null) || (filter == null))
        return false;

    if ((filter.band != "All") && (spot.band != filter.band))
        return false;

    if (filter.hide_qrt && spot.activator_comment.down ().contains ("qrt"))
        return false;

    if (filter.hide_hunted && spot.was_hunted_today)
        return false;

    if (filter.hide_older_than_minutes > 0) {
        var expires = spot.spot_time.add_minutes (filter.hide_older_than_minutes);
        if (filter.now_utc.compare (expires) > 0)
            return false;
    }

    if ((filter.program != null) &&
        !spot.park_ref.down ().has_prefix (filter.program.down ()))
        return false;

    if ((filter.mode != null) &&
        !spot.mode.down ().contains (filter.mode.down ()))
        return false;

    if (filter.search_text != null) {
        var needle = filter.search_text.down ();
        if (!(spot.callsign.down ().contains (needle) ||
              spot.park_ref.down ().contains (needle) ||
              spot.park_name.down ().contains (needle))) {
            return false;
        }
    }

    return true;
}
