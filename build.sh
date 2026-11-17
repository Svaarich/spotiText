#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")"

swift build -c release
BIN="$(swift build -c release --show-bin-path)/SpotiText"

APP="SpotiText.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$BIN" "$APP/Contents/MacOS/SpotiText"

mkdir -p "$APP/Contents/Resources"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>SpotiText</string>
    <key>CFBundleDisplayName</key><string>SpotiText</string>
    <key>CFBundleIdentifier</key><string>dev.spotitext.app</string>
    <key>CFBundleExecutable</key><string>SpotiText</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>26.0</string>
    <key>LSUIElement</key><true/>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSAppleEventsUsageDescription</key>
    <string>SpotiText reads the current Spotify track and playback position to show synced lyrics.</string>
</dict>
</plist>
PLIST

codesign --force --sign - "$APP"
echo "App: $(pwd)/$APP"

mkdir -p dist
rm -f dist/SpotiText.zip
ditto -c -k --keepParent "$APP" dist/SpotiText.zip
echo "ZIP: $(pwd)/dist/SpotiText.zip"

STAGE="$(mktemp -d)"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
rm -f dist/SpotiText.dmg
hdiutil create -volname "SpotiText" -srcfolder "$STAGE" -ov -format UDZO -quiet dist/SpotiText.dmg
rm -rf "$STAGE"
echo "DMG: $(pwd)/dist/SpotiText.dmg"
