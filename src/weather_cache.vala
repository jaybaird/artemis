using Gee;
using GLib;
using Shumate;

public errordomain WeatherError {
    INVALID_REQUEST,
    API_KEY_MISSING,
    HTTP_FAILED,
    PARSE_FAILED
}

public struct WeatherData {
    public double temperature;
    public int relative_humidity;
    public string condition;
    public string icon_code;

    public WeatherData (
        double temperature,
        int relative_humidity,
        string condition,
        string icon_code
    ) {
        this.temperature = temperature;
        this.relative_humidity = relative_humidity;
        this.condition = condition;
        this.icon_code = icon_code;
    }
}

internal sealed class WeatherCacheEntry : Object {
    public int64 expires_at_unix { get; construct; }
    public WeatherData data { get; construct; }

    public WeatherCacheEntry (WeatherData data, int64 expires_at_unix) {
        Object (data: data, expires_at_unix: expires_at_unix);
    }

    public bool is_expired (int64 now_unix) {
        return expires_at_unix <= now_unix;
    }
}

public interface WeatherProvider : Object {
    public abstract async WeatherData fetch_weather (Coordinate coord, string units) throws Error;
}

public interface WeatherUnitsProvider : Object {
    public abstract string get_weather_units ();
}

public interface WeatherSpotDetails : Object {
    public abstract string weather_park_ref ();
    public abstract string weather_grid4 ();
    public abstract string weather_grid6 ();
}

public sealed class SettingsWeatherUnitsProvider : Object, WeatherUnitsProvider {
    private Settings settings;

    public SettingsWeatherUnitsProvider (Settings settings) {
        Object ();
        this.settings = settings;
    }

    public string get_weather_units () {
        return settings.get_boolean ("use-metric") ? "metric" : "imperial";
    }
}

public sealed class WeatherClient : Object, WeatherProvider {
    private const string BASE_URL = "https://api.openweathermap.org/data/2.5/weather";
    private Soup.Session session;

    public WeatherClient () {
        Object ();
    }

    construct {
        session = new Soup.Session ();
        session.timeout = 30;
        session.user_agent = "Artemis/%s".printf (Build.VERSION);
    }

    private static string encode_query_value (string value) {
        return GLib.Uri.escape_string (value, null, false);
    }

    private static string coordinate_to_query_value (double value) {
        return value.to_string ();
    }

    private static string build_url (Coordinate coord, string units, string api_key) {
        return "%s?lat=%s&lon=%s&units=%s&appid=%s".printf (
            BASE_URL,
            encode_query_value (coordinate_to_query_value (coord.latitude)),
            encode_query_value (coordinate_to_query_value (coord.longitude)),
            encode_query_value (units),
            encode_query_value (api_key)
        );
    }

    public async WeatherData fetch_weather (Coordinate coord, string units) throws Error {
        var api_key = Build.OPENWEATHER_API_KEY.strip ();
        if (api_key == "") {
            throw new WeatherError.API_KEY_MISSING ("OpenWeather API key is not configured in this build"
            );
        }

        var message = new Soup.Message ("GET", build_url (coord, units, api_key));
        message.request_headers.replace ("Accept", "application/json");
        message.request_headers.replace ("User-Agent", session.user_agent);

        var response = yield session.send_and_read_async (
            message,
            Priority.DEFAULT,
            null
        );

        if (message.status_code != Soup.Status.OK) {
            throw new WeatherError.HTTP_FAILED ("Weather request failed: %u %s".printf (
                    message.status_code,
                    message.reason_phrase
                )
            );
        }

        var parser = new Json.Parser ();
        parser.load_from_data ((string) response.get_data (), (ssize_t) response.get_size ());

        var root = parser.get_root ();
        if ((root == null) || (root.get_node_type () != Json.NodeType.OBJECT)) {
            throw new WeatherError.PARSE_FAILED ("Weather response did not contain a JSON object"
            );
        }

        var object = root.get_object ();
        var main = object.get_object_member ("main");
        var weather = object.get_array_member ("weather");

        if ((main == null) || (weather == null) || (weather.get_length () == 0)) {
            throw new WeatherError.PARSE_FAILED ("Weather response was missing required fields"
            );
        }

        var condition_object = weather.get_object_element (0);
        if (condition_object == null) {
            throw new WeatherError.PARSE_FAILED ("Weather response was missing the current condition"
            );
        }

        return WeatherData (
            main.get_double_member ("temp"),
            (int) main.get_int_member ("humidity"),
            condition_object.get_string_member ("description"),
            condition_object.get_string_member_with_default ("icon", "")
        );
    }
}

public sealed class WeatherCache : Object {
    private const int64 CACHE_TTL_SECONDS = 4 * 60 * 60;

    private WeatherProvider client;
    private WeatherUnitsProvider units_provider;
    private HashMap<string, WeatherCacheEntry> memory_cache;
    private string cache_path;
    private bool cache_loaded = false;

    public WeatherCache (
        WeatherUnitsProvider units_provider,
        WeatherProvider? client = null,
        string? cache_path = null
    ) {
        this.units_provider = units_provider;
        this.client = client ?? new WeatherClient ();
        memory_cache = new HashMap<string, WeatherCacheEntry> ();
        this.cache_path = cache_path ?? Path.build_filename (
            Environment.get_user_cache_dir (),
            "artemis",
            "weather-cache.ini"
        );
    }

