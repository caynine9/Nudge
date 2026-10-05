#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SOURCE_PNG="$ROOT_DIR/Nudge/Assets/NudgieAppIcon.png"
OUTPUT_ICNS="$ROOT_DIR/Nudge/Assets/Nudgie.icns"
ICONSET_DIR="$(mktemp -d "${TMPDIR:-/tmp}/nudgie-icon.XXXXXX")"
trap 'rm -rf "$ICONSET_DIR"' EXIT
mkdir -p "$ICONSET_DIR/Nudgie.iconset"

for size in 16 32 128 256 512; do
    sips -s format png -z "$size" "$size" "$SOURCE_PNG" --out "$ICONSET_DIR/Nudgie.iconset/icon_${size}x${size}.png" >/dev/null
    double_size=$((size * 2))
    sips -s format png -z "$double_size" "$double_size" "$SOURCE_PNG" --out "$ICONSET_DIR/Nudgie.iconset/icon_${size}x${size}@2x.png" >/dev/null
done

iconutil --convert icns --output "$OUTPUT_ICNS" "$ICONSET_DIR/Nudgie.iconset"
