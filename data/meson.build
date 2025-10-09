desktop_file = i18n.merge_file(
        input: 'com.k0vcz.Artemis.desktop.in',
       output: 'com.k0vcz.Artemis.desktop',
         type: 'desktop',
       po_dir: '../po',
      install: true,
  install_dir: get_option('datadir') / 'applications'
)

desktop_utils = find_program('desktop-file-validate', required: false)
if desktop_utils.found()
  test('Validate desktop file', desktop_utils, args: [desktop_file])
endif

appstream_file = i18n.merge_file(
        input: 'com.k0vcz.Artemis.metainfo.xml.in',
       output: 'com.k0vcz.Artemis.metainfo.xml',
       po_dir: '../po',
      install: true,
  install_dir: get_option('datadir') / 'metainfo'
)

appstreamcli = find_program('appstreamcli', required: false, disabler: true)
test('Validate appstream file', appstreamcli,
     args: ['validate', '--no-net', '--explain', appstream_file])

install_data('com.k0vcz.Artemis.gschema.xml',
  install_dir: get_option('datadir') / 'glib-2.0' / 'schemas'
)

compile_schemas = find_program('glib-compile-schemas', required: false, disabler: true)
test('Validate schema file',
     compile_schemas,
     args: ['--strict', '--dry-run', meson.current_source_dir()])


service_conf = configuration_data()
service_conf.set('bindir', get_option('prefix') / get_option('bindir'))
configure_file(
  input: 'com.k0vcz.Artemis.service.in',
  output: 'com.k0vcz.Artemis.service',
  configuration: service_conf,
  install_dir: get_option('datadir') / 'dbus-1' / 'services'
)

subdir('icons')

compiled_resources = gnome.compile_resources('artemis-vala-resources',
  'artemis-vala.gresource.xml',
  dependencies: blueprint_batch,
  c_name: 'artemis_vala'
)
