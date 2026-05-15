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
using Gdk;

public class CallsignCacheEntry : Object {
    public Activator activator { get; construct; }
    public uint64 expires_at { get; construct; }
    public Gdk.Texture ? avatar { get; set; default = null; }
    public CallsignCacheEntry (Activator activator, uint64 expires_at) {
        Object (
            activator : activator,
            expires_at: expires_at
        );
    }
}

public class CallsignCache : Object {
    private HashTable<string, CallsignCacheEntry> ham_cache;
    private HashSet<string> avatar_fetch_inflight;
    private Soup.Session avatar_session;
    public uint ttl_seconds { get; construct; default = 3600; }
    public signal void entry_updated (string callsign);

    public CallsignCache (uint ttl_seconds) {
        Object (
            ttl_seconds : ttl_seconds
        );
    }

    ~CallsignCache () {
        if (avatar_session != null) {
            avatar_session.abort ();
            avatar_session = null;
        }
    }

    construct {
        ham_cache = new HashTable<string, CallsignCacheEntry> (GLib.str_hash,
            GLib.str_equal);
        avatar_fetch_inflight = new HashSet<string> ();
        avatar_session = new Soup.Session ();
        var cache_dir = Path.build_filename (Environment.get_user_cache_dir (),
            "artemis");
        var cache = new Soup.Cache (cache_dir, Soup.CacheType.SINGLE_USER);
        cache.set_max_size (50 * 1024 * 1024);
        avatar_session.add_feature (cache);
        avatar_session.timeout = 3;
        avatar_session.user_agent = "Artemis/1.0.0";
    }

    private bool is_entry_expired (CallsignCacheEntry? entry) {
        if (entry == null)
            return true;
        return GLib.get_monotonic_time () > entry.expires_at;
    }

    public void clear () {
        ham_cache.remove_all ();
        avatar_fetch_inflight.clear ();
    }

    public async void load_callsigns (HashSet<string> callsigns) {
        foreach (var callsign in callsigns) {
            yield get_callsign (callsign);
        }
    }

    public Gdk.Texture? peek_avatar (string callsign) {
        var entry = ham_cache.lookup (callsign);
        if (is_entry_expired (entry) || (entry == null))
            return null;
        return entry.avatar;
    }

    public Activator? peek_callsign (string callsign) {
        var entry = ham_cache.lookup (callsign);
        if (is_entry_expired (entry) || (entry == null))
            return null;
        return entry.activator;
    }

    public async Gdk.Texture? get_avatar_for (string callsign) {
        var entry = yield get_callsign (callsign);

        if (entry == null)
            return null;

        var cached_entry = ham_cache.lookup (callsign);
        if ((cached_entry != null) && (cached_entry.avatar != null))
            return cached_entry.avatar;

        if (avatar_fetch_inflight.contains (callsign))
            return null;

        avatar_fetch_inflight.add (callsign);
        Gdk.Texture? avatar = null;
        try {
            var gravatar_hash = entry.gravatar_hash;
            if ((gravatar_hash != null) && (gravatar_hash.strip () != "")) {
                var url = "https://www.gravatar.com/avatar/%s?s=128&d=identicon"
                    .printf (gravatar_hash);

                var message = new Soup.Message ("GET", url);

                var stream = yield avatar_session.send_async (message, GLib.Priority.
                    DEFAULT, null);

                var pixbuf = new Gdk.Pixbuf.from_stream (stream);
                if (pixbuf != null) {
                    var texture = Gdk.Texture.for_pixbuf (pixbuf);
                    cached_entry.avatar = texture;
                    avatar = texture;
                    entry_updated (callsign);
                }
            }
        } catch (Error e) {
            warning ("Failed to fetch avatar for %s: %s", callsign, e.message);
        }
        avatar_fetch_inflight.remove (callsign);
        return avatar;
    }

    public async Activator? get_callsign (string callsign) {
        var entry = ham_cache.lookup (callsign);

        if ((entry != null) && !is_entry_expired (entry))
            return entry.activator;

        var profile_callsign = pota_profile_callsign (callsign);
        entry = ham_cache.lookup (profile_callsign);
        if ((entry != null) && !is_entry_expired (entry)) {
            ham_cache.set (callsign, entry);
            return entry.activator;
        }

        // cache miss, load from API
        try {
            var result = yield Application.pota_client.fetch_operator (profile_callsign)
            ;

            var callsign_entry = new CallsignCacheEntry (
                new Activator.from_json (result.get_object ()),
                GLib.get_monotonic_time () + (ttl_seconds * GLib.TimeSpan.SECOND
                                              )
                );
            ham_cache.set (profile_callsign, callsign_entry);
            ham_cache.set (callsign, callsign_entry);
            entry_updated (callsign);
            if (profile_callsign != callsign)
                entry_updated (profile_callsign);
            return callsign_entry.activator;
        } catch (Error err) {
            warning ("Failed to fetch activator profile for %s: %s",
                profile_callsign, err.message);
            return null;
        }
    }
} /* class CallsignCache */

public sealed class SpotRepo : Object {
    public GLib.ListStore store { get; construct; }

    public signal void busy_changed (bool busy);
    public signal void refreshed (uint spots_updated);
    public signal void update_error (Error err);
    public signal void current_spot_changed (Quark spot_hash);

    public Gtk.StringList program_model { get; private set; }
    public Gtk.StringList mode_model { get; private set; }
    public uint64 tracked_spot_hash { get; set; default = uint64.MAX; }

    public HashMap<string, int> band_counts;
    private bool update_in_progress = false;
    private bool update_pending = false;

    public SpotRepo () {
        Object ();
    }

    construct {
        store = new GLib.ListStore (typeof (Spot));
        program_model = new Gtk.StringList ({});
        mode_model = new Gtk.StringList ({});
        band_counts = new HashMap<string, int> ();
    }

    public Spot? get_spot (Quark spot_hash) {
        for (uint i = 0 ; i < store.get_n_items () ; i++) {
            var spot = store.get_item (i) as Spot;
            if ((spot != null) && (spot.hash == spot_hash))
                return spot;
        }

        return null;
    }

    public int get_band_count (string band) {
        if (band_counts.has_key (band)) {
            return band_counts.get (band);
        }

        return 0;
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
                            parsed_spots.add (spot);
                        } catch (Error err) {
                            warning ("Skipping malformed POTA spot at index %u: %s",
                                i, err.message);
                        }
                    }
                }

                // TODO: alert if watched callsign is seen in unique_callsigns

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

                store.remove_all ();
                band_counts.clear ();
                foreach (var entry in parsed_band_counts.entries) {
                    band_counts[entry.key] = entry.value;
                }
                program_model.splice (0, program_model.get_n_items (), {});
                mode_model.splice (0, mode_model.get_n_items (), {});

                foreach (var spot in parsed_spots) {
                    store.append (spot);
                }
                spots_updated = parsed_spots.size;

                program_model.append (_("All"));
                foreach (var program in programs_sorted) {
                    program_model.append (program);
                }
                mode_model.append (_("All"));
                foreach (var mode in modes_sorted) {
                    mode_model.append (mode);
                }

                busy_changed (false);
                refreshed (spots_updated);
            } catch (Error err) {
                busy_changed (false);
                update_error (err);
            }
        } while (update_pending);

        update_in_progress = false;
    } /* update_spots */
}     /* class SpotRepo */
