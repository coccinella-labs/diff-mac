# DIFF Mac Release Checklist

## Local Verification

```bash
swift test
swift build
bash scripts/release-preflight.sh release
CREATE_DMG=1 bash scripts/package-app.sh release
UI_SMOKE_REQUIRE_WINDOW=1 bash scripts/ui-smoke.sh release
SPARKLE_PRIVATE_ED_KEY="<private-key>" bash scripts/generate-appcast.sh 0.1.0 v0.1.0
REQUIRE_DMG=1 REQUIRE_APPCAST=1 REQUIRE_SPARKLE_PUBLIC_KEY=1 REQUIRE_SPARKLE_SIGNATURE=1 bash scripts/verify-package.sh release
```

Confirm these files exist:

```text
dist/DIFF Mac.app
dist/DIFFMac-release.zip
dist/DIFFMac-release.dmg
dist/appcast.xml
```

Confirm the DMG contains both:

- `DIFF Mac.app`
- `Applications` symlink

The helper verification script checks the app bundle, version/build metadata, ZIP contents, DMG layout, URL scheme, Sparkle embedding, update feed keys, and appcast enclosure metadata:

```bash
REQUIRE_DMG=1 REQUIRE_APPCAST=1 REQUIRE_SPARKLE_PUBLIC_KEY=1 REQUIRE_SPARKLE_SIGNATURE=1 bash scripts/verify-package.sh release
```

Run the local UI smoke test from a logged-in macOS desktop session. The window assertion uses System Events and may require Accessibility permission for the terminal app:

```bash
UI_SMOKE_REQUIRE_WINDOW=1 bash scripts/ui-smoke.sh release
```

## Changelog

Keep [CHANGELOG.md](../CHANGELOG.md) as a pointer to GitHub Releases. Write the rendered changelog in the GitHub release body so links, screenshots, and artifacts are reviewed in the same surface users read.

Print the release URL:

```bash
bash scripts/release-url.sh
```

Open it locally:

```bash
bash scripts/release-url.sh --open
```

Before publishing, confirm the GitHub release body includes:

- a concise summary
- user-visible changes
- fixes
- known limitations
- attached ZIP/DMG artifacts

## Nightly Prerelease

Nightly prereleases are handled by `.github/workflows/nightly-prerelease.yml`.

- Runs daily at `03:17 UTC`.
- Can also be run manually with `workflow_dispatch`.
- Publishes a prerelease tag named `nightly-YYYYMMDD`.
- Uploads both `DIFFMac-release.zip` and `DIFFMac-release.dmg`.
- Uploads `appcast.xml` for update-feed validation.
- Marks the release as a prerelease and does not make it the latest stable release.

## Stable Release

Stable releases are handled by `.github/workflows/release.yml`.

- Runs on tags matching `vX.Y.Z`.
- Can also be run manually with `workflow_dispatch`.
- Builds, tests, packages ZIP and DMG artifacts, and publishes a GitHub Release.
- Uses the GitHub release body as the rendered changelog.
- Requires signing/notarization secrets before publishing stable artifacts.
- Recreates the ZIP after stapling the app and notarizes/staples the DMG before upload.
- Publishes `appcast.xml` next to release artifacts for Sparkle-compatible update feeds.

Generate a release notes starter locally:

```bash
bash scripts/release-notes-template.sh 0.1.0
```

Required stable release secrets:

- `CODESIGN_IDENTITY`
- `NOTARYTOOL_PROFILE`
- `SPARKLE_PUBLIC_ED_KEY`
- `SPARKLE_PRIVATE_ED_KEY`

GitHub browser OAuth also requires a deployed exchange endpoint. Configure the endpoint URL in app settings; do not ship the GitHub OAuth client secret in the macOS app.

Run the strict release preflight locally:

```bash
REQUIRE_SIGNING=1 REQUIRE_UPDATES=1 CODESIGN_IDENTITY="<identity>" NOTARYTOOL_PROFILE="<profile>" SPARKLE_PUBLIC_ED_KEY="<public-key>" SPARKLE_PRIVATE_ED_KEY="<private-key>" bash scripts/release-preflight.sh release
```

## Signing

Set an installed signing identity:

```bash
CODESIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" bash scripts/package-app.sh release
```

Verify:

```bash
codesign --verify --deep --strict --verbose=2 "dist/DIFF Mac.app"
spctl --assess --type execute --verbose "dist/DIFF Mac.app"
```

