#!/usr/bin/env bash
set -euo pipefail

# Build an installer-ready Windows bundle from an MSYS2 UCRT shell.
#
# Recommended shell:
#   MSYS2 UCRT64 (or UCRT32 if your toolchain is 32-bit)
#
# Output:
#   dist/windows/Artemis/
#     bin/
#     lib/
#     share/
#
# You can feed dist/windows/Artemis into your installer tool (e.g. Inno Setup).

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="${BUILD_DIR:-$ROOT_DIR/build-windows}"
DESTDIR="${DESTDIR:-$ROOT_DIR/dist/windows/stage}"
BUNDLE_DIR="${BUNDLE_DIR:-$ROOT_DIR/dist/windows/Artemis}"
BUILD_TYPE="${BUILD_TYPE:-release}"
APP_EXE_NAME="${APP_EXE_NAME:-com.k0vcz.Artemis.exe}"
ICON_SVG="${ICON_SVG:-$ROOT_DIR/data/icons/hicolor/scalable/apps/com.k0vcz.Artemis.svg}"
ICON_ICO_BUILD="${ICON_ICO_BUILD:-$ROOT_DIR/data/icons/windows/com.k0vcz.Artemis.ico}"
ICON_ICO_BUNDLE="${ICON_ICO_BUNDLE:-$BUNDLE_DIR/com.k0vcz.Artemis.ico}"
MINGW_PREFIX="${MINGW_PREFIX:-}"

if ! command -v meson >/dev/null 2>&1; then
  echo "error: meson not found in PATH" >&2
  exit 1
fi

if ! command -v ninja >/dev/null 2>&1; then
  echo "error: ninja not found in PATH" >&2
  exit 1
fi

if ! command -v glib-compile-schemas >/dev/null 2>&1; then
  echo "error: glib-compile-schemas not found in PATH" >&2
  exit 1
fi

mkdir -p "$ROOT_DIR/dist/windows"
rm -rf "$DESTDIR" "$BUNDLE_DIR"
mkdir -p "$DESTDIR" "$BUNDLE_DIR"

if [[ -z "$MINGW_PREFIX" ]]; then
  echo "error: MINGW_PREFIX is not set. Run from an MSYS2 MinGW/UCRT shell." >&2
  exit 1
fi
echo "==> Using MINGW_PREFIX: $MINGW_PREFIX"

build_windows_icon() {
  echo "==> Building Windows .ico from SVG"
  if [[ ! -f "$ICON_SVG" ]]; then
    echo "warning: SVG icon not found at $ICON_SVG; skipping .ico generation" >&2
    return 0
  fi

  mkdir -p "$(dirname "$ICON_ICO_BUILD")"
  if command -v magick >/dev/null 2>&1; then
    magick "$ICON_SVG" \
      -background none \
      -define icon:auto-resize=16,24,32,48,64,128,256 \
      "$ICON_ICO_BUILD"
  elif command -v rsvg-convert >/dev/null 2>&1 && command -v convert >/dev/null 2>&1; then
    tmp_png="$(mktemp --suffix=.png)"
    rsvg-convert -w 256 -h 256 "$ICON_SVG" -o "$tmp_png"
    convert "$tmp_png" \
      -background none \
      -define icon:auto-resize=16,24,32,48,64,128,256 \
      "$ICON_ICO_BUILD"
    rm -f "$tmp_png"
  else
    echo "warning: neither 'magick' nor ('rsvg-convert' + 'convert') found; skipping .ico generation" >&2
    return 0
  fi

  echo "  + $(realpath --relative-to="$ROOT_DIR" "$ICON_ICO_BUILD" 2>/dev/null || echo "$ICON_ICO_BUILD")"
}

build_windows_icon

echo "==> Configuring Meson build dir: $BUILD_DIR"
meson setup "$BUILD_DIR" \
  --wipe \
  --buildtype "$BUILD_TYPE" \
  --prefix /

echo "==> Compiling"
meson compile -C "$BUILD_DIR"

echo "==> Installing to staged DESTDIR: $DESTDIR"
meson install -C "$BUILD_DIR" --destdir "$DESTDIR"

# Meson on Windows/MSYS can stage under DESTDIR/<prefix>/... (e.g. DESTDIR/msys64/bin).
STAGE_ROOT=""
APP_STAGE_EXE="$(find "$DESTDIR" -type f -name "$APP_EXE_NAME" | head -n 1 || true)"
if [[ -z "$APP_STAGE_EXE" ]]; then
  echo "error: missing staged executable '$APP_EXE_NAME' under $DESTDIR" >&2
  exit 1
