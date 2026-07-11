# WoC Player Count

[![CI](https://github.com/FernandoX7/woc-widget/actions/workflows/ci.yml/badge.svg)](https://github.com/FernandoX7/woc-widget/actions/workflows/ci.yml)
[![Live API contracts](https://github.com/FernandoX7/woc-widget/actions/workflows/live-api-contracts.yml/badge.svg)](https://github.com/FernandoX7/woc-widget/actions/workflows/live-api-contracts.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-7c5cff.svg)](LICENSE)
[![macOS 14+](https://img.shields.io/badge/macOS-14%2B-35d6ed.svg)](https://www.apple.com/macos/)

<p align="center">
  <img src="scripts/icon-source.png" width="144" alt="WoC Player Count world-and-signal icon">
</p>

A beautiful native macOS menu-bar companion for
[World of ClaudeCraft](https://worldofclaudecraft.com). It keeps live realm population and the
`$WOC` market visible at a glance, then opens into a focused dashboard for local history, community
activity, and configurable alerts.

> **Independent community project.** WoC Player Count is not affiliated with or endorsed by World
> of ClaudeCraft, Dream Home AI Limited, or Levy Street. It never asks for game credentials or a
> wallet connection.

This is a menu-bar app, not a WidgetKit extension: it has no Dock icon, desktop widget, or separate
settings window.

![WoC Player Count overview](docs/preview.png)

## Highlights

- **One calm menu-bar signal** — show Players + `$WOC`, Full, Players, or Token. Stale values are
  visibly distinguished and unavailable prices are never presented as live.
- **Realm overview** — live status, 1h / 6h / 24h / 7d population history, 30-minute change, today's
  high, local record, range average, and local Realm Rhythm context.
- **Honest history** — legible automatic resolution, a bounded point count, and real gaps when the
  Mac was asleep or the app was not running. Hover or use arrow keys to inspect observations.
- **Integrated `$WOC` market** — validated DEX Screener spot/rolling metrics and real GeckoTerminal
  OHLCV candles, with independent live, cached, loading, and unavailable states.
- **On-demand community view** — project totals, latest release, lifetime-XP leaders, realm details,
  and useful game links. One failed feed does not blank the others.
- **Smart alerts** — realm down/recovered, records, busy-realm thresholds, rolling gains/losses,
  price targets, and releases, with cooldowns, quiet hours, hysteresis, mute, and disable actions.
- **Private by design** — no companion account, telemetry, advertising, analytics, password, or
  wallet access. History and preferences stay on the Mac.
- **Mac-native accessibility** — semantic VoiceOver output, Audio Graph descriptors, keyboard chart
  inspection, Dynamic Type, non-color candle encoding, and system accessibility accommodations.

## Install

Release builds support macOS 14 or newer on Apple silicon and Intel Macs.

1. Download the latest signed and notarized DMG from
   [GitHub Releases](https://github.com/FernandoX7/woc-widget/releases/latest).
2. Open the DMG and drag **WoC Player Count** to **Applications**.
3. Launch it once from Applications. The world-and-signal icon will appear in the menu bar.

Use the power button in the popover footer to quit. Because the app is an `LSUIElement`, it does not
appear in the Dock. Updates are manual until a signed update feed is introduced.

If no public release exists yet, build the app from source using the instructions below. Do not
redistribute ad-hoc-signed local builds as official releases.

## Dashboard

The popover keeps one stable 440×660 frame across its four destinations:

| Destination | What it shows |
| --- | --- |
| Overview | Realm health, player history, local records, and Realm Rhythm |
| `$WOC` | Quote, rolling activity, liquidity, volume, transactions, candles, and market alerts |
| Community | Project statistics, releases, lifetime-XP leaders, realms, and game links |
| Settings | Alerts, refresh intervals, menu label, launch at login, local data, and About links |

The footer stays pinned, every page owns its scrolling, and refresh always acts on the current
context.

## Privacy

WoC Player Count makes direct HTTPS requests to World of ClaudeCraft, DEX Screener, and
GeckoTerminal. Those services receive ordinary connection metadata such as an IP address. The app
itself has no analytics or backend.

Observed player history is retained locally for seven days. Settings can export it or permanently
remove both the primary and recovery snapshots. Read [PRIVACY.md](PRIVACY.md) for the complete data
flow, storage locations, defaults domain, and removal instructions.

## Data sources and disclaimer

- World of ClaudeCraft public APIs provide realm and community data.
- [DEX Screener](https://dexscreener.com) provides spot and rolling market metrics.
- [GeckoTerminal](https://www.geckoterminal.com) provides OHLCV candles.

Providers and artwork are documented in [CREDITS.md](CREDITS.md). `$WOC` data is informational and
may be delayed, incomplete, or wrong. This app does not issue or control the token, and nothing in
the app or repository is financial advice or a recommendation to trade.

## Build from source

You need macOS 14 or newer and a full Xcode 16+ installation with its Swift 6 toolchain—not only the
standalone Command Line Tools.

```bash
git clone https://github.com/FernandoX7/woc-widget.git
cd woc-widget
sudo xcode-select --switch /Applications/Xcode.app
./build.sh run
```

`./build.sh run` compiles, ad-hoc signs, installs to `/Applications`, and launches the newest build.
The repository intentionally has no Xcode project; `build.sh` compiles the complete `Sources/` tree
with `swiftc`, assembles the bundle, and compiles the String Catalog with `xcstringstool`.

Other useful commands:

```bash
./build.sh           # build + install, without relaunching
./build.sh bundle    # production bundle under build/; no install or launch
./build.sh check     # type-check every app and view source
./build.sh preview   # windowed, synthetic-data preview; never installed
swift test           # deterministic WoCKit tests
./scripts/verify.sh  # complete production verification, including idle-resource checks
```

Local builds are ad-hoc signed. Universal Developer ID signing, hardened runtime, notarization,
stapling, checksums, and DMG construction are documented in [docs/RELEASE.md](docs/RELEASE.md).

## Architecture and visual QA

The app keeps SwiftUI presentation separate from a SwiftUI-free WoCKit domain layer. Feed states,
history repair, alert policies, and preview fixtures are deterministic and independently testable.

See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for data flow, persistence and alert invariants,
popover constraints, accessibility contracts, and the composable preview matrix. See
[docs/VERIFICATION.md](docs/VERIFICATION.md) for the verification gate.

## Known boundaries

- Population history is observed locally while the app runs; it cannot backfill sleep or quit time.
- The companion intentionally presents aggregate population rather than a separate online-player
  roster.
- Community and market services are best-effort and have no uptime guarantee. Cached values remain
  visible with honest provenance when possible.
- Account-linked character data is out of scope until an appropriate public OAuth/API contract
  exists. The app never scrapes a browser session or requests a game password.
- Automatic updates require a future signed release feed; the current release process is manual.

## Uninstall

1. Quit WoC Player Count and remove it from Applications.
2. Disable its login item in **System Settings → General → Login Items** if present.
3. Optionally remove all companion-owned data:

   ```bash
   rm -rf "$HOME/Library/Application Support/WoCWidget"
   defaults delete io.github.fernandox7.wocplayercount 2>/dev/null || true
   ```

## Contributing and security

Contributions are welcome. Start with [CONTRIBUTING.md](CONTRIBUTING.md), keep fixtures synthetic,
and run the verification gate before opening a pull request. Use the private process in
[SECURITY.md](SECURITY.md) for vulnerabilities rather than a public issue.

Notable public changes are recorded in [CHANGELOG.md](CHANGELOG.md).
For the first GitHub publication, follow [docs/PUBLISHING.md](docs/PUBLISHING.md) so retired private
branding and local-only history are not pushed into the new repository.

## License

WoC Player Count source and original companion artwork are available under the
[MIT License](LICENSE). Third-party names and data remain subject to their owners' terms; see
[CREDITS.md](CREDITS.md).
