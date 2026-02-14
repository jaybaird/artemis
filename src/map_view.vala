/* src/map_view.vala
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

const double MIN_LATITUDE = -85.0511287798;
const double MAX_LATITUDE = 85.0511287798;
const double MIN_LONGITUDE = -180.0;
const double MAX_LONGITUDE = 180.0;

const double EARTH_RADIUS_M = 6378137.0;

static double meters_to_deg_lat (double meters) {
    return meters / 111320.0;
}

static double meters_to_deg_lon (double meters, double latitude_deg) {
    double lat_rad = Distance.to_radians (latitude_deg);

    return meters / (111320.0 * Math.cos (lat_rad));
}

public class BoundingBox : Object {
    public double min_lat { get; private set; }
    public double min_lon { get; private set; }
    public double max_lat { get; private set; }
    public double max_lon { get; private set; }
    public BoundingBox () {
        clear ();
    }

    public BoundingBox.from_points (Gee.Collection<Coordinate> coords) {
        clear ();
        foreach (var c in coords) {
            extend (c.latitude, c.longitude);
        }
    }

    public void clear () {
        min_lat = MAX_LATITUDE;
        max_lat = MIN_LATITUDE;
        min_lon = MAX_LONGITUDE;
        max_lon = MIN_LONGITUDE;
    }

    public bool is_valid () {
        return min_lat <= max_lat && min_lon <= max_lon;
    }

    public void extend (double lat, double lon) {
        lat = clamp (lat, MIN_LATITUDE, MAX_LATITUDE);
        lon = normalize_longitude (lon);

        if (!is_valid ()) {
            min_lat = max_lat = lat;
            min_lon = max_lon = lon;
            return;
        }

        if (lat < min_lat)
            min_lat = lat;
        if (lat > max_lat)
            max_lat = lat;

        // handle wrap-around correctly
        if (lon_distance (lon, min_lon) < lon_distance (lon, max_lon)) {
            if (lon < min_lon)
                min_lon = lon;
        } else {
            if (lon > max_lon)
                max_lon = lon;
        }
    }

    public void extend_coord (Coordinate? coord) {
        if (coord == null)
            return;

        extend (coord.latitude, coord.longitude);
    }

    public void expand (int padding_meters = 50000) {
        if (!is_valid ())
            return;

        double lat_center = (min_lat + max_lat) / 2.0;

        double lat_pad = meters_to_deg_lat (padding_meters);
        double lon_pad = meters_to_deg_lon (padding_meters, lat_center);

        min_lat -= lat_pad;
        max_lat += lat_pad;
        min_lon -= lon_pad;
        max_lon += lon_pad;

        min_lat = clamp (min_lat, MIN_LATITUDE, MAX_LATITUDE);
        max_lat = clamp (max_lat, MIN_LATITUDE, MAX_LATITUDE);
        min_lon = clamp (min_lon, MIN_LONGITUDE, MAX_LONGITUDE);
        max_lon = clamp (max_lon, MIN_LONGITUDE, MAX_LONGITUDE);
    }

    public Coordinate center () {
        var c_lat = (min_lat + max_lat) * 0.5;
        var c_lon = normalize_longitude ((min_lon + max_lon) * 0.5);
        return new Coordinate.full (c_lat, c_lon);
    }

    public bool contains (double lat, double lon) {
        lat = clamp (lat, MIN_LATITUDE, MAX_LATITUDE);
        lon = normalize_longitude (lon);
        return lat >= min_lat && lat <= max_lat &&
               lon >= min_lon && lon <= max_lon;
    }

    public string to_string () {
        return "BBox(lat: %.5f–%.5f, lon: %.5f–%.5f)".printf (min_lat, max_lat,
            min_lon, max_lon);
    }

    private static double normalize_longitude (double lon) {
        while (lon < -180.0) {
            lon += 360.0;
        }

        while (lon > 180.0) {
            lon -= 360.0;
        }

        return lon;
    }

    private static double lon_distance (double a, double b) {
        double d = Math.fabs (a - b);
        return d > 180.0 ? 360.0 - d : d;
    }
} /* class BoundingBox */

public class MapView : Gtk.Box {
    private Viewport viewport;
    private MapSourceRegistry registry;
    private MapSource map_source;
    private Shumate.Map map_widget;

    private Scale map_scale;
    private Layer map_layer;
    private MarkerLayer marker_layer;

    private BoundingBox bbox;
    private Coordinate qth_coordinate;

    private Gtk.Overlay overlay;
    private Adw.OverlaySplitView split_view;

    private bool marker_clicked = false;

    Gtk.Filter filter;
    Gtk.FilterListModel filtered;

    public MapView () {
        Object ();
        add_css_class ("card");
    }

