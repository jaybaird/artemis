/* src/map/heatmap.vapi
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

[CCode (has_target = false)]
public delegate float HeatmapDistShapeFunc (float dist);

[CCode (cname = "heatmap_t", cheader_filename = "map/heatmap.h", cprefix = "heatmap_", free_function = "heatmap_free")]
[Compact]
public class Heatmap {
    public float* buf;
    public float max;
    public uint w;
    public uint h;

    [CCode (cname = "heatmap_new")]
    public Heatmap (uint w, uint h);

    public void add_point (uint x, uint y);
    public void add_point_with_stamp (uint x, uint y, HeatmapStamp stamp);
    public void add_weighted_point (uint x, uint y, float weight);
    public void add_weighted_point_with_stamp (uint x, uint y, float weight, HeatmapStamp stamp);
    public uchar* render_default_to (uchar* colorbuf);
    public uchar* render_to (HeatmapColorScheme colorscheme, uchar* colorbuf);
    public uchar* render_saturated_to (HeatmapColorScheme colorscheme, float saturation, uchar* colorbuf);
}

[CCode (cname = "heatmap_stamp_t", cheader_filename = "map/heatmap.h", cprefix = "heatmap_stamp_", free_function = "heatmap_stamp_free")]
[Compact]
public class HeatmapStamp {
    public float* buf;
    public uint w;
    public uint h;

    [CCode (cname = "heatmap_stamp_load")]
    public HeatmapStamp (uint w, uint h, float* data);

    [CCode (cname = "heatmap_stamp_gen")]
    public static HeatmapStamp gen (uint radius);

    [CCode (cname = "heatmap_stamp_gen_nonlinear")]
    public static HeatmapStamp gen_nonlinear (uint radius, HeatmapDistShapeFunc distshape);
}

[CCode (cname = "heatmap_colorscheme_t", cheader_filename = "map/heatmap.h", cprefix = "heatmap_colorscheme_", free_function = "heatmap_colorscheme_free")]
[Compact]
public class HeatmapColorScheme {
    public uchar* colors;
    public size_t ncolors;

    [CCode (cname = "heatmap_colorscheme_load")]
    public HeatmapColorScheme (uchar* colors, size_t ncolors);
}

[CCode (cname = "heatmap_cs_default", cheader_filename = "map/heatmap.h")]
public static unowned HeatmapColorScheme default_color_scheme;
