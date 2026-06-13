/* src/space_weather_button.vala
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

public sealed class SpaceWeatherButton : Gtk.Box {
    private const int KP_GRAPH_LIMIT = 8;
    private const double KP_GRAPH_SPACING = 4.0;
    private const double KP_GRAPH_MIN_BAR_HEIGHT = 6.0;
    private const double KP_GRAPH_MAX_BAR_HEIGHT = 28.0;

    private Gtk.Popover popover;
    private Gtk.Label kp_badge_label;
    private Gtk.Widget storm_badge;
    private Gtk.Box storm_scale_badge;
    private Gtk.Label storm_scale_label;
    private Gtk.Label title_label;
    private Gtk.Label status_label;
    private Gtk.Label updated_label;
    private Gtk.DrawingArea kp_scale_area;
    private double[] displayed_kp_history = {};
    private DateTime?[] displayed_kp_history_times_utc = {};
    private Gtk.Label sfi_value_label;
    private Gtk.Label ssn_value_label;
    private Gtk.Label a_index_value_label;
    private Gtk.LinkButton source_link_button;

    public SpaceWeatherButton () {
        Object ();
    }

    construct {
        orientation = Gtk.Orientation.HORIZONTAL;
        append (build_button_face ());
        popover = build_popover ();

        show_loading ();
    }

    public Gtk.Popover create_popover () {
        return popover;
    }

    public void show_loading () {
        kp_badge_label.label = "…";
        kp_badge_label.add_css_class ("dim-label");
        storm_badge.visible = false;
        storm_scale_badge.visible = false;
        update_kp_scale_history (null);

        title_label.label = _("Solar Conditions");
        status_label.label = _("Loading current NOAA SWPC conditions.");
        updated_label.label = "";
        set_metric_labels ("—", "—", "—", _("Source: NOAA SWPC"));
    }

    public void show_unavailable () {
        kp_badge_label.label = "—";
        kp_badge_label.add_css_class ("dim-label");
        storm_badge.visible = false;
        storm_scale_badge.visible = false;
        update_kp_scale_history (null);

        title_label.label = _("Solar Unavailable");
        status_label.label = _("NOAA SWPC data is currently unavailable.");
        updated_label.label = "";
        set_metric_labels ("—", "—", "—", _("Source: NOAA SWPC"));
    }

    public void show_snapshot (SpaceWeatherSnapshot snapshot) {
        kp_badge_label.remove_css_class ("dim-label");
        kp_badge_label.label = snapshot.has_kp () ? "%.1f".printf (snapshot.kp) : "—";
        storm_badge.visible = snapshot.is_storm_level ();
        storm_scale_badge.visible = snapshot.is_storm_level ();
        storm_scale_label.label = snapshot.storm_scale_display ();
        update_storm_scale_css (snapshot);
        update_kp_scale_history (snapshot);

        title_label.label = _("Geomagnetic Conditions");

        status_label.label = _("HF: %s").printf (snapshot.geomagnetic_label);
        updated_label.label = snapshot.updated_at_utc != null
            ? _("Updated %s UTC").printf (snapshot.updated_at_utc.format ("%F %R"))
            : _("Updated unavailable");

        set_metric_labels (
            snapshot.has_sfi () ? snapshot.sfi.to_string () : "—",
            snapshot.has_ssn () ? snapshot.ssn.to_string () : "—",
            snapshot.has_a_index () ? snapshot.a_index.to_string () : "—",
            _("Source: %s").printf (snapshot.source)
        );
    }

    private Gtk.Widget build_button_face () {
        var overlay = new Gtk.Overlay () {
            width_request = 28,
            height_request = 28
        };
        overlay.add_css_class ("space-weather-button-face");

        var icon = new Gtk.Image.from_icon_name ("sun-outline-symbolic");
        overlay.set_child (icon);

        kp_badge_label = new Gtk.Label ("—") {
            halign = Gtk.Align.CENTER,
            valign = Gtk.Align.CENTER
        };
        kp_badge_label.add_css_class ("space-weather-kp-badge");
        overlay.add_overlay (kp_badge_label);

        storm_badge = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 0);
        storm_badge.visible = false;
        storm_badge.halign = Gtk.Align.END;
        storm_badge.valign = Gtk.Align.START;
        storm_badge.add_css_class ("toolbar-status-badge");
        storm_badge.add_css_class ("space-weather-storm-badge");
        overlay.add_overlay (storm_badge);

        return overlay;
    }

    private Gtk.Popover build_popover () {
        var popover = new Gtk.Popover () {
            has_arrow = true
        };

        var root = new Gtk.Box (Gtk.Orientation.VERTICAL, 10) {
            margin_top = 12,
            margin_bottom = 12,
            margin_start = 12,
            margin_end = 12,
            width_request = 260
        };

        var header = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 12);

        var hero_overlay = new Gtk.Overlay ();
        hero_overlay.add_css_class ("space-weather-hero");
        hero_overlay.set_child (new Gtk.Image.from_icon_name ("sun-outline-symbolic"));

        var hero_kp = new Gtk.Label ("Kp") {
            halign = Gtk.Align.CENTER,
            valign = Gtk.Align.CENTER
        };
        hero_kp.add_css_class ("space-weather-hero-kp");
        hero_overlay.add_overlay (hero_kp);
        kp_badge_label.bind_property ("label", hero_kp, "label", BindingFlags.SYNC_CREATE);

        header.append (hero_overlay);

        var header_text = new Gtk.Box (Gtk.Orientation.VERTICAL, 3) {
            valign = Gtk.Align.CENTER
        };

        title_label = new Gtk.Label ("") {
            xalign = 0.0f
        };
        title_label.add_css_class ("title-4");

        var title_row = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 8);
        title_row.append (title_label);

        storm_scale_badge = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 0);
        storm_scale_badge.visible = false;
        storm_scale_badge.valign = Gtk.Align.CENTER;
        storm_scale_badge.add_css_class ("space-weather-storm-scale");

        storm_scale_label = new Gtk.Label ("");
        storm_scale_label.add_css_class ("space-weather-storm-scale-label");
        storm_scale_badge.append (storm_scale_label);

        title_row.append (storm_scale_badge);
        header_text.append (title_row);

        status_label = new Gtk.Label ("") {
            xalign = 0.0f,
            wrap = true
        };
        status_label.add_css_class ("dim-label");
        header_text.append (status_label);

        updated_label = new Gtk.Label ("") {
            xalign = 0.0f,
            wrap = true
        };
        updated_label.add_css_class ("caption");
        updated_label.add_css_class ("dim-label");
        header_text.append (updated_label);

        header.append (header_text);
        root.append (header);

        root.append (build_kp_scale ());

        var metrics = new Gtk.Box (Gtk.Orientation.VERTICAL, 6);
        metrics.add_css_class ("space-weather-metrics");
        metrics.append (metric_row (_("Solar Flux"), out sfi_value_label));
        metrics.append (metric_row (_("Sunspots"), out ssn_value_label));
        metrics.append (metric_row (_("A-Index"), out a_index_value_label));
        root.append (metrics);

        source_link_button = new Gtk.LinkButton.with_label (
            "https://swpc.noaa.gov",
            ""
        ) {
            halign = Gtk.Align.CENTER
        };
        source_link_button.add_css_class ("flat");
        source_link_button.add_css_class ("caption");
        source_link_button.add_css_class ("dim-label");
        root.append (source_link_button);

        popover.child = root;
        return popover;
    }

    private Gtk.Widget build_kp_scale () {
        var frame = new Gtk.Box (Gtk.Orientation.VERTICAL, 6);
        frame.add_css_class ("space-weather-metrics");

        var label_row = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 12);

        var title = new Gtk.Label (_("Kp Trend")) {
            xalign = 0.0f,
            hexpand = true
        };
        title.add_css_class ("dim-label");
        label_row.append (title);

        var range = new Gtk.Label (_("Last 24h")) {
            xalign = 1.0f
        };
        range.add_css_class ("caption");
        range.add_css_class ("dim-label");
        label_row.append (range);
        frame.append (label_row);

        kp_scale_area = new Gtk.DrawingArea () {
            content_width = 220,
            content_height = 38,
            hexpand = true
        };
        kp_scale_area.add_css_class ("space-weather-kp-scale");
        kp_scale_area.has_tooltip = true;
        kp_scale_area.set_draw_func ((area, cr, width, height) => {
            draw_kp_scale (cr, width, height);
        });
        kp_scale_area.query_tooltip.connect ((x, y, keyboard_mode, tooltip) => {
            return query_kp_scale_tooltip (x, y, keyboard_mode, tooltip);
        });

        frame.append (kp_scale_area);
        return frame;
    }

    private Gtk.Widget metric_row (string label_text, out Gtk.Label value_label) {
        var row = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 12);

        var label = new Gtk.Label (label_text) {
            xalign = 0.0f,
            hexpand = true
        };
        label.add_css_class ("dim-label");
        row.append (label);

        value_label = new Gtk.Label ("—") {
            xalign = 1.0f
        };
        value_label.add_css_class ("numeric");
        row.append (value_label);

        return row;
    }

    private void set_metric_labels (
        string sfi_text,
        string ssn_text,
        string a_index_text,
        string source_text
    ) {
        sfi_value_label.label = sfi_text;
        ssn_value_label.label = ssn_text;
        a_index_value_label.label = a_index_text;
        source_link_button.label = source_text;
    }

    private void update_storm_scale_css (SpaceWeatherSnapshot snapshot) {
        storm_scale_badge.remove_css_class ("storm-g1");
        storm_scale_badge.remove_css_class ("storm-g2");
        storm_scale_badge.remove_css_class ("storm-g3");
        storm_scale_badge.remove_css_class ("storm-g4");
        storm_scale_badge.remove_css_class ("storm-g5");

        if (!snapshot.is_storm_level ())
            return;

        switch (snapshot.storm_scale_code ()) {
            case "G1":
                storm_scale_badge.add_css_class ("storm-g1");
                break;
            case "G2":
                storm_scale_badge.add_css_class ("storm-g2");
                break;
            case "G3":
                storm_scale_badge.add_css_class ("storm-g3");
                break;
            case "G4":
                storm_scale_badge.add_css_class ("storm-g4");
                break;
            case "G5":
                storm_scale_badge.add_css_class ("storm-g5");
                break;
        }
    }

    private void update_kp_scale_history (SpaceWeatherSnapshot? snapshot) {
        displayed_kp_history = {};
        displayed_kp_history_times_utc = {};

        if ((snapshot != null) && snapshot.has_kp_history ()) {
            displayed_kp_history = new double[snapshot.kp_history.size];
            displayed_kp_history_times_utc = new DateTime?[snapshot.kp_history.size];
            for (int i = 0; i < snapshot.kp_history.size; i++)
                displayed_kp_history[i] = snapshot.kp_history[i];
            for (int i = 0; i < snapshot.kp_history_times_utc.size; i++)
                displayed_kp_history_times_utc[i] = snapshot.kp_history_times_utc[i];
        } else if ((snapshot != null) && snapshot.has_kp ()) {
            displayed_kp_history = { snapshot.kp };
            displayed_kp_history_times_utc = { snapshot.updated_at_utc };
        }

        if (kp_scale_area == null)
            return;

        kp_scale_area.queue_draw ();
    }

    private void draw_kp_scale (Cairo.Context cr, int width, int height) {
        int bar_count = displayed_kp_history.length;
        if (bar_count <= 0)
            bar_count = KP_GRAPH_LIMIT;

        double chart_height = height - 2.0;
        if (chart_height < KP_GRAPH_MAX_BAR_HEIGHT)
            chart_height = KP_GRAPH_MAX_BAR_HEIGHT;
        double bar_width = (width - (KP_GRAPH_SPACING * (bar_count - 1))) / bar_count;
        if (bar_width < 1.0)
            return;

        for (int i = 0; i < bar_count; i++) {
            double kp_value = (i < displayed_kp_history.length) ? displayed_kp_history[i] : -1.0;
            double t = kp_value >= 0.0 ? normalized_kp_height (kp_value) : 0.0;
            double bar_height = KP_GRAPH_MIN_BAR_HEIGHT + ((KP_GRAPH_MAX_BAR_HEIGHT - KP_GRAPH_MIN_BAR_HEIGHT) * t);
            double x = i * (bar_width + KP_GRAPH_SPACING);
            double y = chart_height - bar_height;

            set_cairo_color_rgba (cr, 1.0, 1.0, 1.0, 0.08);
            rounded_rect (cr, x, y, bar_width, bar_height, 3.0);
            cr.fill_preserve ();
            set_cairo_color_rgba (cr, 1.0, 1.0, 1.0, 0.06);
            cr.set_line_width (1.0);
            cr.stroke ();

            if (kp_value >= 0.0) {
                var color = color_for_kp_value (kp_value);
                set_cairo_color_rgba (cr, color.red, color.green, color.blue, 1.0);
                rounded_rect (cr, x, y, bar_width, bar_height, 3.0);
                cr.fill ();
            }
        }
    }

    private bool query_kp_scale_tooltip (
        int x,
        int y,
        bool keyboard_mode,
        Gtk.Tooltip tooltip
    ) {
        if (displayed_kp_history.length <= 0)
            return false;

        int bar_index = kp_bar_index_at_position ((double) x, kp_scale_area.get_width ());
        if ((bar_index < 0) || (bar_index >= displayed_kp_history.length))
            return false;

        double kp_value = displayed_kp_history[bar_index];
        if (kp_value < 0.0)
            return false;

        string time_text = _("Time unavailable");
        if (bar_index < displayed_kp_history_times_utc.length) {
            var history_time = displayed_kp_history_times_utc[bar_index];
            if (history_time != null)
                time_text = history_time.format ("%F %R UTC");
        }

        tooltip.set_text (_("Kp %s\n%s").printf ("%.2f".printf (kp_value), time_text));
        return true;
    }

    private int kp_bar_index_at_position (double x, int width) {
        int bar_count = displayed_kp_history.length;
        if (bar_count <= 0)
            return -1;

        double bar_width = (width - (KP_GRAPH_SPACING * (bar_count - 1))) / bar_count;
        if (bar_width < 1.0)
            return -1;

        for (int i = 0; i < bar_count; i++) {
            double bar_x = i * (bar_width + KP_GRAPH_SPACING);
            if ((x >= bar_x) && (x <= (bar_x + bar_width)))
                return i;
        }

        return -1;
    }

    private Gdk.RGBA color_for_kp_value (double kp_value) {
        int level = (int) Math.floor (kp_value);
        if (level <= 4)
            return rgba_from_hex ("#4caf50");

        switch (level) {
            case 5:
                return rgba_from_hex ("#f6eb14");
            case 6:
                return rgba_from_hex ("#ffc800");
            case 7:
                return rgba_from_hex ("#ff9600");
            case 8:
                return rgba_from_hex ("#ff0000");
            default:
                return rgba_from_hex ("#c80000");
        }
    }

    private Gdk.RGBA rgba_from_hex (string hex) {
        var color = Gdk.RGBA ();
        color.parse (hex);
        return color;
    }

    private void set_cairo_color_rgba (
        Cairo.Context cr,
        double red,
        double green,
        double blue,
        double alpha
    ) {
        cr.set_source_rgba (red, green, blue, alpha);
    }

    private double normalized_kp_height (double kp_value) {
        if (kp_value <= 0.0)
            return 0.0;

        if (kp_value >= 9.0)
            return 1.0;

        // Compress quiet conditions, step unsettled upward, and keep storms prominent.
        if (kp_value < 4.0)
            return (kp_value / 4.0) * 0.28;

        if (kp_value < 5.0)
            return 0.40 + (((kp_value - 4.0) / 1.0) * 0.15);

        return 0.60 + (((kp_value - 5.0) / 4.0) * 0.40);
    }

    private void rounded_rect (
        Cairo.Context cr,
        double x,
        double y,
        double width,
        double height,
        double radius
    ) {
        double right = x + width;
        double bottom = y + height;
        double capped_radius = radius;
        double width_radius = width / 2.0;
        double height_radius = height / 2.0;
        if (capped_radius > width_radius)
            capped_radius = width_radius;
        if (capped_radius > height_radius)
            capped_radius = height_radius;

        cr.new_sub_path ();
        cr.arc (right - capped_radius, y + capped_radius, capped_radius, -Math.PI / 2.0, 0.0);
        cr.arc (right - capped_radius, bottom - capped_radius, capped_radius, 0.0, Math.PI / 2.0);
        cr.arc (x + capped_radius, bottom - capped_radius, capped_radius, Math.PI / 2.0, Math.PI);
        cr.arc (x + capped_radius, y + capped_radius, capped_radius, Math.PI, 3.0 * Math.PI / 2.0);
        cr.close_path ();
    }
}
