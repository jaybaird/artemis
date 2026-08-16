/* src/http_session_factory.vala
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

public sealed class HttpSessionFactory : Object {
    private const uint HTTP_CACHE_MAX_SIZE_BYTES = 50 * 1024 * 1024;
    private static Soup.Cache? shared_cache = null;

    public static Soup.Session create_cached_session (uint timeout_seconds = 30) {
        var session = new Soup.Session () {
            timeout = timeout_seconds,
            user_agent = Build.USER_AGENT
        };
        session.add_feature (get_shared_cache ());
        return session;
    }

    private static Soup.Cache get_shared_cache () {
        if (shared_cache != null)
            return shared_cache;

        var cache_dir = Path.build_filename (Environment.get_user_cache_dir (), "artemis");
        if (DirUtils.create_with_parents (cache_dir, 0700) != 0) {
            warning ("Failed to create HTTP cache directory %s: %s",
                cache_dir, strerror (errno));
        }

        shared_cache = new Soup.Cache (cache_dir, Soup.CacheType.SINGLE_USER);
        shared_cache.set_max_size (HTTP_CACHE_MAX_SIZE_BYTES);
        return shared_cache;
    }
}
