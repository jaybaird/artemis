/* src/application.vala
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

public sealed class AppNotification : Object {
    public string message { get; construct; }
    public DateTime timestamp { get; construct; }

    public AppNotification (string message, DateTime timestamp) {
        Object (
            message: message,
            timestamp: timestamp
        );
    }
}

public sealed class Application : Adw.Application {
    public signal void radio_connection_state_changed ();
    public signal void toast_requested (string message);
    public signal void notification_history_changed ();

    public static AppState state { get; private set; }
    public static LoggingService logging_service { get; private set; }
    public static LogbookImportService logbook_import_service { get; private set; }

    public static CallsignCache callsign_cache { get; private set; }
    public static SpotDb spot_database { get; private set; }
    public static SpotRepo spot_repo { get; private set; }
    public static Settings settings { get; private set; }
    public static PotaClient pota_client { get; private set; }
    public static ParkDetailsCache park_details_cache { get; private set; }
    public static QrzClient qrz_client { get; private set; }
    public static WeatherCache weather_cache { get; private set; }
    public static SpaceWeatherService space_weather_service { get; private set; }
    public static Artemis.Wsjtx.WsjtxSession wsjtx_session { get; private set; }
    private static ZoneDetect.Database? _tz_db = null;
    public static unowned ZoneDetect.Database? tz_db {
        get { return _tz_db; }
    }
    private static Bytes? tz_db_bytes = null;
    private AlertsWindow? alerts_window = null;
    private HelpWindow? help_window = null;
    private LogbookWindow? logbook_window = null;
    private bool setup_dialog_active = false;
    private GLib.ListStore notification_history_store;
    private const uint MAX_NOTIFICATION_HISTORY = 25;

    public static RadioControl? radio_control { get; private set; default = null; }
    public static bool is_radio_connected { get; set; default = false; }
    public static bool tz_db_available {
        get { return _tz_db != null; }
    }

    public static Application app;
    public static Gtk.Window win;

#if ARTEMIS_WINDOWS
    private static string? windows_bundle_root = null;
#endif

    public static bool is_radio_configured {
        get {
            return Application.settings.get_string ("radio-connection-type") != "none";
        }
    }

    private const GLib.ActionEntry[] APP_ENTRIES = {
        { "add-spot", on_add_button_clicked },
        { "alerts", on_alerts_action },
        { "logbook", on_logbook_action },
        { "help", on_help_action },
        { "shortcuts", shortcuts_activated },
        { "about", about_activated },
        { "preferences", on_preferences_action },
        { "refresh", refresh_activated },
        { "not-heard", mark_current_spot_not_heard },
        { "tune", tune_current_spot },
        { "quit", quit_activated }
    };

    public Application () {
        Object (
            application_id : Build.DOMAIN,
            flags: ApplicationFlags.DEFAULT_FLAGS
        );
    }

    construct {
        set_accels_for_action ("app.add-spot", { "<primary>a" });
        set_accels_for_action ("app.alerts", { "<primary><shift>a" });
        set_accels_for_action ("app.help", { "F1" });
        set_accels_for_action ("app.shortcuts", { "<primary>question" });
        set_accels_for_action ("app.preferences", { "<primary>comma" });
        set_accels_for_action ("app.refresh", {"<Ctrl>R", "F5"});
        set_accels_for_action ("app.not-heard", { "<primary>m" });
        set_accels_for_action ("app.tune", { "<primary>t" });
        set_accels_for_action ("app.quit", { "<primary>q" });
        set_accels_for_action ("win.search", { "<Ctrl>F" });
        set_accels_for_action ("win.toggle-sidebar", { "F9" });
        add_action_entries (APP_ENTRIES, this);

        state = new AppState ();
        notification_history_store = new GLib.ListStore (typeof (AppNotification));

        settings = new Settings (Build.DOMAIN);
        settings.changed["show-logbook"].connect (sync_logbook_ui);
        spot_repo = new SpotRepo ();
        pota_client = new PotaClient ();
        park_details_cache = new ParkDetailsCache (pota_client);
        qrz_client = new QrzClient ();
        load_tz_db ();

        spot_database = new SpotDb ();
        Error err;
        if (!spot_database.init (out err)) {
            error (err.message);
        }

        callsign_cache = new CallsignCache (3600, pota_client);
        logging_service = new LoggingService (
            spot_database,
            pota_client,
            qrz_client,
            new FileLocalAdifWriter (),
            new SettingsLoggingPreferences (settings)
        );
        logging_service.qso_added.connect ((spot) => {
            spot_repo.refresh_log_status_for_added_qso (spot);
        });
        logbook_import_service = new LogbookImportService (spot_database);
        weather_cache = new WeatherCache (new SettingsWeatherUnitsProvider (settings));
        space_weather_service = new SpaceWeatherService ();
        wsjtx_session = new Artemis.Wsjtx.WsjtxSession ();
        radio_control = new RadioControl ();
        radio_control.radio_connected.connect (() => {
            is_radio_connected = true;
            radio_connection_state_changed ();
        });
        radio_control.radio_disconnected.connect (() => {
            is_radio_connected = false;
            radio_connection_state_changed ();
        });
        radio_control.radio_error.connect ((err) => {
            is_radio_connected = false;
            radio_connection_state_changed ();
        });
        app = this;

        if (settings.get_string ("callsign").strip () != "" &&
            settings.get_string ("location").strip () != "") {
            settings.set_boolean ("first-run-setup-complete", true);
            return;
        }

        sync_logbook_ui ();
    }

    private static void load_tz_db () {
        try {
            tz_db_bytes = GLib.resources_lookup_data (
                "/com/k0vcz/artemis/tz/timezone21.bin",
                GLib.ResourceLookupFlags.NONE
            );

            unowned uint8[] data = tz_db_bytes.get_data ();
            _tz_db = ZoneDetect.Database.open_from_memory (
                (void*) data,
                data.length
            );

            if (_tz_db == null)
                warning ("Unable to load ZoneDetect timezone database from resources");
        } catch (Error err) {
            tz_db_bytes = null;
            _tz_db = null;
            warning ("Unable to load ZoneDetect timezone database resource: %s", err.message);
        }
    }

    public static void show_toast (string message, bool log_message = true) {
        if ((app == null) || (message.strip () == ""))
            return;

        if (log_message)
            app.add_notification_history (message);
        app.toast_requested (message);
    }

    public GLib.ListModel get_notification_history () {
        return notification_history_store;
    }

    public void clear_notification_history () {
        notification_history_store.remove_all ();
        notification_history_changed ();
    }

    private void add_notification_history (string message) {
        notification_history_store.append (
            new AppNotification (message.strip (), new DateTime.now_local ())
        );

        while (notification_history_store.get_n_items () > MAX_NOTIFICATION_HISTORY)
            notification_history_store.remove (0);

        notification_history_changed ();
    }

    public override void activate () {
        base.activate ();

        // Add application icon directory to icon theme search path
        var icon_theme = Gtk.IconTheme.get_for_display (Gdk.Display.get_default ());
        string data_dir = Build.DATADIR;
#if ARTEMIS_WINDOWS
        if (windows_bundle_root != null) {
            data_dir = Path.build_filename (windows_bundle_root, "share");
        }
#endif
        var icon_dir = File.new_for_path (Path.build_filename (data_dir, Build.DOMAIN)).get_child ("icons");
        debug (icon_dir.get_path ());
        icon_theme.add_resource_path ("/com/k0vcz/artemis/icons");
        if (icon_dir.query_exists ()) {
            icon_theme.add_search_path (icon_dir.get_path ());
        }

        var adw_style_manager = Adw.StyleManager.get_default ();
        adw_style_manager.set_color_scheme (Adw.ColorScheme.DEFAULT);

        var css_provider = new Gtk.CssProvider ();
        css_provider.load_from_resource ("/com/k0vcz/artemis/style.css");

        Gtk.StyleContext.add_provider_for_display (
            Gdk.Display.get_default (),
            css_provider,
            Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION
        );

        win = this.active_window ?? new AppWindow (this);
        space_weather_service.start ();
        win.close_request.connect (() => {
            return false;
        });
        win.present ();
        maybe_show_first_run_setup ();
    }

    public void send_spot_alert (Spot spot) {
        var title = _("Spot alert: %s").printf (spot.callsign);
        var body = _("%s on %s %s").printf (spot.park_ref, spot.band, spot.mode);
        var notification = new GLib.Notification (title);
        notification.set_body (body);
        notification.set_icon (new ThemedIcon ("com.k0vcz.Artemis"));
        notification.set_priority (GLib.NotificationPriority.NORMAL);

        send_notification ("spot-alert-%u".printf ((uint) spot.hash), notification);
        show_toast ("%s: %s".printf (title, body));
    }

    private void maybe_show_first_run_setup () {
        if (setup_dialog_active ||
            settings.get_boolean ("first-run-setup-complete") ||
            win == null) {
            return;
        }

        setup_dialog_active = true;
        var dialog = new FirstRunSetupDialog ();
        dialog.completed.connect ((save, callsign, location, use_metric) => {
            setup_dialog_active = false;
            if (save) {
                settings.set_string ("callsign", callsign);
                settings.set_string ("location", location);
                settings.set_boolean ("use-metric", use_metric);
            }
            settings.set_boolean ("first-run-setup-complete", true);
        });
        dialog.present (win);
    }

    private void on_help_action () {
        try {
            if (help_window == null) {
                help_window = new HelpWindow (this);
                help_window.set_transient_for (win);
                help_window.close_request.connect (() => {
                    help_window = null;
                    return false;
                });
            }

            help_window.present ();
        } catch (Error error) {
            warning ("Unable to open help: %s", error.message);
        }
    }

    private void on_logbook_action () {
        if (!settings.get_boolean ("show-logbook"))
            return;

        if (logbook_window == null) {
            logbook_window = new LogbookWindow (win);
            logbook_window.close_request.connect (() => {
                logbook_window = null;
                return false;
            });
        }

        logbook_window.present ();
    }

    private void sync_logbook_ui () {
        var show_logbook = settings.get_boolean ("show-logbook");
        var action = lookup_action ("logbook") as SimpleAction;
        if (action != null)
            action.set_enabled (show_logbook);

        if (show_logbook)
            set_accels_for_action ("app.logbook", { "<primary>l" });
        else
            set_accels_for_action ("app.logbook", {});
    }

    private void on_alerts_action () {
        if (alerts_window == null) {
            alerts_window = new AlertsWindow (this);
            alerts_window.set_transient_for (win);
            alerts_window.close_request.connect (() => {
                alerts_window = null;
                return false;
            });
        }

        alerts_window.present ();
    }

    private void about_activated () {
        const string[] ARTISTS = {
            "App icon designed by gnoman https://gitlab.gnome.org/gnoman",
            null
        };

        const string[] DESIGNERS = {
            null
        };

        const string[] DEVELOPERS = {
            "Jay Baird (K0VCZ)",
            null
        };

        const string[] CONTRIBUTORS = {
            "Henry Cisneros (KG5VFJ)",
            null
        };

        const string COPYRIGHT = "© 2026 Jay Baird (K0VCZ)";

        var dialog = new Adw.AboutDialog.from_appdata ("/com/k0vcz/artemis/metainfo.xml", Build.PROFILE == "development" ? null : Build.VERSION) {
            version = Build.VERSION,
            copyright = COPYRIGHT,
            developers = DEVELOPERS,
            artists = ARTISTS,
            designers = DESIGNERS,
            translator_credits = _("translator-credits")
        };

        dialog.add_acknowledgement_section (_("Beta Testers"), CONTRIBUTORS);
        dialog.add_legal_section (
            _("Hamlib"),
            RadioControl.hamlib_copyright (),
            Gtk.License.LGPL_2_1, null
        );
        dialog.add_legal_section (
            _("Eclipse Paho MQTT C Client Library"),
            "Copyright © 2007, Eclipse Foundation, Inc. and its licensors.\n" +
            "Licensed under the Eclipse Distribution License v1.0.",
            Gtk.License.CUSTOM,
            null
        );
        dialog.add_legal_section (
            _("libheatmap"),
            "Copyright © 2013 Lucas Beyer\n" +
            "https://github.com/lucasb-eyer/libheatmap",
            Gtk.License.MIT_X11,
            null
        );
        dialog.add_legal_section (
            _("ZoneDetect"),
            "Copyright © 2018 Bertold Van den Bergh\n" +
            "Licensed under the 3-clause BSD license.\n" +
            "https://github.com/BertoldVdb/ZoneDetect",
            Gtk.License.BSD_3,
            null
        );
        dialog.add_legal_section (
            _("Map Tiles"),
            "© Mapbox © OpenStreetMap contributors",
            Gtk.License.CUSTOM,
            null
        );

        //dialog.add_link (_("Translate"), Build.TRANSLATE_WEBSITE);
        if (Build.DONATE_WEBSITE != "")
            dialog.add_link (_("Donate"), Build.DONATE_WEBSITE);

        dialog.present (win);
    }

    private void shortcuts_activated () {
        var dialog = new Adw.ShortcutsDialog ();

        var general = new Adw.ShortcutsSection (_("General"));
        general.add (new Adw.ShortcutsItem.from_action (_("Add Spot"), "app.add-spot"));
        general.add (new Adw.ShortcutsItem.from_action (_("Search"), "win.search"));
        general.add (new Adw.ShortcutsItem.from_action (_("Refresh"), "app.refresh"));
        general.add (new Adw.ShortcutsItem.from_action (_("Mark Not Heard"), "app.not-heard"));
        general.add (new Adw.ShortcutsItem.from_action (_("Tune"), "app.tune"));
        if (settings.get_boolean ("show-logbook"))
            general.add (new Adw.ShortcutsItem.from_action (_("Logbook"), "app.logbook"));
        general.add (new Adw.ShortcutsItem.from_action (_("Toggle Sidebar"), "win.toggle-sidebar"));
        dialog.add (general);

        var application = new Adw.ShortcutsSection (_("Application"));
        application.add (new Adw.ShortcutsItem.from_action (_("Help"), "app.help"));
        application.add (new Adw.ShortcutsItem.from_action (_("Keyboard Shortcuts"), "app.shortcuts"));
        application.add (new Adw.ShortcutsItem.from_action (_("Preferences"), "app.preferences"));
        application.add (new Adw.ShortcutsItem.from_action (_("Quit"), "app.quit"));
        dialog.add (application);

        dialog.present (win);
    }

    private void refresh_activated () {
        spot_repo.update_spots.begin ((obj, res) => {
            spot_repo.update_spots.end (res);
        });
    }

    private void tune_current_spot () {
        Spot? spot = _spot_repo.get_spot (_state.current_spot_hash);
        if (spot != null) {
            tune_spot_with_operating_limit_warning (spot, win);
        }
    }

    private void mark_current_spot_not_heard () {
        Spot? spot = _spot_repo.get_spot (_state.current_spot_hash);
        if (spot != null)
            _spot_repo.mark_spot_not_heard (spot);
    }

    private void quit_activated () {
        this.quit ();
    }

    private void on_add_button_clicked () {
        AddSpot add_spot = new AddSpot ();

        add_spot.present (win);
    }

    private void on_preferences_action () {
        var preferences = new PreferencesDialog ();
        preferences.present (win);
    }

#if ARTEMIS_WINDOWS
    private static string? find_existing_file (string[] candidates) {
        foreach (var path in candidates) {
            if (FileUtils.test (path, FileTest.IS_REGULAR)) {
                return path;
            }
        }
        return null;
    }

    private static string resolve_windows_bundle_root (string[] args) {
        var cwd = Environment.get_current_dir ();
        var exe_dir = cwd;

        if (args.length > 0) {
            var exe_path = args[0];
            if (!Path.is_absolute (exe_path)) {
                exe_path = Path.build_filename (cwd, exe_path);
            }

            exe_dir = Path.get_dirname (exe_path);
            if (!Path.is_absolute (exe_dir)) {
                exe_dir = Path.build_filename (cwd, exe_dir);
            }
        }

        string[] candidate_roots = {
            Path.get_dirname (exe_dir),
            exe_dir,
            cwd,
            Path.get_dirname (cwd)
        };

        foreach (var root in candidate_roots) {
            var schema_dir = Path.build_filename (root, "share", "glib-2.0", "schemas");
            var gio_modules_dir = Path.build_filename (root, "lib", "gio", "modules");
            if (FileUtils.test (schema_dir, FileTest.IS_DIR) &&
                FileUtils.test (gio_modules_dir, FileTest.IS_DIR)) {
                return root;
            }
        }

        return Path.get_dirname (exe_dir);
    }

    private static void configure_windows_runtime_environment (string[] args) {
        var bundle_root = resolve_windows_bundle_root (args);
        windows_bundle_root = bundle_root;
        var schema_dir = Path.build_filename (bundle_root, "share", "glib-2.0", "schemas");
        var cert_dir = Path.build_filename (bundle_root, "etc", "ssl", "certs");
        var gio_modules_dir = Path.build_filename (bundle_root, "lib", "gio", "modules");

        Environment.set_variable ("GSETTINGS_SCHEMA_DIR", schema_dir, false);
        Environment.set_variable ("GIO_USE_TLS", "gnutls", false);
        Environment.set_variable ("SSL_CERT_DIR", cert_dir, false);
        Environment.set_variable ("GIO_MODULE_DIR", gio_modules_dir, false);
        Environment.set_variable ("GIO_EXTRA_MODULES", gio_modules_dir, false);

        var cert_file = find_existing_file ({
            Path.build_filename (cert_dir, "ca-bundle.crt"),
            Path.build_filename (cert_dir, "ca-certificates.crt"),
            Path.build_filename (cert_dir, "ca-bundle.trust.crt")
        });

        if (cert_file != null) {
            var db = TlsFileDatabase.@new (cert_file);
            TlsBackend.get_default ().set_default_database (db);
        }
    }
#endif

    public static int main (string[] args) {
#if ARTEMIS_WINDOWS
        configure_windows_runtime_environment (args);
#endif
        Environment.set_prgname (Build.NAME);
        Environment.set_application_name (Build.NAME);
        Intl.setlocale (LocaleCategory.ALL, "");
        Intl.bindtextdomain (Build.GETTEXT_PACKAGE, Build.LOCALEDIR);
        Intl.bind_textdomain_codeset (Build.GETTEXT_PACKAGE, "UTF-8");
        Intl.textdomain (Build.GETTEXT_PACKAGE);

        app = new Application ();
        return app.run (args);
    }

} /* class Application */
