/* src/operating_limits.vala
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

using Gee;

public const string OPERATING_LIMITS_RESOURCE_PATH = "/com/k0vcz/artemis/operating-limits.json";

private const string[] OPERATING_LIMIT_KNOWN_BANDS = {
    "160m", "80m", "60m", "40m", "30m", "20m", "17m",
    "15m", "12m", "10m", "6m", "2m", "70cm"
};

private const string[] OPERATING_LIMIT_KNOWN_MODES = {
    "SSB", "CW", "FT8", "FT4", "FM", "AM", "RTTY", "JT65"
};

private const double OPERATING_LIMIT_SSB_BANDWIDTH_KHZ = 3.0;

private enum OperatingLimitSideband {
    NONE,
    LOWER,
    UPPER
}

public errordomain OperatingLimitError {
    INVALID_SCHEMA,
    INVALID_RULESET,
    INVALID_PROFILE,
    INVALID_RULE
}

public sealed class OperatingLimitRule : Object {
    public string band { get; private set; }
    public double min_khz { get; private set; }
    public double max_khz { get; private set; }
    public ArrayList<string> modes { get; private set; }

    public OperatingLimitRule (
        string band,
        double min_khz,
        double max_khz,
        ArrayList<string> modes
    ) {
        Object ();
        this.band = band;
        this.min_khz = min_khz;
        this.max_khz = max_khz;
        this.modes = copy_string_list (modes);
    }

    public OperatingLimitRule copy () {
        return new OperatingLimitRule (band, min_khz, max_khz, modes);
    }

    public bool contains_frequency (double frequency_khz) {
        return frequency_khz + 0.0001 >= min_khz && frequency_khz - 0.0001 <= max_khz;
    }

    public bool contains_frequency_range (double min_frequency_khz, double max_frequency_khz) {
        return contains_frequency (min_frequency_khz) && contains_frequency (max_frequency_khz);
    }

    public bool allows_mode (string mode) {
        var normalized = normalize_mode (mode);
        foreach (var allowed_mode in modes) {
            if (allowed_mode == normalized)
                return true;
        }
        return false;
    }

    public string modes_label () {
        return join_strings (modes, ", ");
    }

    public string range_label () {
        if (Math.fabs (min_khz - max_khz) < 0.0001)
            return "%.0f kHz".printf (min_khz);

        return "%.0f–%.0f kHz".printf (min_khz, max_khz);
    }

    public void write_json (Json.Builder builder) {
        builder.begin_object ();
        builder.set_member_name ("band");
        builder.add_string_value (band);
        builder.set_member_name ("minKHz");
        builder.add_double_value (min_khz);
        builder.set_member_name ("maxKHz");
        builder.add_double_value (max_khz);
        builder.set_member_name ("modes");
        builder.begin_array ();
        foreach (var mode in modes)
            builder.add_string_value (mode);
        builder.end_array ();
        builder.end_object ();
    }
}

public sealed class OperatingLimitProfile : Object {
    public string country_code { get; private set; }
    public string country_name { get; private set; }
    public string id { get; private set; }
    public string name { get; private set; }
    public bool hidden { get; private set; }
    public ArrayList<string> inherits { get; private set; }
    public ArrayList<OperatingLimitRule> rules { get; private set; }

    public OperatingLimitProfile (
        string country_code,
        string country_name,
        string id,
        string name,
        bool hidden,
        ArrayList<string>? inherits = null,
        ArrayList<OperatingLimitRule>? rules = null
    ) {
        Object ();
        this.country_code = country_code;
        this.country_name = country_name;
        this.id = id;
        this.name = name;
        this.hidden = hidden;
        this.inherits = inherits != null ? copy_string_list (inherits) : new ArrayList<string> ();
        this.rules = new ArrayList<OperatingLimitRule> ();
        if (rules != null) {
            foreach (var rule in rules)
                this.rules.add (rule.copy ());
        }
    }

    public string label () {
        if (country_name == "")
            return name;
        return "%s - %s".printf (country_name, name);
    }

    public OperatingLimitProfile with_rules (ArrayList<OperatingLimitRule> resolved_rules) {
        return new OperatingLimitProfile (
            country_code,
            country_name,
            id,
            name,
            hidden,
            new ArrayList<string> (),
            resolved_rules
        );
    }

    public string to_json_string () {
        var builder = new Json.Builder ();
        builder.begin_object ();
        builder.set_member_name ("schemaVersion");
        builder.add_int_value (1);
        builder.set_member_name ("frequencyUnit");
        builder.add_string_value ("kHz");
        builder.set_member_name ("countryCode");
        builder.add_string_value (country_code);
        builder.set_member_name ("countryName");
        builder.add_string_value (country_name);
        builder.set_member_name ("profileId");
        builder.add_string_value (id);
        builder.set_member_name ("profileName");
        builder.add_string_value (name);
        builder.set_member_name ("rules");
        builder.begin_array ();
        foreach (var rule in rules)
            rule.write_json (builder);
        builder.end_array ();
        builder.end_object ();

        var generator = new Json.Generator ();
        generator.set_root (builder.get_root ());
        generator.pretty = true;

        size_t length;
        return generator.to_data (out length);
    }
}

public ArrayList<OperatingLimitRule> operating_limit_rules_sorted_for_display (
    ArrayList<OperatingLimitRule> rules
) {
    var sorted = new ArrayList<OperatingLimitRule> ();
    foreach (var rule in rules)
        sorted.add (rule.copy ());

    sorted.sort ((a, b) => {
        return compare_operating_limit_rules_for_display (a, b);
    });
    return sorted;
}

public int compare_operating_limit_rules_for_display (
    OperatingLimitRule a,
    OperatingLimitRule b
) {
    var cmp = compare_int_values (
        operating_limit_band_sort_khz (a.band),
        operating_limit_band_sort_khz (b.band)
    );
    if (cmp != 0)
        return cmp;

    cmp = compare_double_values (a.min_khz, b.min_khz);
    if (cmp != 0)
        return cmp;

    cmp = compare_double_values (a.max_khz, b.max_khz);
    if (cmp != 0)
        return cmp;

    cmp = strcmp (a.band, b.band);
    if (cmp != 0)
        return cmp;

    return strcmp (a.modes_label (), b.modes_label ());
}

private static int operating_limit_band_sort_khz (string band) {
    int min_khz;
    int max_khz;
    if (band_frequency_range_khz (band, out min_khz, out max_khz)) {
        if (max_khz < min_khz)
            return max_khz;
        return min_khz;
    }

    return int.MAX;
}

private static int compare_int_values (int a, int b) {
    if (a < b)
        return -1;
    if (a > b)
        return 1;
    return 0;
}

private static int compare_double_values (double a, double b) {
    if (Math.fabs (a - b) < 0.0001)
        return 0;
    if (a < b)
        return -1;
    return 1;
}

public sealed class OperatingLimitCountry : Object {
    public string code { get; private set; }
    public string name { get; private set; }
    public bool complete { get; private set; }
    public ArrayList<OperatingLimitProfile> profiles { get; private set; }

    public OperatingLimitCountry (
        string code,
        string name,
        bool complete,
        ArrayList<OperatingLimitProfile> profiles
    ) {
        Object ();
        this.code = code;
        this.name = name;
        this.complete = complete;
        this.profiles = profiles;
    }

    public ArrayList<OperatingLimitProfile> visible_profiles () {
        var visible = new ArrayList<OperatingLimitProfile> ();
        foreach (var profile in profiles) {
            if (!profile.hidden)
                visible.add (profile);
        }
        return visible;
    }

    public OperatingLimitProfile? find_profile (string profile_id) {
        foreach (var profile in profiles) {
            if (profile.id == profile_id)
                return profile;
        }
        return null;
    }
}

public sealed class OperatingLimitRuleset : Object {
    public HashMap<string, ArrayList<string>> mode_groups { get; private set; }
    public ArrayList<OperatingLimitCountry> countries { get; private set; }

    public OperatingLimitRuleset (
        HashMap<string, ArrayList<string>> mode_groups,
        ArrayList<OperatingLimitCountry> countries
    ) {
        Object ();
        this.mode_groups = mode_groups;
        this.countries = countries;
    }

    public static OperatingLimitRuleset from_resource (string resource_path) throws Error {
        string json_text = (string) GLib.resources_lookup_data (
            resource_path,
            GLib.ResourceLookupFlags.NONE
        ).get_data ();

        return from_json (json_text);
    }

    public static OperatingLimitRuleset from_json (string json_text) throws Error {
        var parser = new Json.Parser ();
        parser.load_from_data (json_text, (ssize_t) json_text.length);

        var root = parser.get_root ();
        if ((root == null) || (root.get_node_type () != Json.NodeType.OBJECT)) {
            throw new OperatingLimitError.INVALID_SCHEMA (
                "Operating limits root must be a JSON object"
            );
        }

        var object = root.get_object ();
        var schema_version = require_int_member (object, "schemaVersion", "ruleset");
        if (schema_version != 1) {
            throw new OperatingLimitError.INVALID_SCHEMA (
                "Unsupported operating limits schema version %d".printf (schema_version)
            );
        }

        var frequency_unit = require_string_member (object, "frequencyUnit", "ruleset");
        if (frequency_unit != "kHz") {
            throw new OperatingLimitError.INVALID_SCHEMA (
                "Unsupported operating limits frequency unit '%s'".printf (frequency_unit)
            );
        }

        var mode_groups = parse_mode_groups (
            require_object_member (object, "modeGroups", "ruleset")
        );
        var countries = parse_countries (
            require_array_member (object, "countries", "ruleset"),
            mode_groups
        );

        var ruleset = new OperatingLimitRuleset (mode_groups, countries);
        ruleset.validate_inheritance ();
        return ruleset;
    }

    public ArrayList<OperatingLimitCountry> complete_countries () {
        var complete = new ArrayList<OperatingLimitCountry> ();
        foreach (var country in countries) {
            if (country.complete && country.visible_profiles ().size > 0)
                complete.add (country);
        }
        return complete;
    }

    public OperatingLimitCountry? find_country (string country_code) {
        foreach (var country in countries) {
            if (country.code == country_code)
                return country;
        }
        return null;
    }

    public OperatingLimitProfile? find_profile (string country_code, string profile_id) {
        var country = find_country (country_code);
        return country != null ? country.find_profile (profile_id) : null;
    }

    public OperatingLimitProfile resolve_profile (
        string country_code,
        string profile_id
    ) throws OperatingLimitError {
        var country = find_country (country_code);
        if (country == null) {
            throw new OperatingLimitError.INVALID_PROFILE (
                "Unknown operating limits country '%s'".printf (country_code)
            );
        }

        var seen = new HashSet<string> ();
        return resolve_profile_internal (country, profile_id, seen);
    }

    public OperatingLimitProfile parse_custom_profile (string json_text) throws Error {
        var parser = new Json.Parser ();
        parser.load_from_data (json_text, (ssize_t) json_text.length);

        var root = parser.get_root ();
        if ((root == null) || (root.get_node_type () != Json.NodeType.OBJECT)) {
            throw new OperatingLimitError.INVALID_SCHEMA (
                "Custom operating limits root must be a JSON object"
            );
        }

        var object = root.get_object ();
        var schema_version = require_int_member (object, "schemaVersion", "custom profile");
        if (schema_version != 1) {
            throw new OperatingLimitError.INVALID_SCHEMA (
                "Unsupported custom operating limits schema version %d".printf (schema_version)
            );
        }

        var frequency_unit = require_string_member (object, "frequencyUnit", "custom profile");
        if (frequency_unit != "kHz") {
            throw new OperatingLimitError.INVALID_SCHEMA (
                "Unsupported custom operating limits frequency unit '%s'".printf (frequency_unit)
            );
        }

        var country_code = object.get_string_member_with_default ("countryCode", "");
        var country_name = object.get_string_member_with_default ("countryName", "");
        var profile_id = object.get_string_member_with_default ("profileId", "custom");
        var profile_name = object.get_string_member_with_default ("profileName", _("Custom"));
        var rules = parse_rules (
            require_array_member (object, "rules", "custom profile"),
            mode_groups,
            "custom profile"
        );

        return new OperatingLimitProfile (
            country_code,
            country_name,
            profile_id,
            profile_name,
            false,
            new ArrayList<string> (),
            rules
        );
    }

    private OperatingLimitProfile resolve_profile_internal (
        OperatingLimitCountry country,
        string profile_id,
        HashSet<string> seen
    ) throws OperatingLimitError {
        if (seen.contains (profile_id)) {
            throw new OperatingLimitError.INVALID_PROFILE (
                "Operating limit profile inheritance cycle at '%s'".printf (profile_id)
            );
        }

        var profile = country.find_profile (profile_id);
        if (profile == null) {
            throw new OperatingLimitError.INVALID_PROFILE (
                "Unknown operating limit profile '%s' for %s".printf (profile_id, country.code)
            );
        }

        seen.add (profile_id);
        var resolved_rules = new ArrayList<OperatingLimitRule> ();
        foreach (var parent_id in profile.inherits) {
            var parent = resolve_profile_internal (country, parent_id, seen);
            foreach (var rule in parent.rules)
                resolved_rules.add (rule.copy ());
        }

        foreach (var rule in profile.rules)
            resolved_rules.add (rule.copy ());

        seen.remove (profile_id);
        return profile.with_rules (resolved_rules);
    }

    private void validate_inheritance () throws OperatingLimitError {
        foreach (var country in countries) {
            foreach (var profile in country.profiles) {
                var seen = new HashSet<string> ();
                resolve_profile_internal (country, profile.id, seen);
            }
        }
    }
}

public sealed class OperatingLimitMatchResult : Object {
    public bool allowed { get; private set; }
    public string reason { get; private set; }
    public string profile_label { get; private set; }
    public OperatingLimitRule? rule { get; private set; }

    public OperatingLimitMatchResult (
        bool allowed,
        string reason,
        string profile_label,
        OperatingLimitRule? rule = null
    ) {
        Object ();
        this.allowed = allowed;
        this.reason = reason;
        this.profile_label = profile_label;
        this.rule = rule;
    }
}

public sealed class OperatingLimitEvaluator : Object {
    public OperatingLimitProfile profile { get; private set; }

    public OperatingLimitEvaluator (OperatingLimitProfile profile) {
        Object ();
        this.profile = profile;
    }

    public OperatingLimitMatchResult evaluate (double frequency_khz, string mode) {
        var normalized_mode = normalize_mode (mode);
        var label = profile.label ();
        double occupied_min_khz;
        double occupied_max_khz;
        occupied_frequency_range_khz (
            frequency_khz,
            mode,
            out occupied_min_khz,
            out occupied_max_khz
        );

        if (!known_mode (normalized_mode)) {
            return new OperatingLimitMatchResult (
                false,
                _("Mode %s is not covered by the active operating limits").printf (mode),
                label
            );
        }

        bool frequency_seen = false;
        bool mode_seen = false;
        foreach (var rule in profile.rules) {
            if (!rule.contains_frequency (frequency_khz))
                continue;

            frequency_seen = true;
            if (!rule.allows_mode (normalized_mode))
                continue;

            mode_seen = true;
            if (rule.contains_frequency_range (occupied_min_khz, occupied_max_khz)) {
                return new OperatingLimitMatchResult (
                    true,
                    _("Allowed by %s for %s").printf (rule.range_label (), rule.modes_label ()),
                    label,
                    rule
                );
            }
        }

        var frequency_label = "%s MHz".printf (format_frequency_mhz_from_khz (frequency_khz));
        if (mode_seen) {
            return new OperatingLimitMatchResult (
                false,
                _("%s %s signal extends outside the active operating range").printf (
                    frequency_label,
                    normalized_mode
                ),
                label
            );
        }

        if (frequency_seen) {
            return new OperatingLimitMatchResult (
                false,
                _("%s is inside an active range, but %s is not allowed there").printf (
                    frequency_label,
                    normalized_mode
                ),
                label
            );
        }

        return new OperatingLimitMatchResult (
            false,
            _("%s is outside the active operating ranges").printf (frequency_label),
            label
        );
    }
}

private static void occupied_frequency_range_khz (
    double frequency_khz,
    string mode,
    out double min_khz,
    out double max_khz
) {
    min_khz = frequency_khz;
    max_khz = frequency_khz;

    switch (sideband_for_mode (mode, frequency_khz)) {
        case OperatingLimitSideband.LOWER:
            min_khz = frequency_khz - OPERATING_LIMIT_SSB_BANDWIDTH_KHZ;
            break;
        case OperatingLimitSideband.UPPER:
            max_khz = frequency_khz + OPERATING_LIMIT_SSB_BANDWIDTH_KHZ;
            break;
        default:
            break;
    }
}

private static OperatingLimitSideband sideband_for_mode (
    string mode,
    double frequency_khz
) {
    var normalized = mode.strip ().up ();
    switch (normalized) {
        case "USB":
            return OperatingLimitSideband.UPPER;
        case "LSB":
            return OperatingLimitSideband.LOWER;
        case "SSB":
            return frequency_khz >= 10000.0 ?
                OperatingLimitSideband.UPPER :
                OperatingLimitSideband.LOWER;
        default:
            return OperatingLimitSideband.NONE;
    }
}

private static OperatingLimitRuleset? cached_operating_limit_ruleset = null;
private static string? cached_operating_limit_settings_key = null;
private static OperatingLimitEvaluator? cached_operating_limit_evaluator = null;

public static OperatingLimitRuleset operating_limit_ruleset () throws Error {
    if (cached_operating_limit_ruleset == null) {
        cached_operating_limit_ruleset = OperatingLimitRuleset.from_resource (
            OPERATING_LIMITS_RESOURCE_PATH
        );
    }
    return cached_operating_limit_ruleset;
}

public static OperatingLimitEvaluator? operating_limit_evaluator_from_settings (
    Settings settings
) {
    var custom_json = settings.get_string ("operating-limits-custom-rules-json").strip ();
    var country_code = settings.get_string ("operating-limits-country-code").strip ();
    var profile_id = settings.get_string ("operating-limits-profile-id").strip ();
    var settings_key = "%s\n%s\n%s".printf (country_code, profile_id, custom_json);

    if (cached_operating_limit_settings_key != null &&
        cached_operating_limit_settings_key == settings_key)
        return cached_operating_limit_evaluator;

    try {
        var ruleset = operating_limit_ruleset ();
        OperatingLimitProfile profile;

        if (custom_json != "") {
            profile = ruleset.parse_custom_profile (custom_json);
        } else {
            if (country_code == "" || profile_id == "")
                return null;
            profile = ruleset.resolve_profile (country_code, profile_id);
        }

        cached_operating_limit_evaluator = new OperatingLimitEvaluator (profile);
        cached_operating_limit_settings_key = settings_key;
        return cached_operating_limit_evaluator;
    } catch (Error err) {
        warning ("Unable to load operating limits from settings: %s", err.message);
        cached_operating_limit_evaluator = null;
        cached_operating_limit_settings_key = settings_key;
        return null;
    }
}

public static OperatingLimitEvaluator? operating_limit_spot_filter_evaluator_from_settings (
    Settings settings
) {
    if (!settings.get_boolean ("operating-limits-spot-filter-enabled"))
        return null;

    return operating_limit_evaluator_from_settings (settings);
}

public static OperatingLimitEvaluator? operating_limit_tune_warning_evaluator_from_settings (
    Settings settings
) {
    if (!settings.get_boolean ("operating-limits-tune-warning-enabled"))
        return null;

    return operating_limit_evaluator_from_settings (settings);
}

public static string normalize_mode (string mode) {
    var normalized = mode.strip ().up ();
    switch (normalized) {
        case "USB":
        case "LSB":
            return "SSB";
        default:
            return normalized;
    }
}

public static bool known_mode (string mode) {
    var normalized = normalize_mode (mode);
    foreach (var known in OPERATING_LIMIT_KNOWN_MODES) {
        if (known == normalized)
            return true;
    }
    return false;
}

public static bool known_band (string band) {
    foreach (var known in OPERATING_LIMIT_KNOWN_BANDS) {
        if (known == band)
            return true;
    }
    return false;
}

private static Json.Object require_object_member (
    Json.Object object,
    string member,
    string context
) throws OperatingLimitError {
    var node = object.get_member (member);
    if ((node == null) || (node.get_node_type () != Json.NodeType.OBJECT)) {
        throw new OperatingLimitError.INVALID_SCHEMA (
            "%s is missing object member '%s'".printf (context, member)
        );
    }
    return node.get_object ();
}

private static Json.Array require_array_member (
    Json.Object object,
    string member,
    string context
) throws OperatingLimitError {
    var node = object.get_member (member);
    if ((node == null) || (node.get_node_type () != Json.NodeType.ARRAY)) {
        throw new OperatingLimitError.INVALID_SCHEMA (
            "%s is missing array member '%s'".printf (context, member)
        );
    }
    return node.get_array ();
}

private static string require_string_member (
    Json.Object object,
    string member,
    string context
) throws OperatingLimitError {
    if (!object.has_member (member)) {
        throw new OperatingLimitError.INVALID_SCHEMA (
            "%s is missing string member '%s'".printf (context, member)
        );
    }

    var value = object.get_string_member (member).strip ();
    if (value == "") {
        throw new OperatingLimitError.INVALID_SCHEMA (
            "%s has empty string member '%s'".printf (context, member)
        );
    }
    return value;
}

private static int require_int_member (
    Json.Object object,
    string member,
    string context
) throws OperatingLimitError {
    if (!object.has_member (member)) {
        throw new OperatingLimitError.INVALID_SCHEMA (
            "%s is missing integer member '%s'".printf (context, member)
        );
    }
    return (int) object.get_int_member (member);
}

private static double require_double_member (
    Json.Object object,
    string member,
    string context
) throws OperatingLimitError {
    if (!object.has_member (member)) {
        throw new OperatingLimitError.INVALID_SCHEMA (
            "%s is missing number member '%s'".printf (context, member)
        );
    }
    return object.get_double_member (member);
}

private static HashMap<string, ArrayList<string>> parse_mode_groups (
    Json.Object object
) throws OperatingLimitError {
    var groups = new HashMap<string, ArrayList<string>> ();
    var names = object.get_members ();
    foreach (var name in names) {
        var node = object.get_member (name);
        if ((node == null) || (node.get_node_type () != Json.NodeType.ARRAY)) {
            throw new OperatingLimitError.INVALID_SCHEMA (
                "Mode group '%s' must be an array".printf (name)
            );
        }

        groups[name] = parse_mode_array (node.get_array (), "mode group '%s'".printf (name));
    }

    if (!groups.has_key ("all")) {
        throw new OperatingLimitError.INVALID_SCHEMA (
            "Operating limits ruleset is missing mode group 'all'"
        );
    }
    return groups;
}

private static ArrayList<OperatingLimitCountry> parse_countries (
    Json.Array array,
    HashMap<string, ArrayList<string>> mode_groups
) throws OperatingLimitError {
    var countries = new ArrayList<OperatingLimitCountry> ();
    var country_codes = new HashSet<string> ();

    for (uint i = 0; i < array.get_length (); i++) {
        var object = array.get_object_element (i);
        var context = "country %u".printf (i + 1);
        var code = require_string_member (object, "code", context);
        var name = require_string_member (object, "name", context);
        var complete = object.has_member ("complete") ? object.get_boolean_member ("complete") : false;

        if (country_codes.contains (code)) {
            throw new OperatingLimitError.INVALID_RULESET (
                "Duplicate operating limits country '%s'".printf (code)
            );
        }
        country_codes.add (code);

        var profiles = parse_profiles (
            require_array_member (object, "profiles", context),
            code,
            name,
            mode_groups
        );
        countries.add (new OperatingLimitCountry (code, name, complete, profiles));
    }

    if (countries.size == 0) {
        throw new OperatingLimitError.INVALID_RULESET (
            "Operating limits ruleset must include at least one country"
        );
    }
    return countries;
}

private static ArrayList<OperatingLimitProfile> parse_profiles (
    Json.Array array,
    string country_code,
    string country_name,
    HashMap<string, ArrayList<string>> mode_groups
) throws OperatingLimitError {
    var profiles = new ArrayList<OperatingLimitProfile> ();
    var profile_ids = new HashSet<string> ();

    for (uint i = 0; i < array.get_length (); i++) {
        var object = array.get_object_element (i);
        var context = "%s profile %u".printf (country_code, i + 1);
        var id = require_string_member (object, "id", context);
        var name = require_string_member (object, "name", context);
        var hidden = object.has_member ("hidden") ? object.get_boolean_member ("hidden") : false;
        var inherits = object.has_member ("inherits") ?
            parse_string_array (require_array_member (object, "inherits", context), context) :
            new ArrayList<string> ();
        var rules = parse_rules (
            require_array_member (object, "rules", context),
            mode_groups,
            context
        );

        if (profile_ids.contains (id)) {
            throw new OperatingLimitError.INVALID_PROFILE (
                "Duplicate operating limit profile '%s' in %s".printf (id, country_code)
            );
        }
        profile_ids.add (id);

        profiles.add (new OperatingLimitProfile (
            country_code,
            country_name,
            id,
            name,
            hidden,
            inherits,
            rules
        ));
    }

    return profiles;
}

private static ArrayList<OperatingLimitRule> parse_rules (
    Json.Array array,
    HashMap<string, ArrayList<string>> mode_groups,
    string context
) throws OperatingLimitError {
    var rules = new ArrayList<OperatingLimitRule> ();

    for (uint i = 0; i < array.get_length (); i++) {
        var object = array.get_object_element (i);
        var rule_context = "%s rule %u".printf (context, i + 1);
        var band = require_string_member (object, "band", rule_context);
        if (!known_band (band)) {
            throw new OperatingLimitError.INVALID_RULE (
                "%s uses unknown band '%s'".printf (rule_context, band)
            );
        }

        var min_khz = require_double_member (object, "minKHz", rule_context);
        var max_khz = require_double_member (object, "maxKHz", rule_context);
        if (min_khz <= 0.0 || max_khz <= 0.0 || min_khz > max_khz) {
            throw new OperatingLimitError.INVALID_RULE (
                "%s has invalid frequency range %.3f-%.3f kHz".printf (
                    rule_context,
                    min_khz,
                    max_khz
                )
            );
        }

        var modes = parse_rule_modes (object, mode_groups, rule_context);
        rules.add (new OperatingLimitRule (band, min_khz, max_khz, modes));
    }

    return rules;
}

private static ArrayList<string> parse_rule_modes (
    Json.Object object,
    HashMap<string, ArrayList<string>> mode_groups,
    string context
) throws OperatingLimitError {
    var modes = new ArrayList<string> ();

    if (object.has_member ("modes")) {
        append_modes_unique (
            modes,
            parse_mode_array (require_array_member (object, "modes", context), context)
        );
    }

    if (object.has_member ("modeGroup")) {
        append_mode_group (
            modes,
            object.get_string_member ("modeGroup"),
            mode_groups,
            context
        );
    }

    if (object.has_member ("modeGroups")) {
        var groups = require_array_member (object, "modeGroups", context);
        for (uint i = 0; i < groups.get_length (); i++)
            append_mode_group (modes, groups.get_string_element (i), mode_groups, context);
    }

    if (modes.size == 0) {
        throw new OperatingLimitError.INVALID_RULE (
            "%s must include modes, modeGroup, or modeGroups".printf (context)
        );
    }

    return modes;
}

private static void append_mode_group (
    ArrayList<string> modes,
    string group_name,
    HashMap<string, ArrayList<string>> mode_groups,
    string context
) throws OperatingLimitError {
    var normalized_group = group_name.strip ();
    if (!mode_groups.has_key (normalized_group)) {
        throw new OperatingLimitError.INVALID_RULE (
            "%s references unknown mode group '%s'".printf (context, normalized_group)
        );
    }

    append_modes_unique (modes, mode_groups[normalized_group]);
}

private static ArrayList<string> parse_mode_array (
    Json.Array array,
    string context
) throws OperatingLimitError {
    var modes = new ArrayList<string> ();
    for (uint i = 0; i < array.get_length (); i++) {
        var mode = normalize_mode (array.get_string_element (i));
        if (!known_mode (mode)) {
            throw new OperatingLimitError.INVALID_RULE (
                "%s uses unknown mode '%s'".printf (context, mode)
            );
        }

        if (!modes.contains (mode))
            modes.add (mode);
    }

    if (modes.size == 0) {
        throw new OperatingLimitError.INVALID_RULE (
            "%s must include at least one mode".printf (context)
        );
    }
    return modes;
}

private static ArrayList<string> parse_string_array (
    Json.Array array,
    string context
) throws OperatingLimitError {
    var values = new ArrayList<string> ();
    for (uint i = 0; i < array.get_length (); i++) {
        var value = array.get_string_element (i).strip ();
        if (value == "") {
            throw new OperatingLimitError.INVALID_SCHEMA (
                "%s has an empty string array value".printf (context)
            );
        }
        values.add (value);
    }
    return values;
}

private static void append_modes_unique (
    ArrayList<string> target,
    ArrayList<string> source
) {
    foreach (var mode in source) {
        if (!target.contains (mode))
            target.add (mode);
    }
}

private static ArrayList<string> copy_string_list (ArrayList<string> source) {
    var copy = new ArrayList<string> ();
    foreach (var value in source)
        copy.add (value);
    return copy;
}

private static string join_strings (ArrayList<string> values, string separator) {
    var builder = new StringBuilder ();
    for (var i = 0; i < values.size; i++) {
        if (i > 0)
            builder.append (separator);
        builder.append (values[i]);
    }
    return builder.str;
}
