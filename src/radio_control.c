#include "radio_control.h"

#include <glib.h>
#include <libdex.h>
#include <hamlib/rig.h>
#include <sched.h>
#include <stdint.h>
#include <sys/types.h>
#include <unistd.h>

static const RadioModel RADIO_MODELS[] = {
  { RIG_MODEL_NETRIGCTL, "NET rigctl" },
  { RIG_MODEL_FLRIG, "FLRig" },
  
  { RIG_MODEL_K2, "Elecraft - K2" },
  { RIG_MODEL_K3, "Elecraft - K3" },
  { RIG_MODEL_K3S, "Elecraft - K3S" },
  { RIG_MODEL_K4, "Elecraft - K4" },
  { RIG_MODEL_KX2, "Elecraft - KX2" },
  { RIG_MODEL_KX3, "Elecraft - KX3" },
  
  { RIG_MODEL_F6K, "FlexRadio - 6xxx Series" },
  
  { RIG_MODEL_IC703, "Icom - IC-703" },
  { RIG_MODEL_IC705, "Icom - IC-705" },
  { RIG_MODEL_IC706, "Icom - IC-706" },
  { RIG_MODEL_IC706MKII, "Icom - IC-706MkII" },
  { RIG_MODEL_IC706MKIIG, "Icom - IC-706MkIIG" },
  { RIG_MODEL_IC707, "Icom - IC-707" },
  { RIG_MODEL_IC718, "Icom - IC-718" },
  { RIG_MODEL_IC746, "Icom - IC-746" },
  { RIG_MODEL_IC746PRO, "Icom - IC-746PRO" },
  { RIG_MODEL_IC756, "Icom - IC-756" },
  { RIG_MODEL_IC756PRO, "Icom - IC-756PRO" },
  { RIG_MODEL_IC756PROII, "Icom - IC-756PROII" },
  { RIG_MODEL_IC756PROIII, "Icom - IC-756PROIII" },
  { RIG_MODEL_IC7000, "Icom - IC-7000" },
  { RIG_MODEL_IC7100, "Icom - IC-7100" },
  { RIG_MODEL_IC7200, "Icom - IC-7200" },
  { RIG_MODEL_IC7300, "Icom - IC-7300" },
  { RIG_MODEL_IC7600, "Icom - IC-7600" },
  { RIG_MODEL_IC7610, "Icom - IC-7610" },
  { RIG_MODEL_IC7700, "Icom - IC-7700" },
  { RIG_MODEL_IC7800, "Icom - IC-7800" },
  { RIG_MODEL_IC785x, "Icom - IC-7850/7851" },
  { RIG_MODEL_IC905, "Icom - IC-905" },
  { RIG_MODEL_IC9100, "Icom - IC-9100" },
  { RIG_MODEL_IC9700, "Icom - IC-9700" },
  
  { RIG_MODEL_TS50, "Kenwood - TS-50S" },
  { RIG_MODEL_TS140S, "Kenwood - TS-140S" },
  { RIG_MODEL_TS440, "Kenwood - TS-440S" },
  { RIG_MODEL_TS450S, "Kenwood - TS-450S" },
  { RIG_MODEL_TS480, "Kenwood - TS-480" },
  { RIG_MODEL_TS570D, "Kenwood - TS-570D" },
  { RIG_MODEL_TS570S, "Kenwood - TS-570S" },
  { RIG_MODEL_TS590S, "Kenwood - TS-590S" },
  { RIG_MODEL_TS590SG, "Kenwood - TS-590SG" },
  { RIG_MODEL_TS680S, "Kenwood - TS-680S" },
  { RIG_MODEL_TS690S, "Kenwood - TS-690S" },
  { RIG_MODEL_TS790, "Kenwood - TS-790" },
  { RIG_MODEL_TS850, "Kenwood - TS-850" },
  { RIG_MODEL_TS870S, "Kenwood - TS-870S" },
  { RIG_MODEL_TS890S, "Kenwood - TS-890S" },
  { RIG_MODEL_TS940, "Kenwood - TS-940S" },
  { RIG_MODEL_TS950S, "Kenwood - TS-950S" },
  { RIG_MODEL_TS950SDX, "Kenwood - TS-950SDX" },
  { RIG_MODEL_TS990S, "Kenwood - TS-990S" },
  { RIG_MODEL_TS2000, "Kenwood - TS-2000" },
  
  { RIG_MODEL_TT516, "Ten-Tec - TT-516 Argonaut V" },
  { RIG_MODEL_TT538, "Ten-Tec - TT-538 Jupiter" },
  { RIG_MODEL_TT565, "Ten-Tec - TT-565/566 Orion I/II" },
  { RIG_MODEL_TT588, "Ten-Tec - TT-588 Omni VII" },
  { RIG_MODEL_TT599, "Ten-Tec - TT-599 Eagle" },
  
  { RIG_MODEL_G90, "Xiegu - G90" },
  { RIG_MODEL_X108G, "Xiegu - X108G" },
  { RIG_MODEL_X5105, "Xiegu - X5105" },
  { RIG_MODEL_X6100, "Xiegu - X6100" },
  { RIG_MODEL_X6200, "Xiegu - X6200" },
  
  { RIG_MODEL_FT100, "Yaesu - FT-100" },
  { RIG_MODEL_FT1000D, "Yaesu - FT-1000D" },
  { RIG_MODEL_FT1000MP, "Yaesu - FT-1000MP" },
  { RIG_MODEL_FT450, "Yaesu - FT-450/450D" },
  { RIG_MODEL_FT710, "Yaesu - FT-710" },
  { RIG_MODEL_FT736R, "Yaesu - FT-736R" },
  { RIG_MODEL_FT747, "Yaesu - FT-747GX" },
  { RIG_MODEL_FT757, "Yaesu - FT-757GX" },
  { RIG_MODEL_FT757GXII, "Yaesu - FT-757GXII" },
  { RIG_MODEL_FT767, "Yaesu - FT-767GX" },
  { RIG_MODEL_FT817, "Yaesu - FT-817" },
  { RIG_MODEL_FT818, "Yaesu - FT-818" },
  { RIG_MODEL_FT840, "Yaesu - FT-840" },
  { RIG_MODEL_FT847, "Yaesu - FT-847" },
  { RIG_MODEL_FT857, "Yaesu - FT-857" },
  { RIG_MODEL_FT890, "Yaesu - FT-890" },
  { RIG_MODEL_FT891, "Yaesu - FT-891" },
  { RIG_MODEL_FT897, "Yaesu - FT-897" },
  { RIG_MODEL_FT897D, "Yaesu - FT-897D" },
  { RIG_MODEL_FT900, "Yaesu - FT-900" },
  { RIG_MODEL_FT920, "Yaesu - FT-920" },
  { RIG_MODEL_FT950, "Yaesu - FT-950" },
  { RIG_MODEL_FT980, "Yaesu - FT-980" },
  { RIG_MODEL_FT990, "Yaesu - FT-990" },
  { RIG_MODEL_FT991, "Yaesu - FT-991" },
  { RIG_MODEL_FT2000, "Yaesu - FT-2000" },
  { RIG_MODEL_FTDX10, "Yaesu - FTDX-10" },
  { RIG_MODEL_FTDX101D, "Yaesu - FTDX-101D" },
  { RIG_MODEL_FTDX101MP, "Yaesu - FTDX-101MP" },
  { RIG_MODEL_FTDX1200, "Yaesu - FTDX-1200" },
  { RIG_MODEL_FTDX3000, "Yaesu - FTDX-3000" },
  { RIG_MODEL_FTDX5000, "Yaesu - FTDX-5000" },
  { RIG_MODEL_FT9000, "Yaesu - FTDX-9000" },
  { RIG_MODEL_FT1000MPMKV, "Yaesu - MARK-V FT-1000MP" },
  { RIG_MODEL_FT1000MPMKVFLD, "Yaesu - MARK-V Field FT-1000MP" }
};

