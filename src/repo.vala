/* src/repo.vala
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

using Gee;
public sealed class SpotRepo : Object, Artemis.Wsjtx.SpotLookup {
    private const int64 HEARD_CACHE_SECONDS = Spot.HEARD_RECENTLY_TIMEOUT_SECONDS;

    public GLib.ListStore store { get; construct; }

    public signal void busy_changed (bool busy);
    public signal void refreshed (uint spots_updated);
    public signal void log_status_refreshed ();
    public signal void update_error (Error err);
    public signal void current_spot_changed (Quark spot_hash);

    public Gtk.StringList program_model { get; private set; }
    public Gtk.StringList mode_model { get; private set; }
    public uint64 tracked_spot_hash { get; set; default = uint64.MAX; }

    public HashMap<string, int> band_counts;
    private bool update_in_progress = false;
    private bool update_pending = false;
    private HashSet<uint> notified_alert_hashes;
    private HashMap<string, int64?> heard_callsign_times;
    private HashMap<string, int64?> heard_reciprocal_callsign_times;

    public SpotRepo () {
        Object ();
    }

    construct {
        store = new GLib.ListStore (typeof (Spot));
        program_model = new Gtk.StringList ({});
        mode_model = new Gtk.StringList ({});
        band_counts = new HashMap<string, int> ();
        notified_alert_hashes = new HashSet<uint> ();
        heard_callsign_times = new HashMap<string, int64?> ();
        heard_reciprocal_callsign_times = new HashMap<string, int64?> ();
    }

    public Spot? get_spot (Quark spot_hash) {
        for (uint i = 0 ; i < store.get_n_items () ; i++) {
            var spot = store.get_item (i) as Spot;
            if ((spot != null) && (spot.hash == spot_hash))
                return spot;
        }

        return null;
    }

    public Spot? get_spot_for_callsign (string callsign) {
        var normalized_exact = callsign.strip ().up ();
        var normalized_profile = pota_profile_callsign (callsign).strip ().up ();
        if ((normalized_exact == "") && (normalized_profile == ""))
            return null;

        Spot? profile_match = null;
        for (uint i = 0 ; i < store.get_n_items () ; i++) {
            var spot = store.get_item (i) as Spot;
            if (spot == null)
                continue;

            var spot_exact = spot.callsign.strip ().up ();
            var spot_profile = pota_profile_callsign (spot.callsign).strip ().up ();
            if (spot_exact == normalized_exact)
                return spot;

            if ((profile_match == null) && (spot_profile == normalized_profile))
                profile_match = spot;
        }

        return profile_match;
    }

    public Spot? get_spot_for_decode_text (string decode_text) {
        var heard_callsign = Artemis.Wsjtx.heard_callsign_from_decode_text (decode_text);
        if (heard_callsign == "")
            return null;

        var heard_profile = pota_profile_callsign (heard_callsign).strip ().up ();
        Spot? profile_match = null;
        for (uint i = 0 ; i < store.get_n_items () ; i++) {
            var spot = store.get_item (i) as Spot;
            if (spot == null)
                continue;

            var spot_exact = spot.callsign.strip ().up ();
            var spot_profile = pota_profile_callsign (spot.callsign).strip ().up ();
            if ((spot_exact != "") && spot_exact == heard_callsign)
                return spot;

            if ((profile_match == null) &&
                (spot_profile != "") &&
                (spot_profile == heard_callsign || spot_profile == heard_profile)) {
                profile_match = spot;
            }
        }

        return profile_match;
    }

    public int get_band_count (string band) {
        if (band_counts.has_key (band)) {
            return band_counts.get (band);
        }

        return 0;
    }

    private void annotate_spot_log_status (
        Spot spot,
        SpotLogStatusSnapshot snapshot
    ) {
        var was_hunted_today = snapshot.hunted_today.contains (spot.park_ref);
        var is_new_park = !snapshot.hunted_parks.contains (spot.park_ref);
        var is_new_band = !is_new_park && !snapshot.hunted_park_bands.contains (
            SpotLogStatusSnapshot.park_band_key (spot.park_ref, spot.band)
        );

        spot.set_log_status (was_hunted_today, is_new_park, is_new_band);
    }

    public void mark_spot_heard (Spot spot) {
        var now = monotonic_seconds ();
        foreach (var key in callsign_cache_keys (spot.callsign))
            heard_callsign_times[key] = now;

        spot.mark_heard_recently ();
    }

    public void mark_spot_heard_reciprocally (Spot spot) {
        mark_callsign_heard_reciprocally (spot.callsign);
    }

    public void mark_callsign_heard_reciprocally (string callsign) {
        var now = monotonic_seconds ();
        foreach (var key in callsign_cache_keys (callsign))
            heard_reciprocal_callsign_times[key] = now;

        var spot = get_spot_for_callsign (callsign);
        if (spot != null)
            spot.mark_heard_reciprocally ();
    }

    private void apply_heard_status (Spot spot) {
        prune_heard_callsigns (heard_callsign_times);

        var now = monotonic_seconds ();
        foreach (var key in callsign_cache_keys (spot.callsign)) {
            if (!heard_callsign_times.has_key (key))
                continue;

            var age = now - heard_callsign_times[key];
            if (age >= HEARD_CACHE_SECONDS)
                continue;

            spot.mark_heard_recently ((uint) (HEARD_CACHE_SECONDS - age));
            return;
        }
    }

    private void apply_reciprocal_heard_status (Spot spot) {
        prune_heard_callsigns (heard_reciprocal_callsign_times);

        var now = monotonic_seconds ();
        foreach (var key in callsign_cache_keys (spot.callsign)) {
            if (!heard_reciprocal_callsign_times.has_key (key))
                continue;

            var age = now - heard_reciprocal_callsign_times[key];
            if (age >= HEARD_CACHE_SECONDS)
                continue;

            spot.mark_heard_reciprocally ((uint) (HEARD_CACHE_SECONDS - age));
            return;
        }
    }

    public void refresh_log_status () {
        Error? snapshot_error = null;
        var log_status_snapshot = Application.spot_database.load_log_status_snapshot (
            new DateTime.now_utc (),
            out snapshot_error
        );
        if (snapshot_error != null) {
            warning ("Unable to refresh spot log status snapshot: %s",
                snapshot_error.message);
            return;
        }

        for (uint i = 0; i < store.get_n_items (); i++) {
            var spot = store.get_item (i) as Spot;
            if (spot != null)
                annotate_spot_log_status (spot, log_status_snapshot);
        }

        log_status_refreshed ();
    }

    public void refresh_log_status_for_added_qso (Spot logged_spot) {
        if (logged_spot == null || logged_spot.park_ref.strip () == "")
            return;

        var logged_park_ref = logged_spot.park_ref.strip ();
        var logged_band = logged_spot.band;
        var logged_today = logged_spot.spot_time.to_utc ().format ("%Y-%m-%d") ==
            new DateTime.now_utc ().format ("%Y-%m-%d");
        var changed = false;

        for (uint i = 0; i < store.get_n_items (); i++) {
            var spot = store.get_item (i) as Spot;
            if (spot == null || spot.park_ref.strip () != logged_park_ref)
                continue;

            var was_hunted_today = spot.was_hunted_today || logged_today;
            var is_new_park = false;
            var is_new_band = spot.band == logged_band
                ? false
                : spot.is_new_park || spot.is_new_band;

            if (spot.was_hunted_today != was_hunted_today ||
                spot.is_new_park != is_new_park ||
                spot.is_new_band != is_new_band) {
                changed = true;
            }

            spot.set_log_status (was_hunted_today, is_new_park, is_new_band);
        }

        if (changed)
            log_status_refreshed ();
    }

    private void prune_heard_callsigns (HashMap<string, int64?> callsign_times) {
        var now = monotonic_seconds ();
        var expired = new ArrayList<string> ();
        foreach (var entry in callsign_times.entries) {
            if (now - entry.value >= HEARD_CACHE_SECONDS)
                expired.add (entry.key);
        }

        foreach (var key in expired)
            callsign_times.unset (key);
    }

    private static ArrayList<string> callsign_cache_keys (string callsign) {
        var keys = new ArrayList<string> ();
        var exact = callsign.strip ().up ();
        var profile = pota_profile_callsign (callsign).strip ().up ();
        if (exact != "")
            keys.add (exact);
        if (profile != "" && profile != exact)
            keys.add (profile);
        return keys;
    }

    private static int64 monotonic_seconds () {
        return GLib.get_monotonic_time () / 1000000;
    }

    public async void update_spots () {
        if (update_in_progress) {
            update_pending = true;
            return;
        }

        update_in_progress = true;

        do {
            update_pending = false;
            busy_changed (true);

            var spots_updated = 0u;

            try {
                var unique_callsigns = new HashSet<string> ();
                var parsed_spots = new ArrayList<Spot> ();
                var parsed_band_counts = new HashMap<string, int> ();
                var programs = new HashSet<string> ();
                var modes = new HashSet<string> ();
                var spots = yield Application.pota_client.fetch_spots ();

                if ((spots != null) &&
                    (spots.get_node_type () == Json.NodeType.ARRAY)) {
                    var spots_array = spots.get_array ();
                    for (uint i = 0 ; i < spots_array.get_length () ; i++) {
                        try {
                            var element = spots_array.get_element (i).get_object ();
                            var spot = new Spot.from_json (element);

                            unique_callsigns.add (spot.callsign);
                            unique_callsigns.add (spot.spotter);

                            if (spot.park_ref.contains ("-")) {
                                var program = spot.park_ref.split ("-", 2)[0];
                                programs.add (program);
                            }
                            if (spot.mode.strip () != "")
                                modes.add (spot.mode);
                            if (parsed_band_counts.has_key (spot.band)) {
                                parsed_band_counts[spot.band] =
                                    parsed_band_counts[spot.band] + 1;
                            } else {
                                parsed_band_counts[spot.band] = 1;
                            }
                            apply_heard_status (spot);
                            apply_reciprocal_heard_status (spot);
                            parsed_spots.add (spot);
                        } catch (Error err) {
                            warning ("Skipping malformed POTA spot at index %u: %s",
                                i, err.message);
                        }
                    }
                }

                Error? snapshot_error = null;
                var log_status_snapshot = Application.spot_database.load_log_status_snapshot (
                    new DateTime.now_utc (),
                    out snapshot_error
                );
                if (snapshot_error != null) {
                    warning ("Unable to load spot log status snapshot: %s",
                        snapshot_error.message);
                    foreach (var spot in parsed_spots) {
                        spot.set_log_status (false, false, false);
                    }
                } else {
                    foreach (var spot in parsed_spots) {
                        annotate_spot_log_status (spot, log_status_snapshot);
                    }
                }

                notify_matching_spot_alerts (parsed_spots);

                var programs_sorted = new ArrayList<string> ();
                foreach (var program in programs) {
                    programs_sorted.add (program);
                }
                programs_sorted.sort ((a, b) => { return strcmp (a, b); });

                var modes_sorted = new ArrayList<string> ();
                foreach (var known_mode in RadioConstants.MODES) {
                    if (modes.contains (known_mode))
                        modes_sorted.add (known_mode);
                }
                var unknown_modes = new ArrayList<string> ();
                foreach (var mode in modes) {
                    var is_known = false;
                    foreach (var known_mode in RadioConstants.MODES) {
                        if (mode == known_mode) {
                            is_known = true;
                            break;
                        }
                    }
                    if (!is_known)
                        unknown_modes.add (mode);
                }
                unknown_modes.sort ((a, b) => { return strcmp (a, b); });
                foreach (var mode in unknown_modes) {
                    modes_sorted.add (mode);
                }

                band_counts.clear ();
                foreach (var entry in parsed_band_counts.entries) {
                    band_counts[entry.key] = entry.value;
                }

                var new_program_model = new Gtk.StringList ({});
                var new_mode_model = new Gtk.StringList ({});

                GLib.Object[] additions = new GLib.Object[parsed_spots.size];
                for (int i = 0; i < parsed_spots.size; i++)
                    additions[i] = parsed_spots[i];
                store.splice (0, store.get_n_items (), additions);
                spots_updated = parsed_spots.size;

                new_program_model.append (_("All"));
                foreach (var program in programs_sorted) {
                    new_program_model.append (program);
                }
                new_mode_model.append (_("All"));
                foreach (var mode in modes_sorted) {
                    new_mode_model.append (mode);
                }

                program_model = new_program_model;
                mode_model = new_mode_model;

                busy_changed (false);
                refreshed (spots_updated);
            } catch (Error err) {
                busy_changed (false);
                update_error (err);
            }
        } while (update_pending);

        update_in_progress = false;
    } /* update_spots */

    private void notify_matching_spot_alerts (ArrayList<Spot> spots) {
        if (!Application.settings.get_boolean ("spot-alerts-enabled"))
            return;

        var keywords = normalized_alert_keywords ();
        if (keywords.size == 0)
            return;

        foreach (var spot in spots) {
            var hash = (uint) spot.hash;
            if (notified_alert_hashes.contains (hash))
                continue;

            if (!spot_matches_keywords (spot, keywords))
                continue;

            notified_alert_hashes.add (hash);
            Application.app.send_spot_alert (spot);
        }
    }

    private ArrayList<string> normalized_alert_keywords () {
        var keywords = new ArrayList<string> ();
        foreach (var keyword in Application.settings.get_strv ("spot-alert-keywords")) {
            var normalized = keyword.strip ().down ();
            if (normalized != "")
                keywords.add (normalized);
        }
        return keywords;
    }

    private bool spot_matches_keywords (Spot spot, ArrayList<string> keywords) {
        var haystack = "%s\n%s\n%s\n%s\n%s\n%s\n%s\n%s".printf (
            spot.callsign,
            spot.park_ref,
            spot.park_name,
            spot.location_desc,
            spot.grid4,
            spot.grid6,
            spot.activator_comment,
            spot.spotter_comment
        ).down ();

        foreach (var keyword in keywords) {
            if (haystack.contains (keyword))
                return true;
        }

        return false;
    }
}     /* class SpotRepo */
