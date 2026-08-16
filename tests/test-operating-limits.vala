/* tests/test-operating-limits.vala
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

private const string TEST_RULESET = """
{
  "schemaVersion": 1,
  "frequencyUnit": "kHz",
  "modeGroups": {
    "all": ["SSB", "CW", "FT8", "FT4", "FM", "AM", "RTTY", "JT65"],
    "data": ["FT8", "FT4", "RTTY", "JT65"],
    "data-cw": ["CW", "FT8", "FT4", "RTTY", "JT65"],
    "cw": ["CW"]
  },
  "countries": [
    {
      "code": "TS",
      "name": "Testland",
      "complete": true,
      "profiles": [
        {
          "id": "BASE",
          "name": "Base",
          "hidden": true,
          "rules": [
            {"band": "20m", "minKHz": 14000.0, "maxKHz": 14100.0, "modeGroup": "data-cw"}
          ]
        },
        {
          "id": "FULL",
          "name": "Full",
          "inherits": ["BASE"],
          "rules": [
            {"band": "20m", "minKHz": 14100.0, "maxKHz": 14350.0, "modes": ["SSB", "CW"]}
          ]
        }
      ]
    }
  ]
}
""";

private OperatingLimitRuleset load_test_ruleset () {
    try {
        return OperatingLimitRuleset.from_json (TEST_RULESET);
    } catch (Error err) {
        error ("Unable to load test ruleset: %s", err.message);
    }
}

private void test_operating_limits_parse_and_resolve_inheritance () {
    var ruleset = load_test_ruleset ();
    var countries = ruleset.complete_countries ();
    assert (countries.size == 1);
    assert (countries[0].visible_profiles ().size == 1);

    try {
        var profile = ruleset.resolve_profile ("TS", "FULL");
        assert (profile.rules.size == 2);
        assert (profile.rules[0].min_khz == 14000.0);
        assert (profile.rules[1].min_khz == 14100.0);
    } catch (Error err) {
        assert_not_reached ();
    }
}

private void test_operating_limits_mode_group_expansion () {
    var ruleset = load_test_ruleset ();
    try {
        var profile = ruleset.resolve_profile ("TS", "FULL");
        assert (profile.rules[0].allows_mode ("FT8"));
        assert (profile.rules[0].allows_mode ("CW"));
        assert (!profile.rules[0].allows_mode ("SSB"));
    } catch (Error err) {
        assert_not_reached ();
    }
}

private void test_operating_limits_frequency_boundaries () {
    var ruleset = load_test_ruleset ();
    try {
        var evaluator = new OperatingLimitEvaluator (ruleset.resolve_profile ("TS", "FULL"));
        assert (evaluator.evaluate (14000.0, "FT8").allowed);
        assert (evaluator.evaluate (14100.0, "FT8").allowed);
        assert (evaluator.evaluate (14347.0, "SSB").allowed);
        assert (!evaluator.evaluate (14350.0, "SSB").allowed);
        assert (evaluator.evaluate (14350.0, "CW").allowed);
        assert (!evaluator.evaluate (14350.1, "CW").allowed);
    } catch (Error err) {
        assert_not_reached ();
    }
}

private void test_operating_limits_unknown_mode_blocks () {
    var ruleset = load_test_ruleset ();
    try {
        var evaluator = new OperatingLimitEvaluator (ruleset.resolve_profile ("TS", "FULL"));
        assert (!evaluator.evaluate (14074.0, "VARA").allowed);
    } catch (Error err) {
        assert_not_reached ();
    }
}

private void test_operating_limits_validation_errors () {
    var invalid = """
{
  "schemaVersion": 1,
  "frequencyUnit": "Hz",
  "modeGroups": {"all": ["CW"]},
  "countries": []
}
""";

    try {
        OperatingLimitRuleset.from_json (invalid);
        assert_not_reached ();
    } catch (OperatingLimitError err) {
        assert (err is OperatingLimitError.INVALID_SCHEMA);
    } catch (Error err) {
        assert_not_reached ();
    }
}

private void test_operating_limits_sort_rules_for_display () {
    var modes = new Gee.ArrayList<string> ();
    modes.add ("CW");

    var rules = new Gee.ArrayList<OperatingLimitRule> ();
    rules.add (new OperatingLimitRule ("20m", 14225.0, 14350.0, modes));
    rules.add (new OperatingLimitRule ("2m", 144100.0, 148000.0, modes));
    rules.add (new OperatingLimitRule ("80m", 3525.0, 3600.0, modes));
    rules.add (new OperatingLimitRule ("20m", 14025.0, 14150.0, modes));
    rules.add (new OperatingLimitRule ("160m", 1800.0, 2000.0, modes));

    var sorted = operating_limit_rules_sorted_for_display (rules);
    assert_cmpstr (sorted[0].band, CompareOperator.EQ, "160m");
    assert_cmpstr (sorted[1].band, CompareOperator.EQ, "80m");
    assert_cmpstr (sorted[2].band, CompareOperator.EQ, "20m");
    assert (sorted[2].min_khz == 14025.0);
    assert_cmpstr (sorted[3].band, CompareOperator.EQ, "20m");
    assert (sorted[3].min_khz == 14225.0);
    assert_cmpstr (sorted[4].band, CompareOperator.EQ, "2m");
}

private void test_operating_limits_bundled_ruleset_exposes_us_and_ca () {
    string json_text;
    try {
        try {
            FileUtils.get_contents ("../data/operating-limits.json", out json_text);
        } catch (FileError err) {
            FileUtils.get_contents ("data/operating-limits.json", out json_text);
        }

        var ruleset = OperatingLimitRuleset.from_json (json_text);
        var countries = ruleset.complete_countries ();
        assert (countries.size == 2);
        assert (ruleset.find_country ("US") != null);
        assert (ruleset.find_country ("CA") != null);
        assert (ruleset.find_country ("US").visible_profiles ().size > 0);
        assert (ruleset.find_country ("CA").visible_profiles ().size > 0);

        var us_general = new OperatingLimitEvaluator (
            ruleset.resolve_profile ("US", "US_GENERAL")
        );
        assert (us_general.evaluate (14074.0, "FT8").allowed);
        assert (!us_general.evaluate (14175.0, "SSB").allowed);
        assert (us_general.evaluate (14295.0, "SSB").allowed);
        assert (us_general.evaluate (14295.0, "USB").allowed);
        assert (us_general.evaluate (14295.0, "LSB").allowed);
        assert (us_general.evaluate (14347.0, "USB").allowed);
        assert (!us_general.evaluate (14350.0, "USB").allowed);
        assert (us_general.evaluate (14228.0, "LSB").allowed);
        assert (!us_general.evaluate (14225.0, "LSB").allowed);
    } catch (Error err) {
        error ("Unable to validate bundled operating limits: %s", err.message);
    }
}

public int main (string[] args) {
    Test.init (ref args);

    Test.add_func ("/operating-limits/parse-resolve-inheritance",
        test_operating_limits_parse_and_resolve_inheritance);
    Test.add_func ("/operating-limits/mode-group-expansion",
        test_operating_limits_mode_group_expansion);
    Test.add_func ("/operating-limits/frequency-boundaries",
        test_operating_limits_frequency_boundaries);
    Test.add_func ("/operating-limits/unknown-mode-blocks",
        test_operating_limits_unknown_mode_blocks);
    Test.add_func ("/operating-limits/validation-errors",
        test_operating_limits_validation_errors);
    Test.add_func ("/operating-limits/sort-rules-for-display",
        test_operating_limits_sort_rules_for_display);
    Test.add_func ("/operating-limits/bundled-ruleset-us-ca",
        test_operating_limits_bundled_ruleset_exposes_us_and_ca);

    return Test.run ();
}
