#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_PATH="$ROOT_DIR/dist/DIFF Mac.app"

if [[ ! -d "$APP_PATH" ]]; then
  bash "$ROOT_DIR/scripts/package-app.sh" debug
fi

open "$APP_PATH"
