#include "radio_control.h"

#include <glib.h>
#include <glib/gi18n.h>
#include <libdex.h>
#include <hamlib/rig.h>
#include <sched.h>
#include <stdint.h>
#include <sys/types.h>
#include <unistd.h>

#ifdef ARTEMIS_UNIX
#include <gudev/gudev.h>
#endif
#ifdef ARTEMIS_WINDOWS
#include <windows.h>
#include <devguid.h>
#include <regstr.h>
#include <setupapi.h>
#endif

static RadioModel *radio_models_cache = NULL;
static gint radio_models_count = 0;
static gsize radio_models_once = 0;

#ifdef ARTEMIS_UNIX
static GPtrArray *serial_devices_unix_cache = NULL;

const gchar * const *
radio_control_get_serial_devices_unix(gint *count)
{
  if (serial_devices_unix_cache == NULL) {
    serial_devices_unix_cache = g_ptr_array_new_with_free_func(g_free);
  } else {
    g_ptr_array_set_size(serial_devices_unix_cache, 0);
  }

  const gchar *subsystems[] = { "tty", NULL };
  GUdevClient *client = g_udev_client_new(subsystems);
  GList *devices = g_udev_client_query_by_subsystem(client, "tty");

  for (GList *iter = devices; iter != NULL; iter = iter->next) {
    GUdevDevice *device = G_UDEV_DEVICE(iter->data);
    const gchar *path = g_udev_device_get_device_file(device);
    if (path != NULL && *path != '\0') {
      g_ptr_array_add(serial_devices_unix_cache, g_strdup(path));
    }
  }

  g_list_free_full(devices, g_object_unref);
  g_object_unref(client);

  g_ptr_array_sort(serial_devices_unix_cache, (GCompareFunc)g_strcmp0);

  if (count != NULL) {
    *count = (gint)serial_devices_unix_cache->len;
  }

  return (const gchar * const *)serial_devices_unix_cache->pdata;
}
#endif

#ifdef ARTEMIS_WINDOWS
static GPtrArray *serial_devices_windows_cache = NULL;

static gboolean
is_com_port_name(const gchar *name)
{
  return name != NULL && g_ascii_strncasecmp(name, "COM", 3) == 0;
}

const gchar * const *
radio_control_get_serial_devices_windows(gint *count)
{
  if (serial_devices_windows_cache == NULL) {
    serial_devices_windows_cache = g_ptr_array_new_with_free_func(g_free);
  } else {
    g_ptr_array_set_size(serial_devices_windows_cache, 0);
  }

  HDEVINFO devs = SetupDiGetClassDevsA(&GUID_DEVCLASS_PORTS, NULL, NULL, DIGCF_PRESENT);
  if (devs == INVALID_HANDLE_VALUE) {
    if (count != NULL) {
      *count = 0;
    }
    return (const gchar * const *)serial_devices_windows_cache->pdata;
  }

  SP_DEVINFO_DATA dev_info = {0};
  dev_info.cbSize = sizeof(dev_info);

  for (DWORD index = 0; SetupDiEnumDeviceInfo(devs, index, &dev_info); index++) {
    HKEY key = SetupDiOpenDevRegKey(devs, &dev_info, DICS_FLAG_GLOBAL, 0, DIREG_DEV, KEY_READ);
    if (key == INVALID_HANDLE_VALUE) {
      continue;
    }

    gchar port_name[64] = {0};
    DWORD value_size = sizeof(port_name);
    DWORD type = 0;
    LSTATUS status = RegQueryValueExA(
      key,
      "PortName",
      NULL,
      &type,
      (LPBYTE)port_name,
      &value_size
    );
    RegCloseKey(key);

    if (status == ERROR_SUCCESS && type == REG_SZ && is_com_port_name(port_name)) {
      gboolean exists = FALSE;
      for (guint i = 0; i < serial_devices_windows_cache->len; i++) {
        const gchar *existing = g_ptr_array_index(serial_devices_windows_cache, i);
        if (g_ascii_strcasecmp(existing, port_name) == 0) {
          exists = TRUE;
          break;
        }
      }
      if (!exists) {
        g_ptr_array_add(serial_devices_windows_cache, g_strdup(port_name));
      }
    }
  }

  SetupDiDestroyDeviceInfoList(devs);

  g_ptr_array_sort(serial_devices_windows_cache, (GCompareFunc)g_strcmp0);

  if (count != NULL) {
    *count = (gint)serial_devices_windows_cache->len;
  }

  return (const gchar * const *)serial_devices_windows_cache->pdata;
}
#endif

