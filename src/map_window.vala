using Shumate;

public static double MIN_LATITUDE = -85.0511287798;
public static double MAX_LATITUDE = 85.0511287798;
public static double MIN_LONGITUDE = -180;
public static double MAX_LONGITUDE = 180;

// BoundingBox from GNOME Maps, Marcus Lundblad <ml@update.uu.se>
public sealed class BoundingBox : Object {
    public double left    { get; set; }
    public double bottom  { get; set; }
    public double right   { get; set; }
    public double top     { get; set; }
    public BoundingBox (double? left, double? bottom, double? right, double? top
                        )
    {
        Object (
            left: left ?? MAX_LONGITUDE,
            bottom: bottom ?? MAX_LATITUDE,
            right: right ?? MIN_LONGITUDE,
            top: top ?? MIN_LATITUDE
            );
    }

    public BoundingBox.empty ()
    {
        Object (
            left:  MAX_LONGITUDE,
            bottom: MAX_LATITUDE,
            right: MIN_LONGITUDE,
            top: MIN_LATITUDE
            );
    }

    public BoundingBox.centered_on (Coordinate coordinate, double range = 1.0)
    {
        Object (
            left: coordinate.longitude - range,
            bottom: coordinate.latitude - range,
            right: coordinate.longitude + range,
            top: coordinate.latitude + range
            );
    }

    public void clear_all ()
    {
        left = MAX_LONGITUDE;
        bottom = MAX_LATITUDE;
        right = MIN_LONGITUDE;
        top = MIN_LATITUDE;
    }

    public void compose (BoundingBox other)
    {
        if (other.left < this.left) this.left = other.left;
        if (other.right > this.right) this.right = other.right;
        if (other.top > this.top) this.top = other.top;
        if (other.bottom < this.bottom) this.bottom = other.bottom;
    }

    public Coordinate center ()
    {
        var center_lat = (this.top + this.bottom) / 2.0;
        var center_lon = (this.left + this.right) / 2.0;

        // Normalize longitude if it's wrapped
        if (center_lon > 180)
            center_lon -= 360;
        else if (center_lon < -180)
            center_lon += 360;

        return new Coordinate.full (center_lat, center_lon);
    }

    public void extend (double latitude, double longitude)
    {
        if (latitude < this.bottom) this.bottom = latitude;
        if (latitude > this.top) this.top = latitude;

        // Handle longitude - bias toward 0° meridian for map display
        if ((this.left == MAX_LONGITUDE) && (this.right == MIN_LONGITUDE))
        {
            // First point being added
            this.left = longitude;
            this.right = longitude;
        }
        else
        {
            // Always prefer normal bounding box (no wrap) for map display
            // This biases toward the 0° meridian rather than 180°
            if (longitude < this.left) this.left = longitude;
            if (longitude > this.right) this.right = longitude;
        }
    }

    public void extend_coordinate (Coordinate? coordinate)
    {
        if (coordinate == null) return;
        this.extend (coordinate.latitude, coordinate.longitude);
    }

    public bool covers (double latitude, double longitude)
    {
        if (!((latitude >= this.bottom) && (latitude <= this.top)))
            return false;

        // Handle longitude wrap-around
        if (this.left <= this.right)
            // Normal case - no wrap
            return longitude >= this.left && longitude <= this.right;
        else
            // Wrapped case - across 180° meridian
            return longitude >= this.left || longitude <= this.right;
    }

    public bool covers_coordinate (Coordinate? coordinate)
    {
        if (coordinate == null) return false;
        return covers (coordinate.latitude, coordinate.longitude);
    }

    public bool is_valid ()
    {
        return this.bottom < this.top &&
               this.left >= MIN_LONGITUDE &&
               this.left <= MAX_LONGITUDE &&
               this.right >= MIN_LONGITUDE &&
               this.right <= MAX_LONGITUDE &&
               this.bottom >= MIN_LATITUDE &&
               this.bottom <= MAX_LATITUDE &&
               this.top >= MIN_LATITUDE &&
               this.top <= MAX_LATITUDE;
    }
} /* class BoundingBox */

public class MapWindow : Adw.ApplicationWindow {
    private Viewport viewport;
    private MapSourceRegistry registry;
    private Map map_widget;

