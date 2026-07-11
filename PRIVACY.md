# Privacy

Last updated: July 11, 2026

WoC Player Count is an independent, open-source macOS companion. It has no account system,
advertising, analytics, telemetry, or crash-reporting SDK. The project maintainer does not operate
an app backend and does not receive data from the app.

This policy covers WoC Player Count only. It does not replace the policies of World of ClaudeCraft,
DEX Screener, GeckoTerminal, GitHub, Discord, or other sites opened from the app.

## Network requests

The app makes direct HTTPS requests from your Mac to these providers:

- `worldofclaudecraft.com` for realm status, project totals, releases, leaderboards, and realm
  details;
- `api.dexscreener.com` for the `$WOC` spot quote and rolling market metrics; and
- `api.geckoterminal.com` for OHLCV candles.

Realm status and the DEX Screener quote refresh while the app runs at the intervals selected in
Settings (one minute by default). GeckoTerminal candles refresh only while the popover is visible,
or when explicitly requested. Community feeds load on demand. When release alerts are enabled—the
default—the release feed is checked approximately every 30 minutes.

Those providers necessarily receive ordinary connection information such as your IP address,
request time, and standard network metadata. WoC Player Count does not add an account identifier,
advertising identifier, wallet address, game password, or analytics identifier to requests. Each
provider handles connection data under its own policies and terms.

## Data stored on your Mac

WoC Player Count stores only the data needed to provide its local features:

- Up to seven days of observed player-count samples in
  `~/Library/Application Support/WoCWidget/history.json`, plus a last-known-good recovery sidecar.
- Preferences and alert state in the macOS defaults domain
  `io.github.fernandox7.wocplayercount`. This includes refresh intervals, thresholds, quiet hours,
  mutes, display choices, local-record metadata, and alert baselines.
- CSV or JSON history exports only when you choose a destination in the save panel.
- Notification permission and launch-at-login registration managed by macOS.

Public leaderboard names and other community responses are used to render the current view and are
not persisted by the app. Market candles are not written to disk.

## Your controls

- **Clear local history** in Settings permanently removes both history snapshots and the local peak.
  Alert and display preferences remain intact.
- **Export history** writes a user-selected CSV or JSON file.
- Notification rules, launch at login, and refresh intervals can be changed in Settings.
- To remove all app-owned local data after quitting the app, delete the application and run:

  ```bash
  rm -rf "$HOME/Library/Application Support/WoCWidget"
  defaults delete io.github.fernandox7.wocplayercount 2>/dev/null || true
  ```

The second command removes preferences for the public companion identity. macOS may retain its own
notification or login-item records until they are removed in System Settings.

## External links

Play, wiki, market, Discord, GitHub, support, and other links open in your default browser. Once a
link opens, the destination's privacy policy applies.

## Changes and questions

Material changes to this policy will be recorded in the repository. For a privacy question, open an
issue in the [WoC Player Count repository](https://github.com/FernandoX7/woc-widget/issues) without
including private information. Use the private process in [SECURITY.md](SECURITY.md) for a sensitive
report.
