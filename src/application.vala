/* application.vala
 *
 * Copyright 2025 Unknown
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
    public static Quark current_spot_hash { get {
                                                return _current_spot_hash;
                                            } set {
                                                if (_current_spot_hash == value)
                                                    return;
                                                _current_spot_hash = value;
                                                if (_spot_repo != null)
                                                    _spot_repo.
                                                    current_spot_changed (value)
                                                    ;
                                            } }
    public static SpotRepo spot_repo        { get; private set; }
    public static Settings settings         { get; private set; }
    public static PotaClient pota_client    { get; private set; }
    public static MapWindow?    map_window  { get;
                                              private set;
                                              default = null;
    }
    private static string? _current_mode_filter = null;
    public static string? current_mode_filter       { get {
                                                          return
                                                              _current_mode_filter;
                                                      } set {
                                                          if (
                                                              _current_mode_filter
                                                              == value) return;
                                                          _current_mode_filter =
                                                              value;
                                                          if (_map_window !=
                                                              null)
                                                              _map_window.
                                                              bounce_filter ();
                                                      } }
    private static string? _current_program_filter = null;
    public static string? current_program_filter    { get {
                                                          return
                                                              _current_program_filter;
                                                      } set {
                                                          if (
                                                              _current_program_filter
                                                              == value) return;
                                                          _current_program_filter
                                                              = value;
                                                          if (_map_window !=
                                                              null)
                                                              _map_window.
                                                              bounce_filter ();
                                                      } }
    private static string? _current_search_text = null;
    public static string? current_search_text       { get {
                                                          return
                                                              _current_search_text;
                                                      } set {
                                                          if (
                                                              _current_search_text
                                                              == value) return;
                                                          _current_search_text =
                                                              value;
                                                          if (_map_window !=
                                                              null)
                                                              _map_window.
                                                              bounce_filter ();
                                                      } }
    private static string? _current_band_filter = null;
    public static string? current_band_filter       { get {
                                                          return
                                                              _current_band_filter;
                                                      } set {
                                                          if (
                                                              _current_band_filter
                                                              == value) return;
                                                          _current_band_filter =
                                                              value;
                                                          if (_map_window !=
                                                              null)
                                                              _map_window.
                                                              bounce_filter ();
                                                      } }
    public Application()
    {
        Object (
            application_id: "com.k0vcz.artemis",
            flags: ApplicationFlags.DEFAULT_FLAGS,
            resource_base_path: "/com/k0vcz/artemis"
            );
    }

    construct {
        var map_action = new SimpleAction ("open-map", null);
        var preferences_action = new SimpleAction ("preferences", null);
        var quit_action = new SimpleAction ("quit", null);

        map_action.activate.connect (on_open_map_action);
        preferences_action.activate.connect (on_preferences_action);
        quit_action.activate.connect (() => {
            this.quit ();
        });

        add_action (map_action);
        add_action (preferences_action);
        add_action (quit_action);

        set_accels_for_action ("app.open-map", { "<primary>m" });
        set_accels_for_action ("app.preferences", { "<primary>comma" });
        set_accels_for_action ("app.quit", { "<primary>q" });

        settings = new Settings ("com.k0vcz.artemis");
        spot_repo = new SpotRepo ();
        pota_client = new PotaClient ();
    }

    public override void activate ()
    {
        base.activate ();

        var adw_style_manager = Adw.StyleManager.get_default ();
        adw_style_manager.set_color_scheme (Adw.ColorScheme.DEFAULT);

        var css_provider = new Gtk.CssProvider ();
        css_provider.load_from_resource ("/com/k0vcz/artemis/style.css");

        Gtk.StyleContext.add_provider_for_display (
            Gdk.Display.get_default (),
            css_provider,
            Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION
            );

        var win = this.active_window ?? new AppWindow (this);
        win.close_request.connect (() => {
            if (map_window != null)
                map_window.close (); // closing the main window closes all the windows
            return false;
        });
        win.present ();
    }

    public static void open_map_window ()
    {
        if (map_window == null)
        {
            map_window = new MapWindow ()
            {
                default_width = 800,
                default_height = 600
            };
            //map_window.set_application (this);
            map_window.close_request.connect (() => {
                map_window = null;
                return false;
            });
        }
        map_window.present ();
    }

    private void on_open_map_action ()
    {
        open_map_window ();
    }

    private void on_preferences_action ()
    {
        var window = active_window as AppWindow;

        if (window != null)
        {
            var preferences = new PreferencesDialog ();
            preferences.present (window);
        }
    }
} /* class Application */
