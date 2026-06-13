/* src/space_weather_snapshot.vala
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

using Gee;

public sealed class SpaceWeatherSnapshot : Object {
    private const string EM_DASH = "\u2014";

    public DateTime? updated_at_utc { get; set; }

    public double kp { get; set; default = -1.0; }
    public int a_index { get; set; default = -1; }
    public int sfi { get; set; default = -1; }
    public int ssn { get; set; default = -1; }
    public ArrayList<double?> kp_history { get; private set; default = new ArrayList<double?> (); }
    public ArrayList<DateTime?> kp_history_times_utc { get; private set; default = new ArrayList<DateTime?> (); }

    public string geomagnetic_label { get; set; default = "Unknown"; }
    public string hf_note { get; set; default = ""; }
    public string source { get; set; default = "NOAA SWPC"; }

    public bool has_kp () {
        return kp >= 0.0;
    }

    public bool has_a_index () {
        return a_index >= 0;
    }

    public bool has_sfi () {
        return sfi >= 0;
    }

    public bool has_ssn () {
        return ssn >= 0;
    }

    public bool has_any_value () {
        return has_kp () || has_a_index () || has_sfi () || has_ssn ();
    }

    public bool has_kp_history () {
        return kp_history.size > 0;
    }

    public bool is_storm_level () {
        return has_kp () && kp >= 5.0;
    }

    public string storm_scale_code () {
        if (!is_storm_level ())
            return "";

        return "G%d".printf (storm_scale_level ());
    }

    public string storm_scale_display () {
        if (!is_storm_level ())
            return "";

        return "%s %s".printf (storm_scale_code (), storm_scale_severity ());
    }

    public SpaceWeatherSnapshot copy () {
        var snapshot = new SpaceWeatherSnapshot ();
        snapshot.updated_at_utc = updated_at_utc;
        snapshot.kp = kp;
        snapshot.a_index = a_index;
        snapshot.sfi = sfi;
        snapshot.ssn = ssn;
        foreach (double? kp_value in kp_history)
            snapshot.kp_history.add (kp_value);
        foreach (DateTime? history_time in kp_history_times_utc)
            snapshot.kp_history_times_utc.add (history_time);
        snapshot.geomagnetic_label = geomagnetic_label;
        snapshot.hf_note = hf_note;
        snapshot.source = source;
        return snapshot;
    }

    public string primary_text () {
        return _("SFI %s · SSN %s · Kp %s · A %s").printf (
            has_sfi () ? sfi.to_string () : EM_DASH,
            has_ssn () ? ssn.to_string () : EM_DASH,
            has_kp () ? "%.1f".printf (kp) : EM_DASH,
            has_a_index () ? a_index.to_string () : EM_DASH
        );
    }

    public string secondary_text () {
        if (updated_at_utc != null) {
            return _("HF: %s · Updated %s UTC").printf (
                geomagnetic_label,
                updated_at_utc.format ("%R")
            );
        }

        return _("HF: %s").printf (geomagnetic_label);
    }

    public string tooltip_text () {
        var lines = new ArrayList<string> ();
        lines.add (_("HF: %s").printf (geomagnetic_label));
        lines.add (_("Source: %s").printf (source));

        if (updated_at_utc != null) {
            lines.add (_("Updated: %s UTC").printf (
                updated_at_utc.format ("%F %R")
            ));
        } else {
            lines.add (_("Updated: unavailable"));
        }

        var unavailable = unavailable_fields_text ();
        if (unavailable != "")
            lines.add (unavailable);

        return string.joinv ("\n", lines.to_array ());
    }

    private string unavailable_fields_text () {
        var fields = new ArrayList<string> ();

        if (!has_sfi ())
            fields.add (_("SFI"));
        if (!has_ssn ())
            fields.add (_("SSN"));
        if (!has_kp ())
            fields.add (_("Kp"));
        if (!has_a_index ())
            fields.add (_("A-index"));

        if (fields.size == 0)
            return "";

        return _("Unavailable: %s").printf (string.joinv (", ", fields.to_array ()));
    }

    private int storm_scale_level () {
        int rounded_kp = (int) Math.floor (kp);
        if (rounded_kp < 5)
            rounded_kp = 5;
        if (rounded_kp > 9)
            rounded_kp = 9;

        return rounded_kp - 4;
    }

    private string storm_scale_severity () {
        switch (storm_scale_level ()) {
            case 1:
                return _("Minor");
            case 2:
                return _("Moderate");
            case 3:
                return _("Strong");
            case 4:
                return _("Severe");
            default:
                return _("Extreme");
        }
    }
}
