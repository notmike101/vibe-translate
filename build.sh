#!/bin/bash
set -euo pipefail

APP_NAME="Vibe Translate"
EXEC_NAME="VibeTranslate"
BUNDLE_ID="xyz.ignoresolutions.vibetranslate"
MIN_MACOS="13.0"
COPYRIGHT="Copyright © 2026 Mike Santiago. MIT licensed."

# Override per release: VERSION=1.1 ./build.sh
VERSION="${VERSION:-1.0}"
BUILD_NUMBER="${BUILD_NUMBER:-$(git -C "$(dirname "$0")" rev-list --count HEAD 2>/dev/null || echo 1)}"

ROOT="$(cd "$(dirname "$0")" && pwd)"
BUILD="$ROOT/build"
APP="$BUILD/$APP_NAME.app"

rm -rf "$BUILD"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

SOURCES=("$ROOT"/Sources/*.swift)

# Compile one slice per architecture, then lipo into a universal binary.
for ARCH in arm64 x86_64; do
  swiftc -O \
    -target "$ARCH-apple-macos$MIN_MACOS" \
    -o "$BUILD/$EXEC_NAME-$ARCH" \
    "${SOURCES[@]}"
done

lipo -create -output "$APP/Contents/MacOS/$EXEC_NAME" \
  "$BUILD/$EXEC_NAME-arm64" "$BUILD/$EXEC_NAME-x86_64"
rm -f "$BUILD/$EXEC_NAME-arm64" "$BUILD/$EXEC_NAME-x86_64"

# Icon: regenerate from Tools/MakeIcon.swift if it is missing (see make-icon.sh).
if [ ! -f "$ROOT/Resources/AppIcon.icns" ]; then
  "$ROOT/make-icon.sh"
fi
cp "$ROOT/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>            <string>$APP_NAME</string>
    <key>CFBundleDisplayName</key>     <string>$APP_NAME</string>
    <key>CFBundleIdentifier</key>      <string>$BUNDLE_ID</string>
    <key>CFBundleExecutable</key>      <string>$EXEC_NAME</string>
    <key>CFBundleIconFile</key>        <string>AppIcon</string>
    <key>CFBundlePackageType</key>     <string>APPL</string>
    <key>CFBundleShortVersionString</key> <string>$VERSION</string>
    <key>CFBundleVersion</key>         <string>$BUILD_NUMBER</string>
    <key>NSHumanReadableCopyright</key> <string>$COPYRIGHT</string>
    <key>LSMinimumSystemVersion</key>  <string>$MIN_MACOS</string>
    <key>NSHighResolutionCapable</key> <true/>
</dict>
</plist>
PLIST

printf 'APPL????' > "$APP/Contents/PkgInfo"

# A local model on 127.0.0.1 is plain HTTP, which ATS blocks by default.
# Loopback only — this does not open up arbitrary cleartext connections.
/usr/libexec/PlistBuddy -c "Add :NSAppTransportSecurity dict" "$APP/Contents/Info.plist" >/dev/null
/usr/libexec/PlistBuddy -c "Add :NSAppTransportSecurity:NSAllowsLocalNetworking bool true" "$APP/Contents/Info.plist" >/dev/null

# Ad-hoc signature: no developer account needed, opens on any Mac.
# The entitlements keep the keychain item scoped to this app's identity.
codesign --force --deep --sign - --timestamp=none "$APP"
codesign --verify --verbose "$APP"

echo
echo "Built: $APP  (v$VERSION build $BUILD_NUMBER)"
echo "Run:   open \"$APP\""