    construct {
        registry = new MapSourceRegistry.with_defaults ();

        const string API_KEY = "78418e148d9b4447ae11c25d30a735e5";
        string url_template =
            "https://tile.thunderforest.com/outdoors/{z}/{x}/{y}.png?apikey=%s".printf (API_KEY);
        map_source = new Shumate.RasterRenderer.full_from_url (
            "thunderforest-outdoors",
            "Thunderforest Outdoors",
            "© Thunderforest",
            "https://www.thunderforest.com",
            0u,
            19u,
            256u,
            Shumate.MapProjection.MERCATOR,
            url_template
            );

        map_widget = new Shumate.Map () {
            vexpand = true,
            hexpand = true
        };
        map_widget.add_css_class ("card");

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

        split_view = new Adw.OverlaySplitView () {
            sidebar = new Gtk.Box (Gtk.Orientation.VERTICAL, 10) {
                width_request = 350,
                hexpand = true,
                vexpand = true,
                margin_start = 10,
                margin_end = 10,
                margin_top = 10,
                margin_bottom = 10,
            },
            content = overlay,
            show_sidebar = false,
            min_sidebar_width = 250.0
        };
        split_view.add_css_class ("card");
        this.append (split_view);

        viewport = map_widget.get_viewport ();
        viewport.set_reference_map_source (map_source);
        viewport.set_max_zoom_level (19);
        viewport.set_min_zoom_level (0);

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

        qth_coordinate = new Coordinate ();
        var grid = Application.settings.get_string ("location");
        if (grid != "") {
            try {
                qth_coordinate = Distance.maidenhead_to_latlon (grid);
            } catch (Error err) {
                warning ("Failed to parse maidenhead location %s: %s", grid, err
                    .message);
            }
        }
        bbox = new BoundingBox ();

        var layer = new MapLayer (map_source, viewport);
        if (layer != null) {
            map_widget.add_layer (layer);
            layer.tile_error.connect ((layer, tile, err) => {
                warning ("Failed top load tile %u/%u/%u: %s", tile.zoom_level,
                    tile.x, tile.y, err.message);
            });
            layer.map_loaded.connect ((layer, errors) => {
                print ("Map loaded%s".printf ((errors) ? " with errors" : ""));
            });
            map_layer = layer;
        } else {
            warning ("Base map layer is null!");
        }

        filter = new Gtk.CustomFilter ((item) => {
            var spot = item as Spot;
            if (spot == null)
                return false;

            var band_filter = Application.current_band_filter ?? "All";
            if ((band_filter != "All") && (spot.band != band_filter))
                return false;

            if (Application.settings.get_boolean ("hide-qrt") && spot.activator_comment.down ().contains ("qrt"))
                return false;

            if (Application.settings.get_boolean ("hide-hunted") && spot.was_hunted_today)
                return false;

            var stale_minutes = Application.settings.get_int ("hide-older-than")
            ;
            var now = new DateTime.now_utc ();
            var expires = spot.spot_time.add_minutes (stale_minutes);
            if (now.compare (expires) > 0)
                return false;

            if ((Application.current_program_filter != null) &&
                (Application.current_program_filter != _ ("All")) &&
                !spot.park_ref.down ().has_prefix (Application.current_program_filter.down ()))
                return false;

            if ((Application.current_mode_filter != null) &&
                (Application.current_mode_filter != _ ("All")) &&
                !spot.mode.down ().contains (Application.current_mode_filter.down ()))
                return false;

            if (Application.current_search_text != null) {
                var needle = Application.current_search_text.down ();
                if (!(spot.callsign.down ().contains (needle) ||
                      spot.park_ref.down ().contains (needle) ||
                      spot.park_name.down ().contains (needle)))
                    return false;
            }

            return true;
        });

        filtered = new Gtk.FilterListModel (Application.spot_repo.store,
            filter);

        Application.spot_repo.refreshed.connect (load_spots);

        load_spots ();
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
    } /* get_zoom_level_fitting_bounds */

    private void _create_marker (Spot spot) {
        var image = new Gtk.Image.from_icon_name ("map-marker-symbolic") {
            pixel_size = 32
        };

        image.add_css_class ("map-marker-%s".printf (spot.band));

        var coordinate = spot.coordinate;
        if (coordinate == null)
            return;

        var marker = new Marker () {
            child = image,
            latitude = coordinate.latitude,
            longitude = coordinate.longitude
        };
        marker.add_css_class ("marker");

        var click = new Gtk.GestureClick ();
        click.pressed.connect (() => {
            marker_clicked = true;
            Application.current_spot_hash = spot.hash;

            var sidebar_box = split_view.sidebar as Gtk.Box;
            var spot_card = new SpotCard.from_spot (spot);

            for (var child = sidebar_box.get_first_child (); child != null;) {
                sidebar_box.remove (child);
                child = child.get_next_sibling ();
            }
            sidebar_box.append (spot_card);
            map_widget.go_to (coordinate.latitude, coordinate.longitude);
            split_view.show_sidebar = true;
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
    } /* _create_marker */

    public void bounce_filter () {
        filter.changed (Gtk.FilterChange.DIFFERENT);
        load_spots ();
    }

    public void load_spots () {
        bbox.clear ();

        if (marker_layer != null) {
            map_widget.remove_layer (marker_layer);
            marker_layer = null;
        }

        marker_layer = new MarkerLayer (viewport);

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

        map_widget.insert_layer_above (marker_layer, map_layer);

        if (Application.current_spot_hash == BLANK_HASH ||
            !valid_hashes.contains (Application.current_spot_hash)) {
            if (split_view.show_sidebar) {
                split_view.show_sidebar = false;
                Application.current_spot_hash = BLANK_HASH;
            }

            if ((spot_count > 0) && bbox.is_valid ()) {
                var center = bbox.center ();
                var zoom_level = get_zoom_level_fitting_bounds (bbox);

                map_widget.go_to_full (center.latitude, center.longitude, zoom_level);
            } else {
                map_widget.go_to_full (qth_coordinate.latitude, qth_coordinate.longitude, 4);
            }
        }

    } /* load_spots */
}     /* class MapWindow */
