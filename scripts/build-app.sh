#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
export CLANG_MODULE_CACHE_PATH="$PWD/.build/clang-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/swift-cache"
swift build -c release --disable-sandbox
BIN_DIR="$(swift build -c release --show-bin-path --disable-sandbox)"
APP="$PWD/dist/AeroDock.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/AeroDock" "$APP/Contents/MacOS/AeroDock"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AeroDock.icns "$APP/Contents/Resources/AeroDock.icns"
codesign --force --sign - "$APP"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$PWD/dist/AeroDock-macOS.zip"
echo "Built $APP"
