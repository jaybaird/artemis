/* src/map/map_view.vala
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
using Shumate;

public class MapView : Gtk.Box {
    private const uint ASTRONOMY_REFRESH_INTERVAL_SECONDS = 60;
    private const double DEFAULT_QTH_ZOOM_LEVEL = 5.0;
    private const double AUTO_SPOT_MIN_ZOOM_LEVEL = 5.0;
    private const double AUTO_SPOT_MAX_ZOOM_LEVEL = 8.0;
    private const double AUTO_BOUNDS_MAX_ZOOM_LEVEL = 7.0;
    private const string MAPBOX_LICENSE = "© Mapbox © OpenStreetMap";
    private const string MAPBOX_LICENSE_URI = "https://www.mapbox.com/about/maps/";

    private Viewport viewport;
    private MapSourceRegistry registry;
    private MapSource map_source;
    private Shumate.Map map_widget;

    private Scale map_scale;
    private Shumate.License map_license;
    private MapLayer map_layer;
    private HeatmapModel signal_report_model;
    private SignalReportHeatmapLayer signal_report_layer;
    private SignalReportMqttSession signal_report_session;
    private GraylineOverlay grayline_overlay;
    private MarkerLayer marker_layer;
    private MarkerLayer astronomy_marker_layer;
    private HashMap<Quark, Marker> markers;
    private HashMap<Quark, MapMarkerDot> marker_dots;
    private HashMap<Quark, ulong> marker_notify_handlers;
    private Marker? selected_marker = null;
    private Quark selected_marker_hash = BLANK_HASH;
    private Marker? sun_marker = null;
    private Marker? moon_marker = null;
    private uint astronomy_refresh_timeout_id = 0;
    private bool grayline_visible = true;
    private bool astronomy_visible = true;
    private bool signal_reports_visible = false;
    private bool active = false;

    private BoundingBox bbox;
    private Coordinate qth_coordinate;
    private bool has_qth_coordinate = false;
    private bool user_has_adjusted_view = false;
    private bool current_map_is_dark = false;
    private bool loaded_after_map = false;
    private uint load_spots_idle_id = 0;

    private Gtk.Overlay overlay;
    private GLib.SimpleActionGroup overlay_actions;
    private GLib.SimpleAction grayline_action;
    private GLib.SimpleAction astronomy_action;
    private GLib.SimpleAction signal_reports_action;
    private Adw.SplitButton overlay_button;
    private Gtk.Box signal_report_status;
    private Gtk.Image signal_report_status_icon;
    private Gtk.Label signal_report_status_title;
    private Gtk.Label signal_report_status_detail;
    private const int TOP_OVERLAY_MARGIN_OFFSET = 6;

    Gtk.Filter filter;
    Gtk.FilterListModel filtered;

    construct {
        registry = new MapSourceRegistry.with_defaults ();

        if (Build.MAPBOX_ACCESS_TOKEN == "") {
            warning ("Mapbox access token is empty; map tiles will fail to load until mapbox_access_token is set at build time");
        }

        current_map_is_dark = Adw.StyleManager.get_default ().dark;
        map_source = create_map_source (current_map_is_dark);
        grayline_visible = Application.settings.get_boolean ("map-grayline-visible");
        astronomy_visible = Application.settings.get_boolean ("map-astronomy-visible");
        signal_reports_visible = Application.settings.get_boolean ("map-signal-reports-visible");

        map_widget = new Shumate.Map () {
            vexpand = true,
            hexpand = true
        };
        map_widget.set_map_source (map_source);

        install_map_interaction_tracking ();

        var box = new Gtk.Box (Gtk.Orientation.VERTICAL, 0) {
            vexpand = true,
            hexpand = true
        };
        box.add_css_class ("window");
        box.append (map_widget);

        overlay = new Gtk.Overlay () {
            vexpand = true,
            hexpand = true
        };
        overlay.set_child (box);
        this.append (overlay);

        overlay_actions = new GLib.SimpleActionGroup ();
        insert_action_group ("map", overlay_actions);
        install_overlay_controls ();

        Adw.StyleManager.get_default ().notify["dark"].connect (() => {
            update_map_source_for_theme ();
        });

        viewport = map_widget.get_viewport ();
        viewport.set_reference_map_source (map_source);
        viewport.set_max_zoom_level (19);
        viewport.set_min_zoom_level (3);

        map_scale = new Scale (viewport) {
            visible = Application.settings.get_boolean ("show-map-scale"),
            unit = Application.settings.get_boolean ("use-metric") ? Shumate.
                Unit.METRIC : Shumate.Unit.IMPERIAL,
            halign = Gtk.Align.START,
            valign = Gtk.Align.END,
            margin_start = 6,
            margin_end = 6,
            margin_top = 6,
            margin_bottom = 6
        };

        Application.settings.changed["show-map-scale"].connect (() => {
            map_scale.visible = Application.settings.get_boolean ("show-map-scale");
        });

        Application.settings.changed["use-metric"].connect (() => {
            map_scale.unit = Application.settings.get_boolean ("use-metric") ?
                Shumate.Unit.METRIC : Shumate.Unit.IMPERIAL;
        });

        overlay.add_overlay (map_scale);

        map_license = new Shumate.License () {
            xalign = 1.0f
        };
        map_license.append_map_source (map_source);

        var menu = new GLib.Menu ();
        menu.append (_("Grayline"), "map.grayline-visible");
        menu.append (_("Sun and Moon"), "map.astronomy-visible");
        menu.append (_("Signal Reports"), "map.signal-reports-visible");

        overlay_button = new Adw.SplitButton () {
            label = _("Overlays"),
            icon_name = "map-layers-symbolic",
            menu_model = menu,
            can_shrink = true,
            dropdown_tooltip = _("Overlay options")
        };
        overlay_button.add_css_class ("flat");
        overlay_button.clicked.connect (() => {
            set_grayline_visible (!grayline_visible);
        });

        var right_box = new Gtk.Box (
            Gtk.Orientation.VERTICAL,
            8
        ) {
            halign = Gtk.Align.END,
            valign = Gtk.Align.END,
            margin_start = 6,
            margin_end = 6,
            margin_top = 6,
            margin_bottom = 6
        };

        right_box.append (overlay_button);
        right_box.append (map_license);

        overlay.add_overlay (right_box);

        signal_report_status_icon = new Gtk.Image.from_icon_name ("network-offline-symbolic") {
            pixel_size = 16,
            valign = Gtk.Align.CENTER
        };
        signal_report_status_title = new Gtk.Label ("") {
            halign = Gtk.Align.START,
            ellipsize = Pango.EllipsizeMode.END,
            xalign = 0.0f
        };
        signal_report_status_title.add_css_class ("heading");
        signal_report_status_detail = new Gtk.Label ("") {
            halign = Gtk.Align.START,
            ellipsize = Pango.EllipsizeMode.END,
            xalign = 0.0f
        };
        signal_report_status_detail.add_css_class ("caption");

        var signal_report_status_labels = new Gtk.Box (Gtk.Orientation.VERTICAL, 0);
        signal_report_status_labels.append (signal_report_status_title);
        signal_report_status_labels.append (signal_report_status_detail);

        signal_report_status = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 8) {
            can_target = false,
            halign = Gtk.Align.START,
            valign = Gtk.Align.START,
            margin_start = 6,
            margin_end = 6,
            margin_top = 54,
            margin_bottom = 6,
            visible = false
        };
        signal_report_status.add_css_class ("map-signal-report-status");
        signal_report_status.append (signal_report_status_icon);
        signal_report_status.append (signal_report_status_labels);
        overlay.add_overlay (signal_report_status);

        qth_coordinate = new Coordinate ();
        update_qth_coordinate ();
        Application.settings.changed["location"].connect (() => {
            update_qth_coordinate ();
        });
        bbox = new BoundingBox ();
        markers = new HashMap<Quark, Marker> ();
        marker_dots = new HashMap<Quark, MapMarkerDot> ();
        marker_notify_handlers = new HashMap<Quark, ulong> ();

        rebuild_base_map_layer ();

        grayline_overlay = new GraylineOverlay (viewport);
        map_widget.insert_layer_above (grayline_overlay.layer, map_layer);

        signal_report_model = new HeatmapModel ();
        signal_report_layer = new SignalReportHeatmapLayer (viewport, signal_report_model);
        signal_report_model.changed.connect (update_signal_report_status);
        sync_signal_report_preferences ();
        Application.settings.changed["signal-report-max-age-seconds"].connect (() => {
            sync_signal_report_preferences ();
        });
        Application.settings.changed["signal-report-heatmap-radius"].connect (() => {
            sync_signal_report_preferences ();
        });
        signal_report_session = new SignalReportMqttSession (signal_report_model, Application.settings);
        signal_report_session.state_changed.connect (update_signal_report_status);
        map_widget.insert_layer_above (signal_report_layer, grayline_overlay.layer);

        astronomy_marker_layer = new MarkerLayer (viewport);
        map_widget.insert_layer_above (astronomy_marker_layer, signal_report_layer);

        filter = new Gtk.CustomFilter ((item) => {
            var spot = item as Spot;
            if (spot == null)
                return false;
            return spot_matches_current_filters (
                spot,
                Application.state.current_band_filter ?? "All"
            );
        });

        filtered = new Gtk.FilterListModel (Application.spot_repo.store,
            filter);

        Application.spot_repo.refreshed.connect (() => {
            queue_load_spots ();
        });
        Application.spot_repo.current_spot_changed.connect (sync_marker_selection);

        update_astronomy_overlays ();
        astronomy_refresh_timeout_id = Timeout.add_seconds (
            ASTRONOMY_REFRESH_INTERVAL_SECONDS,
            () => {
                update_astronomy_overlays ();
                return true;
            }
        );

        sync_overlay_visibility ();
        update_signal_report_status ();

        map_widget.map.connect (() => {
            if (loaded_after_map)
                return;

            loaded_after_map = true;
            queue_load_spots ();
        });
    }

    ~MapView () {
        if (load_spots_idle_id != 0) {
            Source.remove (load_spots_idle_id);
            load_spots_idle_id = 0;
        }
        if (astronomy_refresh_timeout_id != 0) {
            Source.remove (astronomy_refresh_timeout_id);
            astronomy_refresh_timeout_id = 0;
        }
        if (signal_report_session != null)
            signal_report_session.stop ();
    }

    private MapSource create_map_source (bool dark) {
        string style_id = dark ? Build.MAPBOX_DARK_STYLE_ID : Build.MAPBOX_LIGHT_STYLE_ID;
        string variant = dark ? "dark" : "light";
        string url_template =
            "https://api.mapbox.com/styles/v1/%s/%s/tiles/256/{z}/{x}/{y}@2x?access_token=%s".printf (
                Build.MAPBOX_STYLE_OWNER,
                style_id,
                Build.MAPBOX_ACCESS_TOKEN
            );

        return new Shumate.RasterRenderer.full_from_url (
            "mapbox-artemis-%s".printf (variant),
            "Mapbox %s %s".printf (Build.NAME, variant),
            MAPBOX_LICENSE,
            MAPBOX_LICENSE_URI,
            0u,
            19u,
            256u,
            Shumate.MapProjection.MERCATOR,
            url_template
        );
    }

    private void update_map_source_for_theme () {
        bool dark = Adw.StyleManager.get_default ().dark;
        if (dark == current_map_is_dark)
            return;

        current_map_is_dark = dark;
        map_license.remove_map_source (map_source);
        map_source = create_map_source (current_map_is_dark);
        map_license.append_map_source (map_source);
        viewport.set_reference_map_source (map_source);
        map_widget.set_map_source (map_source);
        rebuild_base_map_layer ();
    }

    private void rebuild_base_map_layer () {
        if (map_layer != null)
            map_widget.remove_layer (map_layer);

        var layer = new MapLayer (map_source, viewport);
        map_widget.add_layer (layer);
        layer.tile_error.connect ((layer, tile, err) => {
            warning ("Failed top load tile %u/%u/%u: %s", tile.zoom_level,
                tile.x, tile.y, err.message);
        });
        map_layer = layer;

        if (grayline_overlay != null)
            map_widget.insert_layer_above (grayline_overlay.layer, map_layer);
        if (signal_report_layer != null)
            map_widget.insert_layer_above (signal_report_layer, grayline_overlay.layer);
        if (marker_layer != null)
            map_widget.insert_layer_above (marker_layer, signal_report_layer);
        if (astronomy_marker_layer != null) {
            if (marker_layer != null)
                map_widget.insert_layer_above (astronomy_marker_layer, marker_layer);
            else
                map_widget.insert_layer_above (astronomy_marker_layer, signal_report_layer);
        }
    }

    // pulled straight from https://gitlab.gnome.org/GNOME/gnome-maps/-/blob/main/src/mapView.js; thanks!
    private double get_zoom_level_fitting_bounds (BoundingBox bbox) {
        if (!bbox.is_valid ())
            return viewport.min_zoom_level;

        var good_size = false;
        var zoom_level = viewport.max_zoom_level;
        Graphene.Rect widget_bounds = {};
        map_widget.compute_bounds (map_widget, out widget_bounds);

        var width = (widget_bounds.size.width > 0) ? widget_bounds.size.width : 800;
        var height = (widget_bounds.size.height > 0) ? widget_bounds.size.height : 600;

        do {
            var min_x = map_source.get_x (zoom_level, bbox.min_lon);
            var min_y = map_source.get_y (zoom_level, bbox.min_lat);
            var max_x = map_source.get_x (zoom_level, bbox.max_lon);
            var max_y = map_source.get_y (zoom_level, bbox.max_lat);

            if ((min_y - max_y <= height) && (max_x - min_x <= width))
                good_size = true;
            else
                zoom_level = zoom_level - 1;

            if (zoom_level <= viewport.min_zoom_level) {
                zoom_level = viewport.min_zoom_level;
                good_size = true;
            }
        }
        while (!good_size);

        return zoom_level;
    }

    private void install_map_interaction_tracking () {
        var drag = new Gtk.GestureDrag () {
            propagation_phase = Gtk.PropagationPhase.CAPTURE
        };
        drag.drag_begin.connect ((start_x, start_y) => {
            user_has_adjusted_view = true;
        });
        map_widget.add_controller (drag);

        var scroll = new Gtk.EventControllerScroll (
            Gtk.EventControllerScrollFlags.VERTICAL |
            Gtk.EventControllerScrollFlags.HORIZONTAL |
            Gtk.EventControllerScrollFlags.DISCRETE
        ) {
            propagation_phase = Gtk.PropagationPhase.CAPTURE
        };
        scroll.scroll.connect ((dx, dy) => {
            user_has_adjusted_view = true;
            return false;
        });
        map_widget.add_controller (scroll);

        var zoom = new Gtk.GestureZoom () {
            propagation_phase = Gtk.PropagationPhase.CAPTURE
        };
        zoom.begin.connect ((sequence) => {
            user_has_adjusted_view = true;
        });
        map_widget.add_controller (zoom);
    }

    private void _create_marker (Spot spot) {
        var marker_content = new Gtk.Overlay () {
            width_request = 28,
            height_request = 28,
            halign = Gtk.Align.CENTER,
            valign = Gtk.Align.CENTER
        };
        marker_content.add_css_class ("map-marker-content");

        var dot = new MapMarkerDot (spot.band);
        marker_content.set_child (dot);

        var heard_icon = new Gtk.Image.from_icon_name ("headphones-symbolic") {
            pixel_size = 12,
            halign = Gtk.Align.CENTER,
            valign = Gtk.Align.CENTER,
            visible = spot.heard_recently
        };
        heard_icon.add_css_class ("map-marker-heard-icon");
        marker_content.add_overlay (heard_icon);

        var coordinate = spot.coordinate;
        if (coordinate == null)
            return;

        var marker = new Marker () {
            child = marker_content,
            latitude = coordinate.latitude,
            longitude = coordinate.longitude
        };
        marker.add_css_class ("marker");
        sync_marker_heard_state (marker, marker_content, heard_icon, spot);
        if (spot.hash == Application.state.current_spot_hash) {
            marker.add_css_class ("selected");
            dot.selected = true;
            selected_marker = marker;
            selected_marker_hash = spot.hash;
        }

        var click = new Gtk.GestureClick ();
        click.pressed.connect (() => {
            Application.state.current_spot_hash = spot.hash;
        });
        marker.add_controller (click);

        var motion = new Gtk.EventControllerMotion ();
        motion.enter.connect (() => {
            marker.add_css_class ("hovered");
            marker.set_cursor_from_name ("pointer");
        });
        motion.leave.connect (() => {
            marker.remove_css_class ("hovered");
            marker.set_cursor_from_name (null);
        });
        marker.add_controller (motion);

        marker_layer.add_marker (marker);
        markers.set (spot.hash, marker);
        marker_dots.set (spot.hash, dot);
        marker_notify_handlers.set (spot.hash, spot.notify["heard-recently"].connect (() => {
            sync_marker_heard_state (marker, marker_content, heard_icon, spot);
        }));
    } /* _create_marker */

    private void sync_marker_heard_state (
        Marker marker,
        Gtk.Widget marker_content,
        Gtk.Widget heard_icon,
        Spot spot
    ) {
        if (spot.heard_recently) {
            marker.add_css_class ("marker-heard-recently");
            marker_content.add_css_class ("map-marker-heard-recently");
            heard_icon.visible = true;
        } else {
            marker.remove_css_class ("marker-heard-recently");
            marker_content.remove_css_class ("map-marker-heard-recently");
            heard_icon.visible = false;
        }
    }

    private void sync_marker_selection (Quark spot_hash) {
        if (selected_marker != null) {
            selected_marker.remove_css_class ("selected");
            selected_marker = null;
        }

        if (selected_marker_hash != BLANK_HASH) {
            var dot = marker_dots.get (selected_marker_hash);
            if (dot != null)
                dot.selected = false;
            selected_marker_hash = BLANK_HASH;
        }

        if (spot_hash == BLANK_HASH)
            return;

        var marker = markers.get (spot_hash);
        if (marker == null)
            return;

        marker.add_css_class ("selected");
        var dot = marker_dots.get (spot_hash);
        if (dot != null)
            dot.selected = true;
        selected_marker = marker;
        selected_marker_hash = spot_hash;
    }

    public void go_to_spot (Spot? spot) {
        if (spot == null)
            return;
        var coordinate = spot.coordinate;
        if (coordinate == null)
            return;
        var zoom = double.min (
            double.max (viewport.zoom_level, AUTO_SPOT_MIN_ZOOM_LEVEL),
            AUTO_SPOT_MAX_ZOOM_LEVEL
        );
        map_widget.go_to_full (coordinate.latitude, coordinate.longitude, zoom);
    }

    public void bounce_filter () {
        filter.changed (Gtk.FilterChange.DIFFERENT);
        queue_load_spots ();
    }

    private void queue_load_spots () {
        if (load_spots_idle_id != 0)
            return;

        load_spots_idle_id = Idle.add (() => {
            load_spots_idle_id = 0;
            load_spots ();
            return Source.REMOVE;
        });
    }

    private void update_astronomy_overlays () {
        var now = new DateTime.now_utc ();
        var bodies = Astronomy.body_markers (now);
        var sun_coordinate = bodies.sun.coordinate;
        var moon_coordinate = bodies.moon.coordinate;
        grayline_overlay.update (now);

        ensure_body_marker (
            ref sun_marker,
            sun_coordinate,
            "sun-outline-symbolic",
            _("Sun"),
            "astronomy-marker",
            "astronomy-marker-sun"
        );
        ensure_body_marker (
            ref moon_marker,
            moon_coordinate,
            "moon-outline-symbolic",
            _("Moon"),
            "astronomy-marker",
            "astronomy-marker-moon"
        );

        var moon_tooltip = "%s\n%s".printf (
            _("Moon"),
            Astronomy.moon_phase_display_name (bodies.moon_phase)
        );
        if (moon_marker != null && moon_marker.child != null)
            moon_marker.child.tooltip_text = moon_tooltip;
    }

    private void install_overlay_controls () {
        grayline_action = new GLib.SimpleAction.stateful (
            "grayline-visible",
            null,
            new Variant.boolean (grayline_visible)
        );
        grayline_action.change_state.connect ((action, value) => {
            if (value == null)
                return;

            set_grayline_visible (value.get_boolean ());
        });
        overlay_actions.add_action (grayline_action);

        astronomy_action = new GLib.SimpleAction.stateful (
            "astronomy-visible",
            null,
            new Variant.boolean (astronomy_visible)
        );
        astronomy_action.change_state.connect ((action, value) => {
            if (value == null)
                return;

            set_astronomy_visible (value.get_boolean ());
        });
        overlay_actions.add_action (astronomy_action);

        signal_reports_action = new GLib.SimpleAction.stateful (
            "signal-reports-visible",
            null,
            new Variant.boolean (signal_reports_visible)
        );
        signal_reports_action.change_state.connect ((action, value) => {
            if (value == null)
                return;

            set_signal_reports_visible (value.get_boolean ());
        });
        overlay_actions.add_action (signal_reports_action);
    }

    private void set_grayline_visible (bool visible) {
        grayline_visible = visible;
        persist_overlay_visibility ("map-grayline-visible", visible);
        if (grayline_action != null)
            grayline_action.set_state (new Variant.boolean (visible));
        sync_overlay_visibility ();
    }

    private void set_astronomy_visible (bool visible) {
        astronomy_visible = visible;
        persist_overlay_visibility ("map-astronomy-visible", visible);
        if (astronomy_action != null)
            astronomy_action.set_state (new Variant.boolean (visible));
        sync_overlay_visibility ();
    }

    private void set_signal_reports_visible (bool visible) {
        signal_reports_visible = visible;
        persist_overlay_visibility ("map-signal-reports-visible", visible);
        if (signal_reports_action != null)
            signal_reports_action.set_state (new Variant.boolean (visible));
        sync_overlay_visibility ();

        if (signal_report_session == null)
            return;

        if (visible && active)
            signal_report_session.start ();
        else
            signal_report_session.stop ();

        update_signal_report_status ();
    }

    public void set_active (bool active) {
        if (this.active == active)
            return;

        this.active = active;
        if (signal_report_session == null)
            return;

        if (active && signal_reports_visible)
            signal_report_session.start ();
        else
            signal_report_session.stop ();

        update_signal_report_status ();
    }

    public void set_top_overlay_margin (int margin) {
        if (signal_report_status != null)
            signal_report_status.margin_top = margin + TOP_OVERLAY_MARGIN_OFFSET;
    }

    private void persist_overlay_visibility (string key, bool visible) {
        if (Application.settings.get_boolean (key) != visible)
            Application.settings.set_boolean (key, visible);
    }

    private void sync_overlay_visibility () {
        if (grayline_overlay != null)
            grayline_overlay.visible = grayline_visible;
        if (signal_report_layer != null)
            signal_report_layer.visible = signal_reports_visible;
        if (astronomy_marker_layer != null)
            astronomy_marker_layer.visible = astronomy_visible;
        if (signal_report_status != null)
            signal_report_status.visible = signal_reports_visible;
    }

    private void update_signal_report_status () {
        if (signal_report_status == null)
            return;

        signal_report_status.visible = signal_reports_visible;
        if (!signal_reports_visible)
            return;

        var report_count = signal_report_model != null ? signal_report_model.report_count () : 0;

        signal_report_status_title.label = ngettext (
            "%u signal report",
            "%u signal reports",
            report_count
        ).printf (report_count);

        signal_report_status_detail.label = signal_report_age_window_text ();

        signal_report_status_icon.icon_name = signal_report_stream_icon_name ();
    }

    private string signal_report_age_window_text () {
        var minutes = Application.settings.get_int ("signal-report-max-age-seconds") / 60;

        return ngettext (
            "Last %d minute",
            "Last %d minutes",
            minutes
        ).printf (minutes);
    }

    private string signal_report_stream_icon_name () {
        if (signal_report_session == null || !signal_report_session.active)
            return "network-offline-symbolic";

        switch (signal_report_session.stream_state) {
            case SignalReportStreamState.LIVE:
            case SignalReportStreamState.RECEIVING:
                return "network-idle-symbolic";
            case SignalReportStreamState.CONNECTING:
                return "network-workgroup-symbolic";
            case SignalReportStreamState.FAILED:
            case SignalReportStreamState.STOPPING:
            case SignalReportStreamState.OFFLINE:
            default:
                return "network-offline-symbolic";
        }
    }

    private void sync_signal_report_preferences () {
        if (signal_report_model != null) {
            signal_report_model.max_age_seconds =
                (uint) Application.settings.get_int ("signal-report-max-age-seconds");
        }

        if (signal_report_layer != null) {
            signal_report_layer.stamp_radius_pixels =
                (uint) Application.settings.get_int ("signal-report-heatmap-radius");
        }
    }

    private void ensure_body_marker (
        ref Marker? marker,
        Coordinate coordinate,
        string icon_name,
        string tooltip_text,
        string base_css_class,
        string accent_css_class
    ) {
        if (marker == null) {
            var icon = new Gtk.Image.from_icon_name (icon_name) {
                pixel_size = 18,
                tooltip_text = tooltip_text
            };
            icon.add_css_class (base_css_class);
            icon.add_css_class (accent_css_class);

            marker = new Marker () {
                child = icon,
                selectable = false
            };
            marker.add_css_class ("astronomy-map-marker");
            marker.x_hotspot = 0.5;
            marker.y_hotspot = 0.5;
            astronomy_marker_layer.add_marker (marker);
        } else if (marker.child != null) {
            marker.child.tooltip_text = tooltip_text;
        }

        marker.latitude = coordinate.latitude;
        marker.longitude = coordinate.longitude;
    }

    private void update_qth_coordinate () {
        has_qth_coordinate = false;

        var grid = Application.settings.get_string ("location").strip ();
        if (grid == "")
            return;

        try {
            qth_coordinate = Distance.maidenhead_to_latlon (grid);
            has_qth_coordinate = true;
        } catch (Error err) {
            warning ("Failed to parse maidenhead location %s: %s", grid, err.message);
        }
    }

    private void load_spots () {
        if (!map_widget.get_mapped ())
            return;

        bbox.clear ();

        foreach (var entry in marker_notify_handlers.entries) {
            var spot = Application.spot_repo.get_spot (entry.key);
            if ((spot != null) && SignalHandler.is_connected (spot, entry.value))
                SignalHandler.disconnect (spot, entry.value);
        }
        marker_notify_handlers.clear ();

        if (marker_layer != null) {
            map_widget.remove_layer (marker_layer);
            marker_layer = null;
        }

        marker_layer = new MarkerLayer (viewport);
        markers.clear ();
        marker_dots.clear ();
        selected_marker = null;
        selected_marker_hash = BLANK_HASH;

        uint spot_count = 0;
        var valid_hashes = new HashSet<GLib.Quark> ();

        for (uint i = 0 ; i < filtered.get_n_items () ; i++) {
            Spot spot = filtered.get_item (i) as Spot;
            if (spot == null)
                continue;

            bbox.extend_coord (spot.coordinate);
            _create_marker (spot);
            valid_hashes.add (spot.hash);

            if (spot.coordinate != null)
                spot_count++;
        }
        bbox.expand ();

        map_widget.insert_layer_above (marker_layer, signal_report_layer);
        sync_marker_selection (Application.state.current_spot_hash);

        if (Application.state.current_spot_hash == BLANK_HASH ||
            !valid_hashes.contains (Application.state.current_spot_hash)) {
            if (user_has_adjusted_view) {
                return;
            }

            if (has_qth_coordinate) {
                map_widget.go_to_full (
                    qth_coordinate.latitude,
                    qth_coordinate.longitude,
                    DEFAULT_QTH_ZOOM_LEVEL
                );
            } else if ((spot_count > 0) && bbox.is_valid ()) {
                var center = bbox.center ();
                var zoom_level = get_zoom_level_fitting_bounds (bbox);
                zoom_level = double.min (zoom_level, AUTO_BOUNDS_MAX_ZOOM_LEVEL);

                map_widget.go_to_full (center.latitude, center.longitude, zoom_level);
            } else {
                map_widget.go_to_full (0.0, 0.0, viewport.min_zoom_level);
            }
        }

    } /* load_spots */
}     /* class MapView */