    private Scale map_scale;
    private Layer map_layer;
    private MarkerLayer marker_layer;

    private BoundingBox bbox;
    private Coordinate qth_coordinate;

    private Gtk.Overlay overlay;

    Gtk.Filter filter;
    Gtk.FilterListModel filtered;

    public MapWindow ()
    {
        Object (
            title: _ ("Map")
            );
    }

    construct {
        var header = new Adw.HeaderBar ()
        {
            title_widget = new Gtk.Label (_ ("Map"))
        };

        registry = new MapSourceRegistry.with_defaults ();

        if (VectorRenderer.is_supported ())
        {
            try {
                var style_json = resources_lookup_data (
                    "/com/k0vcz/artemis/map-style.json", ResourceLookupFlags.
                    NONE);
                var renderer = new VectorRenderer ("vector-tiles", (string)
                    style_json.get_data ())
                {
                    max_zoom_level = 22,
                    license = "© OpenMapTiles © OpenStreetMap contributors"
                };
                registry.add (renderer);
            } catch(Error err) {
                warning ("Failed to create vector map style: %s", err.message);
            }
        }
        else
        {
            debug ("Vector renderer not supported.");
        }

        map_widget = new Map ()
        {
            vexpand = true,
            hexpand = true
        };

        var box = new Gtk.Box (Gtk.Orientation.VERTICAL, 0)
        {
            vexpand = true,
            hexpand = true
        };
        box.append (header);
        box.append (map_widget);

        overlay = new Gtk.Overlay ()
        {
            width_request = 800,
            height_request = 600,
            vexpand = true,
            hexpand = true
        };
        overlay.set_child (box);

        set_content (overlay);

        var map_source = registry.get_by_id ("vector-tiles");
        viewport = map_widget.get_viewport ();
        viewport.set_reference_map_source (map_source);
        viewport.set_max_zoom_level (22);
        viewport.set_min_zoom_level (0);

        map_scale = new Scale (viewport)
        {
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
            map_scale.visible = Application.settings.get_boolean (
                "show-map-scale");
        });

        Application.settings.changed["use-metric"].connect (() => {
            map_scale.unit = Application.settings.get_boolean ("use-metric") ?
                Shumate.Unit.METRIC : Shumate.Unit.IMPERIAL;
        });

        overlay.add_overlay (map_scale);

        qth_coordinate = new Coordinate ();
        var grid = Application.settings.get_string ("location");
        if (grid != "")
        {
            try {
                qth_coordinate = Distance.maidenhead_to_latlon (grid);
            } catch(Error err) {
                warning ("Failed to parse maidenhead location %s: %s", grid, err
                    .message);
            }
        }
        bbox = new BoundingBox.empty ();

        var layer = new MapLayer (map_source, viewport);
        if (layer != null)
        {
            map_widget.add_layer (layer);
            layer.tile_error.connect ((layer, tile, err) => {
                warning ("Failed top load tile %u/%u/%u: %s", tile.zoom_level,
                    tile.x, tile.y, err.message);
            });
            layer.map_loaded.connect ((layer, errors) => {
                print ("Map loaded%s".printf ((errors) ? " with errors" : ""));
            });
            map_layer = layer;
        }
        else
        {
            warning ("Base map layer is null!");
        }

