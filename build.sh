#!/bin/bash
# Build NoteStudio.app — demo ghi chú macOS (Swift/SwiftUI)
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="NoteStudio"
APP="$APP_NAME.app"
MIN_MACOS="13.0"

echo "▸ Compiling Swift sources…"
rm -rf "$APP" build
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" build

SOURCES=$(find Sources -name '*.swift')

swiftc \
    -parse-as-library \
    -swift-version 5 \
    -target "$(uname -m)-apple-macos${MIN_MACOS}" \
    -o "$APP/Contents/MacOS/$APP_NAME" \
    $SOURCES

cp Resources/Info.plist "$APP/Contents/Info.plist"

echo "▸ Generating app icon…"
if swift scripts/make_icon.swift build/icon_1024.png 2>/dev/null; then
    ICONSET="build/AppIcon.iconset"
    mkdir -p "$ICONSET"
    for spec in "16:icon_16x16" "32:icon_16x16@2x" "32:icon_32x32" "64:icon_32x32@2x" \
                "128:icon_128x128" "256:icon_128x128@2x" "256:icon_256x256" "512:icon_256x256@2x" \
                "512:icon_512x512"; do
        px="${spec%%:*}"
        name="${spec#*:}"
        sips -z "$px" "$px" build/icon_1024.png --out "$ICONSET/$name.png" >/dev/null
    done
    cp build/icon_1024.png "$ICONSET/icon_512x512@2x.png"
    iconutil -c icns -o "$APP/Contents/Resources/AppIcon.icns" "$ICONSET"
else
    echo "  (bỏ qua icon — app sẽ dùng icon mặc định)"
fi

echo "▸ Building MCP server (notestudio-mcp)…"
swiftc MCPServer/main.swift -o notestudio-mcp

echo "▸ Codesigning (ad-hoc)…"
codesign --force --sign - "$APP" >/dev/null 2>&1 || true

echo "✓ Xong: $APP + notestudio-mcp"
echo "  Chạy: open $APP"
