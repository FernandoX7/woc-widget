# Architecture and visual QA

WoC Player Count is one native, menu-bar-only macOS application. There is no WidgetKit extension,
Dock scene, Xcode project, or separate settings window. The app targets macOS 14+, uses SwiftUI and
Swift Charts for presentation, and keeps domain logic testable through SwiftPM.

## Layers

- `Sources/WoCKit/` contains SwiftUI-free models, networking, stores, alert policy, analytics,
  persistence, notifications, configuration, and system seams.
- `Sources/Views/` and `Sources/App/` contain pages, charts, the design system, popover shell, app
  delegate, and single `@main` entry point.
- `Tests/WoCKitTests/` provides deterministic swift-testing coverage for services, decoding,
  analytics, alert reducers/integration, stores, export, formatting, and persistence recovery.

`Package.swift` builds only WoCKit and its tests. `build.sh` compiles the full `Sources/` tree,
assembles the app bundle, compiles localization resources, and signs the result.

## Data flow

```text
World of ClaudeCraft status ───────────────┐
DEX Screener spot + market windows ────────┼─> StatusStore ─> menu label / Overview / $WOC
GeckoTerminal OHLCV ───────────────────────┘       │
                                                   ├─> history + records + smart alerts
WoC project/release/leaderboard/realm APIs ─> CommunityStore ─> Community + release observation
```

`StatusStore` is the `@MainActor @Observable` source of truth and an orchestrator over injected
services. Pure decisions live in `HistoryAnalytics`, `AlertEngine`, `AdvancedAlertPolicyEngine`,
`MarketFeedPolicy`, and `HistorySampleNormalizer`. External effects live behind `HTTPClient`,
`HistoryPersisting`, `Notifier`, and `LaunchAtLoginManaging` seams.

## Dashboard contract

The popover keeps one stable 440×660 content frame:

1. **Overview** presents realm health, population history, records, and Realm Rhythm.
2. **$WOC** presents spot context, rolling activity, OHLC candles, and market health.
3. **Community** presents project, release, leaderboard, and realm feeds.
4. **Settings** replaces the dashboard inline and returns with Escape, Back, or Done.

The header, page switcher, and footer remain fixed. Each page owns its scrolling. This avoids the
re-presentation loop that `MenuBarExtra(.window)` can enter when measured content oscillates.

## Refresh and truthfulness

- Player status and the DEX Screener quote use independent timers and in-flight guards.
- Candles refresh only while the popover is visible, after an interval change, or on explicit
  refresh.
- Community sections load on demand, cache independently, and retry only feeds that need work.
- A realm-down alert requires two consecutive remote-failure observations. Local decode,
  persistence, or market errors never confirm an outage.
- Every feed owns attempt, success, freshness, and cached/unavailable state. A healthy zero-player
  response remains online.

## History and persistence

Observed player samples are retained for seven days. Writes are coalesced and atomically update
`~/Library/Application Support/WoCWidget/history.json`; a bounded sidecar supports corruption
recovery. Blocking file work is serialized off the main actor. Startup merges samples that arrive
during the initial read, and termination awaits a bounded final flush.

Clear Local History removes both snapshots and the independently stored local peak. The JSON format
remains an ISO-8601-encoded `[Sample]` array for backward compatibility.

## Alerts

Alert evaluation is baseline-safe: launch does not invent crossings, threshold rules rearm only
after a hysteresis deadband, suppressed events are consumed rather than replayed after quiet hours,
and cooldowns are tracked per stable rule. Successful realm, rich-market, and release observations
are the only inputs. Notification actions carry a stable rule identity so muting one rule cannot
affect another.

## Accessibility

- The menu label exposes semantic realm, population, price, and change text.
- Player and candle charts expose Audio Graph descriptors and keyboard inspection.
- Rising candles are filled and falling candles hollow, in addition to color.
- Reduce Motion removes digit-roll and pulse motion.
- Reduce Transparency uses opaque surfaces; Increase Contrast strengthens text and borders.
- Typography follows Dynamic Type with role-specific caps and an accessibility-size header layout.

## Deterministic preview

`./build.sh preview` swaps `MenuBarExtra` for a normal `WindowGroup`, isolates defaults and history,
uses a fixed clock and offline services, and disables notifications and launch integration.

```bash
WOC_NO_LAUNCH=1 ./build.sh preview
WOC_PREVIEW_STATE=cached-offline WOC_PREVIEW_PAGE=community \
  "build/WoC Player Count.app/Contents/MacOS/WoCWidget"
```

Pages: `overview`, `market`, `community`, and `settings`.

| State | Primary visual contract |
| --- | --- |
| `live` / `happy` | Fresh realm, history, quote, candles, community, and authorized alerts |
| `welcome` / `first-run` | Live fixtures with the first-run welcome card |
| `loading` | Initial loading treatment across all feeds |
| `cached-offline` / `offline` | Two-hour-old values with honest cached/offline provenance |
| `quote-only` / `partial-market` | Live quote with unavailable candles |
| `chart-only` | Live candles with unavailable quote |
| `empty-history` | Healthy feeds with no local population history |
| `notification-denied` | Healthy feeds with enabled alerts blocked by macOS permission |

`WOC_PREVIEW_TEXT_SIZE=accessibility1` through `accessibility5` (or `maximum`) composes with every
state and page.

## Invariants

- No WidgetKit or application-extension target.
- One fixed popover frame and no perpetual animation while closed.
- WoCKit remains free of SwiftUI, AppKit, and Charts.
- Preview code cannot contact production endpoints or mutate production state.
- User-facing text resolves through the String Catalog.
- Market failures never change realm availability.
- Cached values are never represented as live.

`scripts/check-source-invariants.sh`, `scripts/check-localizations.py`, and `scripts/verify.sh`
enforce these boundaries.
