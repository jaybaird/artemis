/* src/radio_dbus_service.vala
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

[DBus (name = "com.k0vcz.Artemis.Radio")]
public interface RadioDbusInterface : Object {
    [DBus (name = "Connected")]
    public abstract bool connected { get; }

    [DBus (name = "FrequencyKHz")]
    public abstract double frequency_khz { get; }

    [DBus (name = "Mode")]
    public abstract string mode { owned get; }

    [DBus (name = "TxActive")]
    public abstract bool tx_active { get; }

    [DBus (name = "RxActive")]
    public abstract bool rx_active { get; }

    [DBus (name = "StatusChanged")]
    public signal void status_changed (
        bool connected,
        double frequency_khz,
        string mode,
        bool tx_active,
        bool rx_active
    );
}

public sealed class RadioDbusService : Object, RadioDbusInterface {
    public const string OBJECT_PATH = "/com/k0vcz/Artemis/Radio";
    public const string INTERFACE_NAME = "com.k0vcz.Artemis.Radio";

    private RadioControl radio_control;
    private RadioStatusModel status_model = new RadioStatusModel ();
    private DBusConnection? connection = null;
    private uint registration_id = 0;

    public bool connected {
        get { return status_model.connected; }
    }

    public double frequency_khz {
        get { return status_model.frequency_khz; }
    }

    public string mode {
        owned get { return status_model.mode; }
    }

    public bool tx_active {
        get { return status_model.tx_active; }
    }

    public bool rx_active {
        get { return status_model.rx_active; }
    }

    public RadioDbusService (RadioControl radio_control) {
        this.radio_control = radio_control;

        if (radio_control.is_rig_connected) {
            RadioStatusSnapshot previous;
            status_model.update_connected_status (
                radio_control.frequency,
                RadioControl.mode_string (radio_control.mode),
                false,
                out previous
            );
        }

        radio_control.radio_connected.connect (on_radio_connected);
        radio_control.radio_disconnected.connect (on_radio_disconnected);
        radio_control.radio_error.connect (on_radio_error);
        radio_control.radio_status.connect (on_radio_status);
    }

    public void export (DBusConnection connection) throws IOError {
        if (registration_id != 0)
            return;

        registration_id = connection.register_object<RadioDbusInterface> (
            OBJECT_PATH,
            this
        );
        this.connection = connection;
    }

    public void unexport () {
        if (connection == null || registration_id == 0)
            return;

        connection.unregister_object (registration_id);
        registration_id = 0;
        connection = null;
    }

    private void on_radio_connected () {
        apply_connected_status (
            radio_control.frequency,
            RadioControl.mode_string (radio_control.mode),
            false
        );
    }

    private void on_radio_disconnected () {
        apply_disconnected_status ();
    }

    private void on_radio_error (Error err) {
        apply_disconnected_status ();
    }

    private void on_radio_status (
        double frequency,
        RadioMode mode,
        bool tx_active
    ) {
        apply_connected_status (
            frequency,
            RadioControl.mode_string (mode),
            tx_active
        );
    }

    private void apply_connected_status (
        double frequency,
        string mode,
        bool tx_active
    ) {
        RadioStatusSnapshot previous;
        if (!status_model.update_connected_status (
            frequency,
            mode,
            tx_active,
            out previous
        )) {
            return;
        }

        emit_status_changed (previous);
    }

    private void apply_disconnected_status () {
        RadioStatusSnapshot previous;
        if (!status_model.update_disconnected (out previous))
            return;

        emit_status_changed (previous);
    }

    private void emit_status_changed (RadioStatusSnapshot previous) {
        var current = status_model.get_snapshot ();
        notify_changed_properties (previous, current);
        status_changed (
            current.connected,
            current.frequency_khz,
            current.mode,
            current.tx_active,
            current.rx_active
        );
    }

    private void notify_changed_properties (
        RadioStatusSnapshot previous,
        RadioStatusSnapshot current
    ) {
        var changed = new VariantDict ();

        if (previous.connected != current.connected) {
            changed.insert_value ("Connected", new Variant.boolean (current.connected));
        }
        if (previous.frequency_khz != current.frequency_khz) {
            changed.insert_value ("FrequencyKHz", new Variant.double (current.frequency_khz));
        }
        if (previous.mode != current.mode) {
            changed.insert_value ("Mode", new Variant.string (current.mode));
        }
        if (previous.tx_active != current.tx_active) {
            changed.insert_value ("TxActive", new Variant.boolean (current.tx_active));
        }
        if (previous.rx_active != current.rx_active) {
            changed.insert_value ("RxActive", new Variant.boolean (current.rx_active));
        }

        emit_properties_changed (changed.end ());
    }

    private void emit_properties_changed (Variant changed_properties) {
        if (connection == null || changed_properties.n_children () == 0)
            return;

        try {
            string[] invalidated_properties = {};
            Variant[] parameters = {
                new Variant.string (INTERFACE_NAME),
                changed_properties,
                new Variant.strv (invalidated_properties)
            };
            connection.emit_signal (
                null,
                OBJECT_PATH,
                "org.freedesktop.DBus.Properties",
                "PropertiesChanged",
                new Variant.tuple (parameters)
            );
        } catch (Error err) {
            warning ("Unable to emit radio D-Bus properties: %s", err.message);
        }
    }
}
