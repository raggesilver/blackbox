bundle_executable = 'BlackBox'

macos_conf = configuration_data()
macos_conf.set('APP_NAME', 'Black Box')
macos_conf.set('APP_ID', 'com.raggesilver.BlackBox')
macos_conf.set('VERSION', meson.project_version())
macos_conf.set('BUNDLE_EXECUTABLE', bundle_executable)

info_plist = configure_file(
  input: 'Info.plist.in',
  output: 'Info.plist',
  configuration: macos_conf,
)

rsvg_convert = find_program('rsvg-convert', required: true)

custom_target(
  bundle_executable + '.icns',
  input: '../icons/hicolor/scalable/apps/com.raggesilver.BlackBox.svg',
  output: bundle_executable + '.icns',
  command: [
    'sh',
    meson.current_source_dir() / 'make-icns.sh',
    '@INPUT@',
    '@OUTPUT@',
    rsvg_convert.full_path(),
  ],
  install: true,
  install_dir: get_option('prefix') / 'BlackBox.app/Contents/Resources',
)

bundle_contents = get_option('prefix') / 'BlackBox.app/Contents'

install_data(
  info_plist,
  install_dir: bundle_contents,
)

install_subdir(
  meson.current_source_dir() / 'gtk-css-compat',
  install_dir: bundle_contents / 'Resources',
)

cc = meson.get_compiler('c')

custom_target(
  bundle_executable,
  input: 'blackbox-launcher.c',
  output: bundle_executable,
  command: [cc.cmd_array(), '@INPUT@', '-o', '@OUTPUT@'],
  install: true,
  install_dir: bundle_contents / 'MacOS',
)