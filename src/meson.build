artemis_vala_sources = [
  'src/application.vala',
  'src/window.vala',
  'src/pota_client.vala',
  'src/preferences.vala',
  'src/spot_card.vala',
  'src/spot.vala',
  'src/repo.vala',
  'src/activator.vala',
  'src/band_view.vala',
  'src/database.vala',
  'src/utils.vala',
  'src/map_view.vala',
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

glib_dep = dependency('glib-2.0')
gobject_dep = dependency('gobject-2.0')
gio_dep = dependency('gio-2.0')
libdex_dep = dependency('libdex-1')
hamlib_dep = dependency('hamlib')

src_inc = include_directories('.')
cc = meson.get_compiler('c')

radio_control_sources = ['radio_control.c']
radio_control_deps = [glib_dep, gobject_dep, gio_dep, libdex_dep, hamlib_dep]

if is_windows
  radio_control_sources += 'windows_serial.c'
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

mathlib = cc.find_library('m', required: true)

artemis_vala_deps = [
  dependency('gtk4'),
  dependency('libsoup-3.0'),
  dependency('json-glib-1.0'),
  dependency('libadwaita-1', version: '>= 1.4'),
  dependency('gio-2.0'),
  dependency('libdex-1'),
  dependency('gee-0.8'),
  dependency('sqlite3'),
  dependency('shumate-1.0'),
  mathlib
]

if not is_windows
  artemis_vala_deps += dependency('webkitgtk-6.0')
endif

artemis_vala_sources += configure_file(
  input: 'build.vala.in',
  output: 'build.vala',
  configuration: config
)
