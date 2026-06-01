/* tests/test-park-details-cache.vala
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

private sealed class FakeParkDetailsProvider : Object, ParkDetailsProvider {
    public int fetch_count { get; private set; default = 0; }
    public string last_reference { get; private set; default = ""; }

    public async PotaParkDetails fetch_park_details (string park_ref) throws Error {
        fetch_count++;
        last_reference = park_ref;

        PotaParkDetails details = {};
        details.reference = park_ref;
        details.name = "%s Test Park State Park".printf (park_ref);
        details.location_desc = "US-MN";
        return details;
    }
}

private PotaParkDetails run_park_lookup (ParkDetailsCache cache, string reference) throws Error {
    var loop = new MainLoop ();
    Error? lookup_error = null;
    PotaParkDetails details = {};

    cache.get_details.begin (reference, (obj, res) => {
        try {
            details = cache.get_details.end (res);
        } catch (Error err) {
            lookup_error = err;
        }
        loop.quit ();
    });
    loop.run ();

    if (lookup_error != null)
        throw lookup_error;
    return details;
}

private void test_park_details_seed_and_peek_normalize_reference () {
    var provider = new FakeParkDetailsProvider ();
    var cache = new ParkDetailsCache (provider);

    cache.seed (" us-1234 ", "Split Rock Lighthouse State Park", "US-MN");
    var details = cache.peek ("US-1234");

    assert (details != null);
    assert (details.reference == "US-1234");
    assert (details.name == "Split Rock Lighthouse State Park");
    assert (details.location_desc == "US-MN");
    assert (provider.fetch_count == 0);
}

private void test_park_details_fetches_once_and_caches () {
    var provider = new FakeParkDetailsProvider ();
    var cache = new ParkDetailsCache (provider);

    try {
        var first = run_park_lookup (cache, " us-9999 ");
        var second = run_park_lookup (cache, "US-9999");

        assert (first.reference == "US-9999");
        assert (second.name == first.name);
        assert (provider.last_reference == "US-9999");
        assert (provider.fetch_count == 1);
    } catch (Error err) {
        error ("Park details lookup failed: %s", err.message);
    }
}

private void test_park_details_rejects_blank_reference () {
    var provider = new FakeParkDetailsProvider ();
    var cache = new ParkDetailsCache (provider);

    try {
        run_park_lookup (cache, " ");
        error ("Expected blank park reference to fail");
    } catch (ParkDetailsCacheError.INVALID_REFERENCE err) {
        assert (provider.fetch_count == 0);
    } catch (Error err) {
        error ("Unexpected error: %s", err.message);
    }
}

public int main (string[] args) {
    Test.init (ref args);

    Test.add_func ("/park-details-cache/seed-peek-normalize",
        test_park_details_seed_and_peek_normalize_reference);
    Test.add_func ("/park-details-cache/fetch-once",
        test_park_details_fetches_once_and_caches);
    Test.add_func ("/park-details-cache/rejects-blank-reference",
        test_park_details_rejects_blank_reference);

    return Test.run ();
}
