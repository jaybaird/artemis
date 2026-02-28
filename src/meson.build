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

glib_dep = dependency('glib-2.0')
gobject_dep = dependency('gobject-2.0')
gio_dep = dependency('gio-2.0')
libdex_dep = dependency('libdex-1')
hamlib_dep = dependency('hamlib')

cc = meson.get_compiler('c')

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

libradiocontrol = static_library(
  'radiocontrol',
  ['radio_control.c'],
  include_directories: src_inc,
  dependencies: [glib_dep, gobject_dep, gio_dep, libdex_dep, hamlib_dep]
)

mathlib = cc.find_library('m', required: true)

artemis_vala_deps = [
  dependency('gtk4'),
  dependency('gudev-1.0'),
  dependency('libsoup-3.0'),
  dependency('json-glib-1.0'),
  dependency('libadwaita-1', version: '>= 1.4'),
  dependency('gio-2.0'),
  dependency('libdex-1'),
  dependency('gee-0.8'),
  dependency('webkitgtk-6.0'),
  dependency('sqlite3'),
  dependency('shumate-1.0'),
  mathlib
]

artemis_vala_sources += configure_file(
  input: 'build.vala.in',
  output: 'build.vala',
  configuration: config
)

