/* src/mqtt/Mqtt.vapi
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

[CCode (
    cname = "MqttStatus",
    cprefix = "MQTT_STATUS_",
    has_type_id = false,
    cheader_filename = "mqtt/mqtt_client.h"
)]
public enum MqttStatus {
    DISCONNECTED,
    CONNECTING,
    CONNECTED,
    SUBSCRIBING,
    SUBSCRIBED,
    SHUTTING_DOWN,
    FAILED
}

[CCode (cname = "MqttClient", cheader_filename = "mqtt/mqtt_client.h")]
public class MqttClient : GLib.Object {
    public MqttClient (string server_uri, string client_id);

    public bool connect () throws GLib.Error;

    public bool subscribe (string topic, int qos) throws GLib.Error;

    public void shutdown ();

    public MqttStatus status { get; }
    public string server_uri { get; construct; }
    public string client_id { get; construct; }

    public signal void message_received (string topic, GLib.Bytes payload);
    public signal void status_changed (MqttStatus status);
    public signal void mqtt_error (int code, string message);
}
