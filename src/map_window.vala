using Shumate;

public static double MIN_LATITUDE = -85.0511287798;
public static double MAX_LATITUDE = 85.0511287798;
public static double MIN_LONGITUDE = -180;
public static double MAX_LONGITUDE = 180;

// BoundingBox from GNOME Maps, Marcus Lundblad <ml@update.uu.se>
public sealed class BoundingBox : Object {
    public double left    { get; private set; }
    public double bottom  { get; private set; }
    public double right   { get; private set; }
    public double top     { get; private set; }
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

    public BoundingBox.centered_on (Coordinate coordinate, double range = 1.0)
    {
        Object (
            left: coordinate.longitude - range,
            bottom: coordinate.latitude - range,
            right: coordinate.longitude + range,
            top: coordinate.latitude + range
            );
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
        return new Coordinate.full ((this.top + this.bottom) / 2.0, (this.left +
                                                                     this.right)
            / 2.0);
    }

    public void extend (double latitude, double longitude)
    {
        if (longitude < this.left) this.left = longitude;
        if (latitude < this.bottom) this.bottom = latitude;
        if (longitude > this.right) this.right = longitude;
        if (latitude > this.top) this.top = latitude;
    }

    public void extend_coordinate (Coordinate? coordinate)
    {
        if (coordinate == null) return;
        this.extend (coordinate.latitude, coordinate.longitude);
    }

    public bool covers (double latitude, double longitude)
    {
        return (latitude >= this.bottom && latitude <= this.top) &&
               (longitude >= this.left && longitude <= this.right);
    }

    public bool covers_coordinate (Coordinate? coordinate)
    {
        if (coordinate == null) return false;
        return covers (coordinate.latitude, coordinate.longitude);
    }

    public bool is_valid ()
    {
        return this.left < this.right && this.bottom < this.top &&
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
        bbox = new BoundingBox.centered_on (qth_coordinate);

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

        Application.spot_repo.refreshed.connect (load_spots);
        load_spots ();
    }

    private void _create_marker (Spot spot)
    {
        var image = new Gtk.Image.from_icon_name ("map-marker-symbolic")
        {
            pixel_size = 32
        };

        image.add_css_class ("map-marker");

        var coordinate = spot.coordinate;
        if (coordinate == null) return;

        var marker = new Marker ()
        {
            child = image,
            latitude = coordinate.latitude,
            longitude = coordinate.longitude
        };

        marker_layer.add_marker (marker);
    }

    public void load_spots ()
    {
        if (marker_layer != null)
        {
            map_widget.remove_layer (marker_layer);
            marker_layer = null;
        }

        marker_layer = new MarkerLayer (viewport);
        var spots = Application.spot_repo.store;

        uint spot_count = 0;
        for (uint i = 0; i < spots.get_n_items (); i++)
        {
            Spot spot = spots.get_item (i) as Spot;
            bbox.extend_coordinate (spot.coordinate);
            _create_marker (spot);
            spot_count++;
        }

        debug ("Added %u spot markers".printf (spot_count));

        map_widget.insert_layer_above (marker_layer, map_layer);
        viewport.set_location (qth_coordinate.latitude, qth_coordinate.longitude
            );
        viewport.set_zoom_level (4);
    }
} /* class MapWindow */
