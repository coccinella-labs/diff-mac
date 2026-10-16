#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_CONFIG="${1:-debug}"
APP_PATH="$ROOT_DIR/dist/DIFF Mac.app"
PROCESS_NAME="DIFFMac"
BUNDLE_ID="com.bniladridas.diff-mac"
REQUIRE_WINDOW="${UI_SMOKE_REQUIRE_WINDOW:-1}"

fail() {
  echo "UI smoke failed: $1" >&2
  exit 1
}

cleanup() {
  osascript -e "tell application id \"$BUNDLE_ID\" to quit" >/dev/null 2>&1 || true
}
trap cleanup EXIT

if [[ ! -d "$APP_PATH" ]]; then
  bash "$ROOT_DIR/scripts/package-app.sh" "$BUILD_CONFIG"
fi

open -n "$APP_PATH"

process_ready=0
for _ in {1..40}; do
  if pgrep -x "$PROCESS_NAME" >/dev/null; then
    process_ready=1
    break
  fi
  sleep 0.25
done

[[ "$process_ready" == "1" ]] || fail "$PROCESS_NAME did not launch"

window_ready=0
last_window_error=""
for _ in {1..40}; do
  set +e
  result="$(
    osascript \
      -e 'tell application "System Events"' \
      -e "if not (exists process \"$PROCESS_NAME\") then return \"missing-process\"" \
      -e "tell process \"$PROCESS_NAME\"" \
      -e 'if (count of windows) > 0 then return "window-ready"' \
      -e 'return "no-window"' \
      -e 'end tell' \
      -e 'end tell' 2>&1
  )"
  status=$?
  set -e

  if [[ "$status" == "0" && "$result" == "window-ready" ]]; then
    window_ready=1
    break
  fi

  last_window_error="$result"
  sleep 0.25
done

if [[ "$window_ready" != "1" ]]; then
  if [[ "$REQUIRE_WINDOW" == "1" ]]; then
    fail "main window was not observable. System Events output: $last_window_error"
  fi
  echo "warning: main window was not observable. System Events output: $last_window_error" >&2
fi

echo "UI smoke passed for $BUILD_CONFIG."
