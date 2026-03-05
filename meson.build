project(
  'com.k0vcz.Artemis', 
  ['c', 'vala'],
  version: '1.0.3',
  meson_version: '>= 1.0.0',
  default_options: [
    'warning_level=2',
    'werror=false', 
  ],
)

is_windows = host_machine.system() == 'windows'

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

# Setup configuration file
config = configuration_data()
config.set('EXEC_NAME', meson.project_name())
config.set('GETTEXT_PACKAGE', meson.project_name())
config.set('BINDIR', join_paths(get_option('prefix'), get_option('bindir')))
config.set('LOCALEDIR', join_paths(get_option('prefix'), get_option('localedir')))
config.set('DATADIR', join_paths(get_option('prefix'), get_option('datadir')))
config.set('DOMAIN', meson.project_name ())
config.set('G_LOG_DOMAIN', 'Artemis')
config.set('RESOURCES', '/' + '/'.join(meson.project_name().split('.')) + '/')
config.set('VERSION', meson.project_version())
config.set('PREFIX', get_option('prefix'))
config.set('NAME', 'Artemis')
config.set('WEBSITE', '')
config.set('DONATE_WEBSITE', '')
config.set('TRANSLATE_WEBSITE', '')
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

subdir('blueprints')
subdir('data')
subdir('src')
subdir('po')

win_sources = []
windows_exe_link_args = []
if is_windows
  windows = import('windows')
  app_icon_res = windows.compile_resources(
    'data/icons/windows/app.rc',
    depend_files: ['data/icons/windows/com.k0vcz.Artemis.ico'],
  )
  win_sources += app_icon_res
  windows_exe_link_args = ['-mwindows']
endif

link_deps = [
  libradiocontrol
]

if is_windows
  # Windows serial enumeration is compiled into libradiocontrol.
endif

if devel
  vala_args = ['-g', '--save-temps', '--pkg=RadioControl', '--vapidir='+srcdir]
else
  vala_args = ['--pkg=RadioControl', '--vapidir='+srcdir]
endif

executable(meson.project_name(), artemis_vala_sources + [compiled_resources] + win_sources,
  dependencies: artemis_vala_deps,
  vala_args: vala_args,
  link_with: link_deps,
  link_args: windows_exe_link_args,
  win_subsystem: is_windows ? 'windows' : 'console',
  install: true,
)

if not is_windows
  gnome.post_install(
      glib_compile_schemas: true,
      gtk_update_icon_cache: true,
    update_desktop_database: true,
  )
endif
