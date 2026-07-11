# Releases and distribution

## Current status: source only

WoC Player Count currently publishes source code and release notes, not a prebuilt macOS app, app
ZIP, or DMG. Users build and install it locally by following
[LOCAL_INSTALL.md](LOCAL_INSTALL.md). That workflow needs macOS 14+, full Xcode 16+, and no paid
Apple Developer Program membership. It ad-hoc signs the resulting bundle on the user's own Mac.

Do not upload or redistribute an app produced by `install.sh` or `build.sh`. An ad-hoc signature is
appropriate for a local build but does not establish a distributable developer identity or provide
Apple notarization. Never instruct users to disable Gatekeeper to run one.

## Publish a source-only GitHub release

A source-only GitHub release provides a stable tag, release notes, and GitHub's automatically
generated source archives. It does not use an Apple account, signing certificate, or notarization
service.

1. Start from a clean, up-to-date `main` branch and confirm the intended version metadata and
   changelog are ready.
2. Run the complete local gate:

   ```bash
   ./scripts/verify.sh
   ./scripts/smoke-live-api.py
   ```

   The live smoke test is diagnostic because upstream availability must not gate normal CI.
   Investigate contract failures while distinguishing an upstream outage from a schema regression.

3. Create and push a signed or annotated version tag.
4. Create a GitHub Release for that tag and clearly label it **Source-only release**. Link to the
   [local installation guide](LOCAL_INSTALL.md) in the release notes.
5. Attach no `.app`, application ZIP, or DMG. The generated **Source code (zip)** and **Source code
   (tar.gz)** links are source archives that users must build locally, not runnable app downloads.

Do not replace a tag after publishing it. If a release points to the wrong source, explain the
withdrawal, correct the source, and publish a new version rather than silently moving the tag.

## Optional future notarized binary distribution

The repository retains a binary-release pipeline for a future maintainer who deliberately chooses
to join the paid Apple Developer Program. A public binary release must be universal
arm64/x86_64, signed with Developer ID, hardened, notarized, stapled, and distributed as ZIP and DMG
artifacts with SHA-256 checksums. The bundle and DMG also carry the project license, privacy policy,
and credits.

Nothing in this section is required for local source builds. Never publish an ad-hoc-signed or
unnotarized binary.

### One-time binary-distribution setup

1. Use macOS 14 or newer with Xcode 16+ selected—not only the standalone Command Line Tools:

   ```bash
   sudo xcode-select --switch /Applications/Xcode.app
   xcodebuild -version
   swift --version
   ```

2. Register the bundle identifier `io.github.fernandox7.wocplayercount` in the Apple Developer
   account used to distribute the app.
3. Install a **Developer ID Application** certificate in the login keychain.
4. Store notarization credentials in the keychain:

   ```bash
   xcrun notarytool store-credentials woc-notary \
     --apple-id "APPLE_ID" --team-id "TEAM_ID" --password "APP_SPECIFIC_PASSWORD"
   ```

5. In GitHub, enable private vulnerability reporting, protect `main`, and require the CI workflow.

Signing certificates, exported identities, API credentials, and notary passwords belong in the
developer keychain or encrypted CI secrets—never in this repository.

### Prepare a binary release

1. Start from a clean, up-to-date `main` branch.
2. Choose a Semantic Versioning release number and monotonically increasing build number.
3. Update `CFBundleShortVersionString` and `CFBundleVersion` in `Info.plist`.
4. Move the relevant entries in [CHANGELOG.md](../CHANGELOG.md) from **Unreleased** to the version and
   release date.
5. Confirm README screenshots, privacy disclosures, provider credits, and support links are current.
6. Run the complete local gate:

   ```bash
   ./scripts/verify.sh
   ./scripts/smoke-live-api.py
   ```

The live smoke test is diagnostic because upstream availability must not gate normal CI. Investigate
contract failures before release; do not blindly retry until a real schema regression disappears.

### Build notarized artifacts

```bash
DEVELOPER_ID_APPLICATION="Developer ID Application: Example (TEAMID)" \
NOTARY_PROFILE=woc-notary \
VERSION=1.0.0 \
BUILD_NUMBER=1 \
./scripts/release.sh
```

`VERSION` accepts two or three numeric components; `BUILD_NUMBER` must be an integer from 1 through
9999. Overrides affect only the staged bundle, so keep `Info.plist` aligned in the release commit.

The script:

1. compiles arm64 and x86_64 binaries and combines them with `lipo`;
2. compiles localization resources and includes the app icon and public notices;
3. signs the app with the hardened runtime;
4. notarizes and staples the app;
5. rebuilds the ZIP so it contains the stapled app;
6. builds, signs, notarizes, staples, and validates the DMG; and
7. writes SHA-256 checksums for both downloadable artifacts.

This ordering follows Apple's [custom notarization
workflow](https://developer.apple.com/documentation/security/customizing-the-notarization-workflow).

An intentionally unnotarized local pipeline test requires both a Developer ID identity and
`ALLOW_UNNOTARIZED_RELEASE=1`. The output is labeled accordingly and must not be uploaded.

### Verify the binary candidate

Artifacts are written to `release/`:

- `WoC Player Count-VERSION.zip`
- `WoC Player Count-VERSION.dmg`
- `WoC Player Count-VERSION-SHA256SUMS.txt`

Verify checksums from the release directory:

```bash
cd release
shasum -a 256 -c "WoC Player Count-VERSION-SHA256SUMS.txt"
```

Then verify the exact candidate:

```bash
xcrun stapler validate "release/WoC Player Count-VERSION.dmg"
spctl --assess --type open -vv "release/WoC Player Count-VERSION.dmg"
```

Mount the DMG, drag the app to Applications, and run:

```bash
codesign --verify --deep --strict --verbose=2 "/Applications/WoC Player Count.app"
spctl --assess --type execute -vv "/Applications/WoC Player Count.app"
```

Test a fresh install and an upgrade on Apple silicon and Intel hardware or equivalent CI runners.
Confirm:

- menu-bar launch, quit, and launch at login;
- notification permission, test delivery, mute, and disable actions;
- realm, market, community, cached/offline, and partial-feed states;
- history export and permanent deletion;
- companion privacy, support, source, and license links;
- VoiceOver, keyboard chart inspection, and Reduce Motion; and
- near-zero idle CPU after closing the popover.

### Publish binary artifacts on GitHub

1. Commit the version/changelog update and confirm CI passes on `main`.
2. Create a signed or annotated tag such as `v1.0.0` at that commit.
3. Create a GitHub Release from the tag using the changelog entry as release notes, explicitly
   describing it as a signed and notarized binary release.
4. Upload the DMG, ZIP, and checksum file generated by the same release run.
5. Mark a release as pre-release when it has not completed the full hardware and accessibility
   matrix.
6. Download the published files once and verify their checksums and Gatekeeper assessment again.

Do not replace artifacts under an existing tag. If a candidate is wrong, delete the draft, fix the
source, increment the build number, and produce a new candidate. If a published version must be
withdrawn, explain why in the release notes and publish a corrected version rather than silently
swapping binaries.
