/* src/band_strip.vala
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

public sealed class BandStrip : Gtk.Widget {
    private string _band = "All";

    public string band {
        get {
            return _band;
        }
        set {
            _band = value;
            sync_band_css ();
        }
    }

    public BandStrip (string band = "All") {
        Object ();
        this.band = band;
    }

    construct {
        add_css_class ("band-strip");
        sync_band_css ();
    }

    private void sync_band_css () {
        foreach (var known_band in RadioConstants.BANDS) {
            remove_css_class ("band-strip-%s".printf (known_band.down ()));
        }

        add_css_class ("band-strip-%s".printf (_band.down ()));
    }
}
