project(
  'com.k0vcz.Artemis', 
  ['c', 'vala'],
  version: '2.2',
  meson_version: '>= 1.0.0',
  default_options: [
    'warning_level=2',
    'werror=false', 
  ],
)

i18n = import('i18n')
gnome = import('gnome')
valac = meson.get_compiler('vala')

prefix = get_option('prefix')
data_dir = prefix / get_option('datadir')
srcdir = meson.project_source_root() / 'src'

# https://gitlab.gnome.org/GNOME/vala/-/issues/1413#note_1707480
if meson.get_compiler ('c').get_id () == 'clang'
  add_project_arguments('-Wno-incompatible-function-pointer-types', language: 'c')
endif

devel = get_option('debug')
valgrind_friendly = get_option('valgrind_friendly')

# Setup configuration file
config = configuration_data()
config.set('EXEC_NAME', meson.project_name())
config.set('GETTEXT_PACKAGE', meson.project_name())
config.set('BINDIR', join_paths(get_option('prefix'), get_option('bindir')))
config.set('LOCALEDIR', join_paths(get_option('prefix'), get_option('localedir')))
config.set('DATADIR', join_paths(get_option('prefix'), get_option('datadir')))
config.set('DOMAIN', meson.project_name ())
config.set('G_LOG_DOMAIN', 'Trailwave')
config.set('RESOURCES', '/' + '/'.join(meson.project_name().split('.')) + '/')
config.set('VERSION', meson.project_version())
config.set('PREFIX', get_option('prefix'))
config.set('NAME', 'Trailwave')
config.set('TARGET', host_machine.system())
config.set('WEBSITE', 'https://gettrailwave.app/linux')
config.set('DONATE_WEBSITE', 'https://buymeacoffee.com/k0vcz')
config.set('TRANSLATE_WEBSITE', '')
config.set('OPENWEATHER_API_KEY', get_option('openweather_api_key'))
config.set('MAPBOX_ACCESS_TOKEN', get_option('mapbox_access_token'))
config.set('MAPBOX_STYLE_OWNER', get_option('mapbox_style_owner'))
config.set('MAPBOX_LIGHT_STYLE_ID', get_option('mapbox_light_style_id'))
config.set('MAPBOX_DARK_STYLE_ID', get_option('mapbox_dark_style_id'))
config.set('PROFILE', devel ? 'development' : 'release')

if devel
  git = find_program('git')
  if git.found()
    branch = run_command('git', 'branch', '--show-current', check: true).stdout().strip()
    revision = run_command('git', 'rev-parse', '--short', 'HEAD', check: true).stdout().strip()
    version = '@0@-@1@'.format(branch, revision)
    config.set('VERSION', version)
  endif
endif

add_project_arguments('-DGETTEXT_PACKAGE="' + meson.project_name() + '"', language: 'c')

if valgrind_friendly
  add_project_arguments(
    [
      '-O0',
      '-fno-omit-frame-pointer',
      '-fno-inline',
      '-fno-inline-functions',
      '-fno-inline-small-functions'
    ],
    language: 'c'
  )
endif

subdir('blueprints')
subdir('data')
subdir('src')
subdir('po')
subdir('tests')

link_deps = [
  libradiocontrol,
  libartemismqtt,
  libzonedetect,
  libheatmap
]

if devel
  vala_args = ['-g', '--save-temps', '--pkg=RadioControl', '--pkg=Mqtt', '--pkg=heatmap', '--pkg=ZoneDetect', '--vapidir='+srcdir, '--vapidir='+srcdir / 'radio', '--vapidir='+srcdir / 'mqtt', '--vapidir='+srcdir / 'map', '--vapidir='+srcdir / 'tz']
else
  vala_args = ['--pkg=RadioControl', '--pkg=Mqtt', '--pkg=heatmap', '--pkg=ZoneDetect', '--vapidir='+srcdir, '--vapidir='+srcdir / 'radio', '--vapidir='+srcdir / 'mqtt', '--vapidir='+srcdir / 'map', '--vapidir='+srcdir / 'tz']
endif

artemis_exe = executable(meson.project_name(), artemis_vala_sources + [compiled_resources],
  dependencies: artemis_vala_deps,
  vala_args: vala_args,
  include_directories: src_inc,
  link_with: link_deps,
  install: true,
)

valgrind = find_program('valgrind', required: false)
if valgrind.found()
  valgrind_env = environment()
  valgrind_env.set('G_DEBUG', 'gc-friendly')
  valgrind_env.set('G_SLICE', 'always-malloc')
  valgrind_env.set('GSETTINGS_SCHEMA_DIR', meson.project_build_root() / 'data')

  run_target(
    'valgrind-memcheck',
    command: [
      valgrind,
      '--tool=memcheck',
      '--leak-check=full',
      '--show-leak-kinds=definite,indirect,possible',
      '--track-origins=yes',
      '--num-callers=40',
      '--log-file=' + meson.project_build_root() / 'valgrind-artemis-%p.log',
      artemis_exe,
    ],
    env: valgrind_env,
  )

  run_target(
    'valgrind-massif',
    command: [
      valgrind,
      '--tool=massif',
      '--time-unit=ms',
      '--detailed-freq=100',
      '--max-snapshots=200',
      '--massif-out-file=' + meson.project_build_root() / 'massif-artemis-%p.out',
      artemis_exe,
    ],
    env: valgrind_env,
  )
endif

gnome.post_install(
    glib_compile_schemas: true,
    gtk_update_icon_cache: true,
  update_desktop_database: true,
)
