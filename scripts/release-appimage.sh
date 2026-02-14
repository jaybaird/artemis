#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="${BUILD_DIR:-$ROOT_DIR/build-appimage}"
APPDIR_PATH="${APPDIR_PATH:-$ROOT_DIR/AppDir}"
RECIPE_PATH="${RECIPE_PATH:-$ROOT_DIR/packaging/appimage/AppImageBuilder.yml}"
DIST_DIR="${DIST_DIR:-$ROOT_DIR/dist/appimage}"

for cmd in meson ninja appimage-builder glib-compile-schemas; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "Missing required tool: $cmd" >&2
    exit 1
  fi
done

rm -rf "$BUILD_DIR" "$APPDIR_PATH" "$DIST_DIR"
mkdir -p "$DIST_DIR"

meson setup "$BUILD_DIR" \
  --buildtype=release \
  --prefix=/usr

meson compile -C "$BUILD_DIR"
DESTDIR="$APPDIR_PATH" meson install -C "$BUILD_DIR"

glib-compile-schemas "$APPDIR_PATH/usr/share/glib-2.0/schemas"

(
  cd "$ROOT_DIR"
  appimage-builder --skip-test --recipe "$RECIPE_PATH"
)

find "$ROOT_DIR" -maxdepth 1 -name '*.AppImage' -print0 | while IFS= read -r -d '' file; do
  mv "$file" "$DIST_DIR/"
done

echo "AppImage artifact(s) available in: $DIST_DIR"
