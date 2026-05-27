/* src/help/help_models.vala
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

public errordomain HelpError {
    INVALID_DATA
}

public enum HelpContentKind {
    PARAGRAPH,
    SPOT_BADGE_LIST
}

public class HelpContentBlock {
    public HelpContentKind kind { get; private set; }
    public string text { get; private set; }

    public HelpContentBlock.paragraph (string text) {
        this.kind = HelpContentKind.PARAGRAPH;
        this.text = text;
    }

    public HelpContentBlock.spot_badge_list () {
        this.kind = HelpContentKind.SPOT_BADGE_LIST;
        this.text = "";
    }
}

public sealed class HelpArticle : Object {
    public string id { get; construct; }
    public string title { get; construct; }
    public string summary { get; construct; }
    public string? icon { get; construct; }
    public string? badge { get; construct; }
    public ArrayList<string> paragraphs { get; construct; }
    public ArrayList<HelpContentBlock> content_blocks { get; construct; }
    public ArrayList<string> keywords { get; construct; }

    public HelpArticle (
        string id,
        string title,
        string summary,
        string? icon,
        string? badge,
        ArrayList<string> paragraphs,
        ArrayList<HelpContentBlock> content_blocks,
        ArrayList<string> keywords
    ) {
        Object (
            id: id,
            title: title,
            summary: summary,
            icon: icon,
            badge: badge,
            paragraphs: paragraphs,
            content_blocks: content_blocks,
            keywords: keywords
        );
    }

    public bool matches_query (string query) {
        string needle = query.strip ().down ();
        if (needle == "")
            return true;

        if (title.down ().contains (needle) || summary.down ().contains (needle))
            return true;

        foreach (string keyword in keywords) {
            if (keyword.down ().contains (needle))
                return true;
        }

        foreach (string paragraph in paragraphs) {
            if (paragraph.down ().contains (needle))
                return true;
        }

        return false;
    }
}

public sealed class HelpSection : Object {
    public string id { get; construct; }
    public string title { get; construct; }
    public ArrayList<HelpArticle> articles { get; construct; }

    public HelpSection (string id, string title, ArrayList<HelpArticle> articles) {
        Object (id: id, title: title, articles: articles);
    }
}

public sealed class HelpDocument : Object {
    public int schema_version { get; construct; }
    public int content_version { get; construct; }
    public ArrayList<HelpSection> sections { get; construct; }

    public HelpDocument (
        int schema_version,
        int content_version,
        ArrayList<HelpSection> sections
    ) {
        Object (
            schema_version: schema_version,
            content_version: content_version,
            sections: sections
        );
    }

    public static HelpDocument from_resource (string resource_path) throws Error {
        string json_text = (string) GLib.resources_lookup_data (
            resource_path,
            ResourceLookupFlags.NONE
        ).get_data ();

        var parser = new Json.Parser ();
        parser.load_from_data (json_text, (ssize_t) json_text.length);

        var root = parser.get_root ();
        if ((root == null) || (root.get_node_type () != Json.NodeType.OBJECT)) {
            throw new HelpError.INVALID_DATA ("Help document root must be a JSON object");
        }

        var object = root.get_object ();
        var sections_node = object.get_member ("sections");
        if ((sections_node == null) || (sections_node.get_node_type () != Json.NodeType.ARRAY)) {
            throw new HelpError.INVALID_DATA ("Help document is missing its sections array");
        }

        var sections = new ArrayList<HelpSection> ();
        var sections_array = sections_node.get_array ();
        for (uint i = 0; i < sections_array.get_length (); i++) {
            var section_object = sections_array.get_object_element (i);
            if (section_object == null)
                continue;

            sections.add (parse_section (section_object));
        }

        return new HelpDocument (
            (int) object.get_int_member_with_default ("schemaVersion", 1),
            (int) object.get_int_member_with_default ("contentVersion", 1),
            sections
        );
    }

    private static HelpSection parse_section (Json.Object object) throws HelpError {
        string id = required_string_member (object, "id");
        string title = required_string_member (object, "title");
        var articles_node = object.get_member ("articles");
        if ((articles_node == null) || (articles_node.get_node_type () != Json.NodeType.ARRAY)) {
            throw new HelpError.INVALID_DATA (
                "Help section '%s' is missing its articles array".printf (id)
            );
        }

        var articles = new ArrayList<HelpArticle> ();
        var articles_array = articles_node.get_array ();
        for (uint i = 0; i < articles_array.get_length (); i++) {
            var article_object = articles_array.get_object_element (i);
            if (article_object == null)
                continue;

            articles.add (parse_article (article_object));
        }

        return new HelpSection (id, title, articles);
    }

    private static HelpArticle parse_article (Json.Object object) throws HelpError {
        string id = required_string_member (object, "id");
        string title = required_string_member (object, "title");
        string summary = object.get_string_member_with_default ("summary", "").strip ();
        string? icon = nullable_string_member (object, "icon");
        string? badge = nullable_string_member (object, "badge");

        var paragraphs = new ArrayList<string> ();
        var content_blocks = new ArrayList<HelpContentBlock> ();
        var paragraphs_node = object.get_member ("paragraphs");
        if ((paragraphs_node != null) && (paragraphs_node.get_node_type () == Json.NodeType.ARRAY)) {
            append_paragraph_array (paragraphs, content_blocks, paragraphs_node.get_array ());
        }

        var content_node = object.get_member ("content");
        if ((content_node != null) && (content_node.get_node_type () == Json.NodeType.ARRAY)) {
            var content_array = content_node.get_array ();
            for (uint i = 0; i < content_array.get_length (); i++) {
                var content_object = content_array.get_object_element (i);
                if (content_object == null)
                    continue;

                string type = content_object.get_string_member_with_default ("type", "");
                if (type == "paragraph") {
                    string text = content_object.get_string_member_with_default ("text", "").strip ();
                    if (text != "") {
                        paragraphs.add (text);
                        content_blocks.add (new HelpContentBlock.paragraph (text));
                    }
                } else if (type == "spot-badge-list") {
                    content_blocks.add (new HelpContentBlock.spot_badge_list ());
                }
            }
        }

        if (content_blocks.size == 0) {
            throw new HelpError.INVALID_DATA (
                "Help article '%s' does not contain any content".printf (id)
            );
        }

        var keywords = new ArrayList<string> ();
        var keywords_node = object.get_member ("keywords");
        if ((keywords_node != null) && (keywords_node.get_node_type () == Json.NodeType.ARRAY)) {
            append_string_array (keywords, keywords_node.get_array ());
        }

        return new HelpArticle (
            id,
            title,
            summary,
            icon,
            badge,
            paragraphs,
            content_blocks,
            keywords
        );
    }

    private static void append_string_array (ArrayList<string> target, Json.Array array) {
        for (uint i = 0; i < array.get_length (); i++) {
            string value = array.get_string_element (i).strip ();
            if (value != "")
                target.add (value);
        }
    }

    private static void append_paragraph_array (
        ArrayList<string> paragraphs,
        ArrayList<HelpContentBlock> content_blocks,
        Json.Array array
    ) {
        for (uint i = 0; i < array.get_length (); i++) {
            string value = array.get_string_element (i).strip ();
            if (value != "") {
                paragraphs.add (value);
                content_blocks.add (new HelpContentBlock.paragraph (value));
            }
        }
    }

    private static string required_string_member (Json.Object object, string member) throws HelpError {
        string value = object.get_string_member_with_default (member, "").strip ();
        if (value == "") {
            throw new HelpError.INVALID_DATA (
                "Help document is missing required string member '%s'".printf (member)
            );
        }

        return value;
    }

    private static string? nullable_string_member (Json.Object object, string member) {
        string value = object.get_string_member_with_default (member, "").strip ();
        return value != "" ? value : null;
    }
}
