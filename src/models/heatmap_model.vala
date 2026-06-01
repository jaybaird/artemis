/* src/models/heatmap_model.vala
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

public class HeatmapModel : Object {
    public const uint DEFAULT_MAX_AGE_SECONDS = 1800;
    public const double SNR_FLOOR = -25.0;
    public const double SNR_CEILING = 5.0;
    public const double DENSITY_LOG_SCALE = 0.08;
    public const double MAX_DENSITY_BONUS = 0.35;

    private HashMap<string, SignalReportBucket> buckets =
        new HashMap<string, SignalReportBucket> ();

    private uint _max_age_seconds = DEFAULT_MAX_AGE_SECONDS;
    private string? _band_filter = null;
    private string? _mode_filter = null;
    private string? _source_filter = null;

    public signal void changed ();

    public uint max_age_seconds {
        get { return _max_age_seconds; }
        set {
            if (_max_age_seconds == value)
                return;

            _max_age_seconds = value;
            changed ();
        }
    }

    public string? band_filter {
        get { return _band_filter; }
        set {
            var normalized = SignalReport.normalize_optional_upper (value);
            if (_band_filter == normalized)
                return;

            _band_filter = normalized;
            changed ();
        }
    }

    public string? mode_filter {
        get { return _mode_filter; }
        set {
            var normalized = SignalReport.normalize_optional_upper (value);
            if (_mode_filter == normalized)
                return;

            _mode_filter = normalized;
            changed ();
        }
    }

    public string? source_filter {
        get { return _source_filter; }
        set {
            var normalized = normalize_optional_source (value);
            if (_source_filter == normalized)
                return;

            _source_filter = normalized;
            changed ();
        }
    }

    public HeatmapModel () {
        Object ();
    }

    public void add_report (SignalReport report) {
        if (add_report_internal (report))
            changed ();
    }

    public void add_reports (Collection<SignalReport> reports) {
        var added = false;

        foreach (var report in reports) {
            if (add_report_internal (report))
                added = true;
        }

        if (added)
            changed ();
    }

    public void clear () {
        if (buckets.size == 0)
            return;

        buckets.clear ();
        changed ();
    }

    public void expire_old_reports () {
        var now = new DateTime.now_utc ().to_unix ();
        expire_reports_before (now - max_age_seconds);
    }

    public void expire_reports_before (int64 cutoff_unix) {
        var expired_keys = new ArrayList<string> ();
        var changed_reports = false;

        foreach (var entry in buckets.entries) {
            if (!entry.value.expire_before (cutoff_unix))
                continue;

            changed_reports = true;
            if (entry.value.count == 0)
                expired_keys.add (entry.key);
        }

        if (!changed_reports)
            return;

        foreach (var key in expired_keys) {
            buckets.unset (key);
        }

        changed ();
    }

    public Gee.List<HeatmapPoint> get_heatmap_points () {
        return get_heatmap_points_at (new DateTime.now_utc ().to_unix ());
    }

    public Gee.List<HeatmapPoint> get_heatmap_points_at (int64 now_unix) {
        var points = new ArrayList<HeatmapPoint> ();

        foreach (var bucket in buckets.values) {
            if (!bucket_matches_filters (bucket))
                continue;

            var point = bucket.to_heatmap_point_at (now_unix, max_age_seconds);
            if (point.weight > 0.0f)
                points.add (point);
        }

        return points;
    }

    public uint bucket_count () {
        return (uint) buckets.size;
    }

    public uint report_count () {
        uint count = 0;

        foreach (var bucket in buckets.values) {
            if (bucket_matches_filters (bucket))
                count += bucket.count;
        }

        return count;
    }

    public static float snr_to_weight (int snr) {
        return (float) clamp_double (((double) snr - SNR_FLOOR) / (SNR_CEILING - SNR_FLOOR), 0.0, 1.0);
    }

    public static float density_bonus (uint count) {
        if (count == 0)
            return 0.0f;

        return (float) double.min (Math.log (count + 1.0) * DENSITY_LOG_SCALE, MAX_DENSITY_BONUS);
    }

    public static float bucket_weight (int strongest_snr, uint count) {
        return (float) clamp_double (snr_to_weight (strongest_snr) + density_bonus (count), 0.0, 1.0);
    }

    public static float age_multiplier (int64 latest_timestamp_unix, int64 now_unix, uint max_age_seconds) {
        if (max_age_seconds == 0)
            return 1.0f;

        var age_seconds = now_unix - latest_timestamp_unix;
        if (age_seconds <= 0)
            return 1.0f;

        return (float) clamp_double (1.0 - ((double) age_seconds / max_age_seconds), 0.0, 1.0);
    }

    private bool add_report_internal (SignalReport report) {
        SignalReport normalized_report;

        try {
            normalized_report = report.normalized ();
        } catch (Error err) {
            return false;
        }

        if (normalized_report.call == "")
            return false;

        var key = new SignalReportBucketKey (normalized_report);
        var bucket = buckets.get (key.stable_id);

        if (bucket == null) {
            bucket = new SignalReportBucket (key);
            buckets.set (key.stable_id, bucket);
        }

        bucket.add_report (normalized_report);
        return true;
    }

    private bool bucket_matches_filters (SignalReportBucket bucket) {
        if (_band_filter != null && bucket.key.band != _band_filter)
            return false;

        if (_mode_filter != null && bucket.key.mode != _mode_filter)
            return false;

        if (_source_filter != null && bucket.key.source != _source_filter)
            return false;

        return true;
    }

    private static string? normalize_optional_source (string? value) {
        if (value == null)
            return null;

        var stripped = value.strip ();
        return stripped == "" ? null : SignalReport.normalize_source (stripped);
    }

    private static double clamp_double (double value, double min_value, double max_value) {
        if (value < min_value)
            return min_value;

        if (value > max_value)
            return max_value;

        return value;
    }
}
