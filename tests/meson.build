wsjtx_test_sources = [
  meson.project_source_root() / 'src/wsjtx/wsjtx_packet.vala',
  meson.project_source_root() / 'src/wsjtx/wsjtx_packet_reader.vala',
  meson.project_source_root() / 'src/wsjtx/wsjtx_packet_parser.vala',
  meson.project_source_root() / 'src/wsjtx/wsjtx_packet_writer.vala',
  meson.project_source_root() / 'tests/test-wsjtx-packet.vala'
]

test_wsjtx_packet = executable(
  'test-wsjtx-packet',
  wsjtx_test_sources,
  dependencies: [
    dependency('gio-2.0'),
    dependency('glib-2.0')
  ]
)

test('WSJT-X Packet Parser', test_wsjtx_packet)

adif_test_sources = [
  meson.project_source_root() / 'src/adif/adif_types.vala',
  meson.project_source_root() / 'src/adif/adif_parser.vala',
  meson.project_source_root() / 'src/adif/adif_generator.vala',
  meson.project_source_root() / 'tests/test-adif.vala'
]

test_adif = executable(
  'test-adif',
  adif_test_sources,
  dependencies: [
    dependency('gee-0.8'),
    dependency('gio-2.0'),
    dependency('glib-2.0')
  ]
)

test('ADIF Parser/Generator', test_adif)

test_frequency = executable(
  'test-frequency',
  [
    meson.project_source_root() / 'src/frequency.vala',
    meson.project_source_root() / 'tests/test-frequency.vala'
  ],
  dependencies: [
    dependency('glib-2.0'),
    dependency('gobject-2.0'),
    cc.find_library('m', required: true)
  ]
)

test('Frequency Parser/Formatter', test_frequency)

test_logbook_import = executable(
  'test-logbook-import',
  [
    meson.project_source_root() / 'src/logbook_import_service.vala',
    meson.project_source_root() / 'tests/test-logbook-import.vala'
  ],
  dependencies: [
    dependency('gee-0.8'),
    dependency('gio-2.0'),
    dependency('glib-2.0'),
    dependency('gobject-2.0')
  ]
)

test('Logbook Import Service', test_logbook_import)

test_local_adif_file = executable(
  'test-local-adif-file',
  [
    meson.project_source_root() / 'src/local_adif_file.vala',
    meson.project_source_root() / 'tests/test-local-adif-file.vala'
  ],
  dependencies: [
    dependency('gio-2.0'),
    dependency('glib-2.0'),
    dependency('gobject-2.0')
  ]
)

test('Local ADIF File Writer', test_local_adif_file)

test_spot_filter = executable(
  'test-spot-filter',
  [
    meson.project_source_root() / 'src/spot_filter.vala',
    meson.project_source_root() / 'tests/test-spot-filter.vala'
  ],
  dependencies: [
    dependency('glib-2.0'),
    dependency('gobject-2.0')
  ]
)

test('Spot Filter', test_spot_filter)

test_wsjtx_logged_adif = executable(
  'test-wsjtx-logged-adif',
  [
    meson.project_source_root() / 'src/adif/adif_types.vala',
    meson.project_source_root() / 'src/adif/adif_parser.vala',
    meson.project_source_root() / 'src/frequency.vala',
    meson.project_source_root() / 'src/logging_preferences.vala',
    meson.project_source_root() / 'src/wsjtx/wsjtx_logged_adif_parser.vala',
    meson.project_source_root() / 'tests/test-wsjtx-logged-adif.vala'
  ],
  dependencies: [
    dependency('gee-0.8'),
    dependency('gio-2.0'),
    dependency('glib-2.0'),
    dependency('gobject-2.0'),
    cc.find_library('m', required: true)
  ]
)

test('WSJT-X Logged ADIF Parser', test_wsjtx_logged_adif)