static int 
collect_radio(rig_model_t rig_model, rig_ptr_t data) {
  GArray *rigs = (GArray *)data;
  RadioModel m = {0};
  
#ifdef RIG_MODEL_DUMMY_NOVFO
  if (rig_model == RIG_MODEL_DUMMY_NOVFO) return 1;
#endif

  if (rig_model == RIG_MODEL_DUMMY) {
    m.display_name = _("None");
  } else {
    const char *mfg = rig_get_caps_cptr(rig_model, RIG_CAPS_MFG_NAME_CPTR);
    const char *model = rig_get_caps_cptr (rig_model, RIG_CAPS_MODEL_NAME_CPTR);
    m.display_name = g_strdup_printf("%s%s%s", mfg, (*mfg && *model) ? " - " : "", model);
  }

  m.model_id = rig_model;
  m.port_type = RADIO_PORT_NONE;
  switch (rig_get_caps_int(rig_model, RIG_CAPS_PORT_TYPE)) {
    case RIG_PORT_SERIAL:
      m.port_type = RADIO_PORT_SERIAL;
      break;
    case RIG_PORT_NETWORK:
      m.port_type = RADIO_PORT_NETWORK;
      break;
    case RIG_PORT_USB:
      m.port_type = RADIO_PORT_USB;
      break;
    default: break;
  }

  g_array_append_val(rigs, m);
  return 1;
}

const gchar * const *
radio_control_get_serial_devices(gint *count)
{
#ifdef ARTEMIS_WINDOWS
  return radio_control_get_serial_devices_windows(count);
#else
  return radio_control_get_serial_devices_unix(count);
#endif
}

static gint
radio_model_cmp(gconstpointer a, gconstpointer b) {
  const RadioModel *ra = a;
  const RadioModel *rb = b;

  return g_ascii_strcasecmp(ra->display_name, rb->display_name);
}

const RadioModel* 
radio_control_get_radio_models(gint *count) {
  if (g_once_init_enter(&radio_models_once)) {
    GArray *rigs = g_array_new(FALSE, FALSE, sizeof(RadioModel));
    rig_load_all_backends();
    rig_list_foreach_model(collect_radio, rigs);

    g_array_sort(rigs, radio_model_cmp);
    radio_models_count = rigs->len;
    radio_models_cache = (RadioModel *)g_array_free(rigs, FALSE);
    printf("Loaded %d rig models for hamlib version %s\n", radio_models_count, rig_version());

    g_once_init_leave(&radio_models_once, 1);
  }

  if (count) *count = radio_models_count;
  return radio_models_cache;
}

static enum RadioMode
map_hamlib_mode(rmode_t mode)
{
  switch (mode)
  {
    case RIG_MODE_AM:
    case RIG_MODE_SAM:
    case RIG_MODE_AMS:
    case RIG_MODE_DSB:
      return RADIO_MODE_AM;

    case RIG_MODE_CW:
      return RADIO_MODE_CW;

    case RIG_MODE_CWR:
      return RADIO_MODE_CW_R;

    case RIG_MODE_USB:
    case RIG_MODE_ECSSUSB:
    case RIG_MODE_SAH:
    case RIG_MODE_FAX:
      return RADIO_MODE_USB;

    case RIG_MODE_LSB:
    case RIG_MODE_ECSSLSB:
    case RIG_MODE_SAL:
      return RADIO_MODE_LSB;

    case RIG_MODE_PKTLSB:
      return RADIO_MODE_DIGITAL_L;

    case RIG_MODE_PKTUSB:
      return RADIO_MODE_DIGITAL_U;

    case RIG_MODE_FM:
    case RIG_MODE_WFM:
      return RADIO_MODE_FM;

    case RIG_MODE_PKTFM:
      return RADIO_MODE_DIGITAL_FM;

    default:
      return RADIO_MODE_UNKNOWN;
  }
}

