/* tests/test-callsign-cache.vala
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

private sealed class FakeOperatorProvider : Object, OperatorProvider {
    public int fetch_count { get; private set; default = 0; }
    public string last_callsign { get; private set; default = ""; }

    public async Json.Node? fetch_operator (string callsign) throws Error {
        fetch_count++;
        last_callsign = callsign;

        var object = new Json.Object ();
        object.set_string_member ("callsign", callsign);
        object.set_string_member ("name", "Test Operator");
        object.set_string_member ("qth", "Minneapolis, MN");
        object.set_string_member ("gravatar", "");
        object.set_int_member ("endorsements", 7);
        object.set_int_member ("activations", 11);
        object.set_int_member ("parks", 3);
        object.set_int_member ("qsos", 42);

        var node = new Json.Node (Json.NodeType.OBJECT);
        node.set_object (object);
        return node;
    }
}

private Activator? run_callsign_lookup (CallsignCache cache, string callsign) {
    var loop = new MainLoop ();
    Activator? activator = null;

    cache.get_callsign.begin (callsign, (obj, res) => {
        activator = cache.get_callsign.end (res);
        loop.quit ();
    });
    loop.run ();

    return activator;
}

private void test_callsign_cache_fetches_once_for_profile_aliases () {
    var provider = new FakeOperatorProvider ();
    var cache = new CallsignCache (3600, provider);

    var first = run_callsign_lookup (cache, "K1ABC/P");
    var second = run_callsign_lookup (cache, "K1ABC");

    assert (first != null);
    assert (second != null);
    assert (first.callsign == "K1ABC");
    assert (second.callsign == "K1ABC");
    assert (provider.last_callsign == "K1ABC");
    assert (provider.fetch_count == 1);
}

private void test_callsign_cache_peek_and_clear () {
    var provider = new FakeOperatorProvider ();
    var cache = new CallsignCache (3600, provider);

    assert (cache.peek_callsign ("K1ABC") == null);
    run_callsign_lookup (cache, "K1ABC");

    var cached = cache.peek_callsign ("K1ABC");
    assert (cached != null);
    assert (cached.name == "Test Operator");

    cache.clear ();
    assert (cache.peek_callsign ("K1ABC") == null);
}

private void test_callsign_cache_zero_ttl_refetches () {
    var provider = new FakeOperatorProvider ();
    var cache = new CallsignCache (0, provider);

    run_callsign_lookup (cache, "K1ABC");
    run_callsign_lookup (cache, "K1ABC");

    assert (provider.fetch_count == 2);
}

public int main (string[] args) {
    Test.init (ref args);

    Test.add_func ("/callsign-cache/profile-aliases",
        test_callsign_cache_fetches_once_for_profile_aliases);
    Test.add_func ("/callsign-cache/peek-clear", test_callsign_cache_peek_and_clear);
    Test.add_func ("/callsign-cache/zero-ttl-refetches",
        test_callsign_cache_zero_ttl_refetches);

    return Test.run ();
}
