#!/bin/bash
# Builds MacPad and assembles MacPad.app in ./build. Works with Command Line Tools only (no Xcode needed).
# Usage: Scripts/bundle.sh [debug|release]   (default: release)
set -euo pipefail

CONFIG="${1:-release}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/build/MacPad.app"
ICONSET="$ROOT/build/AppIcon.iconset"

cd "$ROOT"
swift build -c "$CONFIG"
BIN="$(swift build -c "$CONFIG" --show-bin-path)/MacPad"

rm -rf "$APP" "$ICONSET"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/MacPad"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"

# Release builds pass APP_VERSION (from the git tag). Stamp it before signing, because editing the plist afterwards breaks the signature.
if [ -n "${APP_VERSION:-}" ]; then
  /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $APP_VERSION" "$APP/Contents/Info.plist"
  /usr/libexec/PlistBuddy -c "Set :CFBundleVersion ${BUILD_NUMBER:-1}" "$APP/Contents/Info.plist"
fi

swift "$ROOT/Scripts/make-icon.swift" "$ICONSET"
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"

codesign --force --sign - "$APP"
echo "Built $APP"