## Notarization

Submit the ZIP with `notarytool`, wait, then staple the app:

```bash
xcrun notarytool submit dist/DIFFMac-release.zip --keychain-profile "<profile>" --wait
xcrun stapler staple "dist/DIFF Mac.app"
```

Recreate the ZIP after stapling.

The helper script wraps those commands:

```bash
NOTARYTOOL_PROFILE="<profile>" bash scripts/notarize-app.sh
```

## Update Feed

Generate a Sparkle-compatible appcast after the final DMG exists:

```bash
SPARKLE_PRIVATE_ED_KEY="<private-key>" bash scripts/generate-appcast.sh 0.1.0 v0.1.0
```

For local dry-runs only, a precomputed placeholder signature can be passed with `SPARKLE_ED_SIGNATURE`; stable release automation should use `SPARKLE_PRIVATE_ED_KEY` so the signature is generated for the exact DMG artifact.

The packaged app reads `SUFeedURL` and `SUPublicEDKey` from its generated `Info.plist`. The release workflow requires `SPARKLE_PUBLIC_ED_KEY` for the app bundle and `SPARKLE_PRIVATE_ED_KEY` to sign `dist/appcast.xml` for the specific DMG being uploaded. Nightly prereleases also publish `appcast.xml` for validation, but the stable feed is the one intended for users.

## Preflight

- Confirm GitHub device-code OAuth works with the production client ID.
- Confirm Supabase browser sign-in, session refresh, and preference sync work with the production project.
- Confirm Keychain prompts are acceptable on a clean macOS user.
- Confirm destructive PR actions show confirmations.
- Confirm binary/large files are guarded in Code view.
- Confirm app icon appears in Finder and Dock.

## Production Setup

Before the first public stable release, complete these external setup items.

Apple signing and notarization:

- Create or install a Developer ID Application certificate.
- Ensure the GitHub Actions runner can access the signing certificate.
- Create a notarytool keychain profile named by `NOTARYTOOL_PROFILE`.
- Add `CODESIGN_IDENTITY` and `NOTARYTOOL_PROFILE` as GitHub Actions secrets.
- Run `REQUIRE_SIGNING=1 REQUIRE_UPDATES=1 bash scripts/release-preflight.sh release` with the same values expected in CI.

Sparkle updates:

- Generate a Sparkle EdDSA keypair.
- Add the public key as `SPARKLE_PUBLIC_ED_KEY`.
- Add the private key as `SPARKLE_PRIVATE_ED_KEY`.
- Confirm the packaged app has an HTTPS `SUFeedURL` ending in `appcast.xml`.
- Publish a test release and confirm `Check for Updates...` sees the appcast.

GitHub OAuth backend:

- Deploy an HTTPS endpoint that accepts the GitHub OAuth `code` and optional `state`.
- Store the GitHub OAuth client secret only on that backend.
- Return JSON containing `access_token` to the app.
- Configure the app setting `GitHub OAuth Exchange Endpoint` with that HTTPS URL.
- Confirm `diffmac://github-oauth` is registered in the GitHub OAuth app callback settings.

Supabase production project:

- Configure the Supabase project URL and anon key.
- Allow the native callback URL `diffmac://supabase-auth`.
- Confirm browser sign-in returns access and refresh tokens to the app.
- Confirm session refresh works after token expiry.
- Confirm pull/push preference sync merges local and remote data as expected.

Manual production QA:

- Test with a clean macOS user account.
- Test pasted GitHub token sign-in.
- Test GitHub device-code sign-in.
- Test GitHub browser OAuth sign-in through the deployed backend.
- Test loading pull requests, discussions, checks, commits, and changed files.
- Test file editing, conflict resolution, large-file guards, and binary guards.
- Test PR review actions, comments, merge/update/delete confirmations, and error handling.
- Test the signed DMG install flow from Finder.
- Test Sparkle update from an older signed build to the latest signed build.

Distribution decision:

- GitHub Releases ZIP/DMG is already supported.
- Decide whether to add a custom download page.
- Decide whether to pursue Mac App Store distribution separately; sandboxing and OAuth/update behavior may require app changes.

Accessibility audit:

- Run VoiceOver through the sidebar, PR detail tabs, Code editor, merge panel, and Settings.
- Confirm icon-only controls announce useful labels.
- Confirm disabled controls expose helpful reasons where possible.
- Confirm status and error messages are visible and understandable during failed network/auth actions.
