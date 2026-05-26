# Build and Release

## Run

From source:

```bash
swift run DIFFMac
```

Packaged app:

```bash
bash scripts/open-app.sh
```

## Build

```bash
swift build
```

## Package

App bundle and ZIP:

```bash
bash scripts/package-app.sh
```

Outputs:

```text
dist/DIFF Mac.app
dist/DIFFMac-release.zip
```

DMG:

```bash
CREATE_DMG=1 bash scripts/package-app.sh release
```

## Release Helpers

Appcast:

```bash
SPARKLE_PRIVATE_ED_KEY="<private-key>" bash scripts/generate-appcast.sh 0.1.0 v0.1.0
```

Release notes URL:

```bash
bash scripts/release-url.sh
```

Release notes text:

```bash
bash scripts/release-notes-template.sh 0.1.0
```

## Distribution

Distribution requires:

- Signing.
- Notarization.
- Sparkle public EdDSA key in the app.
- Sparkle EdDSA signature in the appcast.

Local signing:

```bash
CODESIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" bash scripts/package-app.sh release
```
