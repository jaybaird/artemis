/* window.vala
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

using Gee;

[GtkTemplate (ui = "/com/k0vcz/artemis/ui/main_window.ui")]
public sealed class AppWindow : Gtk.Window {
    [GtkChild]
    public unowned Adw.Banner refresh_banner;

    [GtkChild]
    public unowned Gtk.ProgressBar refresh_progress;

    [GtkChild]
    public unowned Gtk.Label current_time;

    [GtkChild]
    public unowned Adw.ViewStack band_stack;

    [GtkChild]
    public unowned Gtk.Box loading_spinner;

    [GtkChild]
    public unowned Adw.ToastOverlay toast_overlay;

    [GtkChild]
    public unowned Gtk.SearchEntry search_entry;

    [GtkChild]
    public unowned Gtk.DropDown search_select;

    [GtkChild]
    public unowned Gtk.DropDown program_select;

    private uint timer_id = 0;
    private uint progress_timer_id = 0;
    private int64 last_refresh_time = 0;

    private uint current_ticks = 0;
    private bool update_paused = false;
    private ArrayList<Adw.ViewStackPage> band_pages;

    private ulong program_select_handler = 0;

    public AppWindow(Gtk.Application app)
    {
        Object (application: app);
    }

    construct {
        band_pages = new ArrayList<Adw.ViewStackPage> ();
        refresh_banner.button_clicked.connect (on_banner_button_clicked);

        Application.settings.changed["update-interval"].connect (() => {
            setup_spot_updates ();
        });

        program_select.model = Application.spot_repo.program_model;

        search_entry.search_changed.connect ( () => {
            Application.current_search_text = search_entry.text;

            foreach (var page in band_pages)
            {
                var band_view = page.get_child () as BandView;
                band_view.bounce_filter ();
            }
        });

        search_select.notify["selected"].connect ( () => {
            var idx = search_select.selected;
            if (idx == Gtk.INVALID_LIST_POSITION) return;

            var model = search_select.get_model () as Gtk.StringList;
            if (model != null)
            {
                string? mode = null;
                if (idx > 0)
                    mode = model.get_string (idx);

                Application.current_mode_filter = mode;
                foreach (var page in band_pages)
                {
                    var band_view = page.get_child () as BandView;
                    band_view.bounce_filter ();
                }
            }
        });

        program_select_handler = program_select.notify["selected"].connect (
            on_program_selected);

        Application.spot_repo.busy_changed.connect ( (busy) => {
            loading_spinner.visible = busy;
            program_select.disconnect (program_select_handler);
        });

        Application.spot_repo.refreshed.connect ( (spots_updated) => {
            string toast_title = ngettext (
                "%u spot refreshed",
                "%u spots refreshed",
                spots_updated
                ).printf (spots_updated);

            var toast = new Adw.Toast (toast_title);
            toast.timeout = 5;
            toast_overlay.add_toast (toast);

            var idx = 0u;
            var model = program_select.get_model () as Gtk.StringList;
            for (uint i = 0; i < model.get_n_items (); i++)
            {
                if (Application.current_program_filter == model.get_string (i))
                {
                    idx = i;
                    break;
                }
            }
            program_select.set_selected (idx);
            program_select_handler = program_select.notify["selected"].connect (
                on_program_selected);
        });

        Application.spot_repo.current_spot_changed.connect ( (spot_hash) => {
            var spot = Application.spot_repo.get_spot (spot_hash);
            if (spot == null) return;

            if (band_stack.get_visible_child_name () != _ ("All"))
                band_stack.set_visible_child_name (spot.band);

            var band_view = band_stack.get_visible_child () as BandView;
            if (band_view == null) return;
            band_view.set_current_spot (spot_hash);
        });

        Application.spot_repo.update_error.connect ( (error) => {
            var alert_dialog = new Adw.AlertDialog (_ (
                "Unable to refresh spots"),
                null);
            alert_dialog.format_body (_ (
                "Unable to refresh spots due to an error: %s"), error.message);
            alert_dialog.add_responses (
                "cancel", _ ("Cancel"),
                "retry", _ ("Retry")
                );
            alert_dialog.set_default_response ("cancel");
            alert_dialog.set_close_response ("cancel");
            alert_dialog.present (this);
        });

        setup_spot_updates ();
        build_band_stack ();

        band_stack.set_visible_child_name (Application.settings.get_string (
            "default-band"));
        band_stack.notify["visible-child-name"].connect (() => {
            Application.current_band_filter = band_stack.visible_child_name;
        });

        var model = search_select.get_model () as Gtk.StringList;
        if (model != null)
        {
            var default_mode = Application.settings.get_string ("default-mode");
            int idx = -1;

            for (uint i = 0; i < model.get_n_items (); i++)
            {
                if (model.get_string (i) == default_mode)
                {
                    idx = (int)i;
                    break;
                }
            }

            if (idx >= 0)
                search_select.set_selected (idx);
            else
                search_select.set_selected (0); // fallback
        }

        refresh_banner.title = "";
        refresh_progress.fraction = 0;
    }

    private void initial_update ()
    {
        Application.spot_repo.update_spots.begin ((obj, res) => {
            Application.spot_repo.update_spots.end (res);
        });
    }

    private void setup_spot_updates ()
    {
        if (timer_id != 0)
            Source.remove (timer_id);

        if (progress_timer_id != 0)
            Source.remove (progress_timer_id);

        last_refresh_time = get_monotonic_time ();

        timer_id = Timeout.add_seconds (1, () => {
            tick.begin ();
            return Source.CONTINUE;
        });

        progress_timer_id = Timeout.add (100, () => {
            progress_tick ();
            return Source.CONTINUE;
        });

        initial_update ();
    }

    private void build_band_stack ()
    {
        for (uint i = 0; i < RadioConstants.BANDS.length; i++)
        {
            var band = RadioConstants.BANDS[i];
            var band_view = new BandView (Application.spot_repo, band,
                @"band-$band");

            var page = band_stack.add_titled_with_icon (band_view, band, band,
                @"band-$band");
            band_view.page = page; // page is unowned, so no circular reference
            band_pages.add (page);
        }
    }

    private void progress_tick ()
    {
        if (update_paused) return;
        var now = get_monotonic_time ();
        double elapsed = (now - last_refresh_time) / 1000000.0;
        var update_time = Application.settings.get_int ("update-interval");

        double fraction = elapsed / (double)update_time;
        if (fraction > 1.0) fraction = 1.0;
        refresh_progress.fraction = fraction;
    }

    private async void tick ()
    {
        if (!update_paused)
        {
            current_ticks += 1;
            var update_time = Application.settings.get_int ("update-interval");
            if (current_ticks >= update_time)
            {
                current_ticks = current_ticks - update_time;
                last_refresh_time = get_monotonic_time ();
                yield Application.spot_repo.update_spots ();

                Idle.add (() => {
                    foreach (var page in band_pages)
                    {
                        var band_view = page.get_child () as BandView;
                        band_view.set_current_spot (Application.
                            current_spot_hash);
                    }
                    return Source.REMOVE;
                });
            }

            var seconds_remaining = update_time - current_ticks;
            refresh_banner.title = ngettext (
                "Spots will refresh in %u second",
                "Spots will refresh in %u seconds",
                seconds_remaining
                ).printf (seconds_remaining);
        }

        var now = new GLib.DateTime.now_utc ().format ("%H:%M:%S UTC");
        current_time.label = now;
    } /* tick */

    [GtkCallback]
    private void on_map_button_clicked ()
    {
        Application.open_map_window ();
    }

    [GtkCallback]
    private void on_add_button_clicked ()
    {
        AddSpot add_spot = new AddSpot ();

        add_spot.present (this);
    }

    private void on_banner_button_clicked ()
    {
        update_paused = !update_paused;
        if (update_paused)
        {
            current_ticks = 0;
            refresh_banner.button_label = _ ("Resume");
            refresh_banner.title = _ ("Updates Paused");
            refresh_progress.fraction = 0;
        }
        else
        {
            last_refresh_time = get_monotonic_time ();
            refresh_banner.button_label = _ ("Pause");
            Application.spot_repo.update_spots.begin ();
        }
    }

    private void on_program_selected ()
    {
        var idx = program_select.selected;

        if (idx == Gtk.INVALID_LIST_POSITION) return;

        var model = program_select.get_model () as Gtk.StringList;
        if (model != null)
        {
            string? program = null;
            if (idx > 0)
                program = model.get_string (idx);

            Application.current_program_filter = program;

            foreach (var page in band_pages)
            {
                var band_view = page.get_child () as BandView;
                band_view.bounce_filter ();
            }
        }
    }

    ~AppWindow ()
    {
        if (timer_id != 0)
            Source.remove (timer_id);

        if (progress_timer_id != 0)
            Source.remove (progress_timer_id);
    }
} /* class AppWindow */
