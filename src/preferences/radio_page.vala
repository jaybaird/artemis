/* src/preferences/radio_page.vala
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

[GtkTemplate (ui = "/com/k0vcz/artemis/ui/preferences/radio_page.ui")]
public sealed class RadioPreferencesPage : Adw.PreferencesPage {
    [GtkChild]
    private unowned Adw.ComboRow row_connection_type;

    [GtkChild]
    private unowned Adw.ComboRow row_radio_model;

    [GtkChild]
    private unowned Adw.ComboRow row_device_path;

    [GtkChild]
    private unowned Adw.ComboRow row_baud_rate;

    [GtkChild]
    private unowned Adw.ComboRow row_data_bits;

    [GtkChild]
    private unowned Adw.ComboRow row_stop_bits;

    [GtkChild]
    private unowned Adw.ComboRow row_handshake;

    [GtkChild]
    private unowned Adw.EntryRow row_network_host;

    [GtkChild]
    private unowned Adw.EntryRow row_network_port;

    [GtkChild]
    private unowned Adw.PreferencesGroup serial_settings_group;

    [GtkChild]
    private unowned Adw.PreferencesGroup network_settings_group;

    [GtkChild]
    private unowned Adw.PreferencesGroup radio_test_group;

    [GtkChild]
    private unowned Gtk.Button test_connection_button;

    [GtkChild]
    private unowned Gtk.Image connection_status_icon;

    [GtkChild]
    private unowned Gtk.Label connection_status_label;

    [GtkChild]
    private unowned Gtk.Label hamlib_version_label;

    public RadioPreferencesPage () {
        Object ();
    }

    public void setup () {
        var radio_models = RadioControl.get_radio_models ();
        var radio_model_list = new Gtk.StringList ({});
        for (var i = 0; i < radio_models.length; i++)
            radio_model_list.append (radio_models[i].display_name);
        row_radio_model.model = radio_model_list;
        row_radio_model.enable_search = true;
        row_radio_model.search_match_mode = Gtk.StringFilterMatchMode.SUBSTRING;

        row_device_path.model = get_serial_devices ();
        hamlib_version_label.label = RadioControl.hamlib_version ();

        setup_bindings ();
        setup_signals ();
        update_connection_groups_visibility ();
    }

    private void setup_bindings () {
        bind_combo_to_string_setting ("radio-device", row_device_path);

        Application.settings.bind_with_mapping (
            "radio-connection-type",
            row_connection_type,
            "selected",
            SettingsBindFlags.GET | SettingsBindFlags.SET,
            (value, variant, user_data) => {
                var connection_type = variant.get_string ();
                if (connection_type == "serial")
                    value.set_uint (1);
                else if (connection_type == "network")
                    value.set_uint (2);
                else
                    value.set_uint (0);
                return true;
            },
            (value, variant, user_data) => {
                switch (value.get_uint ()) {
                    case 1:
                        return new Variant.string ("serial");
                    case 2:
                        return new Variant.string ("network");
                    case 0:
                    default:
                        return new Variant.string ("none");
                }
            },
            null, null
        );

        Application.settings.bind_with_mapping (
            "radio-model",
            row_radio_model,
            "selected",
            SettingsBindFlags.GET | SettingsBindFlags.SET,
            (value, variant, user_data) => {
                var radio_model = variant.get_int32 ();
                var models = RadioControl.get_radio_models ();
                for (var i = 1; i < models.length; i++) {
                    if (models[i].model_id == radio_model) {
                        value.set_uint (i);
                        return true;
                    }
                }
                value.set_uint (0);
                return true;
            },
            (value, variant, user_data) => {
                var models = RadioControl.get_radio_models ();
                var idx = value.get_uint ();
                return new Variant.int32 (models[idx].model_id);
            },
            null, null
        );

        bind_baud_rate_combo ();
        bind_data_bits_combo ();
        bind_stop_bits_combo ();
        bind_handshake_combo ();

        Application.settings.bind ("radio-network-host", row_network_host, "text",
            SettingsBindFlags.DEFAULT);
        bind_network_port_entry ();
    }

    private void setup_signals () {
        row_connection_type.notify["selected"].connect (update_connection_groups_visibility);
        test_connection_button.clicked.connect (on_test_connection);
    }

    private void bind_network_port_entry () {
        sync_network_port_entry ();

        row_network_port.changed.connect (() => {
            int parsed_port;
            if (!try_parse_port (row_network_port.text, out parsed_port))
                return;

            if (Application.settings.get_int ("radio-network-port") != parsed_port)
                Application.settings.set_int ("radio-network-port", parsed_port);
        });

        Application.settings.changed["radio-network-port"].connect (() => {
            sync_network_port_entry ();
        });
    }

    private void sync_network_port_entry () {
        var current_port = Application.settings.get_int ("radio-network-port").to_string ();
        if (row_network_port.text != current_port)
            row_network_port.text = current_port;
    }

    private static bool try_parse_port (string text, out int port) {
        port = 0;
        var stripped = text.strip ();
        if (stripped.length == 0)
            return false;

        int64 parsed_port64 = 0;
        if (!int64.try_parse (stripped, out parsed_port64))
            return false;

        if (parsed_port64 < 1 || parsed_port64 > 65535)
            return false;

        port = (int)parsed_port64;
        return true;
    }

    private void bind_combo_to_string_setting (string setting_key, Adw.ComboRow combo_row) {
        var model = combo_row.model as Gtk.StringList;
        if (model == null)
            return;

        var current_value = Application.settings.get_string (setting_key).up ();
        for (uint i = 0; i < model.get_n_items (); i++) {
            if (model.get_string (i).up () == current_value) {
                combo_row.selected = i;
                break;
            }
        }

        combo_row.notify["selected"].connect (() => {
            var selected_text = model.get_string (combo_row.selected);
            if (selected_text != null)
                Application.settings.set_string (setting_key, selected_text);
        });

        Application.settings.changed[setting_key].connect (() => {
            var value = Application.settings.get_string (setting_key).up ();
            for (uint i = 0; i < model.get_n_items (); i++) {
                if (model.get_string (i).up () == value) {
                    combo_row.selected = i;
                    break;
                }
            }
        });
    }

    private static uint stop_bits_selected_to_actual (uint selected) {
        switch (selected) {
            case 1:
                return 1;
            case 2:
                return 2;
            case 0:
            default:
                return 0;
        }
    }

    private static uint stop_bits_actual_to_selected (uint stop_bits) {
        switch (stop_bits) {
            case 1:
                return 1;
            case 2:
                return 2;
            case 0:
            default:
                return 0;
        }
    }

    private static uint data_bits_selected_to_actual (uint selected) {
        switch (selected) {
            case 1:
                return 7;
            case 2:
                return 8;
            case 0:
            default:
                return 0;
        }
    }

    private static uint data_bits_actual_to_selected (uint data_bits) {
        switch (data_bits) {
            case 7:
                return 1;
            case 8:
                return 2;
            case 0:
            default:
                return 0;
        }
    }

    private static string handshake_selected_to_str (uint selected) {
        switch (selected) {
            case 1:
                return "XONXOFF";
            case 2:
                return "Hardware";
            case 0:
            default:
                return "None";
        }
    }

    private void bind_data_bits_combo () {
        var current_data_bits = Application.settings.get_int ("radio-data-bits");
        row_data_bits.selected = data_bits_actual_to_selected ((uint)current_data_bits);

        row_data_bits.notify["selected"].connect (() => {
            var data_bits = data_bits_selected_to_actual (row_data_bits.selected);
            Application.settings.set_int ("radio-data-bits", (int)data_bits);
        });

        Application.settings.changed["radio-data-bits"].connect (() => {
            var data_bits = Application.settings.get_int ("radio-data-bits");
            row_data_bits.selected = data_bits_actual_to_selected ((uint)data_bits);
        });
    }

    private void bind_handshake_combo () {
        var current_handshake = Application.settings.get_int ("radio-hardware-handshake");
        row_handshake.selected = (uint)current_handshake;

        row_handshake.notify["selected"].connect (() => {
            Application.settings.set_int ("radio-hardware-handshake",
                (int)row_handshake.selected);
        });

        Application.settings.changed["radio-hardware-handshake"].connect (() => {
            var handshake = Application.settings.get_int ("radio-hardware-handshake");
            row_handshake.selected = (uint)handshake;
        });
    }

    private void bind_stop_bits_combo () {
        var current_stop_bits = Application.settings.get_int ("radio-stop-bits");
        row_stop_bits.selected = stop_bits_actual_to_selected ((uint)current_stop_bits);

        row_stop_bits.notify["selected"].connect (() => {
            Application.settings.set_int ("radio-stop-bits",
                (int)stop_bits_selected_to_actual (row_stop_bits.selected));
        });

        Application.settings.changed["radio-stop-bits"].connect (() => {
            var stop_bits = Application.settings.get_int ("radio-stop-bits");
            row_stop_bits.selected = stop_bits_actual_to_selected ((uint)stop_bits);
        });
    }

    private void bind_baud_rate_combo () {
        var model = row_baud_rate.model as Gtk.StringList;
        if (model == null)
            return;

        var current_baud_str = Application.settings.get_int ("radio-baud-rate").to_string ();
        for (uint i = 0; i < model.get_n_items (); i++) {
            if (model.get_string (i) == current_baud_str) {
                row_baud_rate.selected = i;
                break;
            }
        }

        row_baud_rate.notify["selected"].connect (() => {
            var selected_text = model.get_string (row_baud_rate.selected);
            if (selected_text != null)
                Application.settings.set_int ("radio-baud-rate", int.parse (selected_text));
        });

        Application.settings.changed["radio-baud-rate"].connect (() => {
            var baud_str = Application.settings.get_int ("radio-baud-rate").to_string ();
            for (uint i = 0; i < model.get_n_items (); i++) {
                if (model.get_string (i) == baud_str) {
                    row_baud_rate.selected = i;
                    break;
                }
            }
        });
    }

    private void update_connection_groups_visibility () {
        var model = row_connection_type.model as Gtk.StringList;
        if (model == null)
            return;

        var selected_type = model.get_string (row_connection_type.selected);
        row_radio_model.selectable = true;

        switch (selected_type.up ()) {
            case "SERIAL/USB":
                serial_settings_group.visible = true;
                network_settings_group.visible = false;
                row_radio_model.visible = true;
                radio_test_group.visible = true;
                break;
            case "NETWORK":
                row_radio_model.visible = true;
                select_radio_model (RadioControl.netrigctl_model_id ());
                row_radio_model.selectable = false;
                serial_settings_group.visible = false;
                network_settings_group.visible = true;
                radio_test_group.visible = true;
                break;
            default:
                radio_test_group.visible = false;
                row_radio_model.visible = false;
                serial_settings_group.visible = false;
                network_settings_group.visible = false;
                break;
        }
    }

    private void on_test_connection () {
        test_connection_button.sensitive = false;
        connection_status_icon.icon_name = "content-loading-symbolic";
        connection_status_label.label = _("Testing…");
        test_radio_connection ();
    }

    private void test_radio_connection () {
        if (Application.radio_control == null || row_radio_model.selected == 0)
            return;

        var connection_type = row_connection_type.model.get_item (row_connection_type.selected) as Gtk.StringObject;
        var device_path = row_device_path.model.get_item (row_device_path.selected) as Gtk.StringObject;
        var baud_rate = row_baud_rate.model.get_item (row_baud_rate.selected) as Gtk.StringObject;
        var connection_type_text = connection_type.get_string ().down ();
        if (connection_type_text == "serial/usb")
            connection_type_text = "serial";
        else if (connection_type_text != "none")
            connection_type_text = "network";

        var radio_model = connection_type_text == "network" ?
            RadioControl.netrigctl_model_id () :
            Application.settings.get_int ("radio-model");

        var config = RadioConfiguration () {
            model_id = radio_model,
            connection_type = connection_type_text,
            device_path = device_path.get_string (),
            network_host = row_network_host.text,
            network_port = get_network_port (),
            baud_rate = int.parse (baud_rate.get_string ()),
            data_bits = data_bits_selected_to_actual (row_data_bits.selected),
            stop_bits = row_stop_bits.selected,
            handshake = row_handshake.selected
        };
        print ("""Testing radio connection with:
        \tModel ID: %d\n
        \tConnection type: %s\n
        \tDevice path: %s\n
        \tNetwork host: %s\n
        \tNetwork port: %u\n
        \tBaud rate: %u\n
        \tData bits: %u\n
        \tStop bits: %u\n
        \tHandshake: %s\n
        """.printf (
            radio_model,
            config.connection_type,
            config.device_path,
            config.network_host,
            config.network_port,
            config.baud_rate,
            config.data_bits,
            config.stop_bits,
            handshake_selected_to_str (config.handshake)
        ));

        var is_connected = Application.radio_control.connect (config);
        new Dex.Future.finally (is_connected, (result) => {
            Error connection_err = null;
            bool success = false;
            try {
                success = result.await_boolean ();
                Application.radio_control.disconnect ().disown ();
            } catch (Error err) {
                warning ("Connection failed: %s", err.message);
                connection_err = err;
            }

            Dex.Scheduler.get_default ().spawn (0, () => {
                test_connection_button.sensitive = true;
                if (success) {
                    connection_status_icon.icon_name = "network-idle-symbolic";
                    connection_status_label.label = _("Successful!");
                    connection_status_label.tooltip_text = "";
                } else {
                    connection_status_icon.icon_name = "network-offline-symbolic";
                    connection_status_label.label = _("Failed");
                    if (connection_err != null)
                        connection_status_label.tooltip_text = connection_err.message;
                }

                return null;
            }).disown ();

            return null;
        }).disown ();
    }

    private void select_radio_model (int model_id) {
        var models = RadioControl.get_radio_models ();
        for (uint i = 0; i < models.length; i++) {
            if (models[i].model_id == model_id) {
                row_radio_model.selected = i;
                return;
            }
        }
    }

    private int get_network_port () {
        int parsed_port;
        if (try_parse_port (row_network_port.text, out parsed_port))
            return parsed_port;

        return Application.settings.get_int ("radio-network-port");
    }

#if ARTEMIS_WINDOWS
    private Gtk.StringList get_serial_devices () {
        var model = new Gtk.StringList ({});
        var devices = RadioControl.get_serial_devices ();
        foreach (var device in devices)
            model.append (device);

        return model;
    }
#else
    private Gtk.StringList get_serial_devices () {
        var model = new Gtk.StringList ({});
        var devices = RadioControl.get_serial_devices ();
        foreach (var device in devices)
            model.append (device);

        return model;
    }
#endif
}
