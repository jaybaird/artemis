/* src/mqtt/mqtt_client.h
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

#pragma once

#include <glib-object.h>

G_BEGIN_DECLS

#define ARTEMIS_TYPE_MQTT_CLIENT (mqtt_client_get_type())

G_DECLARE_FINAL_TYPE(MqttClient, mqtt_client, ARTEMIS, MQTT_CLIENT, GObject)

typedef enum {
  MQTT_STATUS_DISCONNECTED,
  MQTT_STATUS_CONNECTING,
  MQTT_STATUS_CONNECTED,
  MQTT_STATUS_SUBSCRIBING,
  MQTT_STATUS_SUBSCRIBED,
  MQTT_STATUS_SHUTTING_DOWN,
  MQTT_STATUS_FAILED
} MqttStatus;

MqttClient *
mqtt_client_new(const char *server_uri, const char *client_id);

gboolean
mqtt_client_connect(MqttClient *self, GError **error);

gboolean
mqtt_client_subscribe(MqttClient *self,
                              const char *topic,
                              int qos,
                              GError **error);

void
mqtt_client_shutdown(MqttClient *self);

MqttStatus
mqtt_client_get_status(MqttClient *self);

G_END_DECLS
