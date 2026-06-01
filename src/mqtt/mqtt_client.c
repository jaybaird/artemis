/* src/mqtt/mqtt_client.c
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

#include "mqtt_client.h"

#include <MQTTAsync.h>
#include <gio/gio.h>

struct _MqttClient {
  GObject parent_instance;

  char *server_uri;
  char *client_id;
  MQTTAsync client;
  GMainContext *main_context;
  GMutex mutex;
  MqttStatus status;
  gboolean shutdown_requested;
};

enum {
  PROP_0,
  PROP_SERVER_URI,
  PROP_CLIENT_ID,
  PROP_STATUS,
  N_PROPS
};

enum {
  SIGNAL_MESSAGE_RECEIVED,
  SIGNAL_STATUS_CHANGED,
  SIGNAL_MQTT_ERROR,
  N_SIGNALS
};

static GParamSpec *properties[N_PROPS];
static guint signals[N_SIGNALS];

G_DEFINE_FINAL_TYPE(MqttClient, mqtt_client, G_TYPE_OBJECT)

typedef struct {
  MqttClient *client;
  MqttStatus status;
} StatusEvent;

typedef struct {
  MqttClient *client;
  char *message;
  int code;
} ErrorEvent;

typedef struct {
  MqttClient *client;
  char *topic;
  GBytes *payload;
} MessageEvent;

static gboolean
emit_status_on_main(gpointer user_data)
{
  StatusEvent *event = user_data;

  g_object_notify_by_pspec(G_OBJECT(event->client), properties[PROP_STATUS]);
  g_signal_emit(event->client, signals[SIGNAL_STATUS_CHANGED], 0, event->status);
  g_object_unref(event->client);
  g_free(event);

  return G_SOURCE_REMOVE;
}

static gboolean
emit_error_on_main(gpointer user_data)
{
  ErrorEvent *event = user_data;

  g_signal_emit(event->client, signals[SIGNAL_MQTT_ERROR], 0, event->code, event->message);
  g_object_unref(event->client);
  g_free(event->message);
  g_free(event);

  return G_SOURCE_REMOVE;
}

static gboolean
emit_message_on_main(gpointer user_data)
{
  MessageEvent *event = user_data;

  g_signal_emit(event->client, signals[SIGNAL_MESSAGE_RECEIVED], 0, event->topic, event->payload);
  g_object_unref(event->client);
  g_free(event->topic);
  g_bytes_unref(event->payload);
  g_free(event);

  return G_SOURCE_REMOVE;
}

static void
invoke_on_main(MqttClient *self, GSourceFunc func, gpointer data)
{
  g_main_context_invoke(self->main_context, func, data);
}

static void
set_status(MqttClient *self, MqttStatus status)
{
  gboolean changed = FALSE;

  g_mutex_lock(&self->mutex);
  if (self->status != status) {
    self->status = status;
    changed = TRUE;
  }
  g_mutex_unlock(&self->mutex);

  if (!changed) {
    return;
  }

  StatusEvent *event = g_new0(StatusEvent, 1);
  event->client = g_object_ref(self);
  event->status = status;
  invoke_on_main(self, emit_status_on_main, event);
}

static void
emit_mqtt_error(MqttClient *self, int code, const char *message)
{
  ErrorEvent *event = g_new0(ErrorEvent, 1);
  event->client = g_object_ref(self);
  event->code = code;
  event->message = g_strdup(message != NULL ? message : "MQTT operation failed");
  invoke_on_main(self, emit_error_on_main, event);
}

static void
on_connect_success(void *context, MQTTAsync_successData *response)
{
  MqttClient *self = ARTEMIS_MQTT_CLIENT(context);
  (void)response;

  set_status(self, MQTT_STATUS_CONNECTED);
  g_object_unref(self);
}

static void
on_connect_failure(void *context, MQTTAsync_failureData *response)
{
  MqttClient *self = ARTEMIS_MQTT_CLIENT(context);

  set_status(self, MQTT_STATUS_FAILED);
  emit_mqtt_error(
    self,
    response != NULL ? response->code : MQTTASYNC_FAILURE,
    response != NULL ? response->message : "MQTT connection failed"
  );
  g_object_unref(self);
}

static void
on_subscribe_success(void *context, MQTTAsync_successData *response)
{
  MqttClient *self = ARTEMIS_MQTT_CLIENT(context);
  (void)response;

  set_status(self, MQTT_STATUS_SUBSCRIBED);
  g_object_unref(self);
}

static void
on_subscribe_failure(void *context, MQTTAsync_failureData *response)
{
  MqttClient *self = ARTEMIS_MQTT_CLIENT(context);

  set_status(self, MQTT_STATUS_FAILED);
  emit_mqtt_error(
    self,
    response != NULL ? response->code : MQTTASYNC_FAILURE,
    response != NULL ? response->message : "MQTT subscribe failed"
  );
  g_object_unref(self);
}

static void
on_disconnect_complete(void *context, MQTTAsync_successData *response)
{
  MqttClient *self = ARTEMIS_MQTT_CLIENT(context);
  (void)response;

  set_status(self, MQTT_STATUS_DISCONNECTED);
  g_object_unref(self);
}

static void
on_disconnect_failure(void *context, MQTTAsync_failureData *response)
{
  MqttClient *self = ARTEMIS_MQTT_CLIENT(context);

  set_status(self, MQTT_STATUS_DISCONNECTED);
  emit_mqtt_error(
    self,
    response != NULL ? response->code : MQTTASYNC_FAILURE,
    response != NULL ? response->message : "MQTT disconnect failed"
  );
  g_object_unref(self);
}

static void
on_connection_lost(void *context, char *cause)
{
  MqttClient *self = ARTEMIS_MQTT_CLIENT(context);

  g_mutex_lock(&self->mutex);
  gboolean shutting_down = self->shutdown_requested;
  g_mutex_unlock(&self->mutex);

  if (shutting_down) {
    set_status(self, MQTT_STATUS_DISCONNECTED);
    return;
  }

  set_status(self, MQTT_STATUS_DISCONNECTED);
  emit_mqtt_error(self, MQTTASYNC_FAILURE, cause != NULL ? cause : "MQTT connection lost");
}

static int
on_message_arrived(void *context, char *topic_name, int topic_len, MQTTAsync_message *message)
{
  MqttClient *self = ARTEMIS_MQTT_CLIENT(context);

  if (message == NULL) {
    return 1;
  }

  MessageEvent *event = g_new0(MessageEvent, 1);
  event->client = g_object_ref(self);
  event->topic = topic_len > 0
    ? g_strndup(topic_name, topic_len)
    : g_strdup(topic_name != NULL ? topic_name : "");
  event->payload = g_bytes_new(message->payload, message->payloadlen);

  invoke_on_main(self, emit_message_on_main, event);

  MQTTAsync_freeMessage(&message);
  MQTTAsync_free(topic_name);

  return 1;
}

static void
mqtt_client_get_property(GObject *object, guint prop_id, GValue *value, GParamSpec *pspec)
{
  MqttClient *self = ARTEMIS_MQTT_CLIENT(object);

  switch (prop_id) {
    case PROP_SERVER_URI:
      g_value_set_string(value, self->server_uri);
      break;
    case PROP_CLIENT_ID:
      g_value_set_string(value, self->client_id);
      break;
    case PROP_STATUS:
      g_value_set_enum(value, mqtt_client_get_status(self));
      break;
    default:
      G_OBJECT_WARN_INVALID_PROPERTY_ID(object, prop_id, pspec);
  }
}

static void
mqtt_client_set_property(GObject *object, guint prop_id, const GValue *value, GParamSpec *pspec)
{
  MqttClient *self = ARTEMIS_MQTT_CLIENT(object);

  switch (prop_id) {
    case PROP_SERVER_URI:
      self->server_uri = g_value_dup_string(value);
      break;
    case PROP_CLIENT_ID:
      self->client_id = g_value_dup_string(value);
      break;
    default:
      G_OBJECT_WARN_INVALID_PROPERTY_ID(object, prop_id, pspec);
  }
}

static void
mqtt_client_constructed(GObject *object)
{
  MqttClient *self = ARTEMIS_MQTT_CLIENT(object);
  int rc;

  G_OBJECT_CLASS(mqtt_client_parent_class)->constructed(object);

  rc = MQTTAsync_create(
    &self->client,
    self->server_uri,
    self->client_id,
    MQTTCLIENT_PERSISTENCE_NONE,
    NULL
  );

  if (rc != MQTTASYNC_SUCCESS) {
    set_status(self, MQTT_STATUS_FAILED);
    emit_mqtt_error(self, rc, "Unable to create MQTT client");
    return;
  }

  rc = MQTTAsync_setCallbacks(
    self->client,
    self,
    on_connection_lost,
    on_message_arrived,
    NULL
  );

  if (rc != MQTTASYNC_SUCCESS) {
    set_status(self, MQTT_STATUS_FAILED);
    emit_mqtt_error(self, rc, "Unable to configure MQTT callbacks");
  }
}

static void
mqtt_client_dispose(GObject *object)
{
  MqttClient *self = ARTEMIS_MQTT_CLIENT(object);

  mqtt_client_shutdown(self);

  G_OBJECT_CLASS(mqtt_client_parent_class)->dispose(object);
}

static void
mqtt_client_finalize(GObject *object)
{
  MqttClient *self = ARTEMIS_MQTT_CLIENT(object);

  if (self->client != NULL) {
    MQTTAsync_destroy(&self->client);
  }

  g_clear_pointer(&self->main_context, g_main_context_unref);
  g_clear_pointer(&self->server_uri, g_free);
  g_clear_pointer(&self->client_id, g_free);
  g_mutex_clear(&self->mutex);

  G_OBJECT_CLASS(mqtt_client_parent_class)->finalize(object);
}

static void
mqtt_client_class_init(MqttClientClass *klass)
{
  GObjectClass *object_class = G_OBJECT_CLASS(klass);

  object_class->get_property = mqtt_client_get_property;
  object_class->set_property = mqtt_client_set_property;
  object_class->constructed = mqtt_client_constructed;
  object_class->dispose = mqtt_client_dispose;
  object_class->finalize = mqtt_client_finalize;

  properties[PROP_SERVER_URI] = g_param_spec_string(
    "server-uri",
    "Server URI",
    "MQTT server URI",
    NULL,
    G_PARAM_READWRITE | G_PARAM_CONSTRUCT_ONLY | G_PARAM_STATIC_STRINGS
  );

  properties[PROP_CLIENT_ID] = g_param_spec_string(
    "client-id",
    "Client ID",
    "MQTT client identifier",
    NULL,
    G_PARAM_READWRITE | G_PARAM_CONSTRUCT_ONLY | G_PARAM_STATIC_STRINGS
  );

  properties[PROP_STATUS] = g_param_spec_enum(
    "status",
    "Status",
    "MQTT connection status",
    g_enum_register_static(
      "MqttStatus",
      (const GEnumValue[]) {
        { MQTT_STATUS_DISCONNECTED, "MQTT_STATUS_DISCONNECTED", "disconnected" },
        { MQTT_STATUS_CONNECTING, "MQTT_STATUS_CONNECTING", "connecting" },
        { MQTT_STATUS_CONNECTED, "MQTT_STATUS_CONNECTED", "connected" },
        { MQTT_STATUS_SUBSCRIBING, "MQTT_STATUS_SUBSCRIBING", "subscribing" },
        { MQTT_STATUS_SUBSCRIBED, "MQTT_STATUS_SUBSCRIBED", "subscribed" },
        { MQTT_STATUS_SHUTTING_DOWN, "MQTT_STATUS_SHUTTING_DOWN", "shutting-down" },
        { MQTT_STATUS_FAILED, "MQTT_STATUS_FAILED", "failed" },
        { 0, NULL, NULL }
      }
    ),
    MQTT_STATUS_DISCONNECTED,
    G_PARAM_READABLE | G_PARAM_STATIC_STRINGS
  );

  g_object_class_install_properties(object_class, N_PROPS, properties);

  signals[SIGNAL_MESSAGE_RECEIVED] = g_signal_new(
    "message-received",
    G_TYPE_FROM_CLASS(klass),
    G_SIGNAL_RUN_LAST,
    0,
    NULL,
    NULL,
    NULL,
    G_TYPE_NONE,
    2,
    G_TYPE_STRING,
    G_TYPE_BYTES
  );

  signals[SIGNAL_STATUS_CHANGED] = g_signal_new(
    "status-changed",
    G_TYPE_FROM_CLASS(klass),
    G_SIGNAL_RUN_LAST,
    0,
    NULL,
    NULL,
    NULL,
    G_TYPE_NONE,
    1,
    properties[PROP_STATUS]->value_type
  );

  signals[SIGNAL_MQTT_ERROR] = g_signal_new(
    "mqtt-error",
    G_TYPE_FROM_CLASS(klass),
    G_SIGNAL_RUN_LAST,
    0,
    NULL,
    NULL,
    NULL,
    G_TYPE_NONE,
    2,
    G_TYPE_INT,
    G_TYPE_STRING
  );
}

static void
mqtt_client_init(MqttClient *self)
{
  self->main_context = g_main_context_ref_thread_default();
  self->status = MQTT_STATUS_DISCONNECTED;
  g_mutex_init(&self->mutex);
}

MqttClient *
mqtt_client_new(const char *server_uri, const char *client_id)
{
  return g_object_new(
    ARTEMIS_TYPE_MQTT_CLIENT,
    "server-uri", server_uri,
    "client-id", client_id,
    NULL
  );
}

gboolean
mqtt_client_connect(MqttClient *self, GError **error)
{
  g_return_val_if_fail(ARTEMIS_IS_MQTT_CLIENT(self), FALSE);

  MQTTAsync_connectOptions options = MQTTAsync_connectOptions_initializer;
  options.keepAliveInterval = 20;
  options.cleansession = 1;
  options.context = g_object_ref(self);
  options.onSuccess = on_connect_success;
  options.onFailure = on_connect_failure;

  set_status(self, MQTT_STATUS_CONNECTING);

  int rc = MQTTAsync_connect(self->client, &options);
  if (rc != MQTTASYNC_SUCCESS) {
    g_object_unref(self);
    set_status(self, MQTT_STATUS_FAILED);
    g_set_error(error, G_IO_ERROR, G_IO_ERROR_FAILED, "MQTT connect request failed: %d", rc);
    return FALSE;
  }

  return TRUE;
}

gboolean
mqtt_client_subscribe(MqttClient *self, const char *topic, int qos, GError **error)
{
  g_return_val_if_fail(ARTEMIS_IS_MQTT_CLIENT(self), FALSE);
  g_return_val_if_fail(topic != NULL, FALSE);

  MQTTAsync_responseOptions options = MQTTAsync_responseOptions_initializer;
  options.context = g_object_ref(self);
  options.onSuccess = on_subscribe_success;
  options.onFailure = on_subscribe_failure;

  set_status(self, MQTT_STATUS_SUBSCRIBING);

  int rc = MQTTAsync_subscribe(self->client, topic, qos, &options);
  if (rc != MQTTASYNC_SUCCESS) {
    g_object_unref(self);
    set_status(self, MQTT_STATUS_FAILED);
    g_set_error(error, G_IO_ERROR, G_IO_ERROR_FAILED, "MQTT subscribe request failed: %d", rc);
    return FALSE;
  }

  return TRUE;
}

void
mqtt_client_shutdown(MqttClient *self)
{
  g_return_if_fail(ARTEMIS_IS_MQTT_CLIENT(self));

  g_mutex_lock(&self->mutex);
  if (self->shutdown_requested) {
    g_mutex_unlock(&self->mutex);
    return;
  }
  self->shutdown_requested = TRUE;
  g_mutex_unlock(&self->mutex);

  if (self->client == NULL) {
    set_status(self, MQTT_STATUS_DISCONNECTED);
    return;
  }

  set_status(self, MQTT_STATUS_SHUTTING_DOWN);
  MQTTAsync_setCallbacks(self->client, NULL, NULL, NULL, NULL);

  if (!MQTTAsync_isConnected(self->client)) {
    set_status(self, MQTT_STATUS_DISCONNECTED);
    return;
  }

  MQTTAsync_disconnectOptions options = MQTTAsync_disconnectOptions_initializer;
  options.timeout = 1000;
  options.context = g_object_ref(self);
  options.onSuccess = on_disconnect_complete;
  options.onFailure = on_disconnect_failure;

  int rc = MQTTAsync_disconnect(self->client, &options);
  if (rc != MQTTASYNC_SUCCESS) {
    g_object_unref(self);
    set_status(self, MQTT_STATUS_DISCONNECTED);
  }
}

MqttStatus
mqtt_client_get_status(MqttClient *self)
{
  g_return_val_if_fail(ARTEMIS_IS_MQTT_CLIENT(self), MQTT_STATUS_FAILED);

  g_mutex_lock(&self->mutex);
  MqttStatus status = self->status;
  g_mutex_unlock(&self->mutex);

  return status;
}
