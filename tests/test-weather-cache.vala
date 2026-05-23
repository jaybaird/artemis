/* tests/test-weather-cache.vala
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

private sealed class FixedWeatherUnitsProvider : Object, WeatherUnitsProvider {
    private string units;

    public FixedWeatherUnitsProvider (string units) {
        Object ();
        this.units = units;
    }

    public string get_weather_units () {
        return units;
    }
}

private sealed class FakeWeatherProvider : Object, WeatherProvider {
    public int fetch_count { get; private set; default = 0; }
    public string last_units { get; private set; default = ""; }

    public async WeatherData fetch_weather (Shumate.Coordinate coord, string units) throws Error {
        fetch_count++;
        last_units = units;
        return WeatherData (57.0 + fetch_count, 65, "overcast clouds", "04d");
    }
}

private WeatherData run_weather_lookup (WeatherCache cache, string grid4 = "EN45") throws Error {
    var loop = new MainLoop ();
    Error? lookup_error = null;
    WeatherData data = WeatherData (0, 0, "", "");

    cache.get_weather_for_grid4.begin (grid4, (obj, res) => {
        try {
            data = cache.get_weather_for_grid4.end (res);
        } catch (Error err) {
            lookup_error = err;
        }
        loop.quit ();
    });
    loop.run ();

    if (lookup_error != null)
        throw lookup_error;
    return data;
}

private string cache_path_for_test (string name) {
    return Path.build_filename (Environment.get_tmp_dir (), "artemis-%s.ini".printf (name));
}

private void test_weather_cache_fetches_once_for_memory_hit () {
    var provider = new FakeWeatherProvider ();
    var cache_path = cache_path_for_test ("weather-memory");
    FileUtils.remove (cache_path);
    var cache = new WeatherCache (
        new FixedWeatherUnitsProvider ("imperial"),
        provider,
        cache_path
    );

    try {
        var first = run_weather_lookup (cache);
        var second = run_weather_lookup (cache);

        assert (first.temperature == second.temperature);
        assert (provider.last_units == "imperial");
        assert (provider.fetch_count == 1);
    } catch (Error err) {
        error ("Weather lookup failed: %s", err.message);
    }
}

private void test_weather_cache_persists_to_disk () {
    var cache_path = cache_path_for_test ("weather-disk");
    FileUtils.remove (cache_path);

    try {
        var first_provider = new FakeWeatherProvider ();
        var first_cache = new WeatherCache (
            new FixedWeatherUnitsProvider ("metric"),
            first_provider,
            cache_path
        );
        var first = run_weather_lookup (first_cache);
        assert (first_provider.fetch_count == 1);

        var second_provider = new FakeWeatherProvider ();
        var second_cache = new WeatherCache (
            new FixedWeatherUnitsProvider ("metric"),
            second_provider,
            cache_path
        );
        var second = run_weather_lookup (second_cache);

        assert (second.temperature == first.temperature);
        assert (second_provider.fetch_count == 0);
    } catch (Error err) {
        error ("Weather lookup failed: %s", err.message);
    }
}

private void test_weather_cache_rejects_short_grid () {
    var provider = new FakeWeatherProvider ();
    var cache = new WeatherCache (
        new FixedWeatherUnitsProvider ("imperial"),
        provider,
        cache_path_for_test ("weather-invalid")
    );

    try {
        run_weather_lookup (cache, "EN");
        error ("Expected short grid to fail");
    } catch (WeatherError.INVALID_REQUEST err) {
        assert (provider.fetch_count == 0);
    } catch (Error err) {
        error ("Unexpected error: %s", err.message);
    }
}

public int main (string[] args) {
    Test.init (ref args);

    Test.add_func ("/weather-cache/memory-hit",
        test_weather_cache_fetches_once_for_memory_hit);
    Test.add_func ("/weather-cache/disk-hit", test_weather_cache_persists_to_disk);
    Test.add_func ("/weather-cache/rejects-short-grid",
        test_weather_cache_rejects_short_grid);

    return Test.run ();
}
