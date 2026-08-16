/* src/preferences/operating_limits_page.vala
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

using Gee;

private const string OPERATING_LIMIT_CUSTOM_COUNTRY_CODE = "CUSTOM";
private const string OPERATING_LIMIT_CUSTOM_PROFILE_ID = "custom";

public sealed class OperatingLimitRuleEditForm : Gtk.Box {
    public signal void changed ();

    private Gtk.StringList band_model;
    private Adw.ComboRow band_row;
    private Adw.EntryRow min_row;
    private Adw.EntryRow max_row;
    private Gee.HashMap<string, Adw.SwitchRow> mode_rows;
    private Gtk.Label validation_label;
    private bool syncing = false;

    public OperatingLimitRuleEditForm (OperatingLimitRule rule) {
        Object (
            orientation: Gtk.Orientation.VERTICAL,
            spacing: 12
        );

        margin_top = 6;
        margin_bottom = 6;

        build_rows ();
        load_rule (rule);
        connect_changes ();
        sync_validation ();
    }

    public OperatingLimitRule to_rule () throws OperatingLimitError {
        var band = current_band ();
        if (band == null || band == "") {
            throw new OperatingLimitError.INVALID_RULE (_("Choose a band"));
        }

        double min_khz;
        double max_khz;
        try {
            min_khz = parse_frequency (min_row.text, FrequencyUnit.KHZ, FrequencyUnit.KHZ);
            max_khz = parse_frequency (max_row.text, FrequencyUnit.KHZ, FrequencyUnit.KHZ);
        } catch (FrequencyError err) {
            throw new OperatingLimitError.INVALID_RULE (_("Enter valid kHz frequencies"));
        }

        if (min_khz <= 0.0 || max_khz <= 0.0 || min_khz > max_khz) {
            throw new OperatingLimitError.INVALID_RULE (_("Minimum must be less than maximum"));
        }

        return new OperatingLimitRule (band, min_khz, max_khz, selected_modes ());
    }

    public bool is_valid () {
        try {
            to_rule ();
            return true;
        } catch (OperatingLimitError err) {
            return false;
        }
    }

    public string current_band () {
        var band = band_model.get_string (band_row.selected);
        return band != null ? band : "";
    }

    private void build_rows () {
        var range_group = new Adw.PreferencesGroup ();
        append (range_group);

        band_model = new Gtk.StringList ({});
        foreach (var band in RadioConstants.BANDS) {
            if (band != "All")
                band_model.append (band);
        }

        band_row = new Adw.ComboRow ();
        band_row.title = _("Band");
        band_row.model = band_model;
        range_group.add (band_row);

        min_row = new Adw.EntryRow ();
        min_row.title = _("Minimum kHz");
        range_group.add (min_row);

        max_row = new Adw.EntryRow ();
        max_row.title = _("Maximum kHz");
        range_group.add (max_row);

        var modes_group = new Adw.PreferencesGroup ();
        modes_group.title = _("Modes");
        append (modes_group);

        mode_rows = new Gee.HashMap<string, Adw.SwitchRow> ();
        foreach (var mode in OPERATING_LIMIT_KNOWN_MODES) {
            var row = new Adw.SwitchRow ();
            row.title = mode;
            modes_group.add (row);
            mode_rows[mode] = row;
        }

        validation_label = new Gtk.Label ("");
        validation_label.halign = Gtk.Align.START;
        validation_label.wrap = true;
        validation_label.add_css_class ("error");
        validation_label.add_css_class ("caption");
        append (validation_label);
    }

    private void load_rule (OperatingLimitRule rule) {
        syncing = true;
        select_band (rule.band);
        min_row.text = format_frequency_khz (rule.min_khz);
        max_row.text = format_frequency_khz (rule.max_khz);
        select_modes (rule.modes);
        syncing = false;
    }

    private void connect_changes () {
        band_row.notify["selected"].connect (on_changed);
        min_row.notify["text"].connect (on_changed);
        max_row.notify["text"].connect (on_changed);
        foreach (var entry in mode_rows.entries)
            entry.value.notify["active"].connect (on_changed);
    }

    private void on_changed () {
        if (syncing)
            return;

        sync_validation ();
        changed ();
    }

    private void sync_validation () {
        try {
            to_rule ();
            validation_label.visible = false;
            validation_label.label = "";
        } catch (OperatingLimitError err) {
            validation_label.visible = true;
            validation_label.label = err.message;
        }
    }

    private void select_band (string band) {
        for (uint i = 0; i < band_model.get_n_items (); i++) {
            if (band_model.get_string (i) == band) {
                band_row.selected = i;
                return;
            }
        }
        band_row.selected = 0;
    }

    private void select_modes (ArrayList<string> modes) {
        foreach (var mode in OPERATING_LIMIT_KNOWN_MODES)
            mode_rows[mode].active = modes.contains (mode);
    }

    private ArrayList<string> selected_modes () throws OperatingLimitError {
        var modes = new ArrayList<string> ();
        foreach (var mode in OPERATING_LIMIT_KNOWN_MODES) {
            if (mode_rows[mode].active)
                modes.add (mode);
        }
        if (modes.size == 0)
            throw new OperatingLimitError.INVALID_RULE (_("Select at least one mode"));
        return modes;
    }
}

public sealed class OperatingLimitRuleSummaryRow : Adw.ActionRow {
    public signal void edit_requested (OperatingLimitRuleSummaryRow row);
    public signal void remove_requested (OperatingLimitRuleSummaryRow row);

    public OperatingLimitRule rule { get; private set; }

    public OperatingLimitRuleSummaryRow (OperatingLimitRule rule) {
        Object ();
        this.rule = rule;

        title = rule.range_label ();
        subtitle = rule.modes_label ();
        activatable = true;
        selectable = false;

        var band_strip = new BandStrip (rule.band);
        band_strip.valign = Gtk.Align.CENTER;
        add_prefix (band_strip);

        var edit_button = new Gtk.Button.from_icon_name ("document-edit-symbolic");
        edit_button.tooltip_text = _("Edit Range");
        edit_button.valign = Gtk.Align.CENTER;
        edit_button.add_css_class ("flat");
        add_suffix (edit_button);
        activatable_widget = edit_button;

        var remove_button = new Gtk.Button.from_icon_name ("edit-delete-symbolic");
        remove_button.tooltip_text = _("Remove Range");
        remove_button.valign = Gtk.Align.CENTER;
        remove_button.add_css_class ("flat");
        remove_button.add_css_class ("destructive-action");
        add_suffix (remove_button);

        edit_button.clicked.connect (() => {
            edit_requested (this);
        });
        remove_button.clicked.connect (() => {
            remove_requested (this);
        });
    }
}

[GtkTemplate (ui = "/com/k0vcz/artemis/ui/preferences/operating_limits_page.ui")]
public sealed class OperatingLimitsPreferencesPage : Adw.PreferencesPage {
    [GtkChild]
    private unowned Adw.SwitchRow row_spot_filter_enabled;

    [GtkChild]
    private unowned Adw.SwitchRow row_tune_warning_enabled;

    [GtkChild]
    private unowned Adw.ComboRow row_country;

    [GtkChild]
    private unowned Adw.ComboRow row_profile;

    [GtkChild]
    private unowned Adw.ActionRow custom_notice_row;

    [GtkChild]
    private unowned Adw.ButtonRow apply_template_button;

    [GtkChild]
    private unowned Adw.PreferencesGroup ranges_group;

    [GtkChild]
    private unowned Adw.ButtonRow add_rule_button;

    [GtkChild]
    private unowned Adw.ButtonRow save_button;

    private OperatingLimitRuleset? ruleset = null;
    private ArrayList<OperatingLimitCountry> countries = new ArrayList<OperatingLimitCountry> ();
    private ArrayList<OperatingLimitProfile> profiles = new ArrayList<OperatingLimitProfile> ();
    private ArrayList<OperatingLimitRule> active_rules = new ArrayList<OperatingLimitRule> ();
    private ArrayList<Adw.ExpanderRow> band_group_rows = new ArrayList<Adw.ExpanderRow> ();
    private bool syncing = false;

    public OperatingLimitsPreferencesPage () {
        Object ();
    }

    public void setup () {
        Application.settings.bind (
            "operating-limits-spot-filter-enabled",
            row_spot_filter_enabled,
            "active",
            SettingsBindFlags.DEFAULT
        );
        Application.settings.bind (
            "operating-limits-tune-warning-enabled",
            row_tune_warning_enabled,
            "active",
            SettingsBindFlags.DEFAULT
        );

        try {
            ruleset = operating_limit_ruleset ();
            populate_countries ();
            ensure_selection ();
            load_active_rules ();
        } catch (Error err) {
            set_ranges_status (_("Unable to load operating limits: %s").printf (err.message));
            row_country.sensitive = false;
            row_profile.sensitive = false;
            apply_template_button.sensitive = false;
            add_rule_button.sensitive = false;
            save_button.sensitive = false;
            save_button.visible = false;
            return;
        }

        row_country.notify["selected"].connect (() => {
            if (syncing)
                return;
            sync_country_setting ();
            populate_profiles ();
            sync_profile_setting ();
            load_selected_template_into_editor (true);
        });
        row_profile.notify["selected"].connect (() => {
            if (!syncing) {
                sync_profile_setting ();
                load_selected_template_into_editor (true);
            }
        });
        apply_template_button.activated.connect (confirm_apply_template);
        add_rule_button.activated.connect (() => {
            show_rule_dialog (null);
        });
        save_button.activated.connect (() => {
            save_active_rules ();
        });

        validate_rows (false);
    }

    private void populate_countries () throws Error {
        if (ruleset == null)
            return;

        countries = ruleset.complete_countries ();
        var model = new Gtk.StringList ({});
        foreach (var country in countries)
            model.append (country.name);
        model.append (_("Custom"));
        row_country.model = model;
    }

    private void populate_profiles () {
        profiles.clear ();
        var country = selected_country ();
        if (is_custom_country_selected ()) {
            var model = new Gtk.StringList ({_("Custom")});
            row_profile.model = model;
            row_profile.selected = 0;
            row_profile.sensitive = false;
            apply_template_button.sensitive = false;
            custom_notice_row.visible = true;
            return;
        }

        row_profile.sensitive = true;
        apply_template_button.sensitive = true;
        custom_notice_row.visible = false;

        if (country != null)
            profiles = country.visible_profiles ();

        var model = new Gtk.StringList ({});
        foreach (var profile in profiles)
            model.append (profile.name);
        row_profile.model = model;

        var selected_id = Application.settings.get_string ("operating-limits-profile-id");
        var selected = 0U;
        for (uint i = 0; i < profiles.size; i++) {
            if (profiles[(int) i].id == selected_id) {
                selected = i;
                break;
            }
        }

        row_profile.selected = selected;
    }

    private void ensure_selection () {
        syncing = true;

        var selected_country_code = Application.settings.get_string (
            "operating-limits-country-code"
        );
        var country_index = selected_country_code == OPERATING_LIMIT_CUSTOM_COUNTRY_CODE ?
            (uint) countries.size : 0U;
        for (uint i = 0; i < countries.size; i++) {
            if (countries[(int) i].code == selected_country_code) {
                country_index = i;
                break;
            }
        }
        row_country.selected = country_index;
        sync_country_setting ();

        populate_profiles ();
        if (is_custom_country_selected ()) {
            sync_profile_setting ();
        } else if (profiles.size > 0) {
            var selected_profile_id = Application.settings.get_string (
                "operating-limits-profile-id"
            );
            var profile_index = 0U;
            for (uint i = 0; i < profiles.size; i++) {
                if (profiles[(int) i].id == selected_profile_id) {
                    profile_index = i;
                    break;
                }
            }
            row_profile.selected = profile_index;
            sync_profile_setting ();
        }

        syncing = false;
    }

    private OperatingLimitCountry? selected_country () {
        if (is_custom_country_selected ())
            return null;
        if (row_country.selected >= countries.size)
            return null;
        return countries[(int) row_country.selected];
    }

    private OperatingLimitProfile? selected_profile () {
        if (is_custom_country_selected ())
            return null;
        if (row_profile.selected >= profiles.size)
            return null;
        return profiles[(int) row_profile.selected];
    }

    private bool is_custom_country_selected () {
        return row_country.selected >= countries.size;
    }

    private void sync_country_setting () {
        if (is_custom_country_selected ()) {
            if (Application.settings.get_string ("operating-limits-country-code") !=
                OPERATING_LIMIT_CUSTOM_COUNTRY_CODE) {
                Application.settings.set_string (
                    "operating-limits-country-code",
                    OPERATING_LIMIT_CUSTOM_COUNTRY_CODE
                );
            }
            return;
        }

        var country = selected_country ();
        if (country == null)
            return;

        if (Application.settings.get_string ("operating-limits-country-code") != country.code)
            Application.settings.set_string ("operating-limits-country-code", country.code);
    }

    private void sync_profile_setting () {
        if (is_custom_country_selected ()) {
            if (Application.settings.get_string ("operating-limits-profile-id") !=
                OPERATING_LIMIT_CUSTOM_PROFILE_ID) {
                Application.settings.set_string (
                    "operating-limits-profile-id",
                    OPERATING_LIMIT_CUSTOM_PROFILE_ID
                );
            }
            return;
        }

        var profile = selected_profile ();
        if (profile == null)
            return;

        if (Application.settings.get_string ("operating-limits-profile-id") != profile.id)
            Application.settings.set_string ("operating-limits-profile-id", profile.id);
    }

    private void load_active_rules () {
        if (ruleset == null)
            return;

        try {
            var custom_json = Application.settings.get_string (
                "operating-limits-custom-rules-json"
            ).strip ();
            OperatingLimitProfile? profile = null;
            if (custom_json != "")
                profile = ruleset.parse_custom_profile (custom_json);

            if (profile == null) {
                if (is_custom_country_selected ()) {
                    profile = default_custom_profile ();
                } else {
                    var country = selected_country ();
                    var selected = selected_profile ();
                    if (country != null && selected != null)
                        profile = ruleset.resolve_profile (country.code, selected.id);
                }
            }

            if (profile != null)
                set_rule_rows (profile.rules, false);
        } catch (Error err) {
            set_ranges_status (_("Unable to load saved ranges: %s").printf (err.message));
            save_button.sensitive = false;
            save_button.visible = false;
        }
    }

    private void confirm_apply_template () {
        var alert = new Adw.AlertDialog (_("Apply Operating Limit Template?"), null);
        alert.format_body (
            _("This replaces the active editable ranges with the selected %s template."),
            selected_profile () != null ? selected_profile ().name : _("license")
        );
        alert.add_response ("cancel", _("Cancel"));
        alert.add_response ("apply", _("Apply Template"));
        alert.set_response_appearance ("apply", Adw.ResponseAppearance.DESTRUCTIVE);
        alert.set_default_response ("cancel");
        alert.set_close_response ("cancel");
        alert.choose.begin (get_root (), null, (obj, res) => {
            if (alert.choose.end (res) == "apply")
                apply_selected_template ();
        });
    }

    private void apply_selected_template () {
        if (ruleset == null)
            return;

        var country = selected_country ();
        var profile = selected_profile ();
        if (country == null || profile == null)
            return;

        try {
            var resolved = ruleset.resolve_profile (country.code, profile.id);
            set_rule_rows (resolved.rules, false);
            save_profile (resolved);
            set_ranges_status (_("Template applied"));
        } catch (Error err) {
            set_ranges_status (_("Unable to apply template: %s").printf (err.message));
            save_button.sensitive = false;
            save_button.visible = false;
        }
    }

    private void load_selected_template_into_editor (bool dirty) {
        if (ruleset == null)
            return;

        var country = selected_country ();
        var profile = selected_profile ();
        if (is_custom_country_selected ()) {
            load_active_or_default_custom_profile (dirty);
            return;
        }
        if (country == null || profile == null)
            return;

        try {
            var resolved = ruleset.resolve_profile (country.code, profile.id);
            set_rule_rows (resolved.rules, dirty);
        } catch (Error err) {
            set_ranges_status (_("Unable to load template: %s").printf (err.message));
            save_button.sensitive = false;
            save_button.visible = false;
        }
    }

    private void set_rule_rows (ArrayList<OperatingLimitRule> rules, bool dirty) {
        active_rules.clear ();

        foreach (var rule in operating_limit_rules_sorted_for_display (rules)) {
            active_rules.add (rule.copy ());
        }

        rebuild_range_groups ();
        validate_rows (dirty);
    }

    private void rebuild_range_groups () {
        clear_range_display ();
        var sorted_rules = operating_limit_rules_sorted_for_display (active_rules);
        active_rules.clear ();

        var current_band = "";
        Adw.ExpanderRow? current_group = null;
        foreach (var rule in sorted_rules) {
            active_rules.add (rule);

            if (rule.band != current_band || current_group == null) {
                current_band = rule.band;
                current_group = create_band_group_row (
                    current_band,
                    count_rules_for_band (sorted_rules, current_band)
                );
                band_group_rows.add (current_group);
                ranges_group.add (current_group);
            }

            var row = new OperatingLimitRuleSummaryRow (rule);
            row.edit_requested.connect ((summary_row) => {
                show_rule_dialog (summary_row.rule);
            });
            row.remove_requested.connect ((summary_row) => {
                remove_rule (summary_row.rule);
            });
            current_group.add_row (row);
        }
    }

    private void clear_range_display () {
        foreach (var row in band_group_rows)
            ranges_group.remove (row);
        band_group_rows.clear ();
    }

    private Adw.ExpanderRow create_band_group_row (string band, int count) {
        var row = new Adw.ExpanderRow ();
        row.title = band != "" ? band : _("Unknown Band");
        row.subtitle = ngettext ("%d range", "%d ranges", count).printf (count);
        row.expanded = false;
        return row;
    }

    private int count_rules_for_band (ArrayList<OperatingLimitRule> rules, string band) {
        var count = 0;
        foreach (var rule in rules) {
            if (rule.band == band)
                count++;
        }
        return count;
    }

    private void show_rule_dialog (OperatingLimitRule? existing_rule) {
        var is_new = existing_rule == null;
        var form = new OperatingLimitRuleEditForm (
            existing_rule != null ? existing_rule : default_rule ()
        );
        var alert = new Adw.AlertDialog (
            is_new ? _("Add Operating Range") : _("Edit Operating Range"),
            null
        );
        alert.set_extra_child (form);
        alert.add_response ("cancel", _("Cancel"));
        alert.add_response ("save", is_new ? _("Add") : _("Save"));
        alert.set_response_appearance ("save", Adw.ResponseAppearance.SUGGESTED);
        alert.set_default_response ("save");
        alert.set_close_response ("cancel");
        alert.set_response_enabled ("save", form.is_valid ());

        form.changed.connect (() => {
            alert.set_response_enabled ("save", form.is_valid ());
        });

        alert.choose.begin (get_root (), null, (obj, res) => {
            if (alert.choose.end (res) != "save")
                return;

            try {
                var rule = form.to_rule ();
                if (is_new) {
                    active_rules.add (rule);
                } else {
                    replace_rule (existing_rule, rule);
                }
                rebuild_range_groups ();
                validate_rows (true);
            } catch (OperatingLimitError err) {
                set_ranges_status (err.message);
                save_button.sensitive = false;
                save_button.visible = false;
            }
        });
    }

    private void replace_rule (OperatingLimitRule old_rule, OperatingLimitRule new_rule) {
        var index = index_of_rule (old_rule);
        if (index < 0)
            return;

        active_rules.remove_at (index);
        active_rules.insert (index, new_rule);
    }

    private void remove_rule (OperatingLimitRule rule) {
        var index = index_of_rule (rule);
        if (index >= 0)
            active_rules.remove_at (index);

        rebuild_range_groups ();
        validate_rows (true);
    }

    private int index_of_rule (OperatingLimitRule rule) {
        for (var i = 0; i < active_rules.size; i++) {
            if (active_rules[i] == rule)
                return i;
        }
        return -1;
    }

    private OperatingLimitRule default_rule () {
        var modes = new ArrayList<string> ();
        foreach (var mode in RadioConstants.MODES)
            modes.add (mode);
        return new OperatingLimitRule ("20m", 14000.0, 14350.0, modes);
    }

    private OperatingLimitProfile default_custom_profile () {
        var rules = new ArrayList<OperatingLimitRule> ();
        rules.add (default_rule ());
        return new OperatingLimitProfile (
            OPERATING_LIMIT_CUSTOM_COUNTRY_CODE,
            _("Custom"),
            OPERATING_LIMIT_CUSTOM_PROFILE_ID,
            _("Custom"),
            false,
            new ArrayList<string> (),
            rules
        );
    }

    private void load_active_or_default_custom_profile (bool dirty) {
        if (ruleset == null)
            return;

        try {
            var custom_json = Application.settings.get_string (
                "operating-limits-custom-rules-json"
            ).strip ();
            if (custom_json != "") {
                set_rule_rows (ruleset.parse_custom_profile (custom_json).rules, dirty);
            } else {
                set_rule_rows (default_custom_profile ().rules, dirty);
            }
        } catch (Error err) {
            set_ranges_status (_("Unable to load saved ranges: %s").printf (err.message));
            save_button.sensitive = false;
            save_button.visible = false;
        }
    }

    private ArrayList<OperatingLimitRule>? collect_rules (out string error) {
        error = "";
        var rules = new ArrayList<OperatingLimitRule> ();
        if (active_rules.size == 0) {
            error = _("Add at least one range");
            return null;
        }

        foreach (var rule in active_rules)
            rules.add (rule.copy ());

        return rules;
    }

    private bool validate_rows (bool dirty) {
        string error;
        var rules = collect_rules (out error);
        if (rules == null) {
            set_ranges_status (error);
            save_button.sensitive = false;
            save_button.visible = false;
            return false;
        }

        set_ranges_status (dirty ? _("Unsaved changes") : "");
        save_button.sensitive = dirty;
        save_button.visible = dirty;
        return true;
    }

    private void save_active_rules () {
        string error;
        var rules = collect_rules (out error);
        if (rules == null) {
            set_ranges_status (error);
            save_button.sensitive = false;
            save_button.visible = false;
            return;
        }

        var country = selected_country ();
        var template = selected_profile ();
        var sorted_rules = operating_limit_rules_sorted_for_display (rules);
        var is_custom = is_custom_country_selected ();
        var profile_country_code = is_custom ? OPERATING_LIMIT_CUSTOM_COUNTRY_CODE :
            country != null ? country.code : "";
        var profile_country_name = is_custom ? _("Custom") :
            country != null ? country.name : "";
        var profile_id = is_custom ? OPERATING_LIMIT_CUSTOM_PROFILE_ID :
            template != null ? template.id : OPERATING_LIMIT_CUSTOM_PROFILE_ID;
        var profile_name = is_custom ? _("Custom") :
            template != null ? template.name : _("Custom");
        var profile = new OperatingLimitProfile (
            profile_country_code,
            profile_country_name,
            profile_id,
            profile_name,
            false,
            new ArrayList<string> (),
            sorted_rules
        );

        save_profile (profile);
        set_rule_rows (sorted_rules, false);
    }

    private void set_ranges_status (string status) {
        ranges_group.description = status;
    }

    private void save_profile (OperatingLimitProfile profile) {
        var sorted_profile = profile.with_rules (
            operating_limit_rules_sorted_for_display (profile.rules)
        );

        if (profile.country_code != "")
            Application.settings.set_string ("operating-limits-country-code", profile.country_code);
        if (profile.id != "")
            Application.settings.set_string ("operating-limits-profile-id", profile.id);
        Application.settings.set_string (
            "operating-limits-custom-rules-json",
            sorted_profile.to_json_string ()
        );
    }
}