static rmode_t
map_artemis_mode(enum RadioMode mode)
{
  switch (mode)
  {
    case RADIO_MODE_AM: return RIG_MODE_AM;
    case RADIO_MODE_CW: return RIG_MODE_CW;
    case RADIO_MODE_CW_R: return RIG_MODE_CWR;
    case RADIO_MODE_USB: return RIG_MODE_USB;
    case RADIO_MODE_LSB: return RIG_MODE_LSB;
    case RADIO_MODE_DIGITAL_L: return RIG_MODE_PKTLSB;
    case RADIO_MODE_DIGITAL_U: return RIG_MODE_PKTUSB;
    case RADIO_MODE_FM: return RIG_MODE_FM;
    case RADIO_MODE_DIGITAL_FM: return RIG_MODE_PKTFM;
    default: break;
  }
  return RIG_MODE_USB;
}

static gboolean
try_set_rig_conf(RIG        *rig,
                  const char *key,
                  const char *value,
                  gboolean    required,
                  GError    **error)
{
  token_t token;
  int rc;

  g_return_val_if_fail(rig != NULL, FALSE);
  g_return_val_if_fail(key != NULL, FALSE);
  g_return_val_if_fail(value != NULL, FALSE);

  token = rig_token_lookup(rig, key);

  if (token == 0) {
    if (required) {
      g_set_error(error,
                  G_IO_ERROR,
                  G_IO_ERROR_NOT_SUPPORTED,
                  "Hamlib backend does not support config key '%s'",
                  key);
      return FALSE;
    }

    g_debug("[RadioControl] Optional rig config unsupported: %s=%s", key, value);
    return TRUE;
  }

#ifdef HAVE_HAMLIB_SET_CONF2
  rc = rig_set_conf2(rig, token, value, strlen(value));
#else
  rc = rig_set_conf(rig, token, value);
#endif

  if (rc != RIG_OK) {
    if (required) {
      g_set_error(error,
                  G_IO_ERROR,
                  G_IO_ERROR_FAILED,
                  "Failed to set rig config %s=%s: %s",
                  key, value, rigerror(rc));
      return FALSE;
    }

    g_warning("[RadioControl] Optional rig config rejected: %s=%s (%s)",
              key, value, rigerror(rc));
    return TRUE;
  }

  g_debug("[RadioControl] rig_set_conf ok: %s=%s", key, value);
  return TRUE;
}

static DexFuture *
watcher_iteration(DexFuture *future, gpointer user_data);

static DexFuture *
watcher_worker(void *user_data);

struct _RadioControl {
  GObject parent_instance;

  RIG   *rig;

  guint poll_interval_ms;

  DexCancellable  *canceled;
  DexFuture       *watcher;

  gboolean        is_connected;
  float           frequency_khz;
  enum RadioMode  mode;

  gulong    settings_changed_handler;

  DexScheduler *scheduler;
};
/*
typedef struct {
  gint model_id;
  gchar *connection_type;
  gchar *device_path;
  gchar *network_host;
  gint network_port;
  gint baud_rate;
} RadioConfiguration;
*/
void
radio_configuration_destroy(RadioConfiguration *config)
{
  if (config) {
    g_free(config->connection_type);
    g_free(config->device_path);
    g_free(config->network_host);
  }
}

void
radio_configuration_copy(RadioConfiguration *config, RadioConfiguration *new_config)
{
  new_config->model_id = config->model_id;
  new_config->connection_type = g_strdup(config->connection_type);
  new_config->device_path = g_strdup(config->device_path);
  new_config->network_host = g_strdup(config->network_host);
  new_config->network_port = config->network_port;
  new_config->baud_rate = config->baud_rate;
  new_config->data_bits = config->data_bits;
  new_config->stop_bits = config->stop_bits;
  new_config->handshake = config->handshake;
}

G_DEFINE_FINAL_TYPE(RadioControl, radio_control, G_TYPE_OBJECT);

static guint signals[N_RIG_SIGNALS];

static void
radio_control_dispose(GObject *object)
{
  RadioControl *self = ARTEMIS_RADIO_CONTROL(object);

  if (self->rig != NULL)
  {
    g_autoptr (GError) error = NULL;
    DexFuture *disconnect = radio_control_disconnect_async(self);
    if (!dex_await_boolean(disconnect, &error))
    {
      g_error("[RadioControl] Dispose received an error while disconnecting: %s", error->message);
      return;
    }
  }

  g_debug("[RadioControl] shutting down watcher worker...");
  dex_cancellable_cancel(self->canceled);

  g_autoptr (GError) error = NULL;
  dex_await_boolean(self->watcher, &error);
  
  g_debug("[RadioControl] watcher worker shutdown");

  g_clear_object(&self->scheduler);
  g_clear_object(&self->canceled);
  g_clear_object(&self->watcher);

  G_OBJECT_CLASS(radio_control_parent_class)->dispose(object);
}

