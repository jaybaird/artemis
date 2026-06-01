/* src/models/heatmap_point.vala
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

public class HeatmapPoint : Object {
    public double latitude { get; construct; }
    public double longitude { get; construct; }
    public float weight { get; construct; }
    public uint count { get; construct; }
    public int strongest_snr { get; construct; }
    public int64 latest_timestamp_unix { get; construct; }
    public string? bucket_key { get; construct; }

    public HeatmapPoint (
        double latitude,
        double longitude,
        float weight,
        uint count,
        int strongest_snr,
        int64 latest_timestamp_unix,
        string? bucket_key = null
    ) {
        Object (
            latitude: latitude,
            longitude: longitude,
            weight: weight,
            count: count,
            strongest_snr: strongest_snr,
            latest_timestamp_unix: latest_timestamp_unix,
            bucket_key: bucket_key
        );
    }
}
