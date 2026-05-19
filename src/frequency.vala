/* src/frequency.vala
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