static void
radio_control_class_init(RadioControlClass *klass)
{
  signals[SIG_CONNECTED] = g_signal_new("radio-connected",
    G_TYPE_FROM_CLASS(klass),
    G_SIGNAL_RUN_LAST,
    0,
    NULL, NULL,
    NULL,
    G_TYPE_NONE,
    0
  );

  signals[SIG_DISCONNECTED] = g_signal_new("radio-disconnected",
    G_TYPE_FROM_CLASS(klass),
    G_SIGNAL_RUN_LAST,
    0,
    NULL, NULL,
    NULL,
    G_TYPE_NONE,
    0
  );

  signals[SIG_STATUS] = g_signal_new("radio-status",
    G_TYPE_FROM_CLASS(klass),
    G_SIGNAL_RUN_LAST,
    0,
    NULL, NULL,
    NULL,
    G_TYPE_NONE,
    2,
    G_TYPE_INT,
    G_TYPE_INT
  );

  signals[SIG_ERROR] = g_signal_new("radio-error",
    G_TYPE_FROM_CLASS(klass),
    G_SIGNAL_RUN_LAST,
    0,
    NULL, NULL,
    NULL,
    G_TYPE_NONE,
    1,
    G_TYPE_ERROR
  );

  G_OBJECT_CLASS(klass)->dispose = radio_control_dispose;
}

static int
hamlib_debug_callback(enum rig_debug_level_e level, rig_ptr_t arg, const char* format, va_list ap)
{
  g_autofree gchar *msg = g_strdup_vprintf(format, ap);
  switch (level)
  {
    case RIG_DEBUG_BUG: 
    case RIG_DEBUG_ERR:
    case RIG_DEBUG_WARN:
    case RIG_DEBUG_VERBOSE:
    case RIG_DEBUG_CACHE:
    case RIG_DEBUG_TRACE:
      g_debug("%s", msg);
    case RIG_DEBUG_NONE:
      break;
  }
  return RIG_OK;
}

static void
radio_control_init(RadioControl *self)
{
  rig_set_debug_callback(hamlib_debug_callback, NULL);
  rig_set_debug_level(RIG_DEBUG_NONE);

  self->poll_interval_ms = 500;
  self->canceled = dex_cancellable_new();
  self->scheduler = dex_thread_pool_scheduler_new();

  g_message("[RadioControl] Starting rig watch worker...");
  self->watcher = dex_scheduler_spawn(self->scheduler, 0, watcher_worker, g_object_ref(self), g_object_unref);
}

RadioControl* 
radio_control_new()
{
  return g_object_new(ARTEMIS_TYPE_RADIO_CONTROL, NULL);
}

gboolean
radio_control_get_is_rig_connected(RadioControl *self)
{
  return self->is_connected;
}

float
radio_control_get_frequency(RadioControl *self)
{
  return self->frequency_khz;
}

enum RadioMode
radio_control_get_mode(RadioControl *self)
{
  return self->mode;
}

typedef struct {
  RadioControl            *radio;
  int                     frequency; // in kHz
  enum RadioMode          mode;
  enum RadioStatusSignal  status;
  GError                  *error;
} _RadioStatus;

static void
radio_status_free(_RadioStatus *data)
{
  g_object_unref(data->radio);
  g_clear_error(&data->error);
  g_free(data);
}

static DexFuture *
send_status(gpointer user_data)
{
  _RadioStatus *status = (_RadioStatus *)user_data;
  if (status->status == SIG_STATUS)
  {
    g_signal_emit(status->radio, signals[SIG_STATUS], 0, status->frequency, status->mode);
    goto status_finished;
  }
  
  if (status->status == SIG_ERROR) 
  {
    g_signal_emit(status->radio, signals[SIG_ERROR], 0, status->error);
    goto status_finished;
  }
  
  g_signal_emit(status->radio, signals[status->status], 0);

status_finished:
  return dex_future_new_true();
}

typedef struct {
    RadioControl        *radio_control;
    RadioConfiguration  *config;
} ConnectData;

static void
connect_data_free(ConnectData *data) {
    if (data) {
      g_object_unref(data->radio_control);
      radio_configuration_destroy(data->config);
      g_free(data->config);
    }
    g_free(data);
}

