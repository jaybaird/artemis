/* src/help/help_window.vala
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

private sealed class HelpSectionHeaderRow : Gtk.ListBoxRow {
    public HelpSectionHeaderRow (string title) {
        Object (activatable: false, selectable: false);

        var label = new Gtk.Label (title) {
            xalign = 0.0f,
            margin_top = 16,
            margin_bottom = 8,
            margin_start = 12,
            margin_end = 12
        };
        label.add_css_class ("caption-heading");
        label.add_css_class ("dim-label");
        child = label;
    }
}

private sealed class HelpArticleRow : Gtk.ListBoxRow {
    public HelpArticle article { get; construct; }

    public HelpArticleRow (HelpArticle article) {
        Object (article: article);

        var outer = new Gtk.Box (Gtk.Orientation.VERTICAL, 6) {
            margin_top = 10,
            margin_bottom = 10,
            margin_start = 12,
            margin_end = 12
        };

        var header = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 8);
        if (article.icon != null) {
            var image = new Gtk.Image.from_icon_name (article.icon) {
                pixel_size = 16,
                valign = Gtk.Align.START
            };
            image.add_css_class ("dim-label");
            header.append (image);
        }

        var title = new Gtk.Label (article.title) {
            xalign = 0.0f,
            wrap = true
        };
        title.add_css_class ("heading");
        header.append (title);

        if (article.badge != null) {
            var badge = new Gtk.Label (article.badge) {
                xalign = 1.0f
            };
            badge.add_css_class ("caption");
            badge.add_css_class ("accent");
            header.append (badge);
        }

        outer.append (header);

        var summary = new Gtk.Label (article.summary) {
            xalign = 0.0f,
            wrap = true,
            max_width_chars = 36
        };
        summary.add_css_class ("dim-label");
        summary.add_css_class ("body");
        outer.append (summary);

        child = outer;
    }
}

public sealed class HelpWindow : Gtk.Window {
    private HelpDocument document;
    private Gtk.SearchEntry search_entry;
    private Gtk.ListBox article_list;
    private Gtk.Box article_body;
    private HelpArticle? current_article = null;

    public HelpWindow (Gtk.Application app) throws Error {
        Object (application: app, title: _("Artemis Help"));
        document = HelpDocument.from_resource ("/com/k0vcz/artemis/help/help.json");
        build_ui ();
    }

    private void build_ui () {
        default_width = 1080;
        default_height = 760;

        var header = new Adw.HeaderBar ();
        var title = new Adw.WindowTitle (_("Artemis Help"), "");
        header.set_title_widget (title);
        set_titlebar (header);

        search_entry = new Gtk.SearchEntry () {
            width_request = 320,
            placeholder_text = _("Search Help")
        };
        header.pack_end (search_entry);

        var paned = new Gtk.Paned (Gtk.Orientation.HORIZONTAL) {
            vexpand = true,
            shrink_start_child = false,
            shrink_end_child = false,
            position = 360,
            wide_handle = true
        };

        article_list = new Gtk.ListBox () {
            selection_mode = Gtk.SelectionMode.BROWSE
        };
        article_list.row_activated.connect ((row) => {
            if (row is HelpArticleRow)
                show_article (((HelpArticleRow) row).article);
        });
        article_list.selected_rows_changed.connect (() => {
            var row = article_list.get_selected_row ();
            if (row is HelpArticleRow)
                show_article (((HelpArticleRow) row).article);
        });

        var sidebar_box = new Gtk.Box (Gtk.Orientation.VERTICAL, 0) {
            vexpand = true
        };
        sidebar_box.add_css_class ("sidebar");

        var article_list_scroll = new Gtk.ScrolledWindow () {
            hscrollbar_policy = Gtk.PolicyType.NEVER,
            min_content_width = 320,
            vexpand = true
        };
        article_list_scroll.set_child (article_list);
        sidebar_box.append (article_list_scroll);
        paned.set_start_child (sidebar_box);

        article_body = new Gtk.Box (Gtk.Orientation.VERTICAL, 16) {
            margin_top = 24,
            margin_bottom = 24,
            margin_start = 24,
            margin_end = 24
        };

        var article_scroll = new Gtk.ScrolledWindow () {
            hscrollbar_policy = Gtk.PolicyType.NEVER,
            vexpand = true
        };
        article_scroll.set_child (article_body);
        paned.set_end_child (article_scroll);

        set_child (paned);

        search_entry.search_changed.connect (rebuild_article_list);
        rebuild_article_list ();
    }

    private void rebuild_article_list () {
        clear_list_box (article_list);

        string query = search_entry.text.strip ();
        HelpArticle? first_match = null;
        bool selected_still_visible = false;

        foreach (HelpSection section in document.sections) {
            var matches = new ArrayList<HelpArticle> ();
            foreach (HelpArticle article in section.articles) {
                if (article.matches_query (query))
                    matches.add (article);
            }

            if (matches.size == 0)
                continue;

            article_list.append (new HelpSectionHeaderRow (section.title));

            foreach (HelpArticle article in matches) {
                var row = new HelpArticleRow (article);
                article_list.append (row);

                if (first_match == null)
                    first_match = article;
                if (current_article == article)
                    selected_still_visible = true;
            }
        }

        if (first_match == null) {
            show_empty (_("No Help Articles"), _("Try a different search term."));
            return;
        }

        if (selected_still_visible && (current_article != null)) {
            select_article_row (current_article);
            show_article (current_article);
            return;
        }

        select_article_row (first_match);
        show_article (first_match);
    }

    private void select_article_row (HelpArticle article) {
        for (Gtk.Widget? child = article_list.get_first_child (); child != null;
             child = child.get_next_sibling ()) {
            if (child is HelpArticleRow) {
                var row = (HelpArticleRow) child;
                if (row.article == article) {
                    article_list.select_row (row);
                    return;
                }
            }
        }
    }

    private void show_article (HelpArticle article) {
        current_article = article;
        clear_box (article_body);

        if (article.icon != null) {
            var image = new Gtk.Image.from_icon_name (article.icon) {
                pixel_size = 28,
                halign = Gtk.Align.START
            };
            image.add_css_class ("accent");
            article_body.append (image);
        }

        var title = new Gtk.Label (article.title) {
            xalign = 0.0f,
            wrap = true,
            max_width_chars = 48
        };
        title.add_css_class ("title-2");
        article_body.append (title);

        if (article.badge != null) {
            var badge = new Gtk.Label (article.badge) {
                xalign = 0.0f,
                halign = Gtk.Align.START
            };
            badge.add_css_class ("caption");
            badge.add_css_class ("accent");
            article_body.append (badge);
        }

        if (article.summary != "") {
            var summary = new Gtk.Label (article.summary) {
                xalign = 0.0f,
                wrap = true,
                max_width_chars = 56
            };
            summary.add_css_class ("title-4");
            summary.add_css_class ("dim-label");
            article_body.append (summary);
        }

        foreach (string paragraph in article.paragraphs) {
            var label = new Gtk.Label (paragraph) {
                xalign = 0.0f,
                wrap = true,
                max_width_chars = 64,
                selectable = true
            };
            label.add_css_class ("body");
            article_body.append (label);
        }
    }

    private void show_empty (string title_text, string body_text) {
        current_article = null;
        clear_box (article_body);

        var status = new Adw.StatusPage () {
            title = title_text,
            description = body_text,
            icon_name = "help-browser-symbolic",
            vexpand = true,
            valign = Gtk.Align.CENTER
        };
        article_body.append (status);
    }

    private void clear_box (Gtk.Box box) {
        for (Gtk.Widget? child = box.get_first_child (); child != null; ) {
            Gtk.Widget? next = child.get_next_sibling ();
            box.remove (child);
            child = next;
        }
    }

    private void clear_list_box (Gtk.ListBox list_box) {
        for (Gtk.Widget? child = list_box.get_first_child (); child != null; ) {
            Gtk.Widget? next = child.get_next_sibling ();
            list_box.remove (child);
            child = next;
        }
    }
}
