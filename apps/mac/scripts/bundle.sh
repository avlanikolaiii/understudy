#!/bin/sh
# Build Understudy.app from the Swift package.
#   apps/mac/scripts/bundle.sh          → apps/mac/build/Understudy.app
# If apps/mac/config.local.json exists, it's copied into the bundle (it's git-ignored).
set -e
CONFIGURATION="${CONFIGURATION:-release}"
cd "$(dirname "$0")/.."
swift build -c "$CONFIGURATION"
BIN="$(swift build -c "$CONFIGURATION" --show-bin-path)/Understudy"
APP="build/Understudy.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Understudy"
# SwiftPM resource bundles of dependencies, if any
for b in "$(dirname "$BIN")"/*.bundle; do [ -e "$b" ] && cp -R "$b" "$APP/Contents/Resources/"; done
[ -f config.local.json ] && cp config.local.json "$APP/Contents/Resources/config.json"
# App icon: the website's favicon mark (regenerate with scripts/make-icon.swift + iconutil).
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Understudy</string>
  <key>CFBundleDisplayName</key><string>Understudy</string>
  <key>CFBundleIdentifier</key><string>app.understudy.prototype</string>
  <key>CFBundleExecutable</key><string>Understudy</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>NSAppleEventsUsageDescription</key><string>Skills can use an app's own commands, like playing a Spotify link or creating a Mail draft. Understudy only sends the commands in your skill's steps.</string>
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
# Sign with the fixed identity from scripts/make-signing-identity.sh when it exists, so macOS keeps
# this app's privacy permissions across builds. Otherwise ad-hoc, which macOS treats as a new app
# every build.
KEYCHAIN="$PWD/.signing/understudy.keychain-db"
if [ -f "$KEYCHAIN" ]; then
  security unlock-keychain -p "$(cat .signing/keychain-password)" "$KEYCHAIN"
  codesign --force --deep --sign "Understudy Open Source" --keychain "$KEYCHAIN" "$APP" >/dev/null
  echo "Signed with the Understudy Open Source identity"
else
  codesign --force --deep --sign - "$APP" >/dev/null
  echo "Signed ad-hoc (run scripts/make-signing-identity.sh to keep permissions across builds)"
fi
echo "Built $APP"
