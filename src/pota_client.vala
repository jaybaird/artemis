/* src/pota_client.vala
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

public struct PotaLocation {
    public string entity_name;
    public string location_desc;
    public string location_name;

    public string to_string () {
        return "%s, %s".printf (location_name, entity_name);
    }
}

public sealed class PotaClient : Object, PotaSpotPoster, OperatorProvider, ParkDetailsProvider {
    private Soup.Session session;
    private const string POTA_BASE_URL = "https://api.pota.app";
    private const string POTA_LOCATIONS_URL = "https://api.pota.app/locations";
    private const int64 LOCATION_CACHE_MAX_AGE_SECONDS = 5 * 24 * 60 * 60;
    private HashMap<string, PotaLocation?> location_lookup;
    private string locations_cache_path;
    private bool location_lookup_hydrated = false;

    public signal void locations_updated ();

    public PotaClient () {
        // Configure caching
        var cache_dir = Path.build_filename (Environment.get_user_cache_dir (),
            "artemis");
        var cache = new Soup.Cache (cache_dir, Soup.CacheType.SINGLE_USER);
        cache.set_max_size (50 * 1024 * 1024);

        session = new Soup.Session () {
            timeout = 30,
            user_agent = "Artemis/%s".printf (Build.VERSION)
        };
        session.add_feature (cache);
        location_lookup = new HashMap<string, PotaLocation?> ();
        locations_cache_path = Path.build_filename (cache_dir, "pota-locations.json");

        try {
            hydrate_location_lookup_from_disk ();
        } catch (Error error) {
            warning ("Unable to hydrate POTA locations cache: %s", error.message);
        }

        refresh_locations_if_needed.begin ((obj, res) => {
            try {
                refresh_locations_if_needed.end (res);
            } catch (Error error) {
                warning ("Unable to refresh POTA locations cache: %s", error.message);
            }
        });
    }

    private async Json.Node ? fetch_worker (string url) throws Error {
        var message = new Soup.Message ("GET", url);

        var response = yield session.send_and_read_async (message, Priority.
            DEFAULT, null);

        if (message.status_code != Soup.Status.OK)
            throw new IOError.FAILED ("HTTP request failed: %u %s",
                message.status_code, message.reason_phrase);

        var parser = new Json.Parser ();
        parser.load_from_data ((string)response.get_data (), (ssize_t)response.get_size ());

        return parser.get_root ();
    }

    public PotaLocation? lookup_location (string location_desc) {
        return location_lookup.get (normalize_location_desc (location_desc));
    }

    private static string normalize_location_desc (string location_desc) {
        return location_desc.strip ().up ();
    }

    private void ensure_cache_dir () {
        var cache_dir = Path.get_dirname (locations_cache_path);
        if (DirUtils.create_with_parents (cache_dir, 0700) != 0) {
            warning ("Failed to create POTA cache directory %s: %s",
                cache_dir, strerror (errno));
        }
    }

    private bool cache_file_is_stale () {
        var file = File.new_for_path (locations_cache_path);
        if (!file.query_exists ())
            return true;

        try {
            var info = file.query_info (
                "standard::size,time::modified",
                FileQueryInfoFlags.NONE
            );
            if (info.get_size () <= 0)
                return true;

            int64 modified_unix = (int64) info.get_attribute_uint64 ("time::modified");
            int64 age_seconds = new DateTime.now_utc ().to_unix () - modified_unix;
            return age_seconds >= LOCATION_CACHE_MAX_AGE_SECONDS;
        } catch (Error error) {
            warning ("Unable to stat POTA locations cache: %s", error.message);
            return true;
        }
    }

    private void hydrate_location_lookup_from_disk () throws Error {
        string contents;
        if (!FileUtils.get_contents (locations_cache_path, out contents))
            return;

        hydrate_location_lookup_from_json (contents);
    }

    private void hydrate_location_lookup_from_json (string json_text) throws Error {
        var parser = new Json.Parser ();
        parser.load_from_data (json_text, (ssize_t) json_text.length);

        var root = parser.get_root ();
        if ((root == null) || (root.get_node_type () != Json.NodeType.ARRAY)) {
            throw new IOError.INVALID_DATA ("POTA locations response was not a JSON array");
        }

        var array = root.get_array ();
        var next_lookup = new HashMap<string, PotaLocation?> ();

        for (uint i = 0; i < array.get_length (); i++) {
            var object = array.get_object_element (i);
            if (object == null)
                continue;

            string location_desc = object.get_string_member_with_default (
                "locationDesc",
                ""
            ).strip ();
            if (location_desc == "")
                continue;

            PotaLocation location = {};
            location.entity_name = object.get_string_member_with_default (
                "entityName",
                ""
            ).strip ();
            location.location_desc = location_desc;
            location.location_name = object.get_string_member_with_default (
                "locationName",
                ""
            ).strip ();

            next_lookup.set (normalize_location_desc (location.location_desc), location);
        }

        location_lookup = next_lookup;
        location_lookup_hydrated = true;
        locations_updated ();
    }

    private async string download_locations_json () throws Error {
        var message = new Soup.Message ("GET", POTA_LOCATIONS_URL);
        message.request_headers.replace ("Accept", "application/json");
        message.request_headers.replace ("User-Agent", session.user_agent);

        var response = yield session.send_and_read_async (
            message,
            Priority.DEFAULT,
            null
        );

        if (message.status_code != Soup.Status.OK) {
            throw new IOError.FAILED (
                "POTA locations request failed: %u %s".printf (
                    message.status_code,
                    message.reason_phrase
                )
            );
        }

        return ((string) response.get_data ()).substring (0, (long) response.get_size ());
    }

    public async void refresh_locations_if_needed () throws Error {
        if (!location_lookup_hydrated) {
            try {
                hydrate_location_lookup_from_disk ();
            } catch (Error error) {
                warning ("Unable to read POTA locations cache from disk: %s", error.message);
            }
        }

        if (location_lookup_hydrated && !cache_file_is_stale ())
            return;

        string json_text = yield download_locations_json ();
        ensure_cache_dir ();
        FileUtils.set_contents (locations_cache_path, json_text, json_text.length);
        hydrate_location_lookup_from_json (json_text);
    }

    public async void post_spot (
        string activator,
        string spotter,
        string reference,
        string frequency,
        string mode,
        string comment
    ) throws Error {
        var message = new Soup.Message ("POST", "%s/spot".printf (POTA_BASE_URL));
        size_t len = 0;
        var builder = new Json.Builder ();
        var generator = new Json.Generator ();

        builder.begin_object ();
        builder.set_member_name ("activator");
        builder.add_string_value (activator);
        builder.set_member_name ("spotter");
        builder.add_string_value (spotter);
        builder.set_member_name ("reference");
        builder.add_string_value (reference);
        builder.set_member_name ("frequency");
        builder.add_string_value (frequency);
        builder.set_member_name ("mode");
        builder.add_string_value (mode);
        builder.set_member_name ("comments");
        builder.add_string_value (comment);
        builder.set_member_name ("source");
        builder.add_string_value (Build.NAME);
        builder.end_object ();

        generator.set_root (builder.get_root ());
        var payload = generator.to_data (out len);
        var bytes = new GLib.Bytes (payload.data);
        message.set_request_body_from_bytes ("application/json", bytes);
        message.request_headers.replace ("Accept", "application/json");
        message.request_headers.replace ("User-Agent", session.user_agent);

        yield session.send_and_read_async (message, Priority.DEFAULT, null);

        if (message.get_status () != Soup.Status.OK) {
            throw new IOError.FAILED ("POTA spot upload failed: %u %s",
                message.get_status (), message.get_reason_phrase ());
        }
    }

    public async Json.Node? fetch_spot_history (
        string callsign,
        string park_ref
    ) throws Error {
        var escaped_callsign = GLib.Uri.escape_string (callsign, null, false);
        var escaped_park_ref = GLib.Uri.escape_string (park_ref, null, false);
        var url = "%s/v1/spots/%s/%s".printf (
            POTA_BASE_URL,
            escaped_callsign,
            escaped_park_ref);

        return yield fetch_worker (url);
    }

    public async PotaParkDetails fetch_park_details (string park_ref) throws Error {
        var escaped_ref = GLib.Uri.escape_string (park_ref.strip ().up (), null, false);
        var root = yield fetch_worker ("%s/park/%s".printf (POTA_BASE_URL, escaped_ref));
        if ((root == null) || (root.get_node_type () != Json.NodeType.OBJECT))
            throw new IOError.INVALID_DATA ("POTA park response was not an object");

        var object = root.get_object ();
        var name = object.get_string_member_with_default ("name", "").strip ();
        var park_type = object.get_string_member_with_default ("parktypeDesc", "").strip ();

        PotaParkDetails details = {};
        details.reference = object.get_string_member_with_default ("reference", park_ref).strip ();
        details.name = park_type == "" ? name : "%s %s".printf (name, park_type);
        details.location_desc = object.get_string_member_with_default ("locationDesc", "").strip ();

        if (details.reference == "" || name == "")
            throw new IOError.INVALID_DATA ("POTA park response did not include park details");

        return details;
    }

    public async Json.Node? fetch_operator (string callsign) throws Error {
        var url = "%s/stats/user/%s".printf (POTA_BASE_URL, GLib.Uri.escape_string (
            callsign, null, false));
        return yield fetch_worker (url);
    }

    public async Json.Node? fetch_spots () throws Error {
        string url = "%s/v1/spots".printf (POTA_BASE_URL);

        return yield fetch_worker (url);
    }
} /* class PotaClient */
