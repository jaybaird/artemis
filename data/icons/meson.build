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
    'hicolor/symbolic/actions/media-playback-pause-symbolic.svg',
    'hicolor/symbolic/actions/clock-alt-symbolic.svg',
    'hicolor/symbolic/actions/clocks-symbolic.svg',
    'hicolor/symbolic/actions/grid-filled-symbolic.svg',
    'hicolor/symbolic/actions/bullseye-symbolic.svg',
    'hicolor/symbolic/actions/verified-checkmark-symbolic.svg',
    'hicolor/symbolic/actions/radio-console-symbolic.svg',
    'hicolor/symbolic/actions/sound-wave-alt-symbolic.svg',
    'hicolor/symbolic/actions/sound-wave-add-symbolic.svg',
    'hicolor/symbolic/actions/big-dot-symbolic.svg',
    'hicolor/symbolic/actions/bigger-dot-symbolic.svg',
    'hicolor/symbolic/actions/arrow-circular-bottom-right-symbolic.svg',
    'hicolor/symbolic/actions/dock-right-symbolic.svg',
    'hicolor/symbolic/actions/map-layers-symbolic.svg',
    'hicolor/symbolic/actions/map-marker-symbolic.svg',
    'hicolor/symbolic/actions/map-symbolic.svg',
    'hicolor/symbolic/actions/filter-symbolic.svg',
    'hicolor/symbolic/actions/clouds-outline-symbolic.svg',
    'hicolor/symbolic/actions/few-clouds-outline-symbolic.svg',
    'hicolor/symbolic/actions/fog-symbolic.svg',
    'hicolor/symbolic/actions/globe-alt2-symbolic.svg',
    'hicolor/symbolic/actions/grid-symbolic.svg',
    'hicolor/symbolic/actions/user-home-symbolic.svg',
    'hicolor/symbolic/actions/moon-clouds-outline-symbolic.svg',
    'hicolor/symbolic/actions/moon-outline-symbolic.svg',
    'hicolor/symbolic/actions/rain-outline-symbolic.svg',
    'hicolor/symbolic/actions/rain-scattered-outline-symbolic.svg',
    'hicolor/symbolic/actions/snow-outline-symbolic.svg',
    'hicolor/symbolic/actions/storm-outline-symbolic.svg',
    'hicolor/symbolic/actions/sun-outline-symbolic.svg',
    'hicolor/symbolic/actions/windy-symbolic.svg',
    'hicolor/symbolic/actions/thermometer-symbolic.svg',
    'hicolor/symbolic/actions/drop-hollow-symbolic.svg',
    'hicolor/symbolic/actions/encoder-knob-symbolic.svg',
    'hicolor/symbolic/actions/headphones-symbolic.svg',
    'hicolor/symbolic/actions/daytime-sunrise-symbolic.svg',
    'hicolor/symbolic/actions/daytime-sunset-symbolic.svg',
    'hicolor/symbolic/actions/moonrise-symbolic.svg',
    'hicolor/symbolic/actions/moonset-symbolic.svg'
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
