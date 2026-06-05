/* src/models/signal_report_bucket.vala
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

public class SignalReportBucketKey : Object {
    public string call { get; construct; }
    public string grid { get; construct; }
    public string band { get; construct; }
    public string mode { get; construct; }
    public string source { get; construct; }
    public string stable_id { get; construct; }

    public SignalReportBucketKey (SignalReport report) {
        var call = normalize_callsign (report.call);
        var grid = normalize_bucket_grid (report.grid);
        var band = SignalReport.normalize_optional_upper (report.band) ?? "";
        var mode = SignalReport.normalize_optional_upper (report.mode) ?? "";
        var source = SignalReport.normalize_source (report.source);

        Object (
            call: call,
            grid: grid,
            band: band,
            mode: mode,
            source: source,
            stable_id: "%s|%s|%s|%s|%s".printf (call, grid, band, mode, source)
        );
    }

    public static string normalize_bucket_grid (string grid) {
        var normalized = strip_up (grid);
        return normalized.length > 4 ? normalized.substring (0, 4) : normalized;
    }
}

private class SignalReportBucketSlice : Object {
    public int64 slice_start_unix { get; construct; }
    public uint count { get; private set; default = 0; }
    public int64 latest_timestamp_unix { get; private set; default = 0; }
    public int strongest_snr { get; private set; default = int.MIN; }
    public int64 snr_sum { get; private set; default = 0; }
    public double latitude_sum { get; private set; default = 0.0; }
    public double longitude_sum { get; private set; default = 0.0; }

    public SignalReportBucketSlice (int64 slice_start_unix) {
        Object (slice_start_unix: slice_start_unix);
    }

    public void add_report (SignalReport report) {
        count++;
        snr_sum += report.snr;
        latitude_sum += report.latitude;
        longitude_sum += report.longitude;

        if (report.timestamp_unix > latest_timestamp_unix)
            latest_timestamp_unix = report.timestamp_unix;

        if (report.snr > strongest_snr)
            strongest_snr = report.snr;
    }
}

public class SignalReportBucket : Object {
    private const int64 TIME_SLICE_SECONDS = 30;
    private const int MAX_RETAINED_SLICES = 300;

    private ArrayList<SignalReportBucketSlice> slices =
        new ArrayList<SignalReportBucketSlice> ();

    public SignalReportBucketKey key { get; construct; }
    public uint count { get; private set; default = 0; }
    public int64 latest_timestamp_unix { get; private set; default = 0; }
    public int strongest_snr { get; private set; default = int.MIN; }
    public double average_snr { get; private set; default = 0.0; }
    public double latitude { get; private set; default = 0.0; }
    public double longitude { get; private set; default = 0.0; }

    public SignalReportBucket (SignalReportBucketKey key) {
        Object (key: key);
    }

    public void add_report (SignalReport report) {
        var slice = find_or_create_slice (slice_start_for_timestamp (report.timestamp_unix));
        slice.add_report (report);
        prune_excess_slices ();
        recompute ();
    }

    public bool expire_before (int64 cutoff_unix) {
        var previous_count = slices.size;
        var retained = new ArrayList<SignalReportBucketSlice> ();
        foreach (var slice in slices) {
            if (slice.slice_start_unix + TIME_SLICE_SECONDS > cutoff_unix)
                retained.add (slice);
        }

        if (retained.size == previous_count)
            return false;

        slices = retained;
        recompute ();

        return true;
    }

    public HeatmapPoint to_heatmap_point () {
        return to_heatmap_point_at (new DateTime.now_utc ().to_unix (), HeatmapModel.DEFAULT_MAX_AGE_SECONDS);
    }

    public HeatmapPoint to_heatmap_point_at (int64 now_unix, uint max_age_seconds) {
        var weight = HeatmapModel.bucket_weight (strongest_snr, count);
        weight *= HeatmapModel.age_multiplier (latest_timestamp_unix, now_unix, max_age_seconds);

        return new HeatmapPoint (
            latitude,
            longitude,
            weight,
            count,
            strongest_snr,
            latest_timestamp_unix,
            key.stable_id
        );
    }

    private void recompute () {
        count = 0;

        if (slices.size == 0) {
            latest_timestamp_unix = 0;
            strongest_snr = int.MIN;
            average_snr = 0.0;
            latitude = 0.0;
            longitude = 0.0;
            return;
        }

        int64 snr_sum = 0;
        double latitude_sum = 0.0;
        double longitude_sum = 0.0;
        latest_timestamp_unix = int64.MIN;
        strongest_snr = int.MIN;

        foreach (var slice in slices) {
            count += slice.count;
            snr_sum += slice.snr_sum;
            latitude_sum += slice.latitude_sum;
            longitude_sum += slice.longitude_sum;

            if (slice.latest_timestamp_unix > latest_timestamp_unix)
                latest_timestamp_unix = slice.latest_timestamp_unix;

            if (slice.strongest_snr > strongest_snr)
                strongest_snr = slice.strongest_snr;
        }

        average_snr = (double) snr_sum / count;
        latitude = latitude_sum / count;
        longitude = longitude_sum / count;
    }

    private SignalReportBucketSlice find_or_create_slice (int64 slice_start_unix) {
        foreach (var slice in slices) {
            if (slice.slice_start_unix == slice_start_unix)
                return slice;
        }

        var slice = new SignalReportBucketSlice (slice_start_unix);
        slices.add (slice);
        return slice;
    }

    private void prune_excess_slices () {
        while (slices.size > MAX_RETAINED_SLICES) {
            var oldest_index = 0;
            var oldest_start = slices[0].slice_start_unix;

            for (var index = 1; index < slices.size; index++) {
                if (slices[index].slice_start_unix >= oldest_start)
                    continue;

                oldest_start = slices[index].slice_start_unix;
                oldest_index = index;
            }

            slices.remove_at (oldest_index);
        }
    }

    private static int64 slice_start_for_timestamp (int64 timestamp_unix) {
        return (timestamp_unix / TIME_SLICE_SECONDS) * TIME_SLICE_SECONDS;
    }
}
