inputs = files(
  'add_spot_page.blp',
  'main_window.blp',
  'astronomy_window.blp',
  'help_window.blp',
  'preferences.blp',
  'spot_card.blp',
  'spot_history_dialog.blp',
  'spot_page.blp',
  'spot_list_view.blp',
  'spot_list_row.blp',
  'band_view.blp',
  'status_bar.blp',
  'park_log_dialog.blp',
  'left_sidebar.blp',
  'spot_detail.blp',
  'band_button.blp'
)

outs = [
  'add_spot_page.ui',
  'main_window.ui',
  'astronomy_window.ui',
  'help_window.ui',
  'preferences.ui',
  'spot_card.ui',
  'spot_history_dialog.ui',
  'spot_page.ui',
  'spot_list_view.ui',
  'spot_list_row.ui',
  'band_view.ui',
  'status_bar.ui',
  'park_log_dialog.ui',
  'left_sidebar.ui',
  'spot_detail.ui',
  'band_button.ui'
]

blueprint_batch = custom_target(
  'blueprints compile',
  input: inputs,
  output: outs,
  command: [
    find_program('blueprint-compiler', required: true), 'batch-compile',
    '@CURRENT_SOURCE_DIR@/../data/ui',
    '@CURRENT_SOURCE_DIR@',
    '@INPUT@'
  ],
  build_by_default: true,
  install: false,
)