    private static string normalize_grid4 (string grid) throws Error {
        var normalized = grid.strip ().ascii_up ();
        if (normalized.length < 4) {
            throw new WeatherError.INVALID_REQUEST ("Grid locator %s is too short for weather lookups".printf (grid)
            );
        }

        return normalized.substring (0, 4);
    }

    private static string grid4_for_spot (WeatherSpotDetails spot) throws Error {
        var grid4 = (spot.weather_grid4 () ?? "").strip ();
        if (grid4 != "")
            return normalize_grid4 (grid4);

        var grid6 = (spot.weather_grid6 () ?? "").strip ();
        if (grid6.length >= 4)
            return normalize_grid4 (grid6.substring (0, 4));

        throw new WeatherError.INVALID_REQUEST ("Spot %s has no usable grid square for weather lookups".printf (
                spot.weather_park_ref ()
            )
        );
    }

    private static string cache_key_for (string grid4, string units) throws Error {
        return "%s:%s".printf (normalize_grid4 (grid4), units);
    }

    private static string cache_group_for_key (string cache_key) {
        return GLib.Uri.escape_string (cache_key, null, false);
    }

    private static int64 now_unix () {
        return new DateTime.now_utc ().to_unix ();
    }

    private void ensure_cache_dir () {
        var cache_dir = Path.get_dirname (cache_path);
        if (DirUtils.create_with_parents (cache_dir, 0700) != 0) {
            warning ("Failed to create weather cache directory %s: %s",
                cache_dir, strerror (errno));
        }
    }

    private void prune_expired_entries () {
        var expired_keys = new ArrayList<string> ();
        var now = now_unix ();

        foreach (var entry in memory_cache.entries) {
            if (entry.value.is_expired (now))
                expired_keys.add (entry.key);
        }

        foreach (var key in expired_keys) {
            memory_cache.unset (key);
        }
    }

    private void load_cache_from_disk () {
        if (cache_loaded)
            return;

        cache_loaded = true;
        ensure_cache_dir ();

        if (!FileUtils.test (cache_path, FileTest.EXISTS))
            return;

        var key_file = new KeyFile ();
        try {
            key_file.load_from_file (cache_path, KeyFileFlags.NONE);

            foreach (var group in key_file.get_groups ()) {
                var cache_key = key_file.get_string (group, "cache-key");
                var expires_at_unix = int64.parse (
                    key_file.get_string (group, "expires-at-unix")
                );
                var temperature = double.parse (
                    key_file.get_string (group, "temperature")
                );
                var relative_humidity = int.parse (
                    key_file.get_string (group, "relative-humidity")
                );
                var condition = key_file.get_string (group, "condition");
                var icon_code = key_file.has_key (group, "icon-code") ?
                    key_file.get_string (group, "icon-code") : "";

                var entry = new WeatherCacheEntry (
                    WeatherData (temperature, relative_humidity, condition, icon_code),
                    expires_at_unix
                );
                memory_cache.set (cache_key, entry);
            }
        } catch (Error err) {
            warning ("Failed to load weather cache: %s", err.message);
            memory_cache.clear ();
        }

        prune_expired_entries ();
    }

    private void persist_cache_to_disk () {
        ensure_cache_dir ();
        prune_expired_entries ();

        var key_file = new KeyFile ();
        foreach (var entry in memory_cache.entries) {
            var group = cache_group_for_key (entry.key);
            key_file.set_string (group, "cache-key", entry.key);
            key_file.set_string (group, "expires-at-unix",
                entry.value.expires_at_unix.to_string ());
            key_file.set_string (group, "temperature",
                entry.value.data.temperature.to_string ());
            key_file.set_string (group, "relative-humidity",
                entry.value.data.relative_humidity.to_string ());
            key_file.set_string (group, "condition", entry.value.data.condition);
            key_file.set_string (group, "icon-code", entry.value.data.icon_code);
        }

        try {
            key_file.save_to_file (cache_path);
        } catch (Error err) {
            warning ("Failed to persist weather cache: %s", err.message);
        }
    }

    public async WeatherData get_weather_for_grid4 (string grid4) throws Error {
        load_cache_from_disk ();

        var units = units_provider.get_weather_units ();
        var cache_key = cache_key_for (grid4, units);
        var cached_entry = memory_cache.get (cache_key);
        var now = now_unix ();
        if (cached_entry != null && !cached_entry.is_expired (now))
            return cached_entry.data;

        var coord = Distance.maidenhead_to_latlon (normalize_grid4 (grid4));
        var data = yield client.fetch_weather (coord, units);
        var entry = new WeatherCacheEntry (data, now + CACHE_TTL_SECONDS);
        memory_cache.set (cache_key, entry);
        persist_cache_to_disk ();

        return data;
    }

    public async WeatherData get_weather_for_spot (WeatherSpotDetails spot) throws Error {
        return yield get_weather_for_grid4 (grid4_for_spot (spot));
    }
}
