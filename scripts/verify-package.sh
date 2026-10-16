#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_CONFIG="${1:-release}"
APP_NAME="DIFF Mac"
PRODUCT_NAME="DIFFMac"
APP_PATH="$ROOT_DIR/dist/$APP_NAME.app"
EXECUTABLE_PATH="$APP_PATH/Contents/MacOS/$PRODUCT_NAME"
INFO_PLIST="$APP_PATH/Contents/Info.plist"
ZIP_PATH="$ROOT_DIR/dist/DIFFMac-$BUILD_CONFIG.zip"
DMG_PATH="$ROOT_DIR/dist/DIFFMac-$BUILD_CONFIG.dmg"
APPCAST_PATH="$ROOT_DIR/dist/appcast.xml"
REQUIRE_DMG="${REQUIRE_DMG:-0}"
REQUIRE_SPARKLE_PUBLIC_KEY="${REQUIRE_SPARKLE_PUBLIC_KEY:-0}"
REQUIRE_APPCAST="${REQUIRE_APPCAST:-0}"
REQUIRE_SPARKLE_SIGNATURE="${REQUIRE_SPARKLE_SIGNATURE:-0}"
EXPECTED_VERSION="${DIFFMAC_VERSION:-}"
EXPECTED_BUILD="${DIFFMAC_BUILD:-}"
MOUNT_POINT="${TMPDIR:-/tmp}/diffmac-dmg-check-$$"

fail() {
  echo "Package verification failed: $1" >&2
  exit 1
}

detach_dmg() {
  if [[ -d "$MOUNT_POINT" ]]; then
    hdiutil detach "$MOUNT_POINT" >/dev/null 2>&1 || true
    rmdir "$MOUNT_POINT" >/dev/null 2>&1 || true
  fi
}
trap detach_dmg EXIT

[[ -d "$APP_PATH" ]] || fail "missing app bundle: $APP_PATH"
[[ -x "$EXECUTABLE_PATH" ]] || fail "missing executable: $EXECUTABLE_PATH"
[[ -f "$INFO_PLIST" ]] || fail "missing Info.plist: $INFO_PLIST"
[[ -f "$ZIP_PATH" ]] || fail "missing ZIP: $ZIP_PATH"

zip_listing="$(unzip -Z1 "$ZIP_PATH" 2>/dev/null)" || fail "ZIP cannot be read: $ZIP_PATH"
echo "$zip_listing" | grep -Fxq "$APP_NAME.app/Contents/Info.plist" || fail "ZIP is missing $APP_NAME.app/Contents/Info.plist"
echo "$zip_listing" | grep -Fxq "$APP_NAME.app/Contents/MacOS/$PRODUCT_NAME" || fail "ZIP is missing $APP_NAME.app/Contents/MacOS/$PRODUCT_NAME"

bundle_id="$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$INFO_PLIST")"
[[ -n "$bundle_id" ]] || fail "CFBundleIdentifier is empty"

short_version="$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$INFO_PLIST" 2>/dev/null || true)"
build_version="$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$INFO_PLIST" 2>/dev/null || true)"
[[ -n "$short_version" ]] || fail "CFBundleShortVersionString is missing"
[[ -n "$build_version" ]] || fail "CFBundleVersion is missing"
if [[ -n "$EXPECTED_VERSION" ]]; then
  [[ "$short_version" == "$EXPECTED_VERSION" ]] || fail "CFBundleShortVersionString '$short_version' does not match expected '$EXPECTED_VERSION'"
fi
if [[ -n "$EXPECTED_BUILD" ]]; then
  [[ "$build_version" == "$EXPECTED_BUILD" ]] || fail "CFBundleVersion '$build_version' does not match expected '$EXPECTED_BUILD'"
fi

