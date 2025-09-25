inputs = files(
  'add_spot_page.blp',
  'main_window.blp',
  'preferences.blp',
  'spot_card.blp',
  'spot_history_dialog.blp',
  'spot_page.blp',
  'status_page.blp',
  'band_view.blp',
  'park_log_dialog.blp',
)

outs = [
  'add_spot_page.ui',
  'main_window.ui',
  'preferences.ui',
  'spot_card.ui',
  'spot_history_dialog.ui',
  'spot_page.ui',
  'status_page.ui',
  'band_view.ui',
  'park_log_dialog.ui',
]

blueprint_batch = custom_target(
  'blueprints compile',
  input: inputs,
  output: outs,
  command: [
    find_program('blueprint-compiler', required: true), 'batch-compile',
    '@CURRENT_SOURCE_DIR@/../src/ui',
    '@CURRENT_SOURCE_DIR@',
    '@INPUT@'
  ],
  build_by_default: true,
  install: false,
)
