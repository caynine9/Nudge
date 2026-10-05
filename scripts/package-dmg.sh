#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIGURATION="${CONFIGURATION:-Release}"
VERSION="${VERSION:-0.1}"
BUILD_NUMBER="${BUILD_NUMBER:-1}"
SIGNING_IDENTITY="${SIGNING_IDENTITY:--}"
DEVELOPMENT_TEAM="${DEVELOPMENT_TEAM:-}"
DERIVED_DATA_PATH="${DERIVED_DATA_PATH:-$ROOT_DIR/build/DerivedData}"
DIST_DIR="${DIST_DIR:-$ROOT_DIR/dist}"
APP_ICON_PATH="$ROOT_DIR/Nudge/Assets.xcassets/AppIcon.appiconset/AppIcon.png"
APP_PATH="${APP_PATH:-$DERIVED_DATA_PATH/Build/Products/$CONFIGURATION/Nudge.app}"

swift "$ROOT_DIR/scripts/render-app-icon.swift" "$APP_ICON_PATH"

if [[ -z "${SKIP_BUILD:-}" ]]; then
    xcodebuild \
        -project "$ROOT_DIR/Nudge.xcodeproj" \
        -scheme Nudge \
        -configuration "$CONFIGURATION" \
        -destination 'platform=macOS' \
        -derivedDataPath "$DERIVED_DATA_PATH" \
        ARCHS='arm64 x86_64' \
        ONLY_ACTIVE_ARCH=NO \
        MARKETING_VERSION="$VERSION" \
        CURRENT_PROJECT_VERSION="$BUILD_NUMBER" \
        CODE_SIGN_IDENTITY="$SIGNING_IDENTITY" \
        CODE_SIGN_STYLE=Manual \
        DEVELOPMENT_TEAM="$DEVELOPMENT_TEAM" \
        ENABLE_HARDENED_RUNTIME=YES \
        build
fi

if [[ ! -d "$APP_PATH" ]]; then
    echo "Built app not found at: $APP_PATH" >&2
    exit 1
fi

APP_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP_PATH/Contents/Info.plist")"
DMG_PATH="$DIST_DIR/Nudge-$APP_VERSION-macOS.dmg"
mkdir -p "$DIST_DIR"
STAGING_DIR="$(mktemp -d "${TMPDIR:-/tmp}/nudge-dmg.XXXXXX")"
trap 'rm -rf "$STAGING_DIR"' EXIT

ditto "$APP_PATH" "$STAGING_DIR/Nudge.app"
ln -s /Applications "$STAGING_DIR/Applications"
rm -f "$DMG_PATH"
hdiutil create \
    -volname "Nudge $APP_VERSION" \
    -srcfolder "$STAGING_DIR" \
    -ov \
    -format UDZO \
    "$DMG_PATH"

echo "Created $DMG_PATH"
