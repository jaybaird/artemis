/* src/map/map_marker_popover.vala
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

[GtkTemplate (ui = "/com/k0vcz/artemis/ui/map_marker_popover.ui")]
public sealed class MapMarkerPopover : Gtk.Popover {
  [GtkChild]
  private unowned Gtk.Label marker_title;

  [GtkChild]
  private unowned Gtk.Label marker_subtitle;

  private string _title;
  public string title {
    get {
      return _title;
    }
    set {
      _title = value;
      marker_title.label = _title;
    }
  }

  private string _subtitle;
  public string subtitle {
    get {
      return _subtitle;
    }
    set {
      _subtitle = value;
      marker_subtitle.label = _subtitle;
    }
  }

  public MapMarkerPopover () {
    Object ();
  }
}
