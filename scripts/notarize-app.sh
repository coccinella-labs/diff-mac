#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ZIP_PATH="${1:-$ROOT_DIR/dist/DIFFMac-release.zip}"
DMG_PATH="${2:-$ROOT_DIR/dist/DIFFMac-release.dmg}"
APP_PATH="$ROOT_DIR/dist/DIFF Mac.app"
APP_NAME="DIFF Mac"

create_dmg() {
  local dmg_path="$1"
  local staging_dir="$ROOT_DIR/dist/dmg-staging"
  rm -rf "$staging_dir" "$dmg_path"
  mkdir -p "$staging_dir"
  ditto "$APP_PATH" "$staging_dir/$APP_NAME.app"
  ln -s /Applications "$staging_dir/Applications"
  hdiutil create \
    -volname "$APP_NAME" \
    -srcfolder "$staging_dir" \
    -ov \
    -format UDZO \
    "$dmg_path"
  rm -rf "$staging_dir"
}

if [[ -z "${NOTARYTOOL_PROFILE:-}" ]]; then
  echo "NOTARYTOOL_PROFILE is required." >&2
  exit 1
fi

if [[ ! -f "$ZIP_PATH" ]]; then
  echo "Missing zip: $ZIP_PATH" >&2
  exit 1
fi

xcrun notarytool submit "$ZIP_PATH" --keychain-profile "$NOTARYTOOL_PROFILE" --wait
xcrun stapler staple "$APP_PATH"
codesign --verify --deep --strict --verbose=2 "$APP_PATH"
spctl --assess --type execute --verbose "$APP_PATH"

ditto -c -k --keepParent "$APP_PATH" "$ZIP_PATH"

if [[ -f "$DMG_PATH" ]]; then
  create_dmg "$DMG_PATH"
  xcrun notarytool submit "$DMG_PATH" --keychain-profile "$NOTARYTOOL_PROFILE" --wait
  xcrun stapler staple "$DMG_PATH"
  spctl --assess --type open --context context:primary-signature --verbose "$DMG_PATH"
fi
