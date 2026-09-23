#!/bin/sh
# Build Understudy.app from the Swift package.
#   app/scripts/bundle.sh          → app/build/Understudy.app
# If app/config.local.json exists, it's copied into the bundle (it's git-ignored).
set -e
cd "$(dirname "$0")/.."
swift build -c release
BIN="$(swift build -c release --show-bin-path)/Understudy"
APP="build/Understudy.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Understudy"
# SwiftPM resource bundles of dependencies, if any
for b in "$(dirname "$BIN")"/*.bundle; do [ -e "$b" ] && cp -R "$b" "$APP/Contents/Resources/"; done
[ -f config.local.json ] && cp config.local.json "$APP/Contents/Resources/config.json"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Understudy</string>
  <key>CFBundleDisplayName</key><string>Understudy</string>
  <key>CFBundleIdentifier</key><string>app.understudy.prototype</string>
  <key>CFBundleExecutable</key><string>Understudy</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHumanReadableCopyright</key><string>Understudy prototype. Not for distribution.</string>
  <key>CFBundleURLTypes</key>
  <array>
    <dict>
      <key>CFBundleURLName</key><string>app.understudy.prototype.auth</string>
      <key>CFBundleURLSchemes</key><array><string>understudy</string></array>
    </dict>
  </array>
</dict>
</plist>
PLIST
codesign --force --deep --sign - "$APP" >/dev/null
echo "Built $APP"