static DexFuture *
connect_worker(gpointer user_data)
{
  ConnectData *data = (ConnectData *)user_data;
  RadioControl *self = ARTEMIS_RADIO_CONTROL(data->radio_control);
  RadioConfiguration *config = (RadioConfiguration *)data->config;

  g_autoptr (GError) error = NULL;

  self->rig = rig_init(config->model_id);

  if (self->rig == NULL)
  {
    g_set_error(&error, G_IO_ERROR, G_IO_ERROR_FAILED, "Failed to initialize radio model %d", config->model_id);
    return dex_future_new_for_error(g_steal_pointer(&error));
  }

  if (g_strcmp0(config->connection_type, "serial") == 0) 
  {
    if (!try_set_rig_conf(self->rig, "rig_pathname", config->device_path, TRUE, &error))
      goto connect_fail;

    if (config->baud_rate > 0) {
      char baudstr[16];
      g_snprintf(baudstr, sizeof baudstr, "%d", config->baud_rate);
      try_set_rig_conf(self->rig, "serial_speed", baudstr, FALSE, NULL);
    }

    if (config->data_bits != 0) {
      char datastr[1];
      g_snprintf(datastr, 1, "%d", config->data_bits);
      try_set_rig_conf(self->rig, "data_bits", datastr, FALSE, NULL);
    }
    if (config->stop_bits != 0) {
      char stopstr[1];
      g_snprintf(stopstr, 1, "%d", config->stop_bits);
      try_set_rig_conf(self->rig, "stop_bits", stopstr, FALSE, NULL);
    }
    
    const char *handshake_str = NULL;
    switch (config->handshake) {
      case 0:
        handshake_str = "None";
        break;
      case 1:
        handshake_str = "XONXOFF";
        break;
      case 2:
        handshake_str = "Hardware";
        break;
      default:
        handshake_str = "None";
        break;
    }
    try_set_rig_conf(self->rig, "serial_handshake", handshake_str, FALSE, NULL);
  } else if (g_strcmp0(config->connection_type, "network") == 0) {
      char hostport[256];
      g_snprintf(hostport, sizeof hostport, "%s:%u", config->network_host, config->network_port);

      if (!try_set_rig_conf(self->rig, "rig_pathname", hostport, TRUE, &error))
        goto connect_fail;
  } else {
    g_set_error(&error, G_IO_ERROR, G_IO_ERROR_INVALID_ARGUMENT,
                "Unsupported connection type: %s",
                config->connection_type ? config->connection_type : "(null)");
    goto connect_fail;
  }

  try_set_rig_conf(self->rig, "timeout", "3000", FALSE, NULL);
  
  int result = rig_open(self->rig);

  if (result != RIG_OK) 
  {
    g_set_error(&error, G_IO_ERROR, G_IO_ERROR_CONNECTION_REFUSED,
                "Failed to connect to radio: %s", rigerror(result));
    rig_close(self->rig);
    rig_cleanup(self->rig);
    self->rig = NULL;
    self->is_connected = FALSE;
    return dex_future_new_for_error(g_steal_pointer(&error));
  }
  self->is_connected = TRUE;

  _RadioStatus *status = g_new0(_RadioStatus, 1);
  status->radio = g_object_ref(self);
  status->status = SIG_CONNECTED;

  dex_future_disown(
    dex_scheduler_spawn(dex_scheduler_get_default(), 0, send_status, status, (GDestroyNotify)radio_status_free)
  );

  return dex_future_new_true();

  connect_fail:
    if (self->rig != NULL) {
      rig_cleanup(self->rig);
      self->rig = NULL;
    }
    self->is_connected = FALSE;

    if (error == NULL) {
      g_set_error(&error, G_IO_ERROR, G_IO_ERROR_FAILED, "Radio connection setup failed");
    }

    return dex_future_new_for_error(g_steal_pointer(&error));
}

DexFuture *
radio_control_connect_async(RadioControl *self, RadioConfiguration *config)
{
    ConnectData *data = g_new0(ConnectData, 1);
    data->radio_control = g_object_ref(self);
    data->config = g_new0(RadioConfiguration, 1);
    radio_configuration_copy(config, data->config);

    return dex_scheduler_spawn(
        self->scheduler,
        0,
        connect_worker,
        data,
        (GDestroyNotify)connect_data_free
    );
}

