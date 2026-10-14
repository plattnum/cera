#!/usr/bin/env bash
# Builds Cera in release mode and wraps it in build/Cera.app.
# With --zip, also writes build/Cera.zip for distribution.
set -euo pipefail

cd "$(dirname "$0")/.."

swift build -c release

BIN_DIR="$(swift build -c release --show-bin-path)"
APP="build/Cera.app"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/Cera" "$APP/Contents/MacOS/Cera"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
# Theme fonts (open-licensed; their LICENSE files travel with them).
cp -R Sources/Cera/Resources/Fonts "$APP/Contents/Resources/Fonts"
# The `cera` terminal command; Homebrew links it onto the PATH.
cp scripts/cera "$APP/Contents/Resources/cera"

# Ad-hoc signature so the bundle launches on this Mac without a developer ID.
codesign --force --sign - "$APP"

if [[ "${1:-}" == "--zip" ]]; then
    rm -f build/Cera.zip
    ditto -c -k --keepParent "$APP" build/Cera.zip
    echo "Built build/Cera.zip"
fi

echo "Built $APP"
