/* preferences.vala
 *
 * Copyright 2025 Unknown
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

public sealed class PreferencesDialog : Object {
    private Adw.PreferencesDialog dialog;
    private Settings settings;

    private Adw.EntryRow row_callsign;
    private Adw.EntryRow row_location;
    private Adw.EntryRow row_spot_message;
    private Adw.SpinRow row_update_interval;
    private Adw.ComboRow row_default_band;
    private Adw.ComboRow row_default_mode;

    private Adw.ComboRow row_connection_type;
    private Adw.ComboRow row_radio_model;
    private Adw.EntryRow row_device_path;
    private Adw.ComboRow row_baud_rate;
    private Adw.EntryRow row_network_host;
    private Adw.SpinRow row_network_port;
    private Adw.PreferencesGroup serial_settings_group;
    private Adw.PreferencesGroup network_settings_group;

    private Adw.SwitchRow row_enable_logging;
    private Adw.PasswordEntryRow row_qrz_api_key;
    private Adw.SwitchRow row_highlight_unhunted;
    private Adw.ActionRow import_file_row;

    private Gtk.Button test_connection_button;
    private Gtk.Image connection_status_icon;
    private Gtk.Label connection_status_label;

    public PreferencesDialog()
    {
        var builder = new Gtk.Builder.from_resource(
            "/com/k0vcz/artemis/ui/preferences.ui");

        dialog = builder.get_object("prefs_dialog") as Adw.PreferencesDialog;

        get_widgets(builder);
        settings = new Settings("com.k0vcz.artemis");
        setup_bindings();
        setup_signals();
        update_connection_groups_visibility();
    }

    private void get_widgets(Gtk.Builder builder)
    {
        row_callsign = builder.get_object("row_callsign") as Adw.EntryRow;
        row_location = builder.get_object("row_location") as Adw.EntryRow;
        row_spot_message = builder.get_object("row_spot_message") as Adw.
            EntryRow;
        row_update_interval = builder.get_object("row_update_interval") as Adw.
            SpinRow;
        row_default_band = builder.get_object("row_default_band") as Adw.
            ComboRow;
        row_default_mode = builder.get_object("row_default_mode") as Adw.
            ComboRow;

        row_connection_type = builder.get_object("row_connection_type") as Adw.
            ComboRow;
        row_radio_model = builder.get_object("row_radio_model") as Adw.ComboRow;
        row_device_path = builder.get_object("row_device_path") as Adw.EntryRow;
        row_baud_rate = builder.get_object("row_baud_rate") as Adw.ComboRow;
        row_network_host = builder.get_object("row_network_host") as Adw.
            EntryRow;
        row_network_port = builder.get_object("row_network_port") as Adw.SpinRow
        ;
        serial_settings_group = builder.get_object("serial_settings_group") as
            Adw.PreferencesGroup;
        network_settings_group = builder.get_object("network_settings_group") as
            Adw.PreferencesGroup;

        row_enable_logging = builder.get_object("row_enable_logging") as Adw.
            SwitchRow;
        row_qrz_api_key = builder.get_object("row_qrz_api_key") as Adw.
            PasswordEntryRow;
        row_highlight_unhunted = builder.get_object("row_highlight_unhunted") as
            Adw.SwitchRow;
        import_file_row = builder.get_object("import_file_row") as Adw.ActionRow
        ;

        test_connection_button = builder.get_object("test_connection_button") as
            Gtk.Button;
        connection_status_icon = builder.get_object("connection_status_icon") as
            Gtk.Image;
        connection_status_label = builder.get_object("connection_status_label")
            as Gtk.Label;
    } /* get_widgets */

    public void present(Gtk.Window parent)
    {
        dialog.present(parent);
    }

    private void setup_bindings()
    {
        settings.bind("callsign", row_callsign, "text", SettingsBindFlags.
            DEFAULT);
        settings.bind("location", row_location, "text", SettingsBindFlags.
            DEFAULT);
        settings.bind("spot-message", row_spot_message, "text",
            SettingsBindFlags.DEFAULT);
        settings.bind("update-interval", row_update_interval, "value",
            SettingsBindFlags.DEFAULT);

        bind_combo_to_string_setting("default-band", row_default_band);
        bind_combo_to_string_setting("default-mode", row_default_mode);
        bind_combo_to_string_setting("radio-connection-type",
            row_connection_type);

        settings.bind("radio-model", row_radio_model, "selected",
            SettingsBindFlags.DEFAULT);
        settings.bind("radio-device", row_device_path, "text", SettingsBindFlags
            .DEFAULT);
        bind_baud_rate_combo();
        settings.bind("radio-network-host", row_network_host, "text",
            SettingsBindFlags.DEFAULT);
        settings.bind("radio-network-port", row_network_port, "value",
            SettingsBindFlags.DEFAULT);

        settings.bind("enable-logging", row_enable_logging, "active",
            SettingsBindFlags.DEFAULT);
        settings.bind("qrz-api-key", row_qrz_api_key, "text", SettingsBindFlags.
            DEFAULT);
        settings.bind("highlight-unhunted-parks", row_highlight_unhunted,
            "active", SettingsBindFlags.DEFAULT);
    }

    private void bind_combo_to_string_setting(string setting_key, Adw.ComboRow
        combo_row)
    {
        var model = combo_row.model as Gtk.StringList;

        if (model == null) return;

        var current_value = settings.get_string(setting_key);
        for (uint i = 0; i < model.get_n_items(); i++)
        {
            if (model.get_string(i) == current_value)
            {
                combo_row.selected = i;
                break;
            }
        }

        combo_row.notify["selected"].connect(() => {
            var selected_text = model.get_string(combo_row.selected);
            if (selected_text != null)
                settings.set_string(setting_key, selected_text.down());
        });

        settings.changed[setting_key].connect(() => {
            var value = settings.get_string(setting_key);
            for (uint i = 0; i < model.get_n_items(); i++)
            {
                if (model.get_string(i).down() == value)
                {
                    combo_row.selected = i;
                    break;
                }
            }
        });
    } /* bind_combo_to_string_setting */

    private void bind_baud_rate_combo()
    {
        var model = row_baud_rate.model as Gtk.StringList;

        if (model == null) return;

        var current_baud = settings.get_int("radio-baud-rate");
        var current_baud_str = current_baud.to_string();

        for (uint i = 0; i < model.get_n_items(); i++)
        {
            if (model.get_string(i) == current_baud_str)
            {
                row_baud_rate.selected = i;
                break;
            }
        }

        row_baud_rate.notify["selected"].connect(() => {
            var selected_text = model.get_string(row_baud_rate.selected);
            if (selected_text != null)
            {
                var baud_rate = int.parse(selected_text);
                settings.set_int("radio-baud-rate", baud_rate);
            }
        });

        settings.changed["radio-baud-rate"].connect(() => {
            var baud_rate = settings.get_int("radio-baud-rate");
            var baud_str = baud_rate.to_string();
            for (uint i = 0; i < model.get_n_items(); i++)
            {
                if (model.get_string(i) == baud_str)
                {
                    row_baud_rate.selected = i;
                    break;
                }
            }
        });
    } /* bind_baud_rate_combo */

    private void setup_signals()
    {
        row_connection_type.notify["selected"].connect(
            update_connection_groups_visibility);
        test_connection_button.clicked.connect(on_test_connection);
        import_file_row.activated.connect(on_import_file);
    }

    private void update_connection_groups_visibility()
    {
        var model = row_connection_type.model as Gtk.StringList;

        if (model == null) return;

        var selected_type = model.get_string(row_connection_type.selected);

        switch (selected_type.down())
        {
            case "serial":
            case "usb":
                serial_settings_group.visible = true;
                network_settings_group.visible = false;
                break;
            case "network":
                serial_settings_group.visible = false;
                network_settings_group.visible = true;
                break;
            default:
                serial_settings_group.visible = false;
                network_settings_group.visible = false;
                break;
        }
    }

    private void on_test_connection()
    {
        test_connection_button.sensitive = false;
        connection_status_icon.icon_name = "content-loading-symbolic";
        connection_status_label.label = _("Testing...");

        test_radio_connection.begin((obj, res) => {
            bool success = test_radio_connection.end(res);

            test_connection_button.sensitive = true;
            if (success)
            {
                connection_status_icon.icon_name = "network-idle-symbolic";
                connection_status_label.label = _("Connected");
            }
            else
            {
                connection_status_icon.icon_name = "network-offline-symbolic";
                connection_status_label.label = _("Failed");
            }
        });
    }

    private async bool test_radio_connection()
    {
        return false;
    }

    private void on_import_file()
    {
        var file_dialog = new Gtk.FileDialog();

        file_dialog.title = _("Select Logbook CSV File");

        var csv_filter = new Gtk.FileFilter();
        csv_filter.name = _("CSV Files");
        csv_filter.add_mime_type("text/csv");
        csv_filter.add_pattern("*.csv");

        var filter_list = new GLib.ListStore(typeof(Gtk.FileFilter));
        filter_list.append(csv_filter);
        file_dialog.filters = filter_list;

        file_dialog.open.begin(dialog.get_parent() as Gtk.Window, null, (obj,
                                                                         res) =>
        {
            try {
                var file = file_dialog.open.end(res);
                if (file != null)
                    import_file_row.subtitle = file.get_basename();
            } catch(Error e) {
                warning("Failed to select file: %s", e.message);
            }
        });
    }
} /* class PreferencesDialog */
