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
    public static SpotRepo spot_repo   { get; private set; }
    public static Settings settings    { get; private set; }
    public static PotaClient pota_client { get; private set; }
    public static MapWindow?    map_window  { get;
                                              private set;
                                              default = null;
    }
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
        win.present ();
    }

    private void on_open_map_action ()
    {
        if (map_window == null)
        {
            map_window = new MapWindow ();
            map_window.set_application (this);
            map_window.close_request.connect (() => {
                map_window = null;
                return false;
            });
        }
        map_window.present ();
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
