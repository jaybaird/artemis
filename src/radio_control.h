#include <glib-object.h>
#include <hamlib/rig.h>
#include <libdex.h>

G_BEGIN_DECLS

#define APPLICATION_ID "com.k0vcz.artemis"

#define ARTEMIS_TYPE_RADIO_CONTROL (radio_control_get_type())

G_DECLARE_FINAL_TYPE(RadioControl, radio_control, ARTEMIS, RADIO_CONTROL, GObject)

enum RadioMode {
  RADIO_MODE_UNKNOWN, 
  RADIO_MODE_CW, 
  RADIO_MODE_CW_R, 
  RADIO_MODE_USB, 
  RADIO_MODE_LSB,
  RADIO_MODE_DIGITAL_U, 
  RADIO_MODE_DIGITAL_L, 
  RADIO_MODE_AM, 
  RADIO_MODE_FM,
  RADIO_MODE_DIGITAL_FM
};

enum RadioStatusSignal {
  SIG_CONNECTED,
  SIG_DISCONNECTED,
  SIG_STATUS,
  SIG_ERROR,
  N_RIG_SIGNALS
};

typedef struct {
  gint model_id;
  gchar *connection_type;
  gchar *device_path;
  gchar *network_host;
  gint network_port;
  gint baud_rate;
} RadioConfiguration;


typedef struct {
  int model_id;
  const char *display_name;
} RadioModel;

const 
RadioModel* radio_control_get_radio_models(gint *count);

void
radio_configuration_destroy(RadioConfiguration *config);

void
radio_configuration_copy(RadioConfiguration *config, RadioConfiguration *new_config);

RadioControl *
radio_control_new();

DexFuture *
radio_control_connect_async(RadioControl *self, RadioConfiguration *config);

DexFuture *
radio_control_disconnect_async(RadioControl *self);

/* Getters */

gboolean
radio_control_get_is_rig_connected(RadioControl *self);

float
radio_control_get_frequency(RadioControl *self);

enum RadioMode
radio_control_get_mode(RadioControl *self);

DexFuture *
radio_control_get_vfo_async(RadioControl *self);

DexFuture *
radio_control_get_mode_async(RadioControl *self);

/* Setters */

DexFuture *
radio_control_set_vfo_async(RadioControl *self, int frequency);

DexFuture *
radio_control_set_mode_async(RadioControl *self, enum RadioMode mode);

G_END_DECLS