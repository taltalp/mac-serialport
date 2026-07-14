#!/bin/zsh

set -euo pipefail

ROOT_DIR="${0:A:h:h}"
cd "$ROOT_DIR"

if [[ -d "/Applications/Xcode.app/Contents/Developer" ]]; then
  export DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"
fi
export CLANG_MODULE_CACHE_PATH="$ROOT_DIR/.build/ModuleCache"

swift build \
  -c release \
  --disable-sandbox \
  --cache-path "$ROOT_DIR/.build/cache"

APP_DIR="$ROOT_DIR/.build/Serial Monitor.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
ASSET_INFO_PLIST="$ROOT_DIR/.build/AppIcon-Info.plist"

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"
cp "$ROOT_DIR/.build/release/SerialMonitor" "$MACOS_DIR/SerialMonitor"
cp "$ROOT_DIR/Packaging/Info.plist" "$CONTENTS_DIR/Info.plist"

xcrun actool \
  "$ROOT_DIR/Packaging/Assets.xcassets" \
  --compile "$RESOURCES_DIR" \
  --platform macosx \
  --minimum-deployment-target 13.0 \
  --app-icon AppIcon \
  --output-partial-info-plist "$ASSET_INFO_PLIST" \
  --warnings \
  --notices

codesign \
  --force \
  --sign - \
  --entitlements "$ROOT_DIR/Packaging/SerialMonitor.entitlements" \
  "$APP_DIR"

echo "$APP_DIR"
