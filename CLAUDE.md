# CLAUDE.md — WoC Player Count

macOS menu-bar app (`LSUIElement`, no Dock icon) showing the live *World of Claudecraft*
player count + `$WOC` price (the spot price in the menu-bar label/header, plus a real OHLC
**candlestick chart** in the popover). Pure SwiftUI `MenuBarExtra(.window)`. There is **no Xcode
project**, WidgetKit target, or Dock app—the product is the menu-bar app only, with raw `swiftc`
driven by `build.sh`. The deployment floor is macOS 14.0 — consistent across
`build.sh` (`-target <arch>-apple-macos14.0`), `Info.plist` (`LSMinimumSystemVersion` 14.0), and
`Package.swift` (`.macOS("14.0")`); the built binary's `minos` reads 14.0. Public architecture,
preview, privacy, contribution, and release guidance lives under `docs/` and in the root public
policy files; this document keeps maintainer-only implementation invariants.

## Build, test, run
- `./build.sh` — compile all `Sources/**/*.swift`, ad-hoc sign, and **install to
  `/Applications/WoC Player Count.app`** (the `build/` bundle is *moved*, not copied, so there's
  exactly one copy — always the latest — and no Spotlight/Launchpad duplicate). This is the
  source of truth for "does it build", NOT the LSP/IDE.
- `./build.sh run` — build + install, then kill any running instance and relaunch the
  `/Applications` copy (the running app is always the latest).
- `./build.sh bundle` — optimized production bundle kept under `build/`, with no install or launch.
- `./build.sh preview` — windowed build (`-DPREVIEW`): a `WindowGroup` instead of
  `MenuBarExtra`, seeded with synthetic data, for screenshots / design work. Launches in place
  from `build/` and is **never installed** — don't let the preview binary reach `/Applications`.
  Use `WOC_NO_LAUNCH=1 ./build.sh preview` for automated compile/bundle verification and launch
  the binary with `WOC_PREVIEW_PAGE=overview|market|community|settings` and a
  `WOC_PREVIEW_STATE` documented in `docs/ARCHITECTURE.md` for a deterministic state/page
  combination.
- `swift test` — WoCKit unit tests via `Package.swift`. SwiftPM compiles ONLY
  `Sources/WoCKit` + `Tests/`; it never sees `App/` or `Views/` (those are build.sh-only).
- **Swift language mode is v5** (`Package.swift` `swiftLanguageModes: [.v5]`; `build.sh`
  `-swift-version 5`) even though `swift-tools-version` is 6.0 — deliberate. The code already
  follows Swift 6 best practice by hand (`@MainActor` store, `Sendable` seams/value types). Do
  NOT bump to the Swift 6 language mode or enable default-`MainActor` isolation on WoCKit — it
  would re-home the intentionally-`nonisolated` service/persistence seams onto the main actor.
- Verify UI changes with the page-specific preview build and `screencapture -l <window-id>`.
  SwiftUI controls inside `MenuBarExtra(.window)` are not reliably exposed in the AX tree, so do
  not depend on mouse automation for deterministic review.

## Architecture — two layers, strict boundary
- `Sources/WoCKit/` — SwiftUI-FREE logic library (and the test target): Config, Model,
  Networking, Store, Alerts, Analytics, Persistence, Notifications, System, Strings.
  **Never `import SwiftUI` here.**
- `Sources/Views/` + `Sources/App/` — SwiftUI. Views depend on WoCKit, never the reverse.

