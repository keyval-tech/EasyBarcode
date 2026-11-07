#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
ARCH="$(uname -m)"
CONFIG="release"
BUILD_DIR="$ROOT/build"
APP="$BUILD_DIR/EasyBarcode.app"

echo "==> Building EasyBarcode ($ARCH, $CONFIG)"
xcrun --sdk macosx swift build -c "$CONFIG" --arch "$ARCH" --package-path "$ROOT"
BIN_DIR="$(xcrun --sdk macosx swift build -c "$CONFIG" --arch "$ARCH" --package-path "$ROOT" --show-bin-path)"

echo "==> Assembling app bundle"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/EasyBarcode" "$APP/Contents/MacOS/EasyBarcode"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"

echo "==> Rendering app icon"
ICON_PNG="$BUILD_DIR/AppIcon-1024.png"
mkdir -p "$BUILD_DIR"
xcrun swift "$ROOT/Scripts/make-icon.swift" "$ICON_PNG"

ICONSET="$BUILD_DIR/AppIcon.iconset"
rm -rf "$ICONSET"
mkdir -p "$ICONSET"
for size in 16 32 128 256 512; do
    sips -z "$size" "$size" "$ICON_PNG" --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
    double=$((size * 2))
    sips -z "$double" "$double" "$ICON_PNG" --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"

echo "==> Signing (ad-hoc)"
codesign --force --deep --sign - "$APP"
codesign --verify --verbose "$APP"

echo "==> Built $APP"
