#!/usr/bin/env bash
set -euo pipefail

# Build an NSIS installer from a prepared Windows bundle.
#
# Intended shell:
#   MSYS2 UCRT32
#
# Prerequisites:
#   - Bundle built at dist/windows/Artemis (or override BUNDLE_DIR)
#   - NSIS available in PATH (makensis), e.g. via:
#       nix shell nixpkgs#nsis
#
# Output:
#   dist/windows/Artemis-Setup-<version>.exe

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUNDLE_DIR="${BUNDLE_DIR:-$ROOT_DIR/dist/windows/Artemis}"
APP_NAME="${APP_NAME:-Artemis}"
APP_VERSION="${APP_VERSION:-$(sed -n "s/^[[:space:]]*version:[[:space:]]*'\\([^']*\\)'.*/\\1/p" "$ROOT_DIR/meson.build" | head -n1)}"
OUTPUT_EXE="${OUTPUT_EXE:-$ROOT_DIR/dist/windows/${APP_NAME}-Setup-${APP_VERSION}.exe}"
NSI_SCRIPT="${NSI_SCRIPT:-$ROOT_DIR/scripts/artemis-installer.nsi}"
START_MENU_DIR="${START_MENU_DIR:-Artemis}"
INSTALL_DIR="${INSTALL_DIR:-\$PROGRAMFILES32\\Artemis}"
APP_LAUNCHER="${APP_LAUNCHER:-bin/com.k0vcz.Artemis.exe}"
APP_ICON="${APP_ICON:-$BUNDLE_DIR/com.k0vcz.Artemis.ico}"

if ! command -v makensis >/dev/null 2>&1; then
  echo "error: makensis not found in PATH" >&2
  echo "hint: run under nix shell: nix shell nixpkgs#nsis" >&2
  exit 1
fi

if [[ ! -d "$BUNDLE_DIR" ]]; then
  echo "error: bundle directory not found: $BUNDLE_DIR" >&2
  exit 1
fi

if [[ ! -f "$BUNDLE_DIR/$APP_LAUNCHER" ]]; then
  echo "error: launcher not found in bundle: $BUNDLE_DIR/$APP_LAUNCHER" >&2
  exit 1
fi

if [[ ! -f "$NSI_SCRIPT" ]]; then
  echo "error: NSIS script not found: $NSI_SCRIPT" >&2
  exit 1
fi

mkdir -p "$(dirname "$OUTPUT_EXE")"

to_win_path() {
  if command -v cygpath >/dev/null 2>&1; then
    cygpath -w "$1"
  else
    printf '%s\n' "$1"
  fi
}

BUNDLE_DIR_WIN="$(to_win_path "$BUNDLE_DIR")"
OUTPUT_EXE_WIN="$(to_win_path "$OUTPUT_EXE")"
NSI_SCRIPT_WIN="$(to_win_path "$NSI_SCRIPT")"
APP_ICON_WIN=""
if [[ -f "$APP_ICON" ]]; then
  APP_ICON_WIN="$(to_win_path "$APP_ICON")"
fi
APP_LAUNCHER_NSI="${APP_LAUNCHER//\//\\}"

echo "==> Building NSIS installer"
echo "  Bundle: $BUNDLE_DIR"
echo "  Output: $OUTPUT_EXE"
echo "  Version: $APP_VERSION"

makensis \
  "/DAPP_NAME=$APP_NAME" \
  "/DAPP_VERSION=$APP_VERSION" \
  "/DBUNDLE_DIR=$BUNDLE_DIR_WIN" \
  "/DOUTPUT_EXE=$OUTPUT_EXE_WIN" \
  "/DSTART_MENU_DIR=$START_MENU_DIR" \
  "/DINSTALL_DIR=$INSTALL_DIR" \
  "/DAPP_LAUNCHER=$APP_LAUNCHER_NSI" \
  "/DAPP_ICON=$APP_ICON_WIN" \
  "$NSI_SCRIPT_WIN"

echo
echo "Installer created:"
echo "  $OUTPUT_EXE"
