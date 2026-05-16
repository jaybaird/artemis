/* src/astronomy_window.vala
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

using Cairo;

public sealed class SolarBandRow : Gtk.ListBoxRow {
    private Gtk.Label title_label;
    private Gtk.Label day_value_label;
    private Gtk.Label night_value_label;

    public string title {
        set {
            title_label.label = value;
        }
    }

    public string day_value {
        set {
            day_value_label.label = value;
        }
    }

    public string night_value {
        set {
            night_value_label.label = value;
        }
    }

    public SolarBandRow (string title) {
        Object ();

        var box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 16) {
            margin_top = 10,
            margin_bottom = 10,
            margin_start = 12,
            margin_end = 12,
            hexpand = true
        };

        title_label = new Gtk.Label (title) {
            xalign = 0.0f,
            width_chars = 12
        };
        title_label.add_css_class ("caption");
        title_label.add_css_class ("dim-label");
        box.append (title_label);

        var values_box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 12) {
            hexpand = true,
            halign = Gtk.Align.END
        };

        values_box.append (build_pair (
            "sun-outline-symbolic",
            out day_value_label
        ));
        values_box.append (build_pair (
            "moon-outline-symbolic",
            out night_value_label
        ));

        box.append (values_box);
        child = box;
    }

    private Gtk.Box build_pair (string icon_name, out Gtk.Label value_label) {
        var pair = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 4) {
            halign = Gtk.Align.END
        };

        var icon = new Gtk.Image.from_icon_name (icon_name) {
            pixel_size = 16,
            valign = Gtk.Align.CENTER
        };
        icon.add_css_class ("dim-label");
        pair.append (icon);

        value_label = new Gtk.Label ("") {
            xalign = 1.0f,
            selectable = true
        };
        value_label.add_css_class ("body");
        pair.append (value_label);

        return pair;
    }
}

[GtkTemplate (ui = "/com/k0vcz/artemis/ui/astronomy_window.ui")]
public sealed class AstronomyWindow : Gtk.Window {
    [GtkChild]
    private unowned Gtk.Label updated_label;

    [GtkChild]
    private unowned Gtk.Label error_label;

    [GtkChild]
    private unowned Gtk.ListBox primary_list;

    [GtkChild]
    private unowned Gtk.ListBox geomagnetic_list;

    [GtkChild]
    private unowned Gtk.ListBox hf_list;

    [GtkChild]
    private unowned Gtk.ListBox vhf_list;

    [GtkChild]
    private unowned Gtk.DrawingArea kp_chart;

    [GtkChild]
    private unowned Gtk.ListBox alerts_list;

    public AstronomyWindow (Gtk.Application app) {
        Object (application: app);
    }

    construct {
        Application.solar_conditions.updated.connect (render_state);
        kp_chart.set_draw_func (draw_kp_chart);
        render_state ();
    }

    private void render_state () {
        var service = Application.solar_conditions;
        var model = service.model;

        if (model.last_updated != null) {
            updated_label.label = @"Last updated: $(model.last_updated.to_local ().format ("%Y-%m-%d %H:%M %Z"))";
        } else if (model.refreshing) {
            updated_label.label = _("Loading solar conditions…");
        } else {
            updated_label.label = _("No solar data cached yet");
        }

        error_label.visible = (model.error_message ?? "").strip () != "";
        error_label.label = error_label.visible ? model.error_message : "";

        rebuild_primary_list (model);
        rebuild_geomagnetic_list (model);
        rebuild_hf_list (model);
        rebuild_vhf_list (model);
        rebuild_alerts_list (model);
        kp_chart.queue_draw ();
    }

    private void clear_list_box (Gtk.ListBox list) {
        Gtk.Widget? child = list.get_first_child ();
        while (child != null) {
            var next = child.get_next_sibling ();
            list.remove (child);
            child = next;
        }
    }

    private void rebuild_primary_list (SolarConditionsModel model) {
        clear_list_box (primary_list);
        primary_list.append (metric_row (_("SFI"), "%.0f".printf (model.sfi)));
        primary_list.append (metric_row (_("Sunspots"), "%d".printf (model.sunspots)));
        primary_list.append (metric_row (_("X-ray"), model.xray_class));
        primary_list.append (metric_row (_("304 Å"), "%.1f".printf (model.helium_line)));
    }

    private void rebuild_geomagnetic_list (SolarConditionsModel model) {
        clear_list_box (geomagnetic_list);
        geomagnetic_list.append (metric_row (_("K-index"), "%.1f".printf (model.k_index)));
        geomagnetic_list.append (metric_row (_("A-index"), "%.0f".printf (model.a_index)));
        geomagnetic_list.append (metric_row (_("Solar wind"), "%.0f km/s".printf (model.solar_wind_speed)));
        geomagnetic_list.append (metric_row (_("Bz"), "%.1f nT".printf (model.magnetic_field_bz)));
        geomagnetic_list.append (metric_row (_("Geomagnetic field"), model.geomagnetic_field_label));
        geomagnetic_list.append (metric_row (_("Signal noise"), model.signal_noise));
        geomagnetic_list.append (metric_row (_("Aurora"), "%d".printf (model.aurora)));
        geomagnetic_list.append (metric_row (_("Latitude limit"), "%.1f°".printf (model.aurora_latitude_limit)));
        geomagnetic_list.append (metric_row (_("MUF"), model.muf));
        geomagnetic_list.append (metric_row (_("foF2"), model.fof2));
        geomagnetic_list.append (metric_row (_("Kp estimate"), model.hamqsl_kp_estimate));
    }

    private void rebuild_hf_list (SolarConditionsModel model) {
        clear_list_box (hf_list);

        if (model.hf_conditions.size == 0) {
            hf_list.append (metric_row (_("HF Conditions"), _("No data")));
            return;
        }

        foreach (var condition in model.hf_conditions) {
            var row = new SolarBandRow (condition.band_group);
            row.day_value = condition.day;
            row.night_value = condition.night;
            hf_list.append (row);
        }
    }

    private void rebuild_vhf_list (SolarConditionsModel model) {
        clear_list_box (vhf_list);

        if (model.vhf_conditions.size == 0) {
            vhf_list.append (metric_row (_("VHF / E-skip"), _("No data")));
            return;
        }

        foreach (var condition in model.vhf_conditions) {
            vhf_list.append (metric_row (condition.title, condition.value));
        }
    }

    private void rebuild_alerts_list (SolarConditionsModel model) {
        clear_list_box (alerts_list);

        if (model.alerts.size == 0) {
            alerts_list.append (metric_row (_("Alerts"), _("No NOAA alerts in the last 24 hours")));
            return;
        }

        foreach (var alert in model.alerts) {
            var row = new DetailFieldRow (alert.product_id, true);
            row.value = "%s\n%s".printf (alert.issue_time_text, alert.summary);
            alerts_list.append (row);
        }
    }

    private DetailFieldRow metric_row (string title, string value) {
        var row = new DetailFieldRow (title);
        row.value = value;
        return row;
    }

    private string format_kp_value (double kp) {
        return "%.2f".printf (kp);
    }

    private void draw_kp_chart (Gtk.DrawingArea area, Context ctx, int width, int height) {
        var model = Application.solar_conditions.model;

        ctx.set_source_rgba (0.12, 0.12, 0.12, 0.12);
        ctx.rectangle (0, 0, width, height);
        ctx.fill ();

        if (model.kp_history.size == 0) {
            ctx.set_source_rgba (0.5, 0.5, 0.5, 1.0);
            ctx.select_font_face ("Sans", FontSlant.NORMAL, FontWeight.NORMAL);
            ctx.set_font_size (14);
            var text = _("No Kp history available");
            Cairo.TextExtents extents;
            ctx.text_extents (text, out extents);
            ctx.move_to ((width - extents.width) / 2.0 - extents.x_bearing, (height - extents.height) / 2.0 - extents.y_bearing);
            ctx.show_text (text);
            return;
        }

        var min_kp = 9.0;
        var max_kp = 0.0;
        foreach (var point in model.kp_history) {
            if (point.kp < min_kp)
                min_kp = point.kp;
            if (point.kp > max_kp)
                max_kp = point.kp;
        }
        if (min_kp == max_kp) {
            min_kp = 0.0;
            if (max_kp < 1.0)
                max_kp = 1.0;
        }

        var left = 12.0;
        var top = 12.0;
        var plot_width = (width - (left * 2)) > 1.0 ? (width - (left * 2)) : 1.0;
        var plot_height = (height - (top * 2)) > 1.0 ? (height - (top * 2)) : 1.0;
        var denominator = model.kp_history.size > 1 ? (double) (model.kp_history.size - 1) : 1.0;

        ctx.set_source_rgba (0.5, 0.5, 0.5, 0.25);
        ctx.set_line_width (1.0);
        for (int i = 0; i <= 3; i++) {
            var y = top + (plot_height / 3.0) * i;
            ctx.move_to (left, y);
            ctx.line_to (width - left, y);
        }
        ctx.stroke ();

        ctx.set_source_rgba (0.16, 0.67, 0.93, 1.0);
        ctx.set_line_width (2.5);

        for (uint i = 0; i < model.kp_history.size; i++) {
            var point = model.kp_history.get ((int) i);
            var x = left + (plot_width * (double) i / denominator);
            var y = top + plot_height - ((point.kp - min_kp) / (max_kp - min_kp)) * plot_height;

            if (i == 0)
                ctx.move_to (x, y);
            else
                ctx.line_to (x, y);
        }
        ctx.stroke ();

        foreach (var point in model.kp_history) {
            var x = left + (plot_width * (double) model.kp_history.index_of (point) / denominator);
            var y = top + plot_height - ((point.kp - min_kp) / (max_kp - min_kp)) * plot_height;
            ctx.arc (x, y, 2.5, 0, Math.PI * 2);
            ctx.fill ();
        }
    }
}
