/* src/astronomy.vala
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

using Shumate;
using Gee;

namespace Astronomy {
    private enum BodyKind {
        SUN,
        MOON
    }

    public struct BodyMarker {
        public Coordinate coordinate;

        public BodyMarker (Coordinate coordinate) {
            this.coordinate = coordinate;
        }
    }

    public struct BodyMarkers {
        public BodyMarker sun;
        public BodyMarker moon;
        public MoonPhase moon_phase;

        public BodyMarkers (BodyMarker sun, BodyMarker moon, MoonPhase moon_phase) {
            this.sun = sun;
            this.moon = moon;
            this.moon_phase = moon_phase;
        }
    }

    public struct RiseSetTimes {
        public DateTime? rise;
        public DateTime? set;

        public RiseSetTimes (DateTime? rise, DateTime? set) {
            this.rise = rise;
            this.set = set;
        }
    }

    public enum MoonPhase {
        NEW,
        WAXING_CRESCENT,
        FIRST_QUARTER,
        WAXING_GIBBOUS,
        FULL,
        WANING_GIBBOUS,
        LAST_QUARTER,
        WANING_CRESCENT
    }

    public static string moon_phase_display_name (MoonPhase phase) {
        switch (phase) {
            case MoonPhase.NEW:
                return _("New Moon");
            case MoonPhase.WAXING_CRESCENT:
                return _("Waxing Crescent");
            case MoonPhase.FIRST_QUARTER:
                return _("First Quarter");
            case MoonPhase.WAXING_GIBBOUS:
                return _("Waxing Gibbous");
            case MoonPhase.FULL:
                return _("Full Moon");
            case MoonPhase.WANING_GIBBOUS:
                return _("Waning Gibbous");
            case MoonPhase.LAST_QUARTER:
                return _("Last Quarter");
            case MoonPhase.WANING_CRESCENT:
                return _("Waning Crescent");
            default:
                return "";
        }
    }

    public static string moon_phase_system_image_name (MoonPhase phase) {
        switch (phase) {
            case MoonPhase.NEW:
                return "moonphase.new.moon";
            case MoonPhase.WAXING_CRESCENT:
                return "moonphase.waxing.crescent";
            case MoonPhase.FIRST_QUARTER:
                return "moonphase.first.quarter";
            case MoonPhase.WAXING_GIBBOUS:
                return "moonphase.waxing.gibbous";
            case MoonPhase.FULL:
                return "moonphase.full.moon";
            case MoonPhase.WANING_GIBBOUS:
                return "moonphase.waning.gibbous";
            case MoonPhase.LAST_QUARTER:
                return "moonphase.last.quarter";
            case MoonPhase.WANING_CRESCENT:
                return "moonphase.waning.crescent";
            default:
                return "";
        }
    }

    public static BodyMarkers body_markers (DateTime date) {
        var sun_coordinate = solar_subsolar_point (date);
        var moon_coordinate = lunar_sublunar_point (date);

        return BodyMarkers (
            BodyMarker (sun_coordinate),
            BodyMarker (moon_coordinate),
            moon_phase (date)
        );
    }

    public static Coordinate solar_subsolar_point (DateTime date) {
        return subpoint (solar_equatorial_coordinates (date), date);
    }

    public static Coordinate lunar_sublunar_point (DateTime date) {
        return subpoint (lunar_equatorial_coordinates (date), date);
    }

    public static double solar_terminator_latitude (DateTime date, double longitude) {
        var subsolar = solar_subsolar_point (date);
        var declination_radians = subsolar.latitude * Math.PI / 180.0;
        var tangent = Math.tan (declination_radians);

        if (Math.fabs (tangent) < 1e-6)
            tangent = (tangent < 0.0) ? -1e-6 : 1e-6;

        var hour_angle_radians = (longitude - subsolar.longitude) * Math.PI / 180.0;
        return Math.atan (-Math.cos (hour_angle_radians) / tangent) * 180.0 / Math.PI;
    }

    public static bool is_sunlit (DateTime date, Coordinate coordinate) {
        return altitude_radians (
            solar_equatorial_coordinates (date),
            date,
            coordinate
        ) > 0.0;
    }

    public static ArrayList<Coordinate> solar_terminator_points (
        DateTime date,
        double longitude_step_degrees = 2.0
    ) {
        var points = new ArrayList<Coordinate> ();
        var subsolar = solar_subsolar_point (date);
        var declination_radians = subsolar.latitude * Math.PI / 180.0;
        var tangent = Math.tan (declination_radians);

        if (Math.fabs (tangent) < 1e-6)
            tangent = (tangent < 0.0) ? -1e-6 : 1e-6;

        for (double longitude = -180.0; longitude <= 180.0; longitude += longitude_step_degrees) {
            points.add (new Coordinate.full (
                solar_terminator_latitude (date, longitude),
                longitude
            ));
        }

        if (points.size == 0 || points[points.size - 1].longitude < 180.0) {
            points.add (new Coordinate.full (
                solar_terminator_latitude (date, 180.0),
                180.0
            ));
        }

        return points;
    }

    public static double moon_illuminated_fraction (DateTime date) {
        var elongation = lunar_elongation_degrees (date) * Math.PI / 180.0;
        return Math.ceil (((1.0 - Math.cos (elongation)) / 2.0) * 100.0);
    }

    public static MoonPhase moon_phase (DateTime date) {
        var elongation = lunar_elongation_degrees (date);

        if (((elongation >= 0) && (elongation < 7)) ||
            ((elongation >= 353) && (elongation < 360))) {
            return MoonPhase.NEW;
        } else if (elongation < 83) {
            return MoonPhase.WAXING_CRESCENT;
        } else if (elongation < 97) {
            return MoonPhase.FIRST_QUARTER;
        } else if (elongation < 173) {
            return MoonPhase.WAXING_GIBBOUS;
        } else if (elongation < 187) {
            return MoonPhase.FULL;
        } else if (elongation < 263) {
            return MoonPhase.WANING_GIBBOUS;
        } else if (elongation < 277) {
            return MoonPhase.LAST_QUARTER;
        } else {
            return MoonPhase.WANING_CRESCENT;
        }
    }

    public static double lunar_elongation_degrees (DateTime date) {
        var lunar = lunar_ecliptic_coordinates (date);
        return normalized_degrees (lunar.longitude - solar_ecliptic_longitude (date));
    }

    public static RiseSetTimes sun_rise_set_times (DateTime date, Coordinate coordinate) {
        return rise_set_times (
            date,
            coordinate,
            -0.833,
            BodyKind.SUN
        );
    }

    public static RiseSetTimes moon_rise_set_times (DateTime date, Coordinate coordinate) {
        return rise_set_times (
            date,
            coordinate,
            0.125,
            BodyKind.MOON
        );
    }

    private static RiseSetTimes rise_set_times (
        DateTime date,
        Coordinate coordinate,
        double horizon_altitude_degrees,
        BodyKind kind
    ) {
        var utc_date = date.to_utc ();
        var day_start = new DateTime.utc (
            utc_date.get_year (),
            utc_date.get_month (),
            utc_date.get_day_of_month (),
            0, 0, 0.0
        );
        const double STEP_SECONDS = 600.0;
        var day_end = day_start.add_seconds (172800.0);
        var horizon_altitude = horizon_altitude_degrees * Math.PI / 180.0;

        var previous_date = day_start;
        var previous_altitude = altitude_radians (
            equatorial_coordinates_for_body (kind, previous_date),
            previous_date,
            coordinate
        ) - horizon_altitude;
        DateTime? rise = null;
        DateTime? set = null;

        var current_date = day_start.add_seconds (STEP_SECONDS);
        while (current_date.compare (day_end) <= 0) {
            var current_altitude = altitude_radians (
                equatorial_coordinates_for_body (kind, current_date),
                current_date,
                coordinate
            ) - horizon_altitude;

            if ((previous_altitude == 0) || (sign_of (previous_altitude) != sign_of (current_altitude))) {
                var event_date = refined_horizon_crossing (
                    previous_date,
                    current_date,
                    horizon_altitude,
                    coordinate,
                    kind
                );

                if (previous_altitude <= current_altitude) {
                    if (rise == null)
                        rise = event_date;
                } else {
                    if (set == null)
                        set = event_date;
                }
            }

            previous_date = current_date;
            previous_altitude = current_altitude;
            current_date = current_date.add_seconds (STEP_SECONDS);
        }

        return RiseSetTimes (rise, set);
    }

    private static DateTime refined_horizon_crossing (
        DateTime start,
        DateTime end,
        double horizon_altitude,
        Coordinate observer,
        BodyKind kind
    ) {
        var lower = start;
        var upper = end;
        var lower_sign = sign_of (
            altitude_radians (equatorial_coordinates_for_body (kind, lower), lower, observer) - horizon_altitude
        );

        for (int i = 0; i < 20; i++) {
            var midpoint = lower.add_seconds (
                (upper.to_unix () - lower.to_unix ()) / 2.0
            );
            var midpoint_altitude = altitude_radians (
                equatorial_coordinates_for_body (kind, midpoint),
                midpoint,
                observer
            ) - horizon_altitude;

            if (lower_sign == sign_of (midpoint_altitude)) {
                lower = midpoint;
            } else {
                upper = midpoint;
            }
        }

        return lower.add_seconds ((upper.to_unix () - lower.to_unix ()) / 2.0);
    }

    private struct EquatorialCoordinates {
        public double right_ascension_degrees;
        public double declination_degrees;

        public EquatorialCoordinates (double right_ascension_degrees, double declination_degrees) {
            this.right_ascension_degrees = right_ascension_degrees;
            this.declination_degrees = declination_degrees;
        }
    }

    private static EquatorialCoordinates solar_equatorial_coordinates (DateTime date) {
        var julian_day = julian_day (date);
        var julian_centuries = julian_centuries (julian_day);
        var apparent_longitude = solar_ecliptic_longitude_for_julian_centuries (julian_centuries);

        var omega = 125.04 - 1934.136 * julian_centuries;
        var mean_obliquity = mean_obliquity_degrees (julian_centuries);
        var corrected_obliquity = mean_obliquity + 0.00256 * Math.cos (omega * Math.PI / 180.0);

        return equatorial_coordinates (
            apparent_longitude,
            0.0,
            corrected_obliquity
        );
    }

    private static EquatorialCoordinates lunar_equatorial_coordinates (DateTime date) {
        var julian_day = julian_day (date);
        var julian_centuries = julian_centuries (julian_day);
        var ecliptic_coordinates = lunar_ecliptic_coordinates (date);

        return equatorial_coordinates (
            ecliptic_coordinates.longitude,
            ecliptic_coordinates.latitude,
            mean_obliquity_degrees (julian_centuries)
        );
    }

    private static EquatorialCoordinates equatorial_coordinates_for_body (BodyKind kind, DateTime date) {
        switch (kind) {
            case BodyKind.SUN:
                return solar_equatorial_coordinates (date);
            case BodyKind.MOON:
                return lunar_equatorial_coordinates (date);
            default:
                return solar_equatorial_coordinates (date);
        }
    }

    private static EquatorialCoordinates equatorial_coordinates (
        double longitude_degrees,
        double latitude_degrees,
        double obliquity_degrees
    ) {
        var longitude = longitude_degrees * Math.PI / 180.0;
        var latitude = latitude_degrees * Math.PI / 180.0;
        var obliquity = obliquity_degrees * Math.PI / 180.0;

        var x = Math.cos (latitude) * Math.cos (longitude);
        var y = Math.cos (latitude) * Math.sin (longitude) * Math.cos (obliquity)
            - Math.sin (latitude) * Math.sin (obliquity);
        var z = Math.cos (latitude) * Math.sin (longitude) * Math.sin (obliquity)
            + Math.sin (latitude) * Math.cos (obliquity);

        return EquatorialCoordinates (
            normalized_degrees (Math.atan2 (y, x) * 180.0 / Math.PI),
            Math.asin (z) * 180.0 / Math.PI
        );
    }

    private static Coordinate subpoint (EquatorialCoordinates coordinates, DateTime date) {
        var julian_day = julian_day (date);
        var julian_centuries = julian_centuries (julian_day);
        var gmst_degrees = greenwich_mean_sidereal_time_degrees (julian_day, julian_centuries);

        return new Coordinate.full (
            coordinates.declination_degrees,
            normalized_longitude_degrees (coordinates.right_ascension_degrees - gmst_degrees)
        );
    }

    private static double altitude_radians (
        EquatorialCoordinates coordinates,
        DateTime date,
        Coordinate observer
    ) {
        var latitude = observer.latitude * Math.PI / 180.0;
        var declination = coordinates.declination_degrees * Math.PI / 180.0;
        var local_sidereal_time = normalized_degrees (
            greenwich_mean_sidereal_time_degrees (
                julian_day (date),
                julian_centuries (julian_day (date))
            ) + observer.longitude
        );
        var hour_angle = normalized_signed_degrees (local_sidereal_time - coordinates.right_ascension_degrees) * Math.PI / 180.0;

        return Math.asin (
            Math.sin (latitude) * Math.sin (declination)
                + Math.cos (latitude) * Math.cos (declination) * Math.cos (hour_angle)
        );
    }

    private static double solar_ecliptic_longitude (DateTime date) {
        return solar_ecliptic_longitude_for_julian_centuries (
            julian_centuries (julian_day (date))
        );
    }

    private static double solar_ecliptic_longitude_for_julian_centuries (double julian_centuries) {
        var mean_longitude = normalized_degrees (
            280.46646 + julian_centuries * (36000.76983 + julian_centuries * 0.0003032)
        );
        var mean_anomaly = normalized_degrees (
            357.52911 + julian_centuries * (35999.05029 - 0.0001537 * julian_centuries)
        );

        var mean_anomaly_radians = mean_anomaly * Math.PI / 180.0;
        var center = Math.sin (mean_anomaly_radians) * (1.914602 - julian_centuries * (0.004817 + 0.000014 * julian_centuries))
            + Math.sin (2.0 * mean_anomaly_radians) * (0.019993 - 0.000101 * julian_centuries)
            + Math.sin (3.0 * mean_anomaly_radians) * 0.000289;

        var true_longitude = mean_longitude + center;
        var omega = 125.04 - 1934.136 * julian_centuries;
        return normalized_degrees (true_longitude - 0.00569 - 0.00478 * Math.sin (omega * Math.PI / 180.0));
    }

    private struct EclipticCoordinates {
        public double longitude;
        public double latitude;

        public EclipticCoordinates (double longitude, double latitude) {
            this.longitude = longitude;
            this.latitude = latitude;
        }
    }

    private static EclipticCoordinates lunar_ecliptic_coordinates (DateTime date) {
        var julian_day = julian_day (date);
        var days_since_j2000 = julian_day - 2451545.0;

        var mean_longitude = normalized_degrees (218.3164477 + 13.17639648 * days_since_j2000);
        var mean_anomaly = normalized_degrees (134.9633964 + 13.06499295 * days_since_j2000);
        var solar_mean_anomaly = normalized_degrees (357.5291092 + 0.98560028 * days_since_j2000);
        var mean_elongation = normalized_degrees (297.8501921 + 12.19074912 * days_since_j2000);
        var argument_of_latitude = normalized_degrees (93.2720950 + 13.22935024 * days_since_j2000);

        var ecliptic_longitude = mean_longitude
            + 6.289 * sin_degrees (mean_anomaly)
            + 1.274 * sin_degrees (2.0 * mean_elongation - mean_anomaly)
            + 0.658 * sin_degrees (2.0 * mean_elongation)
            + 0.214 * sin_degrees (2.0 * mean_anomaly)
            - 0.186 * sin_degrees (solar_mean_anomaly)
            - 0.059 * sin_degrees (2.0 * mean_elongation - 2.0 * mean_anomaly)
            - 0.057 * sin_degrees (2.0 * mean_elongation - mean_anomaly - solar_mean_anomaly)
            + 0.053 * sin_degrees (2.0 * mean_elongation + mean_anomaly)
            + 0.046 * sin_degrees (2.0 * mean_elongation - solar_mean_anomaly)
            + 0.041 * sin_degrees (mean_anomaly - solar_mean_anomaly);

        var ecliptic_latitude = 5.128 * sin_degrees (argument_of_latitude)
            + 0.280 * sin_degrees (mean_anomaly + argument_of_latitude)
            + 0.277 * sin_degrees (mean_anomaly - argument_of_latitude)
            + 0.173 * sin_degrees (2.0 * mean_elongation - argument_of_latitude)
            + 0.055 * sin_degrees (2.0 * mean_elongation + argument_of_latitude - mean_anomaly)
            + 0.046 * sin_degrees (2.0 * mean_elongation - argument_of_latitude - mean_anomaly)
            + 0.033 * sin_degrees (2.0 * mean_elongation + argument_of_latitude)
            + 0.017 * sin_degrees (2.0 * mean_anomaly + argument_of_latitude);

        return EclipticCoordinates (
            normalized_degrees (ecliptic_longitude),
            ecliptic_latitude
        );
    }

    private static double julian_day (DateTime date) {
        return date.to_unix () / 86400.0 + 2440587.5;
    }

    private static double julian_centuries (double julian_day) {
        return (julian_day - 2451545.0) / 36525.0;
    }

    private static double mean_obliquity_degrees (double julian_centuries) {
        return 23.0 + (26.0 + ((21.448 - julian_centuries * (46.815 + julian_centuries * (0.00059 - julian_centuries * 0.001813))) / 60.0)) / 60.0;
    }

    private static double greenwich_mean_sidereal_time_degrees (double julian_day, double julian_centuries) {
        return normalized_degrees (
            280.46061837
                + 360.98564736629 * (julian_day - 2451545.0)
                + 0.000387933 * julian_centuries * julian_centuries
                - julian_centuries * julian_centuries * julian_centuries / 38710000.0
        );
    }

    private static double sin_degrees (double degrees) {
        return Math.sin (degrees * Math.PI / 180.0);
    }

    public static double normalized_degrees (double degrees) {
        var normalized = degrees % 360.0;
        return normalized >= 0 ? normalized : normalized + 360.0;
    }

    public static double normalized_longitude_degrees (double degrees) {
        var normalized = normalized_degrees (degrees);
        return (normalized > 180.0) ? normalized - 360.0 : normalized;
    }

    private static double normalized_signed_degrees (double degrees) {
        var normalized = normalized_degrees (degrees);
        return (normalized > 180.0) ? normalized - 360.0 : normalized;
    }

    private static int sign_of (double value) {
        if (value < 0)
            return -1;
        if (value > 0)
            return 1;
        return 0;
    }
}
