using Gee;

public class CallsignCacheEntry : Object {
  public Activator activator;
  public uint64  expires_at;

  public CallsignCacheEntry (Activator activator, uint64 expires_at) {
    Object();
    this.activator = activator;
    this.expires_at = expires_at;
  }
}

public class CallsignCache : Object {
  private unowned PotaClient pota_client;
  private HashTable<string, CallsignCacheEntry> ham_cache;
  private uint ttl_seconds = 3600;

  public CallsignCache (PotaClient pota_client, uint ttl_seconds) {
    Object();
    this.pota_client = pota_client;
    this.ttl_seconds = ttl_seconds;
  }

  construct {
    ham_cache = new HashTable<string, CallsignCacheEntry> (GLib.str_hash, GLib.str_equal);
  }

  private bool is_entry_expired (CallsignCacheEntry? entry) {
    if (entry == null) return true;
    return GLib.get_monotonic_time () > entry.expires_at;
  }

  public void clear () {
    ham_cache.remove_all ();
  }

  public async Activator? get_callsign (string callsign) {
    var entry = ham_cache.lookup(callsign);
    if (entry != null && !is_entry_expired(entry)) {
      return entry.activator;
    }

    // cache miss, load from API
    try {
      var result = yield pota_client.fetch_operator(callsign);
      var callsign_entry = new CallsignCacheEntry (
        new Activator.from_json(result.get_object ()),
        GLib.get_monotonic_time() + (ttl_seconds * GLib.TimeSpan.SECOND)
      );
      ham_cache.set(callsign, callsign_entry);
      return callsign_entry.activator;
    } catch (Error err) {
      return null;
    }
  }
}

public sealed class SpotRepo : Object {
  private GLib.ListStore spot_store;
  private CallsignCache callsign_cache;
  private PotaClient client;

  public signal void busy_changed (bool busy);
  public signal void refreshed (uint spots_updated);
  public signal void update_error (Error err);

  public SpotRepo () {
    Object();
  }

  construct {
    client = new PotaClient ();
    callsign_cache = new CallsignCache(client, 3600);
    spot_store = new GLib.ListStore(typeof (Spot));
  }

  public GLib.ListStore get_model () {
    return spot_store;
  }

  public async void update_spots () {
    busy_changed(true);
    
    var unique_callsigns = new HashSet<string> ();
    var spots_updated = 0u;

    try {
      spot_store.remove_all ();
      var spots = yield client.fetch_spots ();
      if (spots != null && spots.get_node_type () == Json.NodeType.ARRAY) {
        var spots_array = spots.get_array (); 
        for (uint i = 0; i < spots_array.get_length (); i++) {
          var element = spots_array.get_element (i).get_object ();
          var spot = new Spot.from_json(element);

          unique_callsigns.add (spot.callsign);
          unique_callsigns.add (spot.spotter);

          spot_store.append (spot);
        }

        spots_updated = spots_array.get_length ();
      }
      busy_changed(false);
      refreshed(spots_updated);
    } catch (Error err) {
      busy_changed(false);
      update_error(err);
    }
  }
}