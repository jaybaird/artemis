/* src/avatar_detail_dialog.vala
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

[GtkTemplate (ui = "/com/k0vcz/artemis/ui/avatar_detail_dialog.ui")]
public sealed class AvatarDetailDialog : Adw.Dialog {
    [GtkChild]
    private unowned Adw.Avatar avatar_image;

    [GtkChild]
    private unowned Adw.WindowTitle title_widget;

    private bool disposed = false;
    private ulong callsign_cache_handler = 0;

    public string callsign { get; construct; }

    public AvatarDetailDialog (string avatar_callsign) {
      Object (
        callsign: avatar_callsign
      );
    }

    construct {
      title_widget.title = display_callsign (callsign);
    }

    public override void dispose () {
      disposed = true;

      if (callsign_cache_handler != 0) {
        Application.callsign_cache.disconnect (callsign_cache_handler);
        callsign_cache_handler = 0;
      }

      base.dispose ();
    }

    public override void constructed () {
      base.constructed ();

      callsign_cache_handler = Application.callsign_cache.entry_updated.connect ((cs) => {
          if (cs == callsign)
            avatar_image.custom_image = Application.callsign_cache.peek_avatar (callsign);
      });

      Idle.add (() => {
        if (!disposed)
          load_avatar.begin ();
        return Source.REMOVE;
      });
    }

    private async void load_avatar () {
      if (disposed || is_empty_or_whitespace (callsign))
        return;

      var texture = yield Application.callsign_cache.get_avatar_for (callsign);
      avatar_image.custom_image = texture;
    }
}
