#!/bin/bash
set -euo pipefail

# ═══════════════════════════════════════════════════════
# ScreenInspect MCP — Release Packaging Script
# Creates: .app bundle, .zip archive, checksums, and DMG
# ═══════════════════════════════════════════════════════

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
BUILD_DIR="$ROOT_DIR/build"
RELEASE_DIR="$ROOT_DIR/release"
SERVER_DIR="$ROOT_DIR/server"

VERSION="1.0.0"
APP_NAME="ScreenInspect"
BUNDLE_ID="com.screeninspect.app"

echo "╔════════════════════════════════════════════╗"
echo "║   ScreenInspect — Release Package v$VERSION   ║"
echo "╚════════════════════════════════════════════╝"
echo ""

# ── Ensure build exists ──
if [[ ! -f "$BUILD_DIR/bin/ScreenInspectApp" ]]; then
    echo "▸ Build not found, running build first..."
    bash "$SCRIPT_DIR/build.sh"
fi

# ── Clean release dir ──
rm -rf "$RELEASE_DIR"
mkdir -p "$RELEASE_DIR"

# ═══════════════════════════════════════
# 1. Create .app bundle
# ═══════════════════════════════════════
echo "▸ Creating .app bundle..."

APP_DIR="$RELEASE_DIR/$APP_NAME.app"
CONTENTS="$APP_DIR/Contents"
MACOS="$CONTENTS/MacOS"
RESOURCES="$CONTENTS/Resources"

mkdir -p "$MACOS" "$RESOURCES" "$CONTENTS/Frameworks"

# Copy binaries
cp "$BUILD_DIR/bin/ScreenInspectApp" "$MACOS/ScreenInspect"
cp "$BUILD_DIR/bin/RegionSelector" "$MACOS/RegionSelector"

# Copy server
mkdir -p "$RESOURCES/server"
cp -r "$SERVER_DIR/dist" "$RESOURCES/server/dist"
cp "$SERVER_DIR/package.json" "$RESOURCES/server/"
cp -r "$SERVER_DIR/node_modules" "$RESOURCES/server/" 2>/dev/null || true

# Create Info.plist
cat > "$CONTENTS/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>ScreenInspect</string>
    <key>CFBundleIdentifier</key>
    <string>${BUNDLE_ID}</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>${APP_NAME}</string>
    <key>CFBundleDisplayName</key>
    <string>ScreenInspect</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>${VERSION}</string>
    <key>CFBundleVersion</key>
    <string>${VERSION}</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSScreenCaptureUsageDescription</key>
    <string>ScreenInspect needs Screen Recording permission to capture the selected screen region on demand.</string>

    <!-- Sparkle auto-update (TODO: uncomment when Sparkle is integrated) -->
    <!-- <key>SUFeedURL</key> -->
    <!-- <string>https://yoursite.com/appcast.xml</string> -->
    <!-- <key>SUPublicEDKey</key> -->
    <!-- <string>YOUR_ED25519_PUBLIC_KEY</string> -->
</dict>
</plist>
PLIST

# Create launcher script (ensures Node.js server can be found)
cat > "$RESOURCES/start-server.sh" <<'LAUNCHER'
#!/bin/bash
# Launcher for the MCP server from within the .app bundle
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
exec node "$SCRIPT_DIR/server/dist/index.js" "$@"
LAUNCHER
chmod +x "$RESOURCES/start-server.sh"

echo "  ✓ $APP_NAME.app created"

# ═══════════════════════════════════════
# 2. Create ZIP archive
# ═══════════════════════════════════════
echo "▸ Creating ZIP archive..."

cd "$RELEASE_DIR"
ZIP_NAME="${APP_NAME}-v${VERSION}-macos.zip"
zip -r -q "$ZIP_NAME" "$APP_NAME.app"
echo "  ✓ $ZIP_NAME created"

# ═══════════════════════════════════════
# 3. Create checksums
# ═══════════════════════════════════════
echo "▸ Computing checksums..."

shasum -a 256 "$ZIP_NAME" > "$ZIP_NAME.sha256"
echo "  ✓ SHA-256: $(cat "$ZIP_NAME.sha256")"

# ═══════════════════════════════════════
# 4. Create DMG (optional)
# ═══════════════════════════════════════
echo "▸ Creating DMG..."

DMG_NAME="${APP_NAME}-v${VERSION}-macos.dmg"
DMG_TEMP="$RELEASE_DIR/dmg-staging"

mkdir -p "$DMG_TEMP"
cp -r "$APP_DIR" "$DMG_TEMP/"

# Create Applications symlink
ln -s /Applications "$DMG_TEMP/Applications"

# Create README inside DMG
cat > "$DMG_TEMP/README.txt" <<DMGREADME
ScreenInspect v${VERSION}

1. Drag ScreenInspect.app to Applications
2. Launch from Applications
3. Grant Screen Recording permission when prompted
4. Connect your MCP client (Claude Desktop, Cursor, etc.)

For setup instructions: https://github.com/yourname/screeninspect-mcp
DMGREADME

hdiutil create \
    -volname "$APP_NAME" \
    -srcfolder "$DMG_TEMP" \
    -ov \
    -format UDZO \
    "$RELEASE_DIR/$DMG_NAME" \
    2>/dev/null || echo "  ⚠ DMG creation failed (hdiutil may need full disk access). ZIP is available."

rm -rf "$DMG_TEMP"

if [[ -f "$RELEASE_DIR/$DMG_NAME" ]]; then
    shasum -a 256 "$DMG_NAME" > "$DMG_NAME.sha256"
    echo "  ✓ $DMG_NAME created"
fi

# ═══════════════════════════════════════
# Summary
# ═══════════════════════════════════════
echo ""
echo "╔════════════════════════════════════════════╗"
echo "║   Release Package Complete!                ║"
echo "╚════════════════════════════════════════════╝"
echo ""
echo "  Output: $RELEASE_DIR/"
ls -lh "$RELEASE_DIR/" | grep -v "^total" | grep -v "dmg-staging"
echo ""
echo "  To distribute:"
echo "    1. Upload $ZIP_NAME to GitHub Releases"
echo "    2. For Homebrew cask, use the SHA-256 checksum"
echo "    3. For notarization: xcrun notarytool submit $ZIP_NAME --apple-id ... --team-id ..."
echo ""
echo "  TODO for production release:"
echo "    • Code sign with Developer ID: codesign --deep --sign 'Developer ID' $APP_NAME.app"
echo "    • Notarize with Apple"
echo "    • Add Sparkle.framework for auto-updates"
echo "    • Integrate license key validation"
