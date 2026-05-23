/* src/park_details_cache.vala
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
