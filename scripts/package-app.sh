#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="DIFF Mac"
BUILD_CONFIG="${1:-release}"
PRODUCT_NAME="DIFFMac"
VERSION="${DIFFMAC_VERSION:-0.1.0}"
BUILD_NUMBER="${DIFFMAC_BUILD:-1}"
BUNDLE_ID="${DIFFMAC_BUNDLE_ID:-com.bniladridas.diff-mac}"
MIN_SYSTEM_VERSION="${DIFFMAC_MIN_SYSTEM_VERSION:-15.0}"
APPCAST_URL="${DIFFMAC_APPCAST_URL:-https://github.com/bniladridas/diff-mac/releases/latest/download/appcast.xml}"
APP_DIR="$ROOT_DIR/dist/$APP_NAME.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
FRAMEWORKS_DIR="$CONTENTS_DIR/Frameworks"
ENTITLEMENTS="$ROOT_DIR/Packaging/DIFFMac.entitlements"

xml_escape() {
  local value="$1"
  value="${value//&/&amp;}"
  value="${value//</&lt;}"
  value="${value//>/&gt;}"
  value="${value//\"/&quot;}"
  value="${value//\'/&apos;}"
  printf '%s' "$value"
}

create_dmg() {
  local dmg_path="$1"
  local staging_dir="$ROOT_DIR/dist/dmg-staging"
  rm -rf "$staging_dir" "$dmg_path"
  mkdir -p "$staging_dir"
  ditto "$APP_DIR" "$staging_dir/$APP_NAME.app"
  ln -s /Applications "$staging_dir/Applications"
  hdiutil create \
    -volname "$APP_NAME" \
    -srcfolder "$staging_dir" \
    -ov \
    -format UDZO \
    "$dmg_path"
  rm -rf "$staging_dir"
}

cd "$ROOT_DIR"
swift build -c "$BUILD_CONFIG"
BIN_PATH="$(swift build -c "$BUILD_CONFIG" --show-bin-path 2>/dev/null)"

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR" "$FRAMEWORKS_DIR"
cp "$ROOT_DIR/.build/$BUILD_CONFIG/$PRODUCT_NAME" "$MACOS_DIR/$PRODUCT_NAME"
swift "$ROOT_DIR/scripts/generate-icon.swift" "$RESOURCES_DIR/AppIcon.icns"

if [[ -d "$BIN_PATH/Sparkle.framework" ]]; then
  ditto "$BIN_PATH/Sparkle.framework" "$FRAMEWORKS_DIR/Sparkle.framework"
  if ! otool -l "$MACOS_DIR/$PRODUCT_NAME" | grep -q "@loader_path/../Frameworks"; then
    install_name_tool -add_rpath "@loader_path/../Frameworks" "$MACOS_DIR/$PRODUCT_NAME"
  fi
fi

SPARKLE_PLIST_KEYS=""
if [[ -n "$APPCAST_URL" ]]; then
  SPARKLE_PLIST_KEYS+="  <key>SUFeedURL</key>
  <string>$(xml_escape "$APPCAST_URL")</string>
"
fi
if [[ -n "${SPARKLE_PUBLIC_ED_KEY:-}" ]]; then
  SPARKLE_PLIST_KEYS+="  <key>SUPublicEDKey</key>
  <string>$(xml_escape "$SPARKLE_PUBLIC_ED_KEY")</string>
"
fi

cat > "$CONTENTS_DIR/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>$PRODUCT_NAME</string>
  <key>CFBundleIdentifier</key>
  <string>$BUNDLE_ID</string>
  <key>CFBundleName</key>
  <string>$APP_NAME</string>
  <key>CFBundleDisplayName</key>
  <string>$APP_NAME</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>$VERSION</string>
  <key>CFBundleVersion</key>
  <string>$BUILD_NUMBER</string>
  <key>LSMinimumSystemVersion</key>
  <string>$MIN_SYSTEM_VERSION</string>
  <key>NSHighResolutionCapable</key>
  <true/>
  <key>CFBundleIconFile</key>
  <string>AppIcon.icns</string>
  <key>CFBundleURLTypes</key>
  <array>
    <dict>
      <key>CFBundleURLName</key>
      <string>DIFF Mac Callback</string>
      <key>CFBundleURLSchemes</key>
      <array>
        <string>diffmac</string>
      </array>
    </dict>
  </array>
$SPARKLE_PLIST_KEYS</dict>
</plist>
PLIST

if [[ -n "${CODESIGN_IDENTITY:-}" ]]; then
  if [[ -d "$FRAMEWORKS_DIR/Sparkle.framework" ]]; then
    codesign --force --options runtime --sign "$CODESIGN_IDENTITY" "$FRAMEWORKS_DIR/Sparkle.framework"
  fi
  codesign --force --options runtime --entitlements "$ENTITLEMENTS" --sign "$CODESIGN_IDENTITY" "$APP_DIR"
fi

ditto -c -k --keepParent "$APP_DIR" "$ROOT_DIR/dist/DIFFMac-$BUILD_CONFIG.zip"

if [[ "${CREATE_DMG:-0}" == "1" ]]; then
  create_dmg "$ROOT_DIR/dist/DIFFMac-$BUILD_CONFIG.dmg"
fi

echo "$APP_DIR"
