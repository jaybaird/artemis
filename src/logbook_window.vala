/* src/logbook_window.vala
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

public sealed class LogbookQsoItem : Object {
    public QsoRow qso { get; construct; }
    public string date { get; construct; }
    public string raw_date { get; construct; }
    public string activator { get; construct; }
    public string reference { get; construct; }
    public string park_name { get; construct; }
    public string band { get; construct; }
    public string mode { get; construct; }
    public bool has_actionable_items { get; construct; }
    public string action_tooltip { get; construct; }

    public LogbookQsoItem (QsoRow qso) {
        var display_date = display_datetime (qso.created_utc);
        var qso_band = band_from_khz (qso.frequency_khz);
        var missing_park_ref = is_empty_or_whitespace (qso.park_ref);
        var missing_park = missing_park_ref || is_empty_or_whitespace (qso.park_name);
        var qrz_retry = !qso.qrz_uploaded &&
            has_text (qso.qrz_error) &&
            Application.logging_service.preferences.enable_qrz_logging &&
            Application.logging_service.preferences.qrz_api_key != "";
        var local_error = has_text (qso.local_adif_error);
        var pota_error = has_text (qso.pota_error);
        Object (
            qso: qso,
            date: display_date,
            raw_date: qso.created_utc ?? "",
            activator: qso.callsign ?? "",
            reference: qso.park_ref ?? "",
            park_name: qso.park_name ?? "",
            band: qso_band,
            mode: qso.mode ?? "",
            has_actionable_items: missing_park || qrz_retry || local_error || pota_error,
            action_tooltip: action_tooltip_for (missing_park_ref, missing_park, qrz_retry, local_error, pota_error)
        );
    }

    private static string action_tooltip_for (
        bool missing_park_ref,
        bool missing_park,
        bool qrz_retry,
        bool local_error,
        bool pota_error
    ) {
        var actions = new Gee.ArrayList<string> ();
        if (missing_park_ref)
            actions.add (_("Park reference is missing"));
        else if (missing_park)
            actions.add (_("Park details are missing"));
        if (qrz_retry)
            actions.add (_("QRZ upload can be retried"));
        if (local_error)
            actions.add (_("Local ADIF logging failed"));
        if (pota_error)
            actions.add (_("POTA spot failed"));

        var tooltip = "";
        foreach (var action in actions) {
            if (tooltip != "")
                tooltip += "\n";
            tooltip += action;
        }
        return tooltip;
    }
}

public sealed class LogbookParkItem : Object {
    public string reference { get; construct; }
    public string park_name { get; construct; }
    public string location { get; construct; }
    public int qsos { get; construct; }
    public string first_qso { get; construct; }
    public string raw_first_qso { get; construct; }

    public LogbookParkItem (HuntedParkRow park) {
        var first = display_datetime (park.first_qso_date, "%x");
        Object (
            reference: park.reference,
            park_name: park.park_name ?? "",
            location: park.location ?? "",
            qsos: park.qso_count,
            first_qso: first,
            raw_first_qso: park.first_qso_date ?? ""
        );
    }
}

[GtkTemplate (ui = "/com/k0vcz/artemis/ui/logbook_window.ui")]
public sealed class LogbookWindow : Adw.Window {
    [GtkChild]
    private unowned Adw.ViewStack views;

    [GtkChild]
    private unowned Gtk.SearchEntry search_entry;

    [GtkChild]
    private unowned Gtk.Button refresh_button;

    [GtkChild]
    private unowned Gtk.Stack qso_stack;

    [GtkChild]
    private unowned Gtk.ScrolledWindow qso_scroll;

    [GtkChild]
    private unowned Adw.StatusPage qso_status_page;

    [GtkChild]
    private unowned Gtk.ColumnView qso_column_view;

    [GtkChild]
    private unowned Gtk.Stack parks_stack;

    [GtkChild]
    private unowned Gtk.ScrolledWindow parks_scroll;

    [GtkChild]
    private unowned Adw.StatusPage parks_status_page;

    [GtkChild]
    private unowned Gtk.ColumnView parks_column_view;

    [GtkChild]
    private unowned Gtk.Label result_count_label;

    [GtkChild]
    private unowned Gtk.Button previous_page_button;

    [GtkChild]
    private unowned Gtk.Label page_label;

    [GtkChild]
    private unowned Gtk.Button next_page_button;

    private const int PAGE_SIZE = 50;
    private GLib.ListStore qso_store;
    private GLib.ListStore parks_store;
    private Gtk.ColumnViewColumn qso_date_column;
    private Gtk.ColumnViewColumn qso_activator_column;
    private Gtk.ColumnViewColumn qso_reference_column;
    private Gtk.ColumnViewColumn qso_park_column;
    private Gtk.ColumnViewColumn qso_band_column;
    private Gtk.ColumnViewColumn qso_mode_column;
    private Gtk.ColumnViewColumn parks_reference_column;
    private Gtk.ColumnViewColumn parks_park_column;
    private Gtk.ColumnViewColumn parks_location_column;
    private Gtk.ColumnViewColumn parks_qsos_column;
    private Gtk.ColumnViewColumn parks_first_qso_column;
    private Gtk.SingleSelection qso_selection;
    private Gtk.Popover qso_context_popover;
    private Gtk.Button qso_lookup_park_button;
    private LogbookQsoItem? context_qso_item = null;
    private int qso_offset = 0;
    private int qso_total_count = 0;
    private int parks_offset = 0;
    private int parks_total_count = 0;
    private LogbookQsoSortColumn qso_sort_column = LogbookQsoSortColumn.DATE;
    private HuntedParkSortColumn parks_sort_column = HuntedParkSortColumn.FIRST_QSO;
    private LogbookSortDirection qso_sort_direction = LogbookSortDirection.DESC;
    private LogbookSortDirection parks_sort_direction = LogbookSortDirection.DESC;
    private bool handling_sort_change = false;
    private bool qso_load_error = false;
    private bool parks_load_error = false;

    public LogbookWindow (Gtk.Window? parent = null) {
        Object (
            transient_for: parent
        );
    }

    construct {
        qso_store = new GLib.ListStore (typeof (LogbookQsoItem));
        parks_store = new GLib.ListStore (typeof (LogbookParkItem));

        setup_qso_columns ();
        setup_parks_columns ();
        bind_models ();
        setup_qso_context_menu ();

        search_entry.search_changed.connect (() => {
            qso_offset = 0;
            parks_offset = 0;
            reload ();
        });
        refresh_button.clicked.connect (() => reload ());
        previous_page_button.clicked.connect (() => previous_page ());
        next_page_button.clicked.connect (() => next_page ());
        views.notify["visible-child-name"].connect (() => update_pager ());
        qso_column_view.activate.connect ((position) => open_qso_editor (position));

        reload ();
    }

    private void bind_models () {
        qso_selection = new Gtk.SingleSelection (qso_store);
        qso_column_view.model = qso_selection;
        parks_column_view.model = new Gtk.SingleSelection (parks_store);

        var qso_sorter = qso_column_view.sorter as Gtk.ColumnViewSorter;
        if (qso_sorter != null)
            qso_sorter.changed.connect ((change) => on_qso_sort_changed (qso_sorter));

        var parks_sorter = parks_column_view.sorter as Gtk.ColumnViewSorter;
        if (parks_sorter != null)
            parks_sorter.changed.connect ((change) => on_parks_sort_changed (parks_sorter));

        handling_sort_change = true;
        qso_column_view.sort_by_column (qso_date_column, Gtk.SortType.DESCENDING);
        parks_column_view.sort_by_column (parks_first_qso_column, Gtk.SortType.DESCENDING);
        handling_sort_change = false;
    }

    private void setup_qso_columns () {
        append_qso_action_column ();
        qso_date_column = append_text_column (
            qso_column_view,
            _("Date"),
            (item) => ((LogbookQsoItem)item).date,
            (a, b) => compare_strings (((LogbookQsoItem)a).raw_date, ((LogbookQsoItem)b).raw_date),
            true
        );
        qso_activator_column = append_text_column (
            qso_column_view,
            _("Activator"),
            (item) => ((LogbookQsoItem)item).activator,
            (a, b) => compare_strings (((LogbookQsoItem)a).activator, ((LogbookQsoItem)b).activator),
            true
        );
        qso_reference_column = append_text_column (
            qso_column_view,
            _("Reference"),
            (item) => ((LogbookQsoItem)item).reference,
            (a, b) => compare_strings (((LogbookQsoItem)a).reference, ((LogbookQsoItem)b).reference),
            true
        );
        qso_park_column = append_text_column (
            qso_column_view,
            _("Park"),
            (item) => ((LogbookQsoItem)item).park_name,
            (a, b) => compare_strings (((LogbookQsoItem)a).park_name, ((LogbookQsoItem)b).park_name)
        );
        qso_band_column = append_band_column ();
        qso_mode_column = append_text_column (
            qso_column_view,
            _("Mode"),
            (item) => ((LogbookQsoItem)item).mode,
            (a, b) => compare_strings (((LogbookQsoItem)a).mode, ((LogbookQsoItem)b).mode)
        );
    }

    private void setup_parks_columns () {
        parks_reference_column = append_text_column (
            parks_column_view,
            _("Reference"),
            (item) => ((LogbookParkItem)item).reference,
            (a, b) => compare_strings (((LogbookParkItem)a).reference, ((LogbookParkItem)b).reference),
            true
        );
        parks_park_column = append_text_column (
            parks_column_view,
            _("Park"),
            (item) => ((LogbookParkItem)item).park_name,
            (a, b) => compare_strings (((LogbookParkItem)a).park_name, ((LogbookParkItem)b).park_name)
        );
        parks_location_column = append_text_column (
            parks_column_view,
            _("Location"),
            (item) => ((LogbookParkItem)item).location,
            (a, b) => compare_strings (((LogbookParkItem)a).location, ((LogbookParkItem)b).location)
        );
        parks_qsos_column = append_text_column (
            parks_column_view,
            _("QSOs"),
            (item) => "%d".printf (((LogbookParkItem)item).qsos),
            (a, b) => compare_ints (((LogbookParkItem)a).qsos, ((LogbookParkItem)b).qsos)
        );
        parks_first_qso_column = append_text_column (
            parks_column_view,
            _("First QSO"),
            (item) => ((LogbookParkItem)item).first_qso,
            (a, b) => compare_strings (((LogbookParkItem)a).raw_first_qso, ((LogbookParkItem)b).raw_first_qso),
            true
        );
    }

    private delegate string CellTextFunc (Object item);
    private delegate Gtk.Ordering ItemCompareFunc (Object a, Object b);

    private void append_qso_action_column () {
        var factory = new Gtk.SignalListItemFactory ();
        factory.setup.connect ((object) => {
            var list_item = object as Gtk.ListItem;
            var icon = new Gtk.Image.from_icon_name ("dialog-warning-symbolic") {
                valign = Gtk.Align.CENTER,
                halign = Gtk.Align.CENTER
            };
            icon.add_css_class ("logbook-action-warning");
            list_item.child = icon;
        });
        factory.bind.connect ((object) => {
            var list_item = object as Gtk.ListItem;
            var icon = list_item.child as Gtk.Image;
            var item = list_item.item as LogbookQsoItem;
            if (icon == null || item == null)
                return;

            icon.visible = item.has_actionable_items;
            icon.tooltip_text = item.action_tooltip;
        });

        qso_column_view.append_column (new Gtk.ColumnViewColumn ("", factory) {
            fixed_width = 36,
            resizable = false
        });
    }

    private Gtk.ColumnViewColumn append_text_column (
        Gtk.ColumnView view,
        string title,
        CellTextFunc text_func,
        ItemCompareFunc compare_func,
        bool numeric = false
    ) {
        var factory = new Gtk.SignalListItemFactory ();
        factory.setup.connect ((object) => {
            var list_item = object as Gtk.ListItem;
            var label = new Gtk.Label ("") {
                xalign = 0.0f,
                hexpand = true,
                ellipsize = Pango.EllipsizeMode.END
            };
            if (numeric)
                label.add_css_class ("numeric");
            list_item.child = label;
        });
        factory.bind.connect ((object) => {
            var list_item = object as Gtk.ListItem;
            var label = list_item.child as Gtk.Label;
            var item = list_item.item as Object;
            if (label != null && item != null)
                label.label = text_func (item);
        });

        var column = new Gtk.ColumnViewColumn (title, factory) {
            resizable = true,
            expand = title == _("Park") || title == _("Location")
        };
        column.sorter = new Gtk.CustomSorter ((a, b) => compare_func (a as Object, b as Object));
        view.append_column (column);
        return column;
    }

    private Gtk.ColumnViewColumn append_band_column () {
        var factory = new Gtk.SignalListItemFactory ();
        factory.setup.connect ((object) => {
            var list_item = object as Gtk.ListItem;
            var box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 6);
            box.append (new BandStrip ("All") {
                valign = Gtk.Align.CENTER
            });
            box.append (new Gtk.Label ("") {
                xalign = 0.0f,
                hexpand = true
            });
            var label = box.get_last_child () as Gtk.Label;
            if (label != null)
                label.add_css_class ("numeric");
            list_item.child = box;
        });
        factory.bind.connect ((object) => {
            var list_item = object as Gtk.ListItem;
            var item = list_item.item as LogbookQsoItem;
            var box = list_item.child as Gtk.Box;
            if (item == null || box == null)
                return;

            var strip = box.get_first_child () as BandStrip;
            var label = strip != null ? strip.get_next_sibling () as Gtk.Label : null;
            if (strip != null)
                strip.band = item.band;
            if (label != null)
                label.label = item.band;
        });

        var column = new Gtk.ColumnViewColumn (_("Band"), factory) {
            resizable = true
        };
        column.sorter = new Gtk.CustomSorter ((a, b) => compare_strings (
            ((LogbookQsoItem)a).band,
            ((LogbookQsoItem)b).band
        ));
        qso_column_view.append_column (column);
        return column;
    }

    private void setup_qso_context_menu () {
        qso_context_popover = new Gtk.Popover () {
            has_arrow = true,
            autohide = true
        };
        qso_context_popover.set_parent (qso_column_view);

        var box = new Gtk.Box (Gtk.Orientation.VERTICAL, 0) {
            margin_top = 6,
            margin_bottom = 6,
            margin_start = 6,
            margin_end = 6
        };

        qso_lookup_park_button = new Gtk.Button.with_label (_("Lookup Park")) {
            has_frame = false,
            halign = Gtk.Align.FILL,
            hexpand = true
        };
        qso_lookup_park_button.clicked.connect (() => {
            qso_context_popover.popdown ();
            if (context_qso_item != null)
                lookup_park_for_qso (context_qso_item);
        });

        var delete_button = new Gtk.Button.with_label (_("Delete")) {
            has_frame = false,
            halign = Gtk.Align.FILL,
            hexpand = true
        };
        delete_button.add_css_class ("destructive-action");
        delete_button.clicked.connect (() => {
            qso_context_popover.popdown ();
            if (context_qso_item != null)
                confirm_delete_qso (context_qso_item);
        });

        box.append (qso_lookup_park_button);
        box.append (delete_button);
        qso_context_popover.child = box;

        var click = new Gtk.GestureClick ();
        click.button = Gdk.BUTTON_SECONDARY;
        click.pressed.connect ((n_press, x, y) => {
            var item = qso_selection.selected_item as LogbookQsoItem;
            if (item == null)
                return;

            context_qso_item = item;
            qso_lookup_park_button.sensitive = item.reference.strip () != "";
            Gdk.Rectangle rect = { (int)x, (int)y, 1, 1 };
            qso_context_popover.set_pointing_to (rect);
            qso_context_popover.popup ();
        });
        qso_column_view.add_controller (click);
    }

    private void lookup_park_for_qso (LogbookQsoItem item) {
        var reference = item.reference.strip ();
        if (reference == "")
            return;

        Application.park_details_cache.get_details.begin (reference, (obj, res) => {
            try {
                var details = Application.park_details_cache.get_details.end (res);

                Error? db_error = null;
                if (!Application.spot_database.add_park (
                    details.reference,
                    details.name,
                    null,
                    details.location_desc,
                    null,
                    null,
                    0,
                    out db_error
                )) {
                    throw db_error ?? new IOError.FAILED ("Unable to save park details");
                }

                Application.show_toast (_("Park details updated"));
                reload ();
            } catch (Error err) {
                present_error (_("Unable to Lookup Park"), err.message);
            }
        });
    }

    private void confirm_delete_qso (LogbookQsoItem item) {
        var alert = new Adw.AlertDialog (_("Delete QSO?"), null);
        alert.body = _("This removes the QSO from your local logbook.");
        alert.add_response ("cancel", _("Cancel"));
        alert.add_response ("delete", _("Delete"));
        alert.set_response_appearance ("delete", Adw.ResponseAppearance.DESTRUCTIVE);
        alert.set_default_response ("cancel");
        alert.set_close_response ("cancel");
        alert.response.connect ((response) => {
            if (response == "delete")
                delete_qso (item);
        });
        alert.present (this);
    }

    private void delete_qso (LogbookQsoItem item) {
        Error? error = null;
        if (!Application.spot_database.delete_qso (item.qso.id, out error)) {
            present_error (_("Unable to Delete QSO"), error != null ? error.message : _("Unable to delete QSO"));
            return;
        }

        Application.show_toast (_("QSO deleted"));
        Application.spot_repo.refresh_log_status ();
        reload ();
    }

    private void present_error (string title, string message) {
        var alert = new Adw.AlertDialog (title, null);
        alert.format_body ("%s", message);
        alert.add_response ("ok", _("OK"));
        alert.set_default_response ("ok");
        alert.set_close_response ("ok");
        alert.present (this);
    }

    private void reload () {
        qso_load_error = false;
        parks_load_error = false;
        qso_store.remove_all ();
        parks_store.remove_all ();
        load_qsos ();
        load_parks ();
        update_visible_pages ();
        update_pager ();
    }

    private void load_qsos () {
        Error? error = null;
        var page = Application.spot_database.load_qso_page (
            PAGE_SIZE,
            qso_offset,
            search_entry.text,
            qso_sort_column,
            qso_sort_direction,
            out error
        );
        if (error != null) {
            qso_load_error = true;
            qso_total_count = 0;
            show_qso_status (_("Unable to Load QSOs"), error.message, "dialog-error-symbolic");
            return;
        }

        qso_total_count = page.total_count;
        if (page.rows.size == 0 && qso_total_count > 0 && qso_offset > 0) {
            qso_offset = ((qso_total_count - 1) / PAGE_SIZE) * PAGE_SIZE;
            load_qsos ();
            return;
        }

        foreach (var qso in page.rows)
            qso_store.append (new LogbookQsoItem (qso));
    }

    private void load_parks () {
        Error? error = null;
        var page = Application.spot_database.load_hunted_park_page (
            PAGE_SIZE,
            parks_offset,
            search_entry.text,
            parks_sort_column,
            parks_sort_direction,
            out error
        );
        if (error != null) {
            parks_load_error = true;
            parks_total_count = 0;
            show_parks_status (_("Unable to Load Parks"), error.message, "dialog-error-symbolic");
            return;
        }

        parks_total_count = page.total_count;
        if (page.rows.size == 0 && parks_total_count > 0 && parks_offset > 0) {
            parks_offset = ((parks_total_count - 1) / PAGE_SIZE) * PAGE_SIZE;
            load_parks ();
            return;
        }

        foreach (var park in page.rows)
            parks_store.append (new LogbookParkItem (park));
    }

    private void previous_page () {
        if (views.visible_child_name == "parks") {
            parks_offset -= PAGE_SIZE;
            if (parks_offset < 0)
                parks_offset = 0;
        } else {
            qso_offset -= PAGE_SIZE;
            if (qso_offset < 0)
                qso_offset = 0;
        }

        reload ();
    }

    private void next_page () {
        if (views.visible_child_name == "parks") {
            if (parks_offset + PAGE_SIZE < parks_total_count)
                parks_offset += PAGE_SIZE;
        } else if (qso_offset + PAGE_SIZE < qso_total_count) {
            qso_offset += PAGE_SIZE;
        }

        reload ();
    }

    private void open_qso_editor (uint position) {
        var item = qso_store.get_item (position) as LogbookQsoItem;
        if (item == null)
            return;

        var dialog = new QsoDialog (item.qso);
        dialog.qso_changed.connect (() => reload ());
        dialog.present (this);
    }

    private void update_visible_pages () {
        var has_search = search_entry.text.strip () != "";

        if (!qso_load_error && qso_total_count == 0 && !has_search) {
            show_qso_status (
                _("No QSOs Logged"),
                _("Logged QSOs will appear here after they are saved locally."),
                "radio-console-symbolic"
            );
        } else if (!qso_load_error && qso_total_count == 0) {
            show_qso_status (
                _("No Matching QSOs"),
                _("No logged QSOs match the current search."),
                "edit-find-symbolic"
            );
        } else if (!qso_load_error) {
            qso_stack.visible_child = qso_scroll;
        }

        if (!parks_load_error && parks_total_count == 0 && !has_search) {
            show_parks_status (
                _("No Hunted Parks"),
                _("Parks will appear here after a QSO is logged or an imported log marks them hunted."),
                "map-symbolic"
            );
        } else if (!parks_load_error && parks_total_count == 0) {
            show_parks_status (
                _("No Matching Parks"),
                _("No hunted parks match the current search."),
                "edit-find-symbolic"
            );
        } else if (!parks_load_error) {
            parks_stack.visible_child = parks_scroll;
        }
    }

    private void update_pager () {
        var showing_parks = views.visible_child_name == "parks";
        var offset = showing_parks ? parks_offset : qso_offset;
        var total = showing_parks ? parks_total_count : qso_total_count;
        var visible = showing_parks ? parks_store.get_n_items () : qso_store.get_n_items ();
        var noun = showing_parks ? _("parks") : _("QSOs");

        if (total <= 0) {
            result_count_label.label = _("No %s").printf (noun);
            page_label.label = _("Page 0 of 0");
            previous_page_button.sensitive = false;
            next_page_button.sensitive = false;
            return;
        }

        var start = offset + 1;
        var end = offset + (int)visible;
        var pages = (total + PAGE_SIZE - 1) / PAGE_SIZE;
        var page = (offset / PAGE_SIZE) + 1;

        result_count_label.label = _("%d-%d of %d %s").printf (start, end, total, noun);
        page_label.label = _("Page %d of %d").printf (page, pages);
        previous_page_button.sensitive = offset > 0;
        next_page_button.sensitive = offset + PAGE_SIZE < total;
    }

    private void on_qso_sort_changed (Gtk.ColumnViewSorter sorter) {
        if (handling_sort_change)
            return;

        var column = sorter.get_primary_sort_column ();
        if (column == null)
            return;

        qso_sort_column = qso_sort_column_for (column);
        qso_sort_direction = sort_direction_from_gtk (sorter.get_primary_sort_order ());
        qso_offset = 0;
        reload ();
    }

    private void on_parks_sort_changed (Gtk.ColumnViewSorter sorter) {
        if (handling_sort_change)
            return;

        var column = sorter.get_primary_sort_column ();
        if (column == null)
            return;

        parks_sort_column = parks_sort_column_for (column);
        parks_sort_direction = sort_direction_from_gtk (sorter.get_primary_sort_order ());
        parks_offset = 0;
        reload ();
    }

    private LogbookQsoSortColumn qso_sort_column_for (Gtk.ColumnViewColumn column) {
        if (column == qso_activator_column)
            return LogbookQsoSortColumn.ACTIVATOR;
        if (column == qso_reference_column)
            return LogbookQsoSortColumn.REFERENCE;
        if (column == qso_park_column)
            return LogbookQsoSortColumn.PARK;
        if (column == qso_band_column)
            return LogbookQsoSortColumn.BAND;
        if (column == qso_mode_column)
            return LogbookQsoSortColumn.MODE;
        return LogbookQsoSortColumn.DATE;
    }

    private HuntedParkSortColumn parks_sort_column_for (Gtk.ColumnViewColumn column) {
        if (column == parks_park_column)
            return HuntedParkSortColumn.PARK;
        if (column == parks_location_column)
            return HuntedParkSortColumn.LOCATION;
        if (column == parks_qsos_column)
            return HuntedParkSortColumn.QSOS;
        if (column == parks_first_qso_column)
            return HuntedParkSortColumn.FIRST_QSO;
        return HuntedParkSortColumn.REFERENCE;
    }

    private static LogbookSortDirection sort_direction_from_gtk (Gtk.SortType sort_type) {
        return sort_type == Gtk.SortType.ASCENDING ? LogbookSortDirection.ASC : LogbookSortDirection.DESC;
    }

    private static Gtk.Ordering compare_strings (string a, string b) {
        var cmp = a.collate (b);
        if (cmp < 0)
            return Gtk.Ordering.SMALLER;
        if (cmp > 0)
            return Gtk.Ordering.LARGER;
        return Gtk.Ordering.EQUAL;
    }

    private static Gtk.Ordering compare_ints (int a, int b) {
        if (a < b)
            return Gtk.Ordering.SMALLER;
        if (a > b)
            return Gtk.Ordering.LARGER;
        return Gtk.Ordering.EQUAL;
    }

    private void show_qso_status (string title, string description, string icon_name) {
        qso_status_page.title = title;
        qso_status_page.description = description;
        qso_status_page.icon_name = icon_name;
        qso_stack.visible_child = qso_status_page;
    }

    private void show_parks_status (string title, string description, string icon_name) {
        parks_status_page.title = title;
        parks_status_page.description = description;
        parks_status_page.icon_name = icon_name;
        parks_stack.visible_child = parks_status_page;
    }
}

private string display_datetime (string? iso_utc, string format = "%x %R UTC") {
    var value = (iso_utc ?? "").strip ();
    if (value == "")
        return "";

    var dt = new DateTime.from_iso8601 (value, new TimeZone.utc ());
    if (dt == null)
        dt = parse_date_only_utc (value);
    if (dt == null)
        return iso_utc;

    return dt.to_utc ().format (format);
}
