#!/bin/zsh
# Builds Paste.app into ./build.
#   scripts/build.sh            # build only
#   scripts/build.sh --install  # build, copy to /Applications/Paste.app and launch
#   scripts/build.sh --zip      # build and zip to build/Paste-<version>.zip
#
# Environment:
#   VERSION        marketing version (default: latest git tag, else 0.0.0)
#   BUILD_NUMBER   CFBundleVersion (default: git commit count, else 1)
#   SIGN_IDENTITY  codesign identity, e.g. "Developer ID Application: Name (TEAMID)".
#                  Default "-" is an ad-hoc signature. A real identity also turns on
#                  the hardened runtime and a secure timestamp, which notarization needs.
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION=${VERSION:-$(git describe --tags --abbrev=0 2>/dev/null | sed 's/^v//' || true)}
VERSION=${VERSION:-0.0.0}
BUILD_NUMBER=${BUILD_NUMBER:-$(git rev-list --count HEAD 2>/dev/null || echo 1)}
SIGN_IDENTITY=${SIGN_IDENTITY:--}

swift build -c release 2>&1 | grep -v "^\[" || true
BIN=$(swift build -c release --show-bin-path)/Paste
[[ -x "$BIN" ]] || { echo "build failed"; exit 1; }

APP=build/Paste.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Paste"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cp Resources/Copy.wav Resources/Paste.wav "$APP/Contents/Resources/"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Paste</string>
  <key>CFBundleDisplayName</key><string>Paste</string>
  <key>CFBundleExecutable</key><string>Paste</string>
  <key>CFBundleIdentifier</key><string>app.paste.clipboard</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>${VERSION}</string>
  <key>CFBundleVersion</key><string>${BUILD_NUMBER}</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
  <key>LSApplicationCategoryType</key><string>public.app-category.productivity</string>
  <key>NSPrincipalClass</key><string>NSApplication</string>
  <key>NSSupportsAutomaticTermination</key><false/>
</dict>
</plist>
PLIST

if [[ "$SIGN_IDENTITY" == "-" ]]; then
  codesign --force --deep --sign - "$APP" >/dev/null 2>&1
else
  codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" "$APP"
fi
echo "Built $APP ($VERSION, build $BUILD_NUMBER)"

case "${1:-}" in
  --install)
    DEST="/Applications/Paste.app"
    pkill -f "^/Applications/Paste.app/Contents/MacOS/Paste" 2>/dev/null || true
    sleep 0.3
    rm -rf "$DEST"
    cp -R "$APP" "$DEST"
    open "$DEST"
    echo "Installed and launched $DEST"
    ;;
  --zip)
    ZIP="build/Paste-$VERSION.zip"
    rm -f "$ZIP"
    ditto -c -k --keepParent "$APP" "$ZIP"
    echo "Zipped $ZIP"
    ;;
esac
