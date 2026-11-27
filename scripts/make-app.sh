#!/bin/sh
# Wraps the built binary into a menu bar .app bundle.
# Usage: scripts/make-app.sh <binary> <path/to/Rubber Stamp.app> [version]
set -eu
BIN="$1"; APP="$2"; VERSION="${3:-0.0.0}"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$BIN" "$APP/Contents/MacOS/RubberStamp"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Rubber Stamp</string>
  <key>CFBundleDisplayName</key><string>Rubber Stamp</string>
  <key>CFBundleIdentifier</key><string>io.github.gianhiltbrunner.rubber-stamp</string>
  <key>CFBundleExecutable</key><string>RubberStamp</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>${VERSION}</string>
  <key>CFBundleVersion</key><string>${VERSION}</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>LSUIElement</key><true/>
</dict>
</plist>
PLIST
codesign --force --sign - "$APP"
