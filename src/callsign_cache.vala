/* src/callsign_cache.vala
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

public interface OperatorProvider : Object {
    public abstract async Json.Node? fetch_operator (string callsign) throws Error;
}

public class CallsignCacheEntry {
    public Activator activator { get; }
    public uint64 expires_at { get; }
    public Gdk.Texture ? avatar { get; set; default = null; }
    public CallsignCacheEntry (Activator activator, uint64 expires_at) {
        _activator = activator;
        _expires_at = expires_at;
    }
}

public sealed class CallsignCache : Object {
    private const int64 PRUNE_INTERVAL_USEC = 60 * GLib.TimeSpan.SECOND;
    private const int64 PROFILE_MISS_TTL_USEC = 10 * GLib.TimeSpan.MINUTE;
    private HashMap<string, CallsignCacheEntry> ham_cache;
    private HashMap<string, HashSet<string>> profile_aliases;
    private HashSet<string> avatar_fetch_inflight;
    private HashSet<string> profile_fetch_inflight;
    private HashMap<string, int64?> profile_miss_expires_at;
    private Soup.Session avatar_session;
    private OperatorProvider operator_provider;
    private int64 last_prune_time = 0;
    public uint ttl_seconds { get; construct; default = 3600; }
    public signal void entry_updated (string callsign);

    public CallsignCache (uint ttl_seconds, OperatorProvider operator_provider) {
        Object (
            ttl_seconds : ttl_seconds
        );
        this.operator_provider = operator_provider;
    }

    ~CallsignCache () {
        if (avatar_session != null) {
            avatar_session.abort ();
            avatar_session = null;
        }
    }

    construct {
        ham_cache = new HashMap<string, CallsignCacheEntry> ();
        profile_aliases = new HashMap<string, HashSet<string>> ();
        avatar_fetch_inflight = new HashSet<string> ();
        profile_fetch_inflight = new HashSet<string> ();
        profile_miss_expires_at = new HashMap<string, int64?> ();

        var cache_dir = Path.build_filename (Environment.get_user_cache_dir (),
            "artemis");
        var cache = new Soup.Cache (cache_dir, Soup.CacheType.SINGLE_USER);
        cache.set_max_size (50 * 1024 * 1024);

        avatar_session = new Soup.Session () {
            timeout = 30,
            user_agent = Build.USER_AGENT
        };
        avatar_session.add_feature (cache);
    }

    private async Gdk.Texture load_avatar_texture (GLib.Bytes bytes) throws Error {
        var loader = new Gly.Loader.for_bytes (bytes);
        var image = yield loader.load_async (null);
        var frame = yield image.next_frame_async (null);
        return GlyGtk4.frame_get_texture (frame);
    }

    private bool is_entry_expired (CallsignCacheEntry? entry) {
        if (entry == null)
            return true;
        return GLib.get_monotonic_time () > entry.expires_at;
    }

    private void prune_expired_entries () {
        var now = GLib.get_monotonic_time ();
        if (now - last_prune_time < PRUNE_INTERVAL_USEC)
            return;

        last_prune_time = now;
        var expired_keys = new ArrayList<string> ();
        var expired_misses = new ArrayList<string> ();

        foreach (var entry in ham_cache.entries) {
            if (is_entry_expired (entry.value))
                expired_keys.add (entry.key);
        }

        foreach (var entry in profile_miss_expires_at.entries) {
            if (now > entry.value)
                expired_misses.add (entry.key);
        }

        foreach (var key in expired_keys) {
            ham_cache.unset (key);
        }

        foreach (var key in expired_misses) {
            profile_miss_expires_at.unset (key);
        }
    }

    public void clear () {
        ham_cache.clear ();
        profile_aliases.clear ();
        avatar_fetch_inflight.clear ();
        profile_fetch_inflight.clear ();
        profile_miss_expires_at.clear ();
        last_prune_time = 0;
    }

    private string remember_profile_alias (string callsign) {
        var profile = pota_profile_callsign (callsign);
        var aliases = profile_aliases.get (profile);
        if (aliases == null) {
            aliases = new HashSet<string> ();
            profile_aliases[profile] = aliases;
        }

        aliases.add (profile);
        aliases.add (callsign);
        return profile;
    }

    private void emit_profile_updated (string profile, string fallback_callsign) {
        var aliases = profile_aliases.get (profile);
        if (aliases == null) {
            entry_updated (fallback_callsign);
            if (profile != fallback_callsign)
                entry_updated (profile);
            return;
        }

        foreach (var alias in aliases) {
            entry_updated (alias);
        }
    }

    public async void load_callsigns (HashSet<string> callsigns) {
        foreach (var callsign in callsigns) {
            yield get_callsign (callsign);
        }
    }

    public Gdk.Texture? peek_avatar (string callsign) {
        prune_expired_entries ();
        var entry = ham_cache.get (callsign);
        if ((entry == null) || is_entry_expired (entry)) {
            var profile = pota_profile_callsign (callsign);
            entry = ham_cache.get (profile);
        }
        if (is_entry_expired (entry) || (entry == null))
            return null;
        return entry.avatar;
    }

    public Activator? peek_callsign (string callsign) {
        prune_expired_entries ();
        var entry = ham_cache.get (callsign);
        if (is_entry_expired (entry) || (entry == null))
            return null;
        return entry.activator;
    }

    public async Gdk.Texture? get_avatar_for (string callsign) {
        var profile = remember_profile_alias (callsign);
        var entry = yield get_callsign (callsign);

        if (entry == null)
            return null;

        var cached_entry = ham_cache.get (callsign);
        if ((cached_entry != null) && (cached_entry.avatar != null))
            return cached_entry.avatar;

        if (avatar_fetch_inflight.contains (profile))
            return null;

        avatar_fetch_inflight.add (profile);
        Gdk.Texture? avatar = null;
        try {
            var gravatar_hash = entry.gravatar_hash;
            if ((gravatar_hash != null) && (gravatar_hash.strip () != "")) {
                var url = "https://www.gravatar.com/avatar/%s?s=256&d=identicon"
                    .printf (gravatar_hash);

                var message = new Soup.Message ("GET", url);
                var bytes = yield avatar_session.send_and_read_async (
                    message,
                    GLib.Priority.DEFAULT,
                    null
                );

                if (message.status_code != Soup.Status.OK) {
                    throw new IOError.FAILED (
                        "HTTP %u %s".printf (message.status_code, message.reason_phrase)
                    );
                }

                var texture = yield load_avatar_texture (bytes);
                cached_entry.avatar = texture;
                avatar = texture;
                emit_profile_updated (profile, callsign);
            }
        } catch (Error e) {
            warning ("Failed to fetch avatar for %s: %s", callsign, e.message);
        }
        avatar_fetch_inflight.remove (profile);
        return avatar;
    }

    public async Activator? get_callsign (string callsign) {
        prune_expired_entries ();
        var entry = ham_cache.get (callsign);

        if ((entry != null) && !is_entry_expired (entry))
            return entry.activator;

        var profile = remember_profile_alias (callsign);
        entry = ham_cache.get (profile);
        if ((entry != null) && !is_entry_expired (entry)) {
            ham_cache.set (callsign, entry);
            return entry.activator;
        }

        var miss_expires_at = profile_miss_expires_at.get (profile);
        if ((miss_expires_at != null) && GLib.get_monotonic_time () <= miss_expires_at)
            return null;

        if (profile_fetch_inflight.contains (profile))
            return null;

        profile_fetch_inflight.add (profile);
        try {
            var result = yield operator_provider.fetch_operator (profile);

            var callsign_entry = new CallsignCacheEntry (
                new Activator.from_json (result.get_object ()),
                GLib.get_monotonic_time () + (ttl_seconds * GLib.TimeSpan.SECOND)
            );
            profile_miss_expires_at.unset (profile);
            ham_cache.set (profile, callsign_entry);
            ham_cache.set (callsign, callsign_entry);
            emit_profile_updated (profile, callsign);
            profile_fetch_inflight.remove (profile);
            return callsign_entry.activator;
        } catch (Error err) {
            profile_miss_expires_at[profile] =
                GLib.get_monotonic_time () + PROFILE_MISS_TTL_USEC;
            profile_fetch_inflight.remove (profile);
            warning ("Failed to fetch activator profile for %s: %s",
                profile, err.message);
            return null;
        }
    }
} /* class CallsignCache */