static DexFuture *
disconnect_worker(gpointer user_data)
{
  RadioControl *self = ARTEMIS_RADIO_CONTROL(user_data);

  self->is_connected = FALSE;

  if (self->rig != NULL)
  {
    rig_close(self->rig);
    rig_cleanup(self->rig);
    self->rig = NULL;
  }

  _RadioStatus *status = g_new0(_RadioStatus, 1);
  status->status = SIG_DISCONNECTED;
  status->radio = g_object_ref(self);

  dex_future_disown(
    dex_scheduler_spawn(dex_scheduler_get_default(), 0, send_status, status, (GDestroyNotify)radio_status_free)
  );

  return dex_future_new_true();
}

DexFuture *
radio_control_disconnect_async(RadioControl *self)
{
  return dex_scheduler_spawn(self->scheduler, 0, disconnect_worker, g_object_ref(self), g_object_unref);
}

static DexFuture *
get_vfo_worker(gpointer user_data)
{
  RadioControl *self = ARTEMIS_RADIO_CONTROL(user_data);
  g_autoptr (GError) error = NULL;
  freq_t freq;
  int result = rig_get_freq(self->rig, RIG_VFO_CURR, &freq);
  if (result != RIG_OK)
  {
    g_set_error(&error, G_IO_ERROR, G_IO_ERROR_CONNECTION_CLOSED,
      "Failed to get VFO frequency from radio: %s", rigerror(result));
    return dex_future_new_for_error(g_steal_pointer(&error));
  }

  return dex_future_new_for_int((int)(freq / 1000.0));
}

DexFuture *
radio_control_get_vfo_async(RadioControl *self)
{
  return dex_scheduler_spawn(self->scheduler, 0, get_vfo_worker, g_object_ref(self), g_object_unref);
}

static DexFuture *
get_mode_worker(gpointer user_data)
{
  RadioControl *self = ARTEMIS_RADIO_CONTROL(user_data);
  g_autoptr (GError) error = NULL;
  rmode_t mode;
  pbwidth_t pbwidth;
  int result = rig_get_mode(self->rig, RIG_VFO_CURR, &mode, &pbwidth);
  if (result != RIG_OK)
  {
    g_set_error(&error, G_IO_ERROR, G_IO_ERROR_CONNECTION_CLOSED,
      "Failed to get VFO mode from radio: %s", rigerror(result));
    return dex_future_new_for_error(g_steal_pointer(&error));
  }

  return dex_future_new_for_int(map_hamlib_mode(mode));
}

DexFuture *
radio_control_get_mode_async(RadioControl *self)
{
  return dex_scheduler_spawn(self->scheduler, 0, get_mode_worker, g_object_ref(self), g_object_unref);
}

typedef struct {
  RadioControl *radio;
  mode_t       mode;
} _SetModeData;

static void
set_mode_data_free(_SetModeData *data)
{
  g_object_unref(data->radio);
  g_free(data);
}

static DexFuture *
set_mode_worker(gpointer user_data)
{
  _SetModeData *data = (_SetModeData *)user_data;
  RadioControl *self = data->radio;

  g_autoptr (GError) error = NULL;
  if (!self->is_connected)
  {
    g_set_error(&error, G_IO_ERROR, G_IO_ERROR_FAILED,
      "Unable to set mode, rig is not connected");
    return dex_future_new_for_error(g_steal_pointer(&error));
  }

  int result = rig_set_mode(self->rig, RIG_VFO_CURR, map_artemis_mode(data->mode), RIG_PASSBAND_NOCHANGE);
  if (result != RIG_OK)
  {
    g_set_error(&error, G_IO_ERROR, G_IO_ERROR_FAILED,
      "Unable to set mode, rig replied: %s", rigerror(result));
    return dex_future_new_for_error(g_steal_pointer(&error));
  }

  return dex_future_new_true();
}

DexFuture *
radio_control_set_mode_async(RadioControl *self, enum RadioMode mode)
{
  _SetModeData *data = g_new0(_SetModeData, 1);
  data->radio = g_object_ref(self);
  data->mode = mode;
  return dex_scheduler_spawn(self->scheduler, 0, set_mode_worker, data, (GDestroyNotify)set_mode_data_free);
}

typedef struct {
  RadioControl *radio;
  freq_t       frequency;
} _SetVFOData;

static void
set_vfo_data_free(_SetVFOData *data)
{
  g_object_unref(data->radio);
  g_free(data);
}

