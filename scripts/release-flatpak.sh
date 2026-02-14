#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MANIFEST_PATH="${MANIFEST_PATH:-$ROOT_DIR/com.k0vcz.Artemis.json}"
FLATPAK_ID="${FLATPAK_ID:-com.k0vcz.Artemis}"
BUILD_DIR="${BUILD_DIR:-$ROOT_DIR/.flatpak-builder/build-$FLATPAK_ID}"
REPO_DIR="${REPO_DIR:-$ROOT_DIR/dist/flatpak/repo}"
BUNDLE_PATH="${BUNDLE_PATH:-$ROOT_DIR/dist/flatpak/$FLATPAK_ID.flatpak}"

mkdir -p "$REPO_DIR"
mkdir -p "$(dirname "$BUNDLE_PATH")"

flatpak-builder \
  --force-clean \
  --repo="$REPO_DIR" \
  "$BUILD_DIR" \
  "$MANIFEST_PATH"

flatpak build-bundle "$REPO_DIR" "$BUNDLE_PATH" "$FLATPAK_ID"

echo "Flatpak bundle created: $BUNDLE_PATH"
