# Contributing to WoC Player Count

Thanks for helping make WoC Player Count more useful, reliable, and delightful. Bug reports,
accessibility improvements, documentation, tests, and focused feature proposals are welcome.

By contributing, you agree that your contribution may be distributed under the repository's
[MIT License](LICENSE).

## Before you start

- Search existing issues before opening a duplicate.
- Use an issue to discuss a large feature or behavior change before investing in an implementation.
- Report security vulnerabilities privately as described in [SECURITY.md](SECURITY.md).
- Do not include game credentials, wallet keys, notification contents, private player data, or API
  secrets in an issue, fixture, screenshot, or test log.

## Development setup

You need macOS 14 or newer and a full Xcode 16 or newer installation with its Swift 6 toolchain
selected. The standalone Command Line Tools are insufficient, but a paid Apple Developer Program
membership is not required:

```bash
sudo xcode-select --switch /Applications/Xcode.app
xcodebuild -version
swift --version
```

Fork and clone the repository, then run:

```bash
./install.sh --check
swift test
./build.sh check
WOC_NO_LAUNCH=1 ./build.sh preview
WOC_SKIP_RESOURCE_CHECK=1 ./scripts/verify.sh
```

Run `./scripts/verify.sh` without the skip before distribution-sensitive changes; that adds the
bounded closed-popover CPU and memory check.

## Project shape

- `Sources/WoCKit/` is the SwiftUI-free, SwiftPM-tested domain layer.
- `Sources/Views/` and `Sources/App/` contain the native macOS interface and entry point.
- `Resources/Localizable.xcstrings` owns all user-facing and accessibility copy.
- `install.sh` is the friendly source-install entry point; `build.sh` is the lower-level app build
  and bundle path. `Package.swift` intentionally builds only WoCKit and its tests.

Read [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) before changing store boundaries, refresh behavior,
persistence, alerts, or popover layout.

## Engineering expectations

- Keep realm, quote, candle, and community feed states independent and truthful. Cached data must
  never be labeled live, and a market failure must never claim the realm is down.
- Keep WoCKit free of SwiftUI, AppKit, and Charts imports.
- Preserve the fixed popover frame and pinned footer. Do not add perpetual animations or measured
  popover sizing.
- Route user-visible text through the String Catalog and update localization checks.
- Add deterministic tests for policy, decoding, analytics, persistence, and accessibility copy.
- Use synthetic names and values in fixtures; do not freeze real community identities.
- Keep the app icon independent from the World of ClaudeCraft crest and other upstream branding.

Use the preview state/page/text-size matrix documented in
[docs/ARCHITECTURE.md](docs/ARCHITECTURE.md#deterministic-preview) for visual changes. Include the
states you checked in the pull request.

## Pull requests

Keep changes focused and explain:

1. the user-visible outcome;
2. why the approach is truthful and safe;
3. tests and preview states exercised; and
4. any data, compatibility, accessibility, or distribution implications.

The CI verification job must pass before merge. Maintainers may ask for a smaller change, more test
coverage, or an updated screenshot when that makes review safer.
