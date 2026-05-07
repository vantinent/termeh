#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SOURCE_SVG="$ROOT_DIR/assets/icon/icon.svg"
ICONSET_DIR="$ROOT_DIR/macos/Runner/Assets.xcassets/AppIcon.appiconset"

if [[ ! -f "$SOURCE_SVG" ]]; then
  echo "Missing source icon: $SOURCE_SVG" >&2
  exit 1
fi

sizes=(
  16
  32
  64
  128
  256
  512
  1024
)

for size in "${sizes[@]}"; do
  sips -s format png -z "$size" "$size" "$SOURCE_SVG" --out "$ICONSET_DIR/app_icon_${size}.png" >/dev/null
done

echo "Updated macOS app icons from $SOURCE_SVG"
