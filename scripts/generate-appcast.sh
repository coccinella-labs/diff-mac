#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION="${1:?Usage: scripts/generate-appcast.sh <version> <tag> [artifact-path]}"
TAG="${2:?Usage: scripts/generate-appcast.sh <version> <tag> [artifact-path]}"
ARTIFACT_PATH="${3:-$ROOT_DIR/dist/DIFFMac-release.dmg}"
OUTPUT_PATH="${APPCAST_OUTPUT:-$ROOT_DIR/dist/appcast.xml}"
RELEASES_URL="${DIFFMAC_RELEASES_URL:-https://github.com/bniladridas/diff-mac/releases}"
DOWNLOAD_BASE_URL="${DIFFMAC_DOWNLOAD_BASE_URL:-$RELEASES_URL/download/$TAG}"
RELEASE_NOTES_URL="${DIFFMAC_RELEASE_NOTES_URL:-$RELEASES_URL/tag/$TAG}"
MIN_SYSTEM_VERSION="${DIFFMAC_MIN_SYSTEM_VERSION:-15.0}"
BUILD_NUMBER="${DIFFMAC_BUILD:-1}"
REQUIRE_SPARKLE_SIGNATURE="${REQUIRE_SPARKLE_SIGNATURE:-0}"
SPARKLE_SIGN_UPDATE_TOOL="${SPARKLE_SIGN_UPDATE_TOOL:-$ROOT_DIR/.build/artifacts/sparkle/Sparkle/bin/sign_update}"

xml_escape() {
  local value="$1"
  value="${value//&/&amp;}"
  value="${value//</&lt;}"
  value="${value//>/&gt;}"
  value="${value//\"/&quot;}"
  value="${value//\'/&apos;}"
  printf '%s' "$value"
}

if [[ ! -f "$ARTIFACT_PATH" ]]; then
  echo "Missing artifact: $ARTIFACT_PATH" >&2
  exit 1
fi

case "$ARTIFACT_PATH" in
  *.dmg) mime_type="application/x-apple-diskimage" ;;
  *.zip) mime_type="application/zip" ;;
  *) mime_type="application/octet-stream" ;;
esac

artifact_name="$(basename "$ARTIFACT_PATH")"
download_url="$DOWNLOAD_BASE_URL/$artifact_name"
length="$(stat -f%z "$ARTIFACT_PATH")"

signature_attribute=""
if [[ -n "${SPARKLE_ED_SIGNATURE:-}" ]]; then
  signature_attribute=" sparkle:edSignature=\"$(xml_escape "$SPARKLE_ED_SIGNATURE")\""
elif [[ -x "$SPARKLE_SIGN_UPDATE_TOOL" ]]; then
  if [[ -n "${SPARKLE_PRIVATE_ED_KEY:-}" ]]; then
    signature="$("$SPARKLE_SIGN_UPDATE_TOOL" --ed-key-file - -p "$ARTIFACT_PATH" <<< "$SPARKLE_PRIVATE_ED_KEY")"
    signature_attribute=" sparkle:edSignature=\"$(xml_escape "$signature")\""
  elif [[ "${SPARKLE_ALLOW_KEYCHAIN_SIGNING:-0}" == "1" ]]; then
    signature="$("$SPARKLE_SIGN_UPDATE_TOOL" -p "$ARTIFACT_PATH")"
    signature_attribute=" sparkle:edSignature=\"$(xml_escape "$signature")\""
  fi
fi

if [[ "$REQUIRE_SPARKLE_SIGNATURE" == "1" && -z "$signature_attribute" ]]; then
  echo "A Sparkle signature is required when REQUIRE_SPARKLE_SIGNATURE=1." >&2
  echo "Set SPARKLE_PRIVATE_ED_KEY, SPARKLE_ED_SIGNATURE, or SPARKLE_ALLOW_KEYCHAIN_SIGNING=1." >&2
  exit 1
fi

mkdir -p "$(dirname "$OUTPUT_PATH")"
cat > "$OUTPUT_PATH" <<XML
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>DIFF Mac Updates</title>
    <link>$(xml_escape "$RELEASES_URL")</link>
    <description>Release feed for DIFF Mac.</description>
    <item>
      <title>DIFF Mac $(xml_escape "$VERSION")</title>
      <sparkle:releaseNotesLink>$(xml_escape "$RELEASE_NOTES_URL")</sparkle:releaseNotesLink>
      <pubDate>$(date -u '+%a, %d %b %Y %H:%M:%S +0000')</pubDate>
      <enclosure
        url="$(xml_escape "$download_url")"
        length="$length"
        type="$mime_type"
        sparkle:version="$(xml_escape "$BUILD_NUMBER")"
        sparkle:shortVersionString="$(xml_escape "$VERSION")"
        sparkle:minimumSystemVersion="$(xml_escape "$MIN_SYSTEM_VERSION")"$signature_attribute />
    </item>
  </channel>
</rss>
XML

echo "$OUTPUT_PATH"
