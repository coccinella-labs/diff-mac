<p align="center">
  <img src="https://raw.githubusercontent.com/Coccinella-Labs/diff-mac/main/.github/assets/thumbnail.png" alt="diff-mac" width="100%">
</p>

![DIFF Mac image](https://raw.githubusercontent.com/bniladridas/diff-mac/main/docs/assets/readme-hero.png)

# DIFF Mac

[![macos](https://img.shields.io/badge/macos-app-737373?style=flat-square)](docs/build-and-release.md)
[![swift](https://img.shields.io/badge/swift-package-f97316?style=flat-square)](Package.swift)
[![nightly](https://img.shields.io/badge/nightly-prerelease-64748b?style=flat-square)](.github/workflows/nightly-prerelease.yml)
[![release](https://img.shields.io/badge/release-dmg-5f7661?style=flat-square)](docs/release-checklist.md)

<br>

DIFF Mac is a native macOS app for working with GitHub pull requests.

It can browse pull requests, review changed files, read comments and checks, inspect commits and timeline events, browse branches, and commit file edits.

It stores secrets in Keychain. Supabase sync is optional.

## Run

```bash
swift run DIFFMac
```

## Docs

- [Build and release](docs/build-and-release.md)
- [OAuth and Supabase](docs/oauth-and-supabase.md)
- [Release checklist](docs/release-checklist.md)
