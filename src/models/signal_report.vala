/* src/models/signal_report.vala
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

public class SignalReport : Object {
    public string call { get; construct; }
    public string grid { get; construct; }
    public double latitude { get; construct; }
    public double longitude { get; construct; }
    public string? band { get; construct; }
    public string? mode { get; construct; }
    public double frequency { get; construct; }
    public int snr { get; construct; }
    public int64 timestamp_unix { get; construct; }
    public string source { get; construct; }
    public string? reporter { get; construct; }
    public string? dxcc { get; construct; }
    public string? country { get; construct; }
    public string? state { get; construct; }
    public string? raw_payload { get; construct; }

    public SignalReport (
        string call,
        string grid,
        double latitude,
        double longitude,
        string? band,
        string? mode,
        double frequency,
        int snr,
        int64 timestamp_unix,
        string source,
        string? reporter = null,
        string? dxcc = null,
        string? country = null,
        string? state = null,
        string? raw_payload = null
    ) {
        Object (
            call: normalize_call (call),
            grid: normalize_grid_unchecked (grid),
            latitude: latitude,
            longitude: longitude,
            band: normalize_optional_upper (band),
            mode: normalize_optional_upper (mode),
            frequency: frequency,
            snr: snr,
            timestamp_unix: timestamp_unix,
            source: normalize_source (source),
            reporter: normalize_optional_upper (reporter),
            dxcc: normalize_optional_upper (dxcc),
            country: normalize_optional_title (country),
            state: normalize_optional_upper (state),
            raw_payload: raw_payload
        );
    }

    public SignalReport.from_grid (
        string call,
        string grid,
        string? band,
        string? mode,
        double frequency,
        int snr,
        int64 timestamp_unix,
        string source,
        string? reporter = null,
        string? dxcc = null,
        string? country = null,
        string? state = null,
        string? raw_payload = null
    ) throws Error {
        var normalized_grid = Maidenhead.normalize (grid);
        var center = Maidenhead.center (normalized_grid);

        this (
            call,
            normalized_grid,
            center.latitude,
            center.longitude,
            band,
            mode,
            frequency,
            snr,
            timestamp_unix,
            source,
            reporter,
            dxcc,
            country,
            state,
            raw_payload
        );
    }

    public SignalReport normalized () throws Error {
        return new SignalReport.from_grid (
            call,
            grid,
            band,
            mode,
            frequency,
            snr,
            timestamp_unix,
            source,
            reporter,
            dxcc,
            country,
            state,
            raw_payload
        );
    }

    public static string normalize_call (string call) {
        return call.strip ().ascii_up ();
    }

    public static string normalize_grid_unchecked (string grid) {
        return grid.strip ().ascii_up ();
    }

    public static string normalize_source (string source) {
        var normalized = source.strip ().ascii_up ();
        return normalized == "" ? "UNKNOWN" : normalized;
    }

    public static string? normalize_optional_upper (string? value) {
        if (value == null)
            return null;

        var normalized = value.strip ().ascii_up ();
        return normalized == "" ? null : normalized;
    }

    private static string? normalize_optional_title (string? value) {
        if (value == null)
            return null;

        var normalized = value.strip ();
        return normalized == "" ? null : normalized;
    }
}
