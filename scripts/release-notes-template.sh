#!/usr/bin/env bash
set -euo pipefail

VERSION="${1:-}"

if [[ -z "$VERSION" ]]; then
  echo "Usage: scripts/release-notes-template.sh <version>" >&2
  exit 1
fi

cat <<EOF
# DIFF Mac ${VERSION}

## Summary

- 

## User-visible changes

- 

## Fixes

- 

## Known limitations

- GitHub browser OAuth code exchange requires a configured backend endpoint; use device-code sign-in for fully local auth.
- Supabase browser sign-in depends on the project allowing the `diffmac://supabase-auth` callback URL.

## Artifacts

- DIFFMac-release.zip
- DIFFMac-release.dmg
EOF
