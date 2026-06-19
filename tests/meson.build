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

test_wsjtx_decode_matcher = executable(
  'test-wsjtx-decode-matcher',
  [
    meson.project_source_root() / 'src/string_utils.vala',
    meson.project_source_root() / 'src/wsjtx/wsjtx_decode_matcher.vala',
    meson.project_source_root() / 'tests/test-wsjtx-decode-matcher.vala'
  ],
  dependencies: [
    dependency('gee-0.8'),
    dependency('glib-2.0')
  ]
)

test('WSJT-X Decode Matcher', test_wsjtx_decode_matcher)

adif_test_sources = [
  meson.project_source_root() / 'src/string_utils.vala',
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

test_operating_limits = executable(
  'test-operating-limits',
  [
    meson.project_source_root() / 'src/frequency.vala',
    meson.project_source_root() / 'src/operating_limits.vala',
    meson.project_source_root() / 'tests/test-operating-limits.vala'
  ],
  dependencies: [
    dependency('gee-0.8'),
    dependency('gio-2.0'),
    dependency('glib-2.0'),
    dependency('gobject-2.0'),
    dependency('json-glib-1.0'),
    cc.find_library('m', required: true)
  ]
)

test('Operating Limits', test_operating_limits)

test_astronomy = executable(
  'test-astronomy',
  [
    meson.project_source_root() / 'src/string_utils.vala',
    meson.project_source_root() / 'src/distance.vala',
    meson.project_source_root() / 'src/utils/map.vala',
    meson.project_source_root() / 'src/utils/maidenhead.vala',
    meson.project_source_root() / 'src/astronomy.vala',
    meson.project_source_root() / 'tests/test-astronomy.vala'
  ],
  dependencies: [
    dependency('gee-0.8'),
    dependency('glib-2.0'),
    dependency('gobject-2.0'),
    dependency('shumate-1.0'),
    cc.find_library('m', required: true)
  ]
)

test('Astronomy', test_astronomy)

test_csv_parser = executable(
  'test-csv-parser',
  [
    meson.project_source_root() / 'src/csv/csv_parser.vala',
    meson.project_source_root() / 'tests/test-csv-parser.vala'
  ],
  dependencies: [
    dependency('gee-0.8'),
    dependency('gio-2.0'),
    dependency('glib-2.0'),
    dependency('gobject-2.0')
  ]
)

test('CSV Parser', test_csv_parser)

test_logbook_import = executable(
  'test-logbook-import',
	  [
	    meson.project_source_root() / 'src/csv/csv_parser.vala',
	    meson.project_source_root() / 'src/input_parsing.vala',
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

test_park_details_cache = executable(
  'test-park-details-cache',
  [
    meson.project_source_root() / 'src/park_details.vala',
    meson.project_source_root() / 'src/park_details_cache.vala',
    meson.project_source_root() / 'tests/test-park-details-cache.vala'
  ],
  dependencies: [
    dependency('gee-0.8'),
    dependency('gio-2.0'),
    dependency('glib-2.0'),
    dependency('gobject-2.0')
  ]
)

test('Park Details Cache', test_park_details_cache)

test_callsign_cache = executable(
  'test-callsign-cache',
  [
    meson.project_source_root() / 'src/activator.vala',
    meson.project_source_root() / 'src/callsign_cache.vala',
    meson.project_source_root() / 'src/http_session_factory.vala',
    meson.project_source_root() / 'src/utils/callsign_utils.vala',
    meson.project_build_root() / 'src/build.vala',
    meson.project_source_root() / 'tests/test-callsign-cache.vala'
  ],
  dependencies: [
    dependency('gee-0.8'),
    dependency('gio-2.0'),
    dependency('glib-2.0'),
    dependency('gobject-2.0'),
    dependency('gtk4'),
    dependency('json-glib-1.0'),
    dependency('libsoup-3.0'),
    dependency('glycin-2'),
    dependency('glycin-gtk4-2')
  ]
)

test('Callsign Cache', test_callsign_cache)

test_weather_cache = executable(
  'test-weather-cache',
  [
    meson.project_source_root() / 'src/string_utils.vala',
    meson.project_source_root() / 'src/distance.vala',
    meson.project_source_root() / 'src/utils/map.vala',
    meson.project_source_root() / 'src/utils/maidenhead.vala',
    meson.project_source_root() / 'src/http_session_factory.vala',
    meson.project_source_root() / 'src/weather_cache.vala',
    meson.project_build_root() / 'src/build.vala',
    meson.project_source_root() / 'tests/test-weather-cache.vala'
  ],
  dependencies: [
    dependency('gee-0.8'),
    dependency('gio-2.0'),
    dependency('glib-2.0'),
    dependency('gobject-2.0'),
    dependency('json-glib-1.0'),
    dependency('libsoup-3.0'),
    dependency('shumate-1.0'),
    cc.find_library('m', required: true)
  ]
)

test('Weather Cache', test_weather_cache)

test_space_weather_client = executable(
  'test-space-weather-client',
  [
    meson.project_source_root() / 'src/csv/csv_parser.vala',
    meson.project_source_root() / 'src/http_session_factory.vala',
    meson.project_source_root() / 'src/space_weather_snapshot.vala',
    meson.project_source_root() / 'src/space_weather_client.vala',
    meson.project_build_root() / 'src/build.vala',
    meson.project_source_root() / 'tests/test-space-weather-client.vala'
  ],
  dependencies: [
    dependency('gee-0.8'),
    dependency('gio-2.0'),
    dependency('glib-2.0'),
    dependency('gobject-2.0'),
    dependency('json-glib-1.0'),
    dependency('libsoup-3.0'),
    cc.find_library('m', required: true)
  ]
)

test('Space Weather Client', test_space_weather_client)

test_database = executable(
  'test-database',
  [
    meson.project_source_root() / 'src/frequency.vala',
    meson.project_source_root() / 'src/string_utils.vala',
    meson.project_source_root() / 'src/database.vala',
    meson.project_source_root() / 'tests/test-database.vala',
    compiled_resources
  ],
  dependencies: [
    dependency('gee-0.8'),
    dependency('gio-2.0'),
    dependency('glib-2.0'),
    dependency('gobject-2.0'),
    dependency('sqlite3'),
    cc.find_library('m', required: true)
  ]
)

test('Database Schema and Queries', test_database)

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
    meson.project_source_root() / 'src/frequency.vala',
    meson.project_source_root() / 'src/operating_limits.vala',
    meson.project_source_root() / 'src/spot_filter.vala',
    meson.project_source_root() / 'tests/test-spot-filter.vala'
  ],
  dependencies: [
    dependency('gee-0.8'),
    dependency('gio-2.0'),
    dependency('glib-2.0'),
    dependency('gobject-2.0'),
    dependency('json-glib-1.0'),
    cc.find_library('m', required: true)
  ]
)

test('Spot Filter', test_spot_filter)

test_spot_alert_matcher = executable(
  'test-spot-alert-matcher',
  [
    meson.project_source_root() / 'src/utils/callsign_utils.vala',
    meson.project_source_root() / 'src/spot_alert_matcher.vala',
    meson.project_source_root() / 'tests/test-spot-alert-matcher.vala'
  ],
  dependencies: [
    dependency('gee-0.8'),
    dependency('glib-2.0'),
    dependency('gobject-2.0')
  ]
)

test('Spot Alert Matcher', test_spot_alert_matcher)

test_heatmap_model = executable(
  'test-heatmap-model',
  [
    meson.project_source_root() / 'src/string_utils.vala',
    meson.project_source_root() / 'src/distance.vala',
    meson.project_source_root() / 'src/utils/map.vala',
    meson.project_source_root() / 'src/utils/maidenhead.vala',
    meson.project_source_root() / 'src/utils/callsign_utils.vala',
    meson.project_source_root() / 'src/frequency.vala',
    meson.project_source_root() / 'src/models/heatmap_model.vala',
    meson.project_source_root() / 'src/models/heatmap_point.vala',
    meson.project_source_root() / 'src/models/signal_report.vala',
    meson.project_source_root() / 'src/models/signal_report_bucket.vala',
    meson.project_source_root() / 'src/psk_reporter_client.vala',
    meson.project_source_root() / 'src/psk_reporter_decoder.vala',
    meson.project_build_root() / 'src/build.vala',
    meson.project_source_root() / 'tests/test-heatmap-model.vala'
  ],
  dependencies: [
    dependency('gee-0.8'),
    dependency('gio-2.0'),
    dependency('glib-2.0'),
    dependency('gobject-2.0'),
    dependency('json-glib-1.0'),
    dependency('libsoup-3.0'),
    dependency('libxml-2.0'),
    dependency('shumate-1.0'),
    cc.find_library('m', required: true)
  ]
)

test('Heatmap Model', test_heatmap_model)

test_wsjtx_logged_adif = executable(
  'test-wsjtx-logged-adif',
  [
    meson.project_source_root() / 'src/adif/adif_types.vala',
    meson.project_source_root() / 'src/adif/adif_parser.vala',
    meson.project_source_root() / 'src/adif/adif_generator.vala',
    meson.project_source_root() / 'src/frequency.vala',
    meson.project_source_root() / 'src/spot_lookup.vala',
    meson.project_source_root() / 'src/string_utils.vala',
    meson.project_source_root() / 'src/utils/callsign_utils.vala',
    meson.project_source_root() / 'src/logging_service.vala',
    meson.project_source_root() / 'src/logging_preferences.vala',
    meson.project_source_root() / 'src/wsjtx/wsjtx_packet.vala',
    meson.project_source_root() / 'src/wsjtx/wsjtx_logged_adif_parser.vala',
    meson.project_source_root() / 'src/wsjtx/wsjtx_logged_adif_handler.vala',
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