static DexFuture *
set_vfo_worker(gpointer user_data)
{
  _SetVFOData *data = (_SetVFOData *)user_data;
  RadioControl *self = data->radio;

  g_autoptr (GError) error = NULL;
  if (!self->is_connected)
  {
    g_set_error(&error, G_IO_ERROR, G_IO_ERROR_FAILED,
      "Unable to set mode, rig is not connected");
    return dex_future_new_for_error(g_steal_pointer(&error));
  }

  int result = rig_set_freq(self->rig, RIG_VFO_CURR, data->frequency);
  if (result != RIG_OK)
  {
    g_set_error(&error, G_IO_ERROR, G_IO_ERROR_FAILED,
      "Unable to set VFO, rig replied: %s", rigerror(result));
    return dex_future_new_for_error(g_steal_pointer(&error));
  }

  return dex_future_new_true();
}

DexFuture *
radio_control_set_vfo_async(RadioControl *self, int frequency)
{
  _SetVFOData *data = g_new0(_SetVFOData, 1);
  data->radio = g_object_ref(self);
  data->frequency = (double)frequency * 1000.0;

  return dex_scheduler_spawn(self->scheduler, 0, set_vfo_worker, data, (GDestroyNotify)set_vfo_data_free);
}

const gchar *
radio_control_hamlib_version(void)
{
  return rig_version();
}

const gchar *
radio_control_hamlib_copyright(void)
{
  return rig_copyright();
}

static DexFuture *
watcher_iteration(DexFuture *_, gpointer user_data)
{
  RadioControl *self = ARTEMIS_RADIO_CONTROL(user_data);

  /* Exit the watcher loop once disposal has requested cancellation. */
  if (dex_future_get_status(DEX_FUTURE(self->canceled)) != DEX_FUTURE_STATUS_PENDING) {
    return NULL;
  }

  /* Stay idle while disconnected instead of running a tight loop. */
  if (!self->is_connected || self->rig == NULL) {
    return dex_timeout_new_msec(self->poll_interval_ms);
  }

  freq_t freq;
  rmode_t mode;
  pbwidth_t width;
  powerstat_t pwr_stat;
  split_t _st;
  int satmode;
  
  int r_f = rig_get_vfo_info(self->rig, RIG_VFO_CURR, &freq, &mode, &width, &_st, &satmode);
  int r_ps = rig_get_powerstat(self->rig, &pwr_stat);

  _RadioStatus *status = g_new0(_RadioStatus, 1);
  status->radio = g_object_ref(self);
  
  if (r_f == RIG_OK && r_ps == RIG_OK)
  {
    status->status = SIG_STATUS;
    status->frequency = (int)(freq / 1000.0);
    status->mode = map_hamlib_mode(mode);

    self->frequency_khz = (float)(freq / 1000.0);
    self->mode = map_hamlib_mode(mode);
  }
  else 
  {
    status->status = SIG_ERROR;
    status->frequency = -1;
    status->mode = 0;

    self->frequency_khz = -1;
    self->mode = 0;

    GError *error = g_error_new(G_IO_ERROR, G_IO_ERROR_FAILED, "[RadioControl] heartbeat received error from hamlib: %s; %s", rigerror(r_f), rigerror(r_ps));
    status->error = g_steal_pointer(&error);

    if (self->is_connected)
    {
      self->is_connected = FALSE;
      if (self->rig != NULL)
      {
        rig_close(self->rig);
        rig_cleanup(self->rig);
        self->rig = NULL;
      }

      _RadioStatus *disconnect_status = g_new0(_RadioStatus, 1);
      disconnect_status->radio = g_object_ref(self);
      disconnect_status->status = SIG_DISCONNECTED;
      dex_future_disown(
        dex_scheduler_spawn(dex_scheduler_get_default(), 0, send_status, disconnect_status, (GDestroyNotify)radio_status_free)
      );
    }
  }
  
  dex_future_disown(
    dex_scheduler_spawn(dex_scheduler_get_default(), 0, send_status, status, (GDestroyNotify)radio_status_free)
  );

  return dex_timeout_new_msec(self->poll_interval_ms);
}

static DexFuture *
watcher_worker(void *user_data)
{
  RadioControl *self = ARTEMIS_RADIO_CONTROL(user_data);
  return dex_future_finally_loop(dex_future_new_true(), watcher_iteration, g_object_ref(self), g_object_unref);
}
