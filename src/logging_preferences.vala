/* src/logging_preferences.vala
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

public interface LoggingPreferences : Object {
    public abstract bool enable_qrz_logging { get; }
    public abstract string qrz_api_key { owned get; }
    public abstract string station_callsign { owned get; }
    public abstract string spot_message { owned get; }
    public abstract bool enable_local_adif_log { get; }
    public abstract string local_adif_log_path { owned get; }
}

public sealed class SettingsLoggingPreferences : Object, LoggingPreferences {
    public GLib.Settings settings { get; construct; }

    public bool enable_qrz_logging {
        get { return settings.get_boolean ("enable-logging"); }
    }

    public string qrz_api_key {
        owned get { return settings.get_string ("qrz-api-key").strip (); }
    }

    public string station_callsign {
        owned get { return settings.get_string ("callsign").strip (); }
    }

    public string spot_message {
        owned get { return settings.get_string ("spot-message").strip (); }
    }

    public bool enable_local_adif_log {
        get { return settings.get_boolean ("enable-local-adif-log"); }
    }

    public string local_adif_log_path {
        owned get { return settings.get_string ("local-adif-log-path").strip (); }
    }

    public SettingsLoggingPreferences (GLib.Settings settings) {
        Object (settings: settings);
    }
}
