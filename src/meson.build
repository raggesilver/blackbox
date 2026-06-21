blackbox_cli = 'blackbox-terminal'

blackbox_sources = files(
  'Application.vala',
  'CommandLine.vala',
  'main.vala',
)

subdir('widgets')
subdir('services')
subdir('utils')

conf_data = configuration_data()
conf_data.set_quoted('PROJECT_NAME', meson.project_name())
conf_data.set_quoted('PROJECT_EXE', blackbox_cli)
conf_data.set_quoted('GETTEXT_PACKAGE', meson.project_name())
conf_data.set_quoted('VERSION', meson.project_version())
conf_data.set_quoted('PREFIX', get_option('prefix'))
conf_data.set_quoted('DATADIR', join_paths(get_option('prefix'), get_option('datadir')))
conf_data.set_quoted('LOCALEDIR', join_paths(get_option('prefix'), get_option('localedir')))
conf_data.set('DEVEL', get_option('devel').to_string().to_lower())

config_header = configure_file(input: 'config.vala.in', output: 'config.vala', configuration: conf_data)

blackbox_deps = [
  dependency('gio-2.0', version: '>= 2.50'),
  dependency('gtk4', version: '>= 4.12.0'),
  dependency('libadwaita-1', version: '>= 1.4'),
  dependency('vte-2.91-gtk4', version: '>= 0.69.0'),
  dependency('json-glib-1.0', version: '>= 1.4.4'),
  dependency('libpcre2-8'),
  dependency('libxml-2.0', version: '>= 2.9.12'),
  dependency('librsvg-2.0', version: '>= 2.54.0'),
  dependency('gee-0.8', version: '>=0.20'),
  dependency('graphene-gobject-1.0'),
  meson.get_compiler('vala').find_library('posix'),
]

vapi_dir = meson.current_source_dir() / 'vapi'
add_project_arguments('--vapidir=' + vapi_dir, language: 'vala')

# We add `-w` because the C code Vala generates has a bunch of unused variables
# which keep polluting the build output with warnings.
add_project_arguments(['-DPCRE2_CODE_UNIT_WIDTH=0', '-w'], language: 'c')

if get_option('blackbox_debug_memory')
  add_project_arguments('-D', 'BLACKBOX_DEBUG_MEMORY', language: 'vala')
endif

if host_machine.system() == 'darwin'
  add_project_arguments('--define=MACOS', language: 'vala')
endif

gnome = import('gnome')

blackbox_sources += gnome.compile_resources('blackbox-resources', 'blackbox.gresource.xml', c_name: 'blackbox')

blackbox_exe = executable(
  blackbox_cli,
  blackbox_sources,
  config_header,
  vala_args: '--target-glib=2.50',
  dependencies: blackbox_deps,
  install: true,
)

# The Adwaita theme prints several thousand warnings when running apps in macOS,
# mostly "Expected ';' at the end of the block". Here we use environment
# variables to override the theme and avoid those warnings.
if host_machine.system() == 'darwin'
  gtk_css_compat_dir = meson.project_source_root() / 'data' / 'gtk-css-compat'

  run_target(
    'run',
    command: blackbox_exe,
    env: {
      'G_RESOURCE_OVERLAYS': '/org/gnome/Adwaita=' + gtk_css_compat_dir,
    },
  )
endif