        filter = new Gtk.CustomFilter ((item) => {
            var spot = item as Spot;
            if (spot == null)
                return false;

            if ((Application.current_band_filter != "All") && (spot.band !=
                                                               Application.
                                                               current_band_filter) )

                return false;

            if (Application.settings.get_boolean ("hide-qrt") &&
                spot.activator_comment.down ().contains ("qrt"))
                return false;

            if (Application.settings.get_boolean ("hide-hunted") && spot.
                was_hunted_today)
                return false;

            var stale_minutes = Application.settings.get_int ("hide-older-than")
            ;
            var now = new DateTime.now_utc ();
            var expires = spot.spot_time.add_minutes (stale_minutes);
            if (now.compare (expires) > 0)
                return false;

            if ((Application.current_program_filter != null) && (Application.
                                                                 current_program_filter
                                                                 != _
                                                                     ("All")) &&
                !spot.park_ref.down ().has_prefix (Application.
                    current_program_filter.down
                        ()))
                return false;

            if ((Application.current_mode_filter != null) && (Application.
                                                              current_mode_filter
                                                              != _ (
                                                                  "All")) &&
                !spot.mode.down ().contains (Application.current_mode_filter.
                    down ()))
                return false;

            if (Application.current_search_text != null)
            {
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

    private void _create_marker (Spot spot)
    {
        var image = new Gtk.Image.from_icon_name ("map-marker-symbolic")
        {
            pixel_size = 32
        };

        image.add_css_class ("map-marker-%s".printf (spot.band));

        var coordinate = spot.coordinate;
        if (coordinate == null) return;

        var marker = new Marker ()
        {
            child = image,
            latitude = coordinate.latitude,
            longitude = coordinate.longitude
        };

        var click = new Gtk.GestureClick ();
        click.pressed.connect (() => {
            Application.current_spot_hash = spot.hash;
        });
        marker.add_controller (click);

        var motion = new Gtk.EventControllerMotion ();
        motion.enter.connect ( () => {
            marker.set_opacity (0.5);
            marker.set_cursor_from_name ("pointer");
        });
        motion.leave.connect ( () => {
            marker.set_opacity (1.0);
            marker.set_cursor_from_name (null);
        });
        marker.add_controller (motion);

        marker_layer.add_marker (marker);
    } /* _create_marker */

    public void bounce_filter ()
    {
        filter.changed (Gtk.FilterChange.DIFFERENT);
        load_spots ();
    }

    private double calculate_zoom_level (BoundingBox bbox)
    {
        if (!bbox.is_valid ())
            return 4.0; // Default zoom if bounding box is invalid

        // Calculate the geographic span
        var lat_span = bbox.top - bbox.bottom;
        var lon_span = bbox.right - bbox.left;

        // Use the larger span (latitude or longitude) to determine zoom
        var max_span = double.max (lat_span, lon_span);

        // Convert geographic span to zoom level
        // These values are approximate and can be adjusted based on testing
        if (max_span > 180) return 1.0;   // Whole world
        if (max_span > 90) return 2.0;    // Hemisphere
        if (max_span > 45) return 3.0;    // Large continent
        if (max_span > 22) return 4.0;    // Continent
        if (max_span > 11) return 5.0;    // Large country
        if (max_span > 5.5) return 6.0;   // Country
        if (max_span > 2.7) return 7.0;   // Large state/province
        if (max_span > 1.4) return 8.0;   // State/province
        if (max_span > 0.7) return 9.0;   // Large region
        if (max_span > 0.35) return 10.0; // Region
        if (max_span > 0.17) return 11.0; // Large city area
        if (max_span > 0.085) return 12.0; // City area
        if (max_span > 0.042) return 13.0; // City
        if (max_span > 0.021) return 14.0; // Neighborhood
        if (max_span > 0.010) return 15.0; // Large block
        if (max_span > 0.005) return 16.0; // Block
        if (max_span > 0.002) return 17.0; // Street
        if (max_span > 0.001) return 18.0; // Building

        return 19.0; // Maximum detail
    } /* calculate_zoom_level */

    public void load_spots ()
    {
        bbox.clear_all ();

        if (marker_layer != null)
        {
            map_widget.remove_layer (marker_layer);
            marker_layer = null;
        }

        marker_layer = new MarkerLayer (viewport);

        uint spot_count = 0;
        for (uint i = 0; i < filtered.get_n_items (); i++)
        {
            Spot spot = filtered.get_item (i) as Spot;
            bbox.extend_coordinate (spot.coordinate);
            _create_marker (spot);
            spot_count++;
        }

        map_widget.insert_layer_above (marker_layer, map_layer);

        if ((spot_count > 0) && bbox.is_valid ())
        {
            var center = bbox.center ();
            var zoom_level = calculate_zoom_level (bbox);
            viewport.set_location (center.latitude, center.longitude);
            viewport.set_zoom_level (zoom_level);
        }
        else
        {
            // No spots or invalid bbox, use default location/zoom
            viewport.set_location (qth_coordinate.latitude, qth_coordinate.
                longitude);
            viewport.set_zoom_level (4);
        }
    } /* load_spots */
} /* class MapWindow */
