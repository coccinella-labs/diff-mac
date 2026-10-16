#!/usr/bin/env bash
set -euo pipefail

REPO_URL="${DIFFMAC_RELEASES_URL:-https://github.com/bniladridas/diff-mac/releases}"

if [[ "${1:-}" == "--open" ]]; then
  open "$REPO_URL"
else
  echo "$REPO_URL"
fi
