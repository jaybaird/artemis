artemis_vala_sources = [
  'src/help/help_models.vala',
  'src/help/help_window.vala',
  'src/http_session_factory.vala',
  'src/adif/adif_types.vala',
  'src/adif/adif_parser.vala',
  'src/adif/adif_generator.vala',
  'src/adif/adif_qso.vala',
  'src/add_spot.vala',
  'src/avatar_detail_dialog.vala',
  'src/alerts_window.vala',
  'src/app_state.vala',
  'src/application.vala',
  'src/callsign_cache.vala',
  'src/csv/csv_parser.vala',
  'src/distance.vala',
  'src/frequency.vala',
  'src/first_run_setup_dialog.vala',
  'src/input_parsing.vala',
  'src/logging_preferences.vala',
  'src/local_adif_file.vala',
  'src/local_adif_log.vala',
  'src/logging_service.vala',
  'src/logbook_import_service.vala',
  'src/logbook_window.vala',
  'src/park_log_dialog.vala',
  'src/models/heatmap_model.vala',
  'src/models/heatmap_point.vala',
  'src/models/signal_report.vala',
  'src/models/signal_report_bucket.vala',
  'src/park_details.vala',
  'src/park_details_cache.vala',
  'src/psk_reporter_client.vala',
  'src/psk_reporter_decoder.vala',
  'src/spot_filter.vala',
  'src/spot_alert_matcher.vala',
  'src/space_weather_button.vala',
  'src/space_weather_popover.vala',
  'src/space_weather_client.vala',
  'src/space_weather_snapshot.vala',
  'src/space_weather_service.vala',
  'src/models/signal_report_mqtt_session.vala',
  'src/window.vala',
  'src/pota_client.vala',
  'src/qrz_client.vala',
  'src/qso_dialog.vala',
  'src/preferences.vala',
  'src/preferences/general_page.vala',
  'src/preferences/map_page.vala',
  'src/preferences/radio_page.vala',
  'src/preferences/logging_page.vala',
  'src/preferences/wsjtx_page.vala',
  'src/spot_card.vala',
  'src/spot_history_dialog.vala',
  'src/spot.vala',
  'src/repo.vala',
  'src/activator.vala',
  'src/band_view.vala',
  'src/band_strip.vala',
  'src/database.vala',
  'src/utils.vala',
  'src/status_bar.vala',
  'src/string_utils.vala',
  'src/utils/callsign_utils.vala',
  'src/utils/maidenhead.vala',
  'src/utils/map.vala',
  'src/utils/spot_format.vala',
  'src/map/bounding_box.vala',
  'src/map/grayline_overlay.vala',
  'src/map/map_marker_dot.vala',
  'src/map/map_marker_popover.vala',
  'src/map/signal_report_heatmap_layer.vala',
  'src/map/wrapped_marker_layer.vala',
  'src/map/map_view.vala',
  'src/left_sidebar.vala',
  'src/astronomy.vala',
  'src/spot_detail.vala',
  'src/spot_list_view.vala',
  'src/spot_lookup.vala',
  'src/weather_cache.vala',
  'src/wsjtx/wsjtx_packet.vala',
  'src/wsjtx/wsjtx_packet_reader.vala',
  'src/wsjtx/wsjtx_packet_parser.vala',
  'src/wsjtx/wsjtx_packet_writer.vala',
  'src/wsjtx/wsjtx_decode_matcher.vala',
  'src/wsjtx/wsjtx_listener.vala',
  'src/wsjtx/wsjtx_logged_adif_parser.vala',
  'src/wsjtx/wsjtx_logged_adif_handler.vala',
  'src/wsjtx/wsjtx_session.vala'
]

if is_windows
  add_project_arguments(
    ['--define=ARTEMIS_WINDOWS'],
    language: 'vala')
  add_project_arguments('-DARTEMIS_WINDOWS', language: 'c')
else
  add_project_arguments(
    ['--define=ARTEMIS_UNIX'],
    language: 'vala')
  add_project_arguments('-DARTEMIS_UNIX', language: 'c')
endif

if devel
  add_project_arguments('-DARTEMIS_DEBUG', language: 'c')
endif


glib_dep = dependency('glib-2.0')
gobject_dep = dependency('gobject-2.0')
gio_dep = dependency('gio-2.0')
libdex_dep = dependency('libdex-1')
hamlib_dep = dependency('hamlib')

cc = meson.get_compiler('c')

paho_mqtt_dep = cc.find_library('paho-mqtt3a', required: true)
if not cc.has_header('MQTTAsync.h')
  error('MQTTAsync.h not found. Install paho.mqtt.c development headers.')
endif

has_set_conf2 = cc.has_function(
  'rig_set_conf2',
  prefix: '#include <hamlib/rig.h>',
  dependencies: hamlib_dep
)
config.set('HAVE_HAMLIB_SET_CONF2', has_set_conf2 ? 1 : 0)
if has_set_conf2
  message('Hamlib >= 4.7 detected. Using set_conf2')
  add_project_arguments('-DHAVE_HAMLIB_SET_CONF2=1', language: 'c')
endif

src_inc = include_directories('.')
cc = meson.get_compiler('c')

radio_control_sources = ['radio/radio_control.c']
radio_control_deps = [glib_dep, gobject_dep, gio_dep, libdex_dep, hamlib_dep]

if is_windows
  radio_control_deps += cc.find_library('setupapi', required: true)
else
  radio_control_deps += dependency('gudev-1.0')
endif

libradiocontrol = static_library(
  'radiocontrol',
  radio_control_sources,
  include_directories: src_inc,
  dependencies: radio_control_deps
)

artemis_mqtt_sources = ['mqtt/mqtt_client.c']
artemis_mqtt_deps = [glib_dep, gobject_dep, gio_dep, paho_mqtt_dep]

libartemismqtt = static_library(
  'artemismqtt',
  artemis_mqtt_sources,
  include_directories: src_inc,
  dependencies: artemis_mqtt_deps
)

mathlib = cc.find_library('m', required: true)

zonedetect_sources = ['tz/zonedetect.c']
zonedetect_deps = [mathlib]

libzonedetect = static_library(
  'zonedetect',
  zonedetect_sources,
  include_directories: src_inc,
  dependencies: zonedetect_deps
)

heatmap_sources = ['map/heatmap.c']
heatmap_deps = [mathlib]

libheatmap = static_library(
  'heatmap',
  heatmap_sources,
  include_directories: src_inc,
  dependencies: heatmap_deps
)

artemis_vala_deps = [
  dependency('gtk4'),
  dependency('libsoup-3.0'),
  dependency('json-glib-1.0'),
  dependency('libadwaita-1', version: '>= 1.4'),
  dependency('gio-2.0'),
  dependency('libdex-1'),
  dependency('gee-0.8'),
  dependency('sqlite3'),
  dependency('libxml-2.0'),
  dependency('shumate-1.0'),
  mathlib
]

if not is_windows
  artemis_vala_deps += [
    dependency('glycin-2'),
    dependency('glycin-gtk4-2')
  ]
endif

artemis_vala_sources += configure_file(
  input: 'build.vala.in',
  output: 'build.vala',
  configuration: config
)
