#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DISPLAY_NAME="Termeh"
BUILD_DIR="$ROOT_DIR/build/macos/Build/Products/Release"
DIST_DIR="$ROOT_DIR/dist"
STAGING_DIR="$(mktemp -d "${TMPDIR:-/tmp}/termeh-dmg.XXXXXX")"
DMG_PATH="$DIST_DIR/${DISPLAY_NAME}-macos.dmg"

cleanup() {
  rm -rf "$STAGING_DIR"
}
trap cleanup EXIT

cd "$ROOT_DIR"

flutter build macos --release

APP_PATH="$(find "$BUILD_DIR" -maxdepth 1 -type d -name '*.app' -print -quit)"

if [[ -z "$APP_PATH" ]]; then
  echo "Expected app bundle not found in: $BUILD_DIR" >&2
  exit 1
fi

rm -rf "$DIST_DIR"
mkdir -p "$DIST_DIR"

cp -R "$APP_PATH" "$STAGING_DIR/"
ln -s /Applications "$STAGING_DIR/Applications"

hdiutil create \
  -volname "$DISPLAY_NAME" \
  -srcfolder "$STAGING_DIR" \
  -ov \
  -format UDZO \
  "$DMG_PATH"

echo "Created DMG: $DMG_PATH"
