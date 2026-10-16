#!/usr/bin/env bash
set -euo pipefail

BUILD_CONFIG="${1:-release}"
REQUIRE_SIGNING="${REQUIRE_SIGNING:-0}"
REQUIRE_UPDATES="${REQUIRE_UPDATES:-0}"

missing=()

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    missing+=("command: $1")
  fi
}

require_env() {
  if [[ -z "${!1:-}" ]]; then
    missing+=("env: $1")
  fi
}

require_command swift
require_command ditto
require_command hdiutil
require_command codesign
require_command spctl
require_command xcrun
require_command gh

if [[ "$BUILD_CONFIG" == "release" && "$REQUIRE_SIGNING" == "1" ]]; then
  require_env CODESIGN_IDENTITY
  require_env NOTARYTOOL_PROFILE
fi

if [[ "$BUILD_CONFIG" == "release" && "$REQUIRE_UPDATES" == "1" ]]; then
  require_env SPARKLE_PUBLIC_ED_KEY
  if [[ -z "${SPARKLE_PRIVATE_ED_KEY:-}" && -z "${SPARKLE_ED_SIGNATURE:-}" && "${SPARKLE_ALLOW_KEYCHAIN_SIGNING:-0}" != "1" ]]; then
    missing+=("env: SPARKLE_PRIVATE_ED_KEY or SPARKLE_ED_SIGNATURE or SPARKLE_ALLOW_KEYCHAIN_SIGNING=1")
  fi
fi

if (( ${#missing[@]} > 0 )); then
  echo "Release preflight failed. Missing requirements:" >&2
  for item in "${missing[@]}"; do
    echo "- $item" >&2
  done
  exit 1
fi

if [[ "$BUILD_CONFIG" == "release" ]]; then
  if [[ -z "${CODESIGN_IDENTITY:-}" ]]; then
    echo "warning: CODESIGN_IDENTITY is not set; app bundle will not be Developer ID signed." >&2
  fi
  if [[ -z "${NOTARYTOOL_PROFILE:-}" ]]; then
    echo "warning: NOTARYTOOL_PROFILE is not set; artifacts will not be notarized." >&2
  fi
  if [[ -z "${SPARKLE_PUBLIC_ED_KEY:-}" ]]; then
    echo "warning: SPARKLE_PUBLIC_ED_KEY is not set; packaged app will not include a Sparkle public key." >&2
  fi
  if [[ -z "${SPARKLE_PRIVATE_ED_KEY:-}" && -z "${SPARKLE_ED_SIGNATURE:-}" && "${SPARKLE_ALLOW_KEYCHAIN_SIGNING:-0}" != "1" ]]; then
    echo "warning: no Sparkle signing source is configured; appcast.xml will not include an archive signature." >&2
  fi
fi

echo "Release preflight passed for $BUILD_CONFIG."
