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
        var icon_dir = File.new_for_path ("%s/%s".printf (Build.DATADIR, Build.DOMAIN)).get_child ("icons");
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

    public static int main (string[] args) {
#if ARTEMIS_WINDOWS
        Environment.set_variable ("GSETTINGS_SCHEMA_DIR", "../share/glib-2.0/schemas", false);
        Environment.set_variable ("GIO_USE_TLS", "gnutls", false);
        Environment.set_variable ("SSL_CERT_DIR", "../etc/ssl/certs", false);
        Environment.set_variable ("SSL_CERT_FILE", "../etc/ssl/certs/ca-bundle.crt", false);
        Environment.set_variable ("G_TLS_CA_FILE", "../etc/ssl/certs/ca-bundle.crt", false);
        Environment.set_variable ("CURL_CA_BUNDLE", "../etc/ssl/certs/ca-bundle.crt", false);
        Environment.set_variable ("GIO_MODULE_DIR", "../lib/gio/modules", false);
        Environment.set_variable ("GIO_EXTRA_MODULES", "../lib/gio/modules", false);
#endif
        Intl.setlocale (LocaleCategory.ALL, "");
        Intl.bindtextdomain (Build.GETTEXT_PACKAGE, Build.LOCALEDIR);
        Intl.bind_textdomain_codeset (Build.GETTEXT_PACKAGE, "UTF-8");
        Intl.textdomain (Build.GETTEXT_PACKAGE);

        app = new Application ();
        return app.run (args);
    }

} /* class Application */
