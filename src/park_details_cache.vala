/* src/park_details_cache.vala
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

public errordomain ParkDetailsCacheError {
    INVALID_REFERENCE
}

public sealed class ParkDetailsCache : Object {
    private ParkDetailsProvider client;
    private HashMap<string, PotaParkDetails?> details_by_reference;

    public ParkDetailsCache (ParkDetailsProvider client) {
        Object ();
        this.client = client;
        details_by_reference = new HashMap<string, PotaParkDetails?> ();
    }

    private static string normalize_reference (string reference) throws Error {
        var normalized = reference.strip ().ascii_up ();
        if (normalized == "")
            throw new ParkDetailsCacheError.INVALID_REFERENCE (_("Park reference cannot be empty"));

        return normalized;
    }

    public void seed (string reference, string? name, string? location_desc = null) {
        if ((name ?? "").strip () == "")
            return;

        try {
            var normalized = normalize_reference (reference);
            PotaParkDetails details = {};
            details.reference = normalized;
            details.name = name.strip ();
            details.location_desc = (location_desc ?? "").strip ();
            details_by_reference.set (normalized, details);
        } catch (Error err) {
            warning ("Unable to cache park details: %s", err.message);
        }
    }

    public PotaParkDetails? peek (string reference) {
        try {
            return details_by_reference.get (normalize_reference (reference));
        } catch (Error err) {
            return null;
        }
    }

    public async PotaParkDetails get_details (string reference) throws Error {
        var normalized = normalize_reference (reference);
        var cached = details_by_reference.get (normalized);
        if (cached != null)
            return cached;

        var details = yield client.fetch_park_details (normalized);
        details_by_reference.set (normalized, details);
        return details;
    }
}
