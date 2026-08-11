#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# release.sh  —  Build, bundle, and package netBee for distribution
#
# Produces:
#   dist/netBee.app            — macOS .app bundle (drag-to-install)
#   dist/netBee-v<ver>.zip     — zipped bundle
#   dist/netBee-v<ver>.dmg     — drag-to-install DMG with /Applications symlink
#
# Usage:  ./scripts/release.sh [version]
#   e.g.  ./scripts/release.sh 1.0.0
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$ROOT"

VERSION="${1:-1.0.0}"
APP_NAME="netBee"
DIST="$ROOT/dist"
APP_BUNDLE="$DIST/$APP_NAME.app"
BINARY="$ROOT/.build/release/$APP_NAME"
DMG_STAGING="$DIST/dmg-staging"
DMG_FILE="$DIST/$APP_NAME-v$VERSION.dmg"
ZIPFILE="$DIST/$APP_NAME-v$VERSION.zip"

echo "🐝 netBee — release build v$VERSION"
echo ""

# ── 1. Compile ─────────────────────────────────────────────────────────────
echo "▸ Building release binary…"
swift build -c release
echo "  Binary: $BINARY ($(du -sh "$BINARY" | cut -f1))"

# ── 2. Create .app bundle structure ────────────────────────────────────────
echo "▸ Creating .app bundle…"
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

cp "$BINARY" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"

# Copy app icon if present
ICNS_SRC="$ROOT/Sources/netBee/Assets/AppIcon.icns"
if [ -f "$ICNS_SRC" ]; then
  cp "$ICNS_SRC" "$APP_BUNDLE/Contents/Resources/AppIcon.icns"
  echo "  Icon: AppIcon.icns"
fi

cat > "$APP_BUNDLE/Contents/Info.plist" << PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>             <string>$APP_NAME</string>
    <key>CFBundleDisplayName</key>      <string>$APP_NAME</string>
    <key>CFBundleIdentifier</key>       <string>com.beemon.netbee</string>
    <key>CFBundleVersion</key>          <string>$VERSION</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundlePackageType</key>      <string>APPL</string>
    <key>CFBundleExecutable</key>       <string>$APP_NAME</string>
    <key>LSUIElement</key>              <true/>
    <key>NSHighResolutionCapable</key>  <true/>
    <key>LSMinimumSystemVersion</key>   <string>13.0</string>
    <key>CFBundleIconFile</key>         <string>AppIcon</string>
    <key>NSHumanReadableCopyright</key> <string>© 2026 Daneyand &amp; IBM's Bob</string>
</dict>
</plist>
PLIST

printf "APPL????" > "$APP_BUNDLE/Contents/PkgInfo"
echo "  Bundle: $APP_BUNDLE"

# ── 3. Ad-hoc code sign ────────────────────────────────────────────────────
echo "▸ Code-signing (ad-hoc)…"
codesign --force --deep --sign - "$APP_BUNDLE" 2>&1 && echo "  Signed." \
  || echo "  ⚠️  codesign skipped"

# ── 4. Zip ─────────────────────────────────────────────────────────────────
echo "▸ Creating zip archive…"
rm -f "$ZIPFILE"
cd "$DIST" && zip -qr "$ZIPFILE" "$APP_NAME.app" && cd "$ROOT"
echo "  Archive: $ZIPFILE ($(du -sh "$ZIPFILE" | cut -f1))"

# ── 5. DMG ─────────────────────────────────────────────────────────────────
echo "▸ Building DMG…"
rm -rf "$DMG_STAGING"
rm -f "$DMG_FILE"
mkdir -p "$DMG_STAGING"
cp -r "$APP_BUNDLE" "$DMG_STAGING/"
ln -s /Applications "$DMG_STAGING/Applications"

TMP_DMG="$DIST/tmp-rw.dmg"
rm -f "$TMP_DMG"
hdiutil create \
  -volname "netBee $VERSION" \
  -srcfolder "$DMG_STAGING" \
  -ov \
  -format UDRW \
  -fs HFS+ \
  "$TMP_DMG" > /dev/null

DEVICE="$(hdiutil attach -readwrite -noverify -noautoopen "$TMP_DMG" \
  | awk '/Apple_HFS/ { print $1 }')"

sleep 1

osascript << APPLESCRIPT
tell application "Finder"
  tell disk "netBee $VERSION"
    open
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set bounds of container window to {200, 120, 760, 440}
    set theViewOptions to the icon view options of container window
    set arrangement of theViewOptions to not arranged
    set icon size of theViewOptions to 96
    set position of item "netBee.app" of container window to {160, 140}
    set position of item "Applications" of container window to {400, 140}
    close
    open
    update without registering applications
    delay 2
  end tell
end tell
APPLESCRIPT

hdiutil detach "$DEVICE" > /dev/null
sleep 1

hdiutil convert "$TMP_DMG" \
  -format UDZO \
  -imagekey zlib-level=9 \
  -o "$DMG_FILE" > /dev/null

rm -f "$TMP_DMG"
rm -rf "$DMG_STAGING"
echo "  DMG: $DMG_FILE ($(du -sh "$DMG_FILE" | cut -f1))"

# ── 6. Summary ─────────────────────────────────────────────────────────────
echo ""
echo "✅  Release v$VERSION complete!"
echo ""
echo "   App bundle : dist/$APP_NAME.app"
echo "   Zip archive: $ZIPFILE"
echo "   DMG        : $DMG_FILE"
echo ""
echo "   To install : open dist/ and drag netBee.app → /Applications"
echo "   To release : gh release create v$VERSION \"$DMG_FILE\" \"$ZIPFILE\" \\"
echo "                --title 'netBee v$VERSION' --notes-file CHANGELOG.md"