feed_url="$(/usr/libexec/PlistBuddy -c "Print :SUFeedURL" "$INFO_PLIST" 2>/dev/null || true)"
[[ -n "$feed_url" ]] || fail "SUFeedURL is missing"
[[ "$feed_url" == https://* ]] || fail "SUFeedURL must be HTTPS"
[[ "$feed_url" == *"/appcast.xml" ]] || fail "SUFeedURL must point to appcast.xml"

url_schemes="$(/usr/libexec/PlistBuddy -c "Print :CFBundleURLTypes:0:CFBundleURLSchemes" "$INFO_PLIST" 2>/dev/null || true)"
echo "$url_schemes" | grep -q "diffmac" || fail "diffmac URL scheme is missing"

if [[ "$REQUIRE_SPARKLE_PUBLIC_KEY" == "1" ]]; then
  public_key="$(/usr/libexec/PlistBuddy -c "Print :SUPublicEDKey" "$INFO_PLIST" 2>/dev/null || true)"
  [[ -n "$public_key" ]] || fail "SUPublicEDKey is missing"
  [[ "$public_key" != *"test"* && "$public_key" != *"placeholder"* ]] || fail "SUPublicEDKey appears to be a placeholder"
  [[ ${#public_key} -ge 40 ]] || fail "SUPublicEDKey is too short"
fi

if otool -L "$EXECUTABLE_PATH" | grep -q "Sparkle.framework"; then
  [[ -d "$APP_PATH/Contents/Frameworks/Sparkle.framework" ]] || fail "Sparkle.framework is linked but not embedded"
  otool -l "$EXECUTABLE_PATH" | grep -q "@loader_path/../Frameworks" || fail "missing Frameworks rpath"
fi

if [[ "$REQUIRE_DMG" == "1" ]]; then
  [[ -f "$DMG_PATH" ]] || fail "missing DMG: $DMG_PATH"
  mkdir -p "$MOUNT_POINT"
  hdiutil attach -readonly -nobrowse -mountpoint "$MOUNT_POINT" "$DMG_PATH" >/dev/null
  [[ -d "$MOUNT_POINT/$APP_NAME.app" ]] || fail "DMG is missing $APP_NAME.app"
  [[ "$(readlink "$MOUNT_POINT/Applications")" == "/Applications" ]] || fail "DMG is missing Applications symlink"
fi

if [[ "$REQUIRE_APPCAST" == "1" ]]; then
  [[ -f "$APPCAST_PATH" ]] || fail "missing appcast: $APPCAST_PATH"
  xmllint --noout "$APPCAST_PATH" || fail "appcast.xml is not valid XML"
  enclosure_url="$(xmllint --xpath 'string(/*[local-name()="rss"]/*[local-name()="channel"]/*[local-name()="item"]/*[local-name()="enclosure"]/@url)' "$APPCAST_PATH")"
  release_notes_url="$(xmllint --xpath 'string(/*[local-name()="rss"]/*[local-name()="channel"]/*[local-name()="item"]/*[local-name()="releaseNotesLink"])' "$APPCAST_PATH")"
  enclosure_length="$(xmllint --xpath 'string(/*[local-name()="rss"]/*[local-name()="channel"]/*[local-name()="item"]/*[local-name()="enclosure"]/@length)' "$APPCAST_PATH")"
  enclosure_type="$(xmllint --xpath 'string(/*[local-name()="rss"]/*[local-name()="channel"]/*[local-name()="item"]/*[local-name()="enclosure"]/@type)' "$APPCAST_PATH")"
  appcast_short_version="$(xmllint --xpath 'string(/*[local-name()="rss"]/*[local-name()="channel"]/*[local-name()="item"]/*[local-name()="enclosure"]/@*[local-name()="shortVersionString"])' "$APPCAST_PATH")"
  appcast_build_version="$(xmllint --xpath 'string(/*[local-name()="rss"]/*[local-name()="channel"]/*[local-name()="item"]/*[local-name()="enclosure"]/@*[local-name()="version"])' "$APPCAST_PATH")"
  signature="$(xmllint --xpath 'string(/*[local-name()="rss"]/*[local-name()="channel"]/*[local-name()="item"]/*[local-name()="enclosure"]/@*[local-name()="edSignature"])' "$APPCAST_PATH")"
  [[ "$enclosure_url" == https://* ]] || fail "appcast enclosure URL must be HTTPS"
  [[ "$release_notes_url" == https://* ]] || fail "appcast release notes URL must be HTTPS"
  [[ "$enclosure_url" == *"DIFFMac-$BUILD_CONFIG.dmg" ]] || fail "appcast enclosure does not point to DIFFMac-$BUILD_CONFIG.dmg"
  if [[ "$enclosure_url" == *"/download/"* && "$release_notes_url" == *"/tag/"* ]]; then
    download_tag="${enclosure_url#*/download/}"
    download_tag="${download_tag%%/*}"
    notes_tag="${release_notes_url#*/tag/}"
    notes_tag="${notes_tag%%/*}"
    [[ "$download_tag" == "$notes_tag" ]] || fail "appcast release notes tag '$notes_tag' does not match download tag '$download_tag'"
  fi
  [[ "$enclosure_length" =~ ^[0-9]+$ && "$enclosure_length" -gt 0 ]] || fail "appcast enclosure length is invalid"
  if [[ -f "$DMG_PATH" ]]; then
    actual_dmg_length="$(stat -f%z "$DMG_PATH")"
    [[ "$enclosure_length" == "$actual_dmg_length" ]] || fail "appcast enclosure length '$enclosure_length' does not match DMG size '$actual_dmg_length'"
  fi
  [[ "$enclosure_type" == "application/x-apple-diskimage" ]] || fail "appcast enclosure type is invalid"
  [[ -n "$appcast_short_version" ]] || fail "appcast short version is missing"
  [[ -n "$appcast_build_version" ]] || fail "appcast build version is missing"
  [[ "$appcast_short_version" == "$short_version" ]] || fail "appcast short version '$appcast_short_version' does not match app '$short_version'"
  [[ "$appcast_build_version" == "$build_version" ]] || fail "appcast build version '$appcast_build_version' does not match app '$build_version'"
  if [[ "$REQUIRE_SPARKLE_SIGNATURE" == "1" ]]; then
    [[ -n "$signature" ]] || fail "appcast Sparkle signature is missing"
  fi
fi

echo "Package verification passed for $BUILD_CONFIG."
