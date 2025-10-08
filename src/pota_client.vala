/* pota_client.vala
 *
 * Copyright 2025 Unknown
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

public sealed class PotaClient : Object {
    private Soup.Session session;
    private const string POTA_BASE_URL = "https://api.pota.app";

    public PotaClient () {
        session = new Soup.Session ();

        // Configure caching
        var cache_dir = Path.build_filename (Environment.get_user_cache_dir (),
            "artemis");
        var cache = new Soup.Cache (cache_dir, Soup.CacheType.SINGLE_USER);
        cache.set_max_size (50 * 1024 * 1024);
        session.add_feature (cache);
        session.timeout = 30;
        session.user_agent = "Artemis/0.1.0";
    }

    private async Json.Node ? fetch_worker (string url) throws Error {
        var message = new Soup.Message ("GET", url);

        var response = yield session.send_and_read_async (message, Priority.
            DEFAULT, null);

        if (message.status_code != Soup.Status.OK)
            throw new IOError.FAILED ("HTTP request failed: %u %s",
                message.status_code, message.reason_phrase);

        var data = (string)response.get_data ();
        var parser = new Json.Parser ();
        parser.load_from_data (data);

        return parser.get_root ();
    }

    public async void post_spot (Spot spot) throws Error {
        var message = new Soup.Message ("POST", "%s/spot".printf (POTA_BASE_URL));
        size_t len = 0;
        var generator = new Json.Generator ();

        generator.set_root (spot.to_json ());
        var payload = generator.to_data (out len);
        var bytes = new GLib.Bytes (payload.data);
        message.set_request_body_from_bytes ("application/json", bytes);
        message.request_headers.replace ("Accept", "application/json");
        message.request_headers.replace ("User-Agent", session.user_agent);

        yield session.send_and_read_async (message, Priority.DEFAULT, null);

        if (message.get_status () != Soup.Status.OK) {
            warning ("POST failed: %u %s", message.get_status (), message.
                get_reason_phrase ());
            return;
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
