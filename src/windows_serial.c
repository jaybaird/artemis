#include "radio_control.h"

#ifdef ARTEMIS_WINDOWS

#include <glib.h>
#include <windows.h>
#include <devguid.h>
#include <regstr.h>
#include <setupapi.h>

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
