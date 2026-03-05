#!/usr/bin/env bash
set -euo pipefail

# Build a WiX MSI installer from a prepared Windows bundle.
#
# Intended shell:
#   MSYS2 UCRT32
#
# Prerequisites:
#   - Bundle exists at dist/windows/Artemis (or override BUNDLE_DIR)
#   - WiX v3 tools available in PATH: heat, candle, light
#
# Output:
#   dist/windows/Artemis-Setup-<version>.msi

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUNDLE_DIR="${BUNDLE_DIR:-$ROOT_DIR/dist/windows/Artemis}"
APP_NAME="${APP_NAME:-Artemis}"
APP_VERSION="${APP_VERSION:-$(sed -n "s/^[[:space:]]*version:[[:space:]]*'\\([^']*\\)'.*/\\1/p" "$ROOT_DIR/meson.build" | head -n1)}"
START_MENU_DIR="${START_MENU_DIR:-Artemis}"
APP_ICON="${APP_ICON:-$BUNDLE_DIR/com.k0vcz.Artemis.ico}"

WIX_TEMPLATE="${WIX_TEMPLATE:-$ROOT_DIR/scripts/artemis.wxs}"
WIX_FILES="${WIX_FILES:-$ROOT_DIR/scripts/wix-files.wxs}"
WIX_OBJ_PRODUCT="${WIX_OBJ_PRODUCT:-$ROOT_DIR/scripts/artemis.wixobj}"
WIX_OBJ_FILES="${WIX_OBJ_FILES:-$ROOT_DIR/scripts/wix-files.wixobj}"
OUTPUT_MSI="${OUTPUT_MSI:-$ROOT_DIR/dist/windows/${APP_NAME}-Setup-${APP_VERSION}.msi}"

for tool in heat candle light; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "error: '$tool' not found in PATH (install WiX Toolset v3)" >&2
    exit 1
  fi
done

if [[ ! -d "$BUNDLE_DIR" ]]; then
  echo "error: bundle directory not found: $BUNDLE_DIR" >&2
  exit 1
fi

if [[ ! -f "$BUNDLE_DIR/bin/com.k0vcz.Artemis.exe" ]]; then
  echo "error: expected launcher not found: $BUNDLE_DIR/bin/com.k0vcz.Artemis.exe" >&2
  exit 1
fi

if [[ ! -f "$WIX_TEMPLATE" ]]; then
  echo "error: WiX template not found: $WIX_TEMPLATE" >&2
  exit 1
fi

mkdir -p "$(dirname "$OUTPUT_MSI")"

to_win_path() {
  if command -v cygpath >/dev/null 2>&1; then
    cygpath -w "$1"
  else
    printf '%s\n' "$1"
  fi
}

BUNDLE_DIR_WIN="$(to_win_path "$BUNDLE_DIR")"
WIX_TEMPLATE_WIN="$(to_win_path "$WIX_TEMPLATE")"
WIX_FILES_WIN="$(to_win_path "$WIX_FILES")"
WIX_OBJ_PRODUCT_WIN="$(to_win_path "$WIX_OBJ_PRODUCT")"
WIX_OBJ_FILES_WIN="$(to_win_path "$WIX_OBJ_FILES")"
OUTPUT_MSI_WIN="$(to_win_path "$OUTPUT_MSI")"
APP_ICON_WIN="$(to_win_path "$APP_ICON")"

echo "==> Harvesting bundle files (heat)"
heat dir "$BUNDLE_DIR_WIN" \
  -nologo \
  -gg \
  -srd \
  -dr INSTALLFOLDER \
  -cg ArtemisFiles \
  -var var.BundleDir \
  -out "$WIX_FILES_WIN"

echo "==> Compiling WiX sources (candle)"
candle -nologo \
  -dBundleDir="$BUNDLE_DIR_WIN" \
  -dAppName="$APP_NAME" \
  -dAppVersion="$APP_VERSION" \
  -dStartMenuDir="$START_MENU_DIR" \
  -dAppIcon="$APP_ICON_WIN" \
  -out "$WIX_OBJ_PRODUCT_WIN" \
  "$WIX_TEMPLATE_WIN"

candle -nologo \
  -dBundleDir="$BUNDLE_DIR_WIN" \
  -out "$WIX_OBJ_FILES_WIN" \
  "$WIX_FILES_WIN"

echo "==> Linking MSI (light)"
light -nologo \
  -ext WixUIExtension \
  -out "$OUTPUT_MSI_WIN" \
  "$WIX_OBJ_PRODUCT_WIN" \
  "$WIX_OBJ_FILES_WIN"

echo
echo "MSI created:"
echo "  $OUTPUT_MSI"