fi

APP_STAGE_DIR="$(dirname "$APP_STAGE_EXE")"
if [[ "$(basename "$APP_STAGE_DIR")" != "bin" ]]; then
  echo "error: staged executable not under a bin directory: $APP_STAGE_EXE" >&2
  exit 1
fi
STAGE_ROOT="$(dirname "$APP_STAGE_DIR")"

if [[ ! -d "$STAGE_ROOT/bin" ]]; then
  echo "error: detected stage root has no bin dir: $STAGE_ROOT" >&2
  exit 1
fi

echo "==> Detected staged install root: $STAGE_ROOT"

echo "==> Copying staged install to bundle dir: $BUNDLE_DIR"
cp -a "$STAGE_ROOT/." "$BUNDLE_DIR/"

if [[ ! -f "$BUNDLE_DIR/bin/$APP_EXE_NAME" ]]; then
  echo "error: missing app executable: $BUNDLE_DIR/bin/$APP_EXE_NAME" >&2
  exit 1
fi

copy_runtime_deps() {
  local target="$1"
  local dep
  local dep_list

  if command -v ntldd >/dev/null 2>&1; then
    dep_list="$(ntldd -R "$target" 2>/dev/null | awk '
      /=>/ {print $3}
      /^[A-Za-z]:\\/ {print $1}
      /^\/(ucrt64|ucrt32|mingw64|mingw32|clang64|clang32)\// {print $1}
    ' | tr -d "\r" | sort -u)"
  else
    dep_list="$(ldd "$target" 2>/dev/null | awk '/=> \// {print $3}' | tr -d "\r" | sort -u)"
  fi

  while IFS= read -r dep; do
    [[ -z "$dep" ]] && continue
    [[ ! -f "$dep" ]] && continue

    local base
    base="$(basename "$dep")"
    if [[ ! -f "$BUNDLE_DIR/bin/$base" ]]; then
      cp -f "$dep" "$BUNDLE_DIR/bin/"
      echo "  + $base"
    fi
  done <<< "$dep_list"
}

copy_first_existing_tree() {
  local dst="$1"
  shift
  local src
  for src in "$@"; do
    if [[ -d "$src" ]]; then
      mkdir -p "$(dirname "$dst")"
      rm -rf "$dst"
      cp -a "$src" "$dst"
      echo "  + $(realpath --relative-to="$ROOT_DIR" "$dst" 2>/dev/null || echo "$dst") <= $src"
      return 0
    fi
  done
  return 1
}

echo "==> Copying runtime DLL dependencies"
for pass in 1 2 3; do
  echo "  pass $pass"
  shopt -s nullglob
  for f in "$BUNDLE_DIR/bin/"*.exe "$BUNDLE_DIR/bin/"*.dll; do
    copy_runtime_deps "$f"
  done
  shopt -u nullglob
done

# Bundle GIO modules (includes glib-networking TLS backend) explicitly.
echo "==> Bundling GIO modules"
if ! copy_first_existing_tree \
  "$BUNDLE_DIR/lib/gio/modules" \
  "$MINGW_PREFIX/lib/gio/modules"
then
  echo "warning: could not find source gio/modules directory; TLS may fail at runtime" >&2
fi

# Bundle GDK Pixbuf loaders/modules explicitly.
echo "==> Bundling GDK Pixbuf loaders"
if ! copy_first_existing_tree \
  "$BUNDLE_DIR/lib/gdk-pixbuf-2.0" \
  "$MINGW_PREFIX/lib/gdk-pixbuf-2.0"
then
  echo "warning: could not find source gdk-pixbuf-2.0 directory; image loader support may be incomplete" >&2
fi

# Ensure schemas are compiled inside the staged bundle.
SCHEMA_DIR="$BUNDLE_DIR/share/glib-2.0/schemas"
if [[ ! -d "$SCHEMA_DIR" ]]; then
  mkdir -p "$SCHEMA_DIR"
fi

if [[ ! -f "$SCHEMA_DIR/com.k0vcz.Artemis.gschema.xml" ]] && [[ -f "$ROOT_DIR/data/com.k0vcz.Artemis.gschema.xml" ]]; then
  echo "==> Restoring missing app schema into bundle"
  cp -f "$ROOT_DIR/data/com.k0vcz.Artemis.gschema.xml" "$SCHEMA_DIR/"
fi

