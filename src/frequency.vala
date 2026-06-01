/* src/frequency.vala
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

public enum FrequencyUnit {
    HZ,
    KHZ,
    MHZ
}

public errordomain FrequencyError {
    INVALID
}

public double parse_frequency (
    string text,
    FrequencyUnit input_unit,
    FrequencyUnit output_unit
) throws FrequencyError {
    double value = 0.0;
    unowned string unparsed;
    var stripped = text.strip ();

    if (stripped == "") {
        throw new FrequencyError.INVALID (
            "Invalid frequency '%s'".printf (text)
        );
    }

    if (!double.try_parse (stripped, out value, out unparsed) || unparsed != "") {
        throw new FrequencyError.INVALID (
            "Invalid frequency '%s'".printf (text)
        );
    }

    if (value < 0.0) {
        throw new FrequencyError.INVALID (
            "Frequency must not be negative"
        );
    }

    return frequency_from_hz (frequency_to_hz (value, input_unit), output_unit);
}

public double parse_frequency_or_zero (
    string text,
    FrequencyUnit input_unit,
    FrequencyUnit output_unit
) {
    try {
        return parse_frequency (text, input_unit, output_unit);
    } catch (FrequencyError err) {
        return 0.0;
    }
}

public double parse_mhz_to_khz_or_zero (string text) {
    return parse_frequency_or_zero (text, FrequencyUnit.MHZ, FrequencyUnit.KHZ);
}

public double parse_khz_or_zero (string text) {
    return parse_frequency_or_zero (text, FrequencyUnit.KHZ, FrequencyUnit.KHZ);
}

public string format_frequency_khz (double frequency_khz) {
    return format_frequency (frequency_khz, 3);
}

public string format_frequency_mhz_from_khz (double frequency_khz) {
    return format_frequency (frequency_khz / 1000.0, 6);
}

public bool band_frequency_range_khz (string band, out int min_khz, out int max_khz) {
    min_khz = 0;
    max_khz = 0;

    switch (band) {
        case "160m":
            min_khz = 1800;
            max_khz = 2000;
            return true;
        case "80m":
            min_khz = 3500;
            max_khz = 4100;
            return true;
        case "60m":
            min_khz = 5250;
            max_khz = 5450;
            return true;
        case "40m":
            min_khz = 7000;
            max_khz = 7300;
            return true;
        case "30m":
            min_khz = 10100;
            max_khz = 10150;
            return true;
        case "20m":
            min_khz = 14000;
            max_khz = 14350;
            return true;
        case "17m":
            min_khz = 18068;
            max_khz = 18168;
            return true;
        case "15m":
            min_khz = 21000;
            max_khz = 21450;
            return true;
        case "12m":
            min_khz = 24890;
            max_khz = 24990;
            return true;
        case "10m":
            min_khz = 28000;
            max_khz = 29700;
            return true;
        case "6m":
            min_khz = 50000;
            max_khz = 54000;
            return true;
        case "2m":
            min_khz = 144000;
            max_khz = 148000;
            return true;
        case "70cm":
            min_khz = 420000;
            max_khz = 450000;
            return true;
        default:
            return false;
    }
}

public string? band_for_frequency_khz (double frequency_khz) {
    string[] bands = {
        "160m",
        "80m",
        "60m",
        "40m",
        "30m",
        "20m",
        "17m",
        "15m",
        "12m",
        "10m",
        "6m",
        "2m",
        "70cm"
    };

    foreach (var band in bands) {
        int min_khz;
        int max_khz;

        if (band_frequency_range_khz (band, out min_khz, out max_khz) &&
            frequency_khz >= min_khz && frequency_khz <= max_khz) {
            return band;
        }
    }

    return null;
}

private double frequency_to_hz (double value, FrequencyUnit unit) {
    switch (unit) {
        case FrequencyUnit.HZ:
            return value;
        case FrequencyUnit.KHZ:
            return value * 1000.0;
        case FrequencyUnit.MHZ:
            return value * 1000000.0;
        default:
            return value;
    }
}

private double frequency_from_hz (double hz, FrequencyUnit unit) {
    switch (unit) {
        case FrequencyUnit.HZ:
            return hz;
        case FrequencyUnit.KHZ:
            return hz / 1000.0;
        case FrequencyUnit.MHZ:
            return hz / 1000000.0;
        default:
            return hz;
    }
}

private string format_frequency (double value, int precision) {
    if (Math.fabs (value - Math.round (value)) < 0.0005)
        return "%.0f".printf (value);

    var formatted = "%.*f".printf (precision, value);
    while (formatted.has_suffix ("0")) {
        formatted = formatted.substring (0, formatted.length - 1);
    }
    if (formatted.has_suffix ("."))
        formatted = formatted.substring (0, formatted.length - 1);

    return formatted;
}
