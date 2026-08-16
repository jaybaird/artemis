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

[GtkTemplate (ui = "/com/k0vcz/artemis/ui/help_section_header_row.ui")]
private sealed class HelpSectionHeaderRow : Gtk.ListBoxRow {
    [GtkChild]
    private unowned Gtk.Label title_label;

    public HelpSectionHeaderRow (string title) {
        Object ();
        title_label.label = title;
    }
}

[GtkTemplate (ui = "/com/k0vcz/artemis/ui/help_article_row.ui")]
private sealed class HelpArticleRow : Gtk.ListBoxRow {
    [GtkChild]
    private unowned Gtk.Image icon;
    [GtkChild]
    private unowned Gtk.Label title_label;
    [GtkChild]
    private unowned Gtk.Label badge_label;
    [GtkChild]
    private unowned Gtk.Label summary_label;

    public HelpArticle article { get; construct; }

    public HelpArticleRow (HelpArticle article) {
        Object (article: article);

        if (article.icon != null) {
            icon.icon_name = article.icon;
            icon.visible = true;
        }

        title_label.label = article.title;

        if (article.badge != null) {
            badge_label.label = article.badge;
            badge_label.visible = true;
        }

        summary_label.label = article.summary;
    }
}

[GtkTemplate (ui = "/com/k0vcz/artemis/ui/help_spot_badge_row.ui")]
private sealed class HelpSpotBadgeRow : Gtk.ListBoxRow {
    [GtkChild]
    private unowned Gtk.Image icon;
    [GtkChild]
    private unowned Gtk.Label label;
    [GtkChild]
    private unowned Gtk.Label description;

    public HelpSpotBadgeRow (SpotBadgeHelpInfo badge) {
        Object ();

        icon.icon_name = badge.icon_name;
        icon.add_css_class (badge.css_class);
        label.label = badge.label;
        description.label = badge.description;
    }
}

[GtkTemplate (ui = "/com/k0vcz/artemis/ui/help_window.ui")]
public sealed class HelpWindow : Adw.Window {
    private HelpDocument document;
    [GtkChild]
    private unowned Gtk.SearchEntry search_entry;
    [GtkChild]
    private unowned Gtk.ListBox article_list;
    [GtkChild]
    private unowned Gtk.Box article_body;
    private HelpArticle? current_article = null;

    public HelpWindow (Gtk.Application app) throws Error {
        Object (application: app);
        document = HelpDocument.from_resource ("/com/k0vcz/artemis/help/help.json");
        setup_ui ();
    }

    private void setup_ui () {
        article_list.row_activated.connect ((row) => {
            if (row is HelpArticleRow)
                show_article (((HelpArticleRow) row).article);
        });
        article_list.selected_rows_changed.connect (() => {
            var row = article_list.get_selected_row ();
            if (row is HelpArticleRow)
                show_article (((HelpArticleRow) row).article);
        });

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

        foreach (HelpContentBlock block in article.content_blocks) {
            switch (block.kind) {
                case HelpContentKind.PARAGRAPH:
                    article_body.append (build_paragraph (block.text));
                    break;
                case HelpContentKind.SPOT_BADGE_LIST:
                    article_body.append (build_spot_badge_list ());
                    break;
                default:
                    break;
            }
        }
    }

    private Gtk.Widget build_paragraph (string paragraph) {
        var label = new Gtk.Label (paragraph) {
            xalign = 0.0f,
            wrap = true,
            max_width_chars = 64,
            selectable = true
        };
        label.add_css_class ("body");
        return label;
    }

    private Gtk.Widget build_spot_badge_list () {
        var list = new Gtk.ListBox () {
            selection_mode = Gtk.SelectionMode.NONE
        };
        list.add_css_class ("boxed-list");

        foreach (SpotBadgeHelpInfo badge in spot_badge_help_items ())
            list.append (new HelpSpotBadgeRow (badge));

        return list;
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
