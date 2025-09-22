project('artemis', ['c', 'vala'],
          version: '0.1.0',
    meson_version: '>= 1.0.0',
  default_options: ['werror=false', ],
)

i18n = import('i18n')
gnome = import('gnome')
valac = meson.get_compiler('vala')


srcdir = meson.project_source_root() / 'src'

config_h = configuration_data()
config_h.set_quoted('PACKAGE_VERSION', meson.project_version ())
config_h.set_quoted('GETTEXT_PACKAGE', 'artemis')
config_h.set_quoted('LOCALEDIR', get_option('prefix') / get_option('localedir'))
configure_file(output: 'config.h', configuration: config_h)

config_dep = valac.find_library ('config', dirs: srcdir)
config_inc = include_directories('.')

add_project_arguments('-DGETTEXT_PACKAGE="' + meson.project_name() + '"', language: 'c')

subdir('blueprints')
subdir('data')
subdir('src')
subdir('po')

executable('artemis', artemis_vala_sources,
  dependencies: artemis_vala_deps,
  include_directories: config_inc,
  vala_args: ['-g', '--save-temps', '--pkg=RadioControl', '--vapidir='+srcdir],
  link_with: libradiocontrol,
  install: true,
)

gnome.post_install(
     glib_compile_schemas: true,
    gtk_update_icon_cache: true,
  update_desktop_database: true,
)

# Code formatting targets
uncrustify = find_program('uncrustify', required: false)
if uncrustify.found()
  run_target('format',
    command: [find_program('bash'), files('format.sh')],
    depends: []
  )

  run_target('check-format',
    command: [find_program('bash'), files('check-format.sh')],
    depends: []
  )
endif
