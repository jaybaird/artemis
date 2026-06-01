/* src/spot_detail.vala
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
using Adw;

#if ARTEMIS_UNIX
using WebKit;
#endif

public class ParkDetailsView : Adw.Window {
#if ARTEMIS_UNIX
    private WebKit.WebView webview;
    private Adw.WindowTitle title_widget;

    public ParkDetailsView (Gtk.Window parent, string title, string url) {
        Object (
            application: Application.app,
            transient_for: parent,
            modal: false,
            default_width: 800,
            default_height: 600
        );

        var toolbar_view = new Adw.ToolbarView ();

        var headerbar = new Adw.HeaderBar ();
        title_widget = new Adw.WindowTitle (title, "");
        headerbar.set_title_widget (title_widget);

        toolbar_view.add_top_bar (headerbar);

        var scrolled = new Gtk.ScrolledWindow () {
            hexpand = true,
            vexpand = true
        };

        webview = new WebKit.WebView ();
        webview.load_uri (url);
        webview.notify["title"].connect (() => {
          title_widget.title = "%s • %s".printf (webview.title, Build.NAME);
        });

        scrolled.set_child (webview);
        toolbar_view.set_content (scrolled);
        content = toolbar_view;
    }
#endif
} /* class ParkDetailsView */
