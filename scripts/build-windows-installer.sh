#!/usr/bin/env bash
set -euo pipefail

# Build a WiX v4 MSI installer from a prepared Windows bundle.
#
# Intended shell:
#   MSYS2 UCRT32
#
# Prerequisites:
#   - Bundle exists at dist/windows/Artemis (or override BUNDLE_DIR)
#   - WiX v4 CLI available, either:
#       - wix (global dotnet tool shim), or
#       - dotnet tool run wix (local tool manifest)
#
# Output:
#   dist/windows/Artemis-Setup-<version>.msi

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUNDLE_DIR="${BUNDLE_DIR:-$ROOT_DIR/dist/windows/Artemis}"
APP_NAME="${APP_NAME:-Artemis}"
APP_VERSION="${APP_VERSION:-$(sed -n "s/^[[:space:]]*version:[[:space:]]*'\\([^']*\\)'.*/\\1/p" "$ROOT_DIR/meson.build" | head -n1)}"
START_MENU_DIR="${START_MENU_DIR:-Artemis}"
APP_ICON="${APP_ICON:-$BUNDLE_DIR/com.k0vcz.Artemis.ico}"
WIX_ARCH="${WIX_ARCH:-x86}"

WIX_TEMPLATE="${WIX_TEMPLATE:-$ROOT_DIR/scripts/artemis.wxs}"
OUTPUT_MSI="${OUTPUT_MSI:-$ROOT_DIR/dist/windows/${APP_NAME}-Setup-${APP_VERSION}.msi}"

if command -v wix >/dev/null 2>&1; then
  WIX_CMD=(wix)
elif command -v dotnet >/dev/null 2>&1; then
  if dotnet tool run wix --help >/dev/null 2>&1; then
    WIX_CMD=(dotnet tool run wix)
  else
    echo "error: WiX v4 CLI not found. Install with: dotnet tool install --global wix" >&2
    exit 1
  fi
else
  echo "error: neither 'wix' nor 'dotnet' is available in PATH" >&2
  exit 1
fi

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
OUTPUT_MSI_WIN="$(to_win_path "$OUTPUT_MSI")"
APP_ICON_WIN="$(to_win_path "$APP_ICON")"

echo "==> Building MSI (wix build)"
"${WIX_CMD[@]}" build \
  -nologo \
  -arch "$WIX_ARCH" \
  -d BundleDir="$BUNDLE_DIR_WIN" \
  -d AppName="$APP_NAME" \
  -d AppVersion="$APP_VERSION" \
  -d StartMenuDir="$START_MENU_DIR" \
  -d AppIcon="$APP_ICON_WIN" \
  -o "$OUTPUT_MSI_WIN" \
  "$WIX_TEMPLATE_WIN"

echo
echo "MSI created:"
echo "  $OUTPUT_MSI"
