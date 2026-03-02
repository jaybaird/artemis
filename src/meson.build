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

is_windows = host_machine.system() == 'windows'

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

libradiocontrol = static_library(
  'radiocontrol',
  ['radio_control.c'],
  include_directories: src_inc,
  dependencies: [glib_dep, gobject_dep, gio_dep, libdex_dep, hamlib_dep]
)

cc = meson.get_compiler('c')
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
  artemis_vala_deps += dependency('gudev-1.0')
  artemis_vala_deps += dependency('webkitgtk-6.0')
endif

artemis_vala_sources += configure_file(
  input: 'build.vala.in',
  output: 'build.vala',
  configuration: config
)

