artemis_vala_sources = [
  'src/main.vala',
  'src/application.vala',
  'src/window.vala',
  'src/pota_client.vala',
  'src/preferences.vala',
  'src/spot_card.vala',
  'src/spot.vala',
  'src/repo.vala',
  'src/activator.vala',
  'src/band_view.vala',
  'src/status_page.vala',
  'src/database.vala',
]

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

artemis_vala_deps = [
  config_dep,
  dependency('gtk4'),
  dependency('libsoup-3.0'),
  dependency('json-glib-1.0'),
  dependency('libadwaita-1', version: '>= 1.4'),
  dependency('gio-2.0'),
  dependency('libdex-1'),
  dependency('gee-0.8'),
  dependency('webkitgtk-6.0'),
  dependency('sqlite3')
]

artemis_vala_sources += gnome.compile_resources('artemis-vala-resources',
  '../data/artemis-vala.gresource.xml',
  dependencies: blueprint_batch,
  c_name: 'artemis_vala'
)