static size_t get_radio_models_count(void) {
    return sizeof(RADIO_MODELS) / sizeof(RADIO_MODELS[0]);
}

const RadioModel* radio_control_get_radio_models(gint *count) {
    *count = get_radio_models_count();
    return RADIO_MODELS;
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
      return AM;

    case RIG_MODE_CW:
      return CW;

    case RIG_MODE_CWR:
      return CW_R;

    case RIG_MODE_USB:
    case RIG_MODE_ECSSUSB:
    case RIG_MODE_SAH:
    case RIG_MODE_FAX:
      return USB;

    case RIG_MODE_LSB:
    case RIG_MODE_ECSSLSB:
    case RIG_MODE_SAL:
      return LSB;

    case RIG_MODE_PKTLSB:
      return DIGITAL_L;

    case RIG_MODE_PKTUSB:
      return DIGITAL_U;

    case RIG_MODE_FM:
    case RIG_MODE_WFM:
      return FM;

    case RIG_MODE_PKTFM:
      return DIGITAL_FM;

    default:
      return UNKNOWN;
  }
}

static rmode_t
map_artemis_mode(enum RadioMode mode)
{
  switch (mode)
  {
    case AM: return RIG_MODE_AM;
    case CW: return RIG_MODE_CW;
    case CW_R: return RIG_MODE_CWR;
    case USB: return RIG_MODE_USB;
    case LSB: return RIG_MODE_LSB;
    case DIGITAL_L: return RIG_MODE_PKTLSB;
    case DIGITAL_U: return RIG_MODE_PKTUSB;
    case FM: return RIG_MODE_FM;
    case DIGITAL_FM: return RIG_MODE_PKTFM;
    default: break;
  }
  return RIG_MODE_USB;
}


