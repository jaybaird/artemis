application_id = 'com.k0vcz.Artemis'

scalable_dir = 'hicolor' / 'scalable' / 'apps'
install_data(
  scalable_dir / ('@0@.svg').format(application_id),
  install_dir: get_option('datadir') / 'icons' / scalable_dir
)

symbolic_apps_dir = 'hicolor' / 'symbolic' / 'apps'
install_data(
  symbolic_apps_dir / ('@0@-symbolic.svg').format(application_id),
  install_dir: get_option('datadir') / 'icons' / symbolic_apps_dir
)

# Install action icons in application data directory
install_data(
  [
    'hicolor/symbolic/actions/update-symbolic.svg',
    'hicolor/symbolic/actions/history-undo-symbolic.svg',
    'hicolor/symbolic/actions/bullseye-symbolic.svg',
    'hicolor/symbolic/actions/test-pass-symbolic.svg',
    'hicolor/symbolic/actions/radio-console-symbolic.svg',
    'hicolor/symbolic/actions/sound-wave-alt-symbolic.svg',
    'hicolor/symbolic/actions/compass2-symbolic.svg',
    'hicolor/symbolic/actions/distance-symbolic.svg',
    'hicolor/symbolic/actions/map-marker-symbolic.svg',
    'hicolor/symbolic/actions/map-symbolic.svg',
    'hicolor/symbolic/actions/mode-symbolic.svg'
  ],
  install_dir: get_option('datadir') / application_id / 'icons/hicolor/scalable/actions'
)

# Install status icons in application data directory
install_data(
  [
    'hicolor/scalable/status/band-All.svg',
    'hicolor/scalable/status/band-160m.svg',
    'hicolor/scalable/status/band-80m.svg',
    'hicolor/scalable/status/band-60m.svg',
    'hicolor/scalable/status/band-40m.svg',
    'hicolor/scalable/status/band-30m.svg',
    'hicolor/scalable/status/band-20m.svg',
    'hicolor/scalable/status/band-17m.svg',
    'hicolor/scalable/status/band-15m.svg',
    'hicolor/scalable/status/band-12m.svg',
    'hicolor/scalable/status/band-10m.svg',
    'hicolor/scalable/status/band-6m.svg',
    'hicolor/scalable/status/band-2m.svg',
    'hicolor/scalable/status/band-70cm.svg',
  ],
  install_dir: get_option('datadir') / application_id / 'icons/hicolor/scalable/status/'
)