if [[ -d "$SCHEMA_DIR" ]]; then
  echo "==> Compiling GSettings schemas in bundle"
  glib-compile-schemas "$SCHEMA_DIR"
else
  echo "warning: no schema dir at $SCHEMA_DIR; skipping glib-compile-schemas" >&2
fi

# Bundle CA certificates used by TLS backends/libsoup.
echo "==> Bundling CA certificates"
if ! copy_first_existing_tree \
  "$BUNDLE_DIR/etc/ssl/certs" \
  "$MINGW_PREFIX/etc/ssl/certs"
then
  echo "warning: could not find $MINGW_PREFIX/etc/ssl/certs; TLS cert validation may fail" >&2
fi

# Bundle fontconfig config + fonts so GTK can resolve Adwaita/Cantarell/mono faces.
echo "==> Bundling fontconfig + fonts"
if ! copy_first_existing_tree \
  "$BUNDLE_DIR/etc/fonts" \
  "$MINGW_PREFIX/etc/fonts"
then
  echo "warning: could not find fontconfig config dir; font fallback warnings may occur" >&2
fi

if ! copy_first_existing_tree \
  "$BUNDLE_DIR/share/fonts" \
  "$MINGW_PREFIX/share/fonts"
then
  echo "warning: could not find shared fonts dir; font fallback warnings may occur" >&2
fi

# Build font cache in bundle, if fontconfig is available.
if command -v fc-cache >/dev/null 2>&1 && [[ -d "$BUNDLE_DIR/etc/fonts" ]]; then
  echo "==> Running fc-cache for bundled fonts"
  FONTCONFIG_PATH="$BUNDLE_DIR/etc/fonts" \
  FONTCONFIG_FILE="$BUNDLE_DIR/etc/fonts/fonts.conf" \
  XDG_DATA_HOME="$BUNDLE_DIR/share" \
  fc-cache -f -v "$BUNDLE_DIR/share/fonts" >/dev/null || true
fi

if [[ ! -f "$BUNDLE_DIR/share/glib-2.0/schemas/gschemas.compiled" ]]; then
  echo "error: gschemas.compiled not found in bundle at $BUNDLE_DIR/share/glib-2.0/schemas" >&2
  exit 1
fi

# Rebuild GIO module cache in the bundled module dir.
if command -v gio-querymodules >/dev/null 2>&1 && [[ -d "$BUNDLE_DIR/lib/gio/modules" ]]; then
  echo "==> Running gio-querymodules in bundle"
  gio-querymodules "$BUNDLE_DIR/lib/gio/modules"
else
  echo "warning: gio-querymodules not found or no bundled gio/modules; skipping cache generation" >&2
fi

# Include icon themes used by GTK runtime where available.
for d in \
  "$MINGW_PREFIX/share/icons/Adwaita" \
  "$MINGW_PREFIX/share/icons/hicolor"
do
  if [[ -d "$d" ]]; then
    mkdir -p "$BUNDLE_DIR/share/icons"
    cp -a "$d" "$BUNDLE_DIR/share/icons/"
  fi
done

if [[ -f "$ICON_ICO_BUILD" ]]; then
  cp -f "$ICON_ICO_BUILD" "$ICON_ICO_BUNDLE"
fi

echo "==> Writing launcher: Artemis.bat"
cat > "$BUNDLE_DIR/Artemis.bat" <<EOF
@echo off
setlocal
set "APPDIR=%~dp0"
set "GSETTINGS_SCHEMA_DIR=%APPDIR%share\glib-2.0\schemas"
set "XDG_DATA_DIRS=%APPDIR%share"
set "GDK_PIXBUF_MODULEDIR=%APPDIR%lib\gdk-pixbuf-2.0\2.10.0\loaders"
set "GIO_MODULE_DIR=%APPDIR%lib\gio\modules"
set "FONTCONFIG_PATH=%APPDIR%etc\fonts"
set "FONTCONFIG_FILE=%APPDIR%etc\fonts\fonts.conf"
set "SSL_CERT_FILE=%APPDIR%etc\ssl\certs\ca-certificates.crt"
set "G_TLS_CA_FILE=%APPDIR%etc\ssl\certs\ca-certificates.crt"
"%APPDIR%bin\${APP_EXE_NAME}" %*
endlocal
EOF

echo
echo "Bundle complete:"
echo "  $BUNDLE_DIR"
echo
echo "Next step:"
echo "  Point your installer to this directory tree."
echo "  Use icon file: $ICON_ICO_BUNDLE"