static DexFuture *
watcher_worker(DexFuture *future, gpointer user_data);

struct _RadioControl {
  GObject parent_instance;

  RIG   *rig;

  guint poll_interval_ms;

  DexCancellable  *canceled;
  DexFuture       *watcher;

  gboolean  is_connected;
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

G_DEFINE_FINAL_TYPE(RadioControl, radio_control, G_TYPE_OBJECT);

static guint signals[N_RIG_SIGNALS];

static void
radio_control_dispose(GObject *object)
{
  RadioControl *self = ARTEMIS_RADIO_CONTROL(object);

  if (self->rig)
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

  self->poll_interval_ms = 5000;
  self->canceled = dex_cancellable_new();
  self->scheduler = dex_thread_pool_scheduler_new();

  g_message("[RadioControl] Starting rig watch worker...");
  self->watcher = dex_future_finally_loop(dex_future_new_true(), watcher_worker, g_object_ref(self), g_object_unref);
}

RadioControl* 
radio_control_new()
{
  return g_object_new(ARTEMIS_TYPE_RADIO_CONTROL, NULL);
}

gboolean
radio_control_is_rig_connected(RadioControl *self)
{
  return self->is_connected;
}

typedef struct {
    RadioControl        *radio_control;
    RadioConfiguration    *config;
} ConnectData;

static void
connect_data_free(ConnectData *data) {
    if (data) {
        g_object_unref(data->radio_control);
        g_free(data);
    }
}

static DexFuture *
connect_worker(gpointer user_data)
{
  ConnectData *data = (ConnectData *)user_data;
  RadioControl *self = ARTEMIS_RADIO_CONTROL(data->radio_control);
  RadioConfiguration *config = (RadioConfiguration *)data->config;

  g_autoptr (GError) error = NULL;

  if (!self->rig)
  {
    g_set_error(&error, G_IO_ERROR, G_IO_ERROR_FAILED, "Failed to initialize radio model %d", config->model_id);
    return dex_future_new_for_error(g_steal_pointer(&error));
  }

  if (g_strcmp0(config->connection_type, "serial") == 0 || g_strcmp0(config->connection_type, "usb") == 0) 
  {
    rig_set_conf(self->rig, rig_token_lookup(self->rig, "rig_pathname"), (char*)config->device_path);
    if (config->baud_rate > 0) {
      char baudstr[16]; 
      g_snprintf(baudstr, sizeof baudstr, "%d", config->baud_rate);
      rig_set_conf(self->rig, rig_token_lookup(self->rig, "serial_speed"), baudstr);
    }
  } 
  else if (g_strcmp0(config->connection_type, "network") == 0) 
  {
    char hostport[256];
    g_snprintf(hostport, sizeof hostport, "%s:%d", config->network_host, config->network_port);
    rig_set_conf(self->rig, rig_token_lookup(self->rig, "rig_pathname"), hostport);
  }
  rig_set_conf(self->rig, rig_token_lookup(self->rig, "timeout"), "3000");
  
  int result = rig_open(self->rig);

  if (result != RIG_OK) 
  {
    g_set_error(&error, G_IO_ERROR, G_IO_ERROR_CONNECTION_REFUSED,
                "Failed to connect to radio: %s", rigerror(result));
    rig_cleanup(self->rig);
    return dex_future_new_for_error(g_steal_pointer(&error));
  }
  self->is_connected = TRUE;

  return dex_future_new_true();
}

DexFuture *
radio_control_connect_async(RadioControl *self, RadioConfiguration *config)
{
    ConnectData *data = g_new0(ConnectData, 1);
    data->radio_control = g_object_ref(self);
    data->config = config;

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
  rig_close(self->rig);
  rig_cleanup(self->rig);

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
}

static DexFuture *
send_status(gpointer user_data)
{
  g_message("[RadioControl] *** sending rig heartbeat ***");
  _RadioStatus *status = (_RadioStatus *)user_data;
  if (status->frequency < 0)
  {
    g_signal_emit(status->radio, signals[SIG_ERROR], 0, status->error);
  }
  else
  {
    g_signal_emit(status->radio, signals[SIG_STATUS], 0, status->frequency, status->mode);
  }

  return dex_future_new_true();
}

static DexFuture *
watcher_worker(DexFuture *future, gpointer user_data)
{
  RadioControl *self = ARTEMIS_RADIO_CONTROL(user_data);
  
  if (!self->is_connected)
  {
    return dex_future_new_for_boolean(TRUE);
  }

  if (!self->canceled)
  {
    return dex_future_new_for_boolean(FALSE);
  }

  freq_t freq;
  rmode_t mode;
  pbwidth_t width;
  
  int r_f = rig_get_freq(self->rig, RIG_VFO_CURR, &freq);
  int r_m = rig_get_mode(self->rig, RIG_VFO_CURR, &mode, &width);

  _RadioStatus *status = g_new0(_RadioStatus, 1);
  status->radio = g_object_ref(self);
  
  if (r_f == RIG_OK && r_m == RIG_OK)
  {
    status->status = SIG_STATUS;
    status->frequency = (int)(freq / 1000.0);
    status->mode = map_hamlib_mode(mode);
  }
  else 
  {
    status->status = SIG_ERROR;
    status->frequency = -1;
    status->mode = 0;

    GError *error = g_error_new(G_IO_ERROR, G_IO_ERROR_FAILED, "[RadioControl] heartbeat received error from hamlib: %s; %s", rigerror(r_f), rigerror(r_m));
    status->error = g_steal_pointer(&error);
  }
  
  dex_future_disown(
    dex_scheduler_spawn(dex_scheduler_get_default(), 0, send_status, status, (GDestroyNotify)radio_status_free)
  );

  return dex_timeout_new_msec(self->poll_interval_ms);
}