`StatusStore` (`@MainActor @Observable`, singleton `.shared`) is a THIN orchestrator: it
owns view state and delegates everything via protocol seams injected through default-param
init — `StatusFetching`/`CryptoFetching`/`CandleFetching` (over `HTTPClient`), `HistoryPersisting`,
`Notifier`, `LaunchAtLoginManaging` — plus the pure value types `HistoryAnalytics`
(clock-injected), `AlertEngine`, and `AdvancedAlertPolicyEngine`. Keep it thin; push logic into
those collaborators.
No DI container, no separate ViewModel layer, no `@AppStorage` (it can't live in `@Observable`).

`HistoryPersistenceWorker` is the narrow actor adapter around synchronous `HistoryPersisting`.
Startup load and coalesced saves stay off the main actor; `StatusStore` owns merge generations and
termination draining so an older snapshot cannot overwrite a sample that arrived during I/O.

The `$WOC` candlestick chart uses **real OHLC bars fetched ready-made from GeckoTerminal**
(`CandleFetching`/`GeckoTerminalService`), NOT bars synthesized from the DexScreener spot price —
that spot feed barely moves between polls, so synthesizing OHLC produced degenerate flat candles.
The store just holds the fetched `[Candle]`; no bucketing/persistence (so nothing to unit-test there).
DexScreener spot polling stays for the header price / menu-bar label / alerts.

Views are split into the fixed `OverviewPageView`/`MarketPageView`/`CommunityPageView` pages plus
per-section structs (`HeaderView`/`ChartCardView`/`CryptoChartCardView`/`FooterView`) so
`@Observable` tracking is scoped per section. Use `@Bindable`
ONLY in a view that writes `$store.x` back (e.g. the pickers, the settings panel).

## Conventions (enforced — a reviewer greps for violations)
- **Zero hard-coded values/strings.** Every constant has exactly one named home:
  - endpoints / timeouts / retention / staleness / chart-cap → `AppConfig`
  - colors, fonts, spacing, radii, shadows, opacities, frame sizes → DesignSystem
    (`Palette` / `Typo` / `Space` / `Radius` / `Shadow` / `Opacity` / `Size` / `Gradients`)
  - user-facing strings → `Resources/Localizable.xcstrings`, accessed via `Str`
    (SwiftUI `LocalizedStringKey`), `AppText` (Foundation `String(localized:)`), `AlertPresenter`
  - UserDefaults keys → `DefaultsKey`; notification ids → `AlertKind`; poll options → `PollInterval`
  - pure numeric/value interpolation (`"$\(price)"`, `"\(count)"`) is fine in view bodies.
  - time-unit abbreviations (`10s` / `1m` / `24h` / `4h`) are requested by each interval enum's
    `label` and resolved through `AppText.compactDuration` + the String Catalog.
- New user-facing string ⇒ add the key to `Localizable.xcstrings` AND its accessor enum.
  build.sh compiles the catalog with `xcstringstool`; a missing key shows the raw key at runtime.
- Match surrounding comment density and naming; tokens are value-suffixed (`Space.s12`, `Radius.r14`).

## DO-NOT-REGRESS invariants (deliberate workarounds; reverting reintroduces real bugs)
1. **⚠️ IMPORTANT — no always-on animation in popover content** (costliest invariant if
   violated). `MenuBarExtra(.window)` re-presents in a
   loop (~40% idle CPU even while closed) if content animates perpetually or its measured
   size oscillates. The badge pulse is gated `isActive: scenePhase == .active && !reduceMotion`
   (the `!reduceMotion` half is load-bearing for accessibility — keep it); the footer
   `TimelineView`/`ProgressView` are tolerated only because they're scoped to the OPEN
   popover. After touching the badge/footer/scene/DesignSystem, re-measure idle CPU:
   `ps -p <pid> -o %cpu=` with the popover CLOSED must read ~0%.
2. **Settings is inline** (toggled by `showingSettings`), never a separate window —
   `openSettings`/`openWindow`/`SettingsLink`/`NSWindow` are unreliable under LSUIElement.
3. **One FIXED popover size** (440×660 for dashboard and inline settings) — named constants in
   `Size`, never measured / dynamic / animated. The footer is **pinned to the bottom** (outside
   page `ScrollView`s); page content scrolls within the fixed frame. If you add/remove rows,
   re-measure the result without introducing width transitions.
4. **Two independent timers** (status + crypto), separate in-flight guards set synchronously
   BEFORE the first `await`; the selected-page footer refresh preserves feed ownership and market
   requests run concurrently. Don't merge the timers. The
   crypto timer fires `refreshCryptoTick()` = spot price (DexScreener) + OHLC candles
   (GeckoTerminal) concurrently via `async let`, each with its own in-flight guard — still one timer.
5. **No `didSet` during `init`.** The settings seeds (esp. `launchAtLogin = launch.isEnabled`)
   must not fire observers, or every launch re-registers the login item / restarts timers.
6. **Frozen persisted compatibility.** `history.json` remains ISO-8601 `[Sample]`; the recovery
   sidecar may repair it but cannot replace that primary format. Existing UserDefaults key strings
   are frozen; new alert/menu keys stay typed in `DefaultsKey`. There is NO UserDefaults key for
   launch-at-login (`SMAppService.mainApp.status` is the source of truth).
7. **Feed isolation.** A crypto/community/decode/persistence failure must never flip the realm to
   server-reported-down or clear valid cached data. Only repeated remote status failures may claim
   an outage. Keep spot, candle, community, and status freshness/error state independent.
8. **Alert semantics + menu-bar truthfulness:** skip-first-observation for transitions, no peak on
   the first-ever sample, advanced threshold hysteresis and per-rule cooldowns, suppressed events
   consumed rather than replayed, stable notification rule IDs, stale price omitted/marked, and
   `Text(verbatim: store.menuBarLabel)`.
9. **Frozen visual identity; content-layer material is correct.** DesignSystem extractions are
   pixel-identical in the default render. The popover cards/pills are the content layer; do not
   replace them with a new SDK-only glass API or raise the deployment floor without an explicit
   product decision. `glassCard()`/`glassPill()` (and the popover background)
   are ViewModifiers that swap to opaque `Palette.cardOpaque`/`pillOpaque` under Reduce Transparency;
   cards use `Palette.cardStrokeStrong` and pills increase border width under Increase Contrast.
   Keep the default branch byte-identical.
10. **One `@main` + `-parse-as-library` + the `#if PREVIEW` scene branch** survive any file split.
11. **`build.sh` stays the build/install path** (compile → bundle → codesign → move to
    `/Applications`). The preview build is the lone exception: local, never installed.
12. **Swift v5 language mode** (see *Build, test, run*). `Package.swift swiftLanguageModes: [.v5]`
    + `build.sh -swift-version 5`, despite `swift-tools-version` 6.0. Do NOT bump to the Swift 6
    language mode / default-`MainActor` isolation — it re-homes the intentionally-`nonisolated`
    WoCKit service/persistence seams onto the main actor.

## Gotchas
- **LSP false positive:** the IDE reports `@main attribute cannot be used in a module that
  contains top-level code`. Ignore it — it doesn't see `-parse-as-library`. Trust `./build.sh`.
- **SDK > deployment floor (expected, not a bug):** the binary's `minos` is pinned to 14.0 by
  `build.sh`'s `-target`, while the SDK it links against can be newer. That skew is intentional.
- **Preview-only code** (synthetic player/market data, offline community fixtures, isolated
  defaults/history/clock/side effects, distinct bundle identity, and destination selection) is
  `#if PREVIEW` — never ships in release.
- **GeckoTerminal pool address is case-sensitive.** `AppConfig.API.geckoPool` = `5wE9YJ…` (mixed
  case). DexScreener lowercases the same address, which GeckoTerminal 404s on — keep the exact case.
  GeckoTerminal OHLCV is free/no-key; the `CandleInterval` set maps 1:1 to its timeframes (minute
  1/5/15, hour 1/4), which is why there's no 30m candle.

## Repo etiquette
- Do NOT commit, branch, or push unless explicitly asked.
- Before calling a change done, run `scripts/verify.sh`. It checks shell helpers, Swift tests, the
  complete app source, both production/preview bundles, signing, and bounded popover-closed CPU/RSS
  thresholds against an isolated temporary home. It never replaces the `/Applications` copy.
  `MenuBarExtra` still cannot be opened/closed programmatically, so re-measure manually after an
  open→close cycle for any badge/footer/scene/DesignSystem edit.
