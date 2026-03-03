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

public sealed class Application : Adw.Application {
    private static Quark _current_spot_hash = 0;
    public static Quark current_spot_hash {
        get {
            return _current_spot_hash;
        } set {
            if (_current_spot_hash == value)
                return;
            _current_spot_hash = value;
            if (_spot_repo != null) {
                _spot_repo.current_spot_changed (value);
            }
        }
    }
    public static CallsignCache callsign_cache { get; private set; }
    public static SpotDb spot_database { get; private set; }
    public static SpotRepo spot_repo { get; private set; }
    public static Settings settings { get; private set; }
    public static PotaClient pota_client { get; private set; }

    public static RadioControl? radio_control { get; private set; default = null; }
    public static bool is_radio_connected { get; set; default = false; }

    public static Application app;
    public static Gtk.Window win;

    public static string? current_mode_filter { get; set; }
    public static string? current_program_filter { get; set; }
    public static string? current_search_text { get; set; }
    public static string? current_band_filter { get; set; }
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
        { "about", about_activated },
        { "preferences", on_preferences_action },
        { "refresh", refresh_activated },
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
        set_accels_for_action ("app.about", { "F1" });
        set_accels_for_action ("app.preferences", { "<primary>comma" });
        set_accels_for_action ("app.refresh", {"<Ctrl>R", "F5"});
        set_accels_for_action ("app.quit", { "<primary>q" });
        add_action_entries (APP_ENTRIES, this);

        settings = new Settings (Build.DOMAIN);
        spot_repo = new SpotRepo ();
        pota_client = new PotaClient ();

        spot_database = new SpotDb ();
        Error err;
        if (!spot_database.init (out err)) {
            error (err.message);
        }

        callsign_cache = new CallsignCache (3600);

        radio_control = new RadioControl ();
        var radio_models = RadioControl.get_radio_models ();
        for (int i = 0; i < radio_models.length; i++) {
            var radio = radio_models[i];
            print ("%s: %d\n".printf (radio.display_name, radio.model_id));
        }
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
        win.close_request.connect (() => {
            return false;
        });
        win.present ();
    }

    private void about_activated () {
        const string[] ARTISTS = {
        };

        const string[] DESIGNERS = {
        };

        const string[] DEVELOPERS = {
            "Jay Baird (K0VCZ)"
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

        //dialog.add_link (_("Translate"), Build.TRANSLATE_WEBSITE);
        //dialog.add_link (_("Donate"), Build.DONATE_WEBSITE);

        dialog.present (win);
    }

    private void refresh_activated () {
        spot_repo.update_spots.begin ((obj, res) => {
            spot_repo.update_spots.end (res);
        });
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
            var db = TlsFileDatabase.@new(cert_file);
            TlsBackend.get_default ().set_default_database (db);
        }
    }
#endif

    public static int main (string[] args) {
#if ARTEMIS_WINDOWS
        configure_windows_runtime_environment (args);
#endif
        Intl.setlocale (LocaleCategory.ALL, "");
        Intl.bindtextdomain (Build.GETTEXT_PACKAGE, Build.LOCALEDIR);
        Intl.bind_textdomain_codeset (Build.GETTEXT_PACKAGE, "UTF-8");
        Intl.textdomain (Build.GETTEXT_PACKAGE);

        app = new Application ();
        return app.run (args);
    }

} /* class Application */
