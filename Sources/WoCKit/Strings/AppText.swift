import Foundation

/// Foundation-side user-facing strings — resolved SwiftUI-free via `String(localized:)` against
/// the `Localizable` String Catalog (so the store / future alert presenter never import SwiftUI).
/// Each `defaultValue` mirrors the catalog English so a lookup still returns the right text when
/// the compiled catalog isn't on disk (e.g. under `swift test`, where there's no app bundle).
enum AppText {
    private static func t(_ key: StaticString, _ fallback: String.LocalizationValue) -> String {
        String(localized: key, defaultValue: fallback, table: "Localizable", bundle: .main)
    }

    static func compactDuration(seconds: Int) -> String {
        switch seconds {
        case 10: return t("duration.compact.10s", "10s")
        case 30: return t("duration.compact.30s", "30s")
        case 60: return t("duration.compact.1m", "1m")
        case 300: return t("duration.compact.5m", "5m")
        case 900: return t("duration.compact.15m", "15m")
        case 1_800: return t("duration.compact.30m", "30m")
        case 3_600: return t("duration.compact.1h", "1h")
        case 14_400: return t("duration.compact.4h", "4h")
        case 21_600: return t("duration.compact.6h", "6h")
        case 86_400: return t("duration.compact.24h", "24h")
        case 604_800: return t("duration.compact.7d", "7d")
        default: return String(seconds)
        }
    }

    /// "never" / "updated just now" / "updated Ns ago" / "updated Nm ago" / "updated Nh ago".
    /// `now` is injected (defaulting to the wall clock) so the boundaries are deterministically
    /// testable — matching `AlertKind.requestID(now:)` and the clock-injected `HistoryAnalytics`.
    static func relativeUpdated(_ date: Date?, now: () -> Date = Date.init) -> String {
        guard let date else { return t("updated.never", "never") }
        let s = Int(now().timeIntervalSince(date))
        if s < 2 { return t("updated.justNow", "updated just now") }
        if s < 60 { return String(format: t("updated.seconds", "updated %llds ago"), s) }
        let m = s / 60
        if m < 60 { return String(format: t("updated.minutes", "updated %lldm ago"), m) }
        return String(format: t("updated.hours", "updated %lldh ago"), m / 60)
    }

    /// Locale-aware relative date with an injected reference instant. SwiftUI's `Text(date,
    /// format: .relative)` always reads the wall clock, which makes previews and clock tests lie.
    static func relativeDate(_ date: Date, now: () -> Date = Date.init) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: now())
    }

    /// Realm name fallback when the API hasn't reported one yet.
    static var realmFallback: String { t("realm.fallback", "World of Claudecraft") }

    /// VoiceOver phrase for the menu-bar status — semantic words instead of the colored emoji dots
    /// the visible label uses. syncing → "Syncing"; online → "Online, N players"; else → "Offline".
    static func menuBarStatus(online: Bool, syncing: Bool, count: Int) -> String {
        if syncing { return t("menubar.a11y.syncing", "Syncing") }
        if online { return menuBarOnlineCount(count) }
        return t("menubar.a11y.offline", "Offline")
    }

    static func menuBarStatus(availability: RealmAvailability, syncing: Bool,
                              count: Int?) -> String {
        if syncing { return t("menubar.a11y.syncing", "Syncing") }
        switch availability {
        case .healthy:
            return menuBarOnlineCount(count ?? 0)
        case .unreachable where count != nil:
            return menuBarCachedCount(count ?? 0)
        case .unreachable:
            return t("menubar.a11y.unavailable", "Unavailable")
        case .loading, .serverReportedDown:
            return t("menubar.a11y.offline", "Offline")
        }
    }

    private static func menuBarOnlineCount(_ count: Int) -> String {
        if count == 1 { return t("menubar.a11y.onlineOne", "Online, 1 player") }
        return String(format: t("menubar.a11y.online", "Online, %lld players"), count)
    }

    private static func menuBarCachedCount(_ count: Int) -> String {
        if count == 1 { return t("menubar.a11y.cachedOne", "Cached, 1 player") }
        return String(format: t("menubar.a11y.cached", "Cached, %lld players"), count)
    }

    static func menuBarAccessibility(status: String, price: String, change24h: Double?) -> String {
        let change = change24h.map { signedPercentWords($0) }
            ?? t("menubar.a11y.changeUnknown", "24-hour change unavailable")
        return String(format: t("menubar.a11y.full", "World of ClaudeCraft. %@. WOC spot price %@ dollars, %@."),
                      status, price, change)
    }

    static func menuBarAccessibility(status: String, change24h: Double) -> String {
        String(format: t("menubar.a11y.statusAndChange", "%@. WOC %@."),
               status, signedPercentWords(change24h))
    }

    static func menuBarTokenAccessibility(price: String, change24h: Double?) -> String {
        let change = change24h.map { signedPercentWords($0) }
            ?? t("menubar.a11y.changeUnknown", "24-hour change unavailable")
        return String(format: t("menubar.a11y.token", "WOC spot price %@ dollars, %@."),
                      price, change)
    }

    static func marketQuoteAccessibility(price: String, change24h: Double?,
                                         cached: Bool) -> String {
        let quote = menuBarTokenAccessibility(price: price, change24h: change24h)
        guard cached else { return quote }
        return String(format: t("market.a11y.cachedQuote", "Cached. %@"), quote)
    }

    static var marketQuoteLoadingAccessibility: String {
        t("market.a11y.quoteLoading", "$WOC market quote loading.")
    }

    static var marketQuoteUnavailableAccessibility: String {
        t("market.a11y.quoteUnavailable", "$WOC market quote unavailable.")
    }

    private static func signedPercentWords(_ value: Double) -> String {
        String(format: value >= 0
               ? t("menubar.a11y.changeUp", "up %.1f percent over 24 hours")
               : t("menubar.a11y.changeDown", "down %.1f percent over 24 hours"),
               abs(value))
    }

    /// VoiceOver summary for the player-count chart (its marks are decorative for VoiceOver).
    static func chartAccessibility(latest: Int, peak: Int) -> String {
        String(format: t("chart.a11y.summary", "Players over time. Latest %lld, peak %lld."), latest, peak)
    }

    /// VoiceOver summary for the $WOC candle chart (its candles are decorative for VoiceOver) —
    /// direction over the window plus the visible range, not just the latest price.
    static func cryptoChartAccessibility(latest: Double, high: Double, low: Double, up: Bool) -> String {
        String(format: t("chart.crypto.a11y.summary", "$WOC price over time, trending %@. Latest %@, high %@, low %@."),
               up ? t("trend.up", "up") : t("trend.down", "down"),
               CryptoFormat.chartPrice(latest), CryptoFormat.chartPrice(high), CryptoFormat.chartPrice(low))
    }

    static func chartResolution(_ interval: String) -> String {
        String(format: t("chart.resolution", "%@ averages"), interval)
    }

    static func candleClose(interval: String, price: String) -> String {
        String(format: t("chart.candle.close", "%@ close %@"), interval, price)
    }

    static func percentageAccessibility(_ value: Int) -> String {
        String(format: t("format.percent", "%lld percent"), value)
    }

    static var chartAxisTime: String { t("chart.a11y.axis.time", "Time") }
    static var chartAxisPlayers: String { t("chart.a11y.axis.players", "Players") }
    static var chartAxisClosePrice: String {
        t("chart.crypto.a11y.axis.close", "Close price in U.S. dollars")
    }
    static var chartAxisOpenPrice: String { t("chart.crypto.a11y.axis.open", "Open price") }
    static var chartAxisHighPrice: String { t("chart.crypto.a11y.axis.high", "High price") }
    static var chartAxisLowPrice: String { t("chart.crypto.a11y.axis.low", "Low price") }
    static var chartCandleSeries: String { t("chart.crypto.a11y.series", "Candle close") }

    static func playerCountAccessibility(_ count: Int) -> String {
        if count == 1 { return t("chart.a11y.playerCount.one", "1 player") }
        return String(format: t("chart.a11y.playerCount.other", "%lld players"), count)
    }

    static func playerPointAccessibility(count: Int, date: String) -> String {
        if count == 1 {
            return String(format: t("chart.a11y.playerPoint.one", "1 player, %@"), date)
        }
        return String(format: t("chart.a11y.playerPoint.other", "%lld players, %@"),
                      count, date)
    }

    static func playerSeriesAccessibility(segment: Int?) -> String {
        guard let segment else { return t("chart.a11y.series.players", "Players") }
        return String(format: t("chart.a11y.series.segment", "Players, observed segment %lld"), segment)
    }

    static func candlePointAccessibility(date: String, open: String, high: String, low: String,
                                         close: String, isUp: Bool, change: String) -> String {
        String(format: t("chart.crypto.a11y.point",
                         "%@; open %@, high %@, low %@, close %@, %@ %@ percent"),
               date, open, high, low, close,
               isUp ? t("trend.up", "up") : t("trend.down", "down"), change)
    }

    static func cachedCandles(interval: String) -> String {
        String(format: t("feed.cachedCandles", "Showing cached %@ candles"), interval)
    }

    static func marketWindowChange(timeframe: String, change: Double) -> String {
        String(format: t("market.change.window", "%@ change %@"), timeframe,
               CryptoFormat.signedChange(change))
    }

    static func marketWindowVolume(timeframe: String) -> String {
        String(format: t("market.volume.window", "%@ volume"), timeframe)
    }

    static func marketWindowTransactions(timeframe: String) -> String {
        String(format: t("market.transactions.window", "%@ buys / sells"), timeframe)
    }

    static func marketBuyShare(_ fraction: Double) -> String {
        String(format: t("market.activity.buys", "%lld%% buys"),
               min(100, max(0, Int((fraction * 100).rounded()))))
    }

    static func marketSellShare(_ fraction: Double) -> String {
        String(format: t("market.activity.sells", "%lld%% sells"),
               min(100, max(0, Int((fraction * 100).rounded()))))
    }

    static func marketActivityAccessibility(timeframe: String, buys: Int, sells: Int) -> String {
        String(format: t("market.activity.a11y", "%@ activity, %lld buys and %lld sells"),
               timeframe, buys, sells)
    }

    static func marketAlertSummary(threshold: Int, window: String) -> String {
        String(format: t("market.alert.summary", "%lld%% · %@"), threshold, window)
    }

    static func marketAlertAccessibility(threshold: Int, window: String) -> String {
        String(format: t("market.alert.accessibility", "Market alerts, %lld percent over %@"),
               threshold, window)
    }

    static var marketAlertEnableHelp: String {
        t("market.alert.enableHelp", "Notify me about rolling $WOC moves")
    }

    static var marketAlertDisableHelp: String {
        t("market.alert.disableHelp", "Turn off rolling $WOC move alerts")
    }

    static var releaseAlertLabel: String {
        t("community.releaseAlert.label", "Release alerts")
    }

    static var releaseAlertEnableHelp: String {
        t("community.releaseAlert.enableHelp", "Notify me about new game releases")
    }

    static var releaseAlertDisableHelp: String {
        t("community.releaseAlert.disableHelp", "Turn off new-release alerts")
    }

    static var contextualAlertPermissionDeniedHelp: String {
        t("contextualAlert.permissionDenied.help",
          "Notifications are blocked in macOS Settings. This alert remains enabled.")
    }

    static var contextualAlertBlockedValue: String {
        t("contextualAlert.permissionDenied.value", "On, but blocked by macOS")
    }

    static var contextualAlertPermissionNeededHelp: String {
        t("contextualAlert.permissionNeeded.help",
          "Allow macOS notifications for this enabled alert")
    }

    static var contextualAlertPermissionNeededValue: String {
        t("contextualAlert.permissionNeeded.value", "On, permission needed")
    }

    static var contextualAlertPermissionCheckingHelp: String {
        t("contextualAlert.permissionChecking.help", "Checking notification access")
    }

    static var contextualAlertPermissionCheckingValue: String {
        t("contextualAlert.permissionChecking.value", "On, checking permission")
    }

    static var accessibilityOn: String { t("accessibility.on", "On") }
    static var accessibilityOff: String { t("accessibility.off", "Off") }

    static func communityLevel(_ level: Int) -> String {
        String(format: t("community.level", "Level %lld"), level)
    }

    static func communityXP(_ value: String) -> String {
        String(format: t("community.xp", "%@ XP"), value)
    }

    static func communityPrestige(_ rank: Int) -> String {
        String(format: t("community.prestige", "Prestige %lld"), rank)
    }

    static func realmRhythmPercentile(_ percentile: Int) -> String {
        String(format: t("rhythm.percentile", "Busier than %lld%% of your observed window"),
                      percentile)
    }

    static func realmRhythmCoverage(_ fraction: Double) -> String {
        let percent = min(100, max(0, Int((fraction * 100).rounded())))
        return String(format: t("rhythm.coverageValue", "%lld%% observed"), percent)
    }

    static func busyAlertThreshold(_ threshold: Int) -> String {
        String(format: t("rhythm.alert.threshold", "Alert at %lld"), threshold)
    }

    static var busyAlertEnableHelp: String {
        t("rhythm.alert.enableHelp", "Notify me when the realm reaches this population")
    }

    static var busyAlertDisableHelp: String {
        t("rhythm.alert.disableHelp", "Turn off the busy-realm alert")
    }

    static func communityLeaderAccessibility(rank: Int, name: String, detail: String) -> String {
        if detail.isEmpty {
            return String(format: t("community.a11y.leaderNoDetail", "Rank %lld, %@"), rank, name)
        }
        return String(format: t("community.a11y.leader", "Rank %lld, %@, %@"), rank, name, detail)
    }

    static var notificationTestTitle: String {
        t("notification.test.title", "WoC notifications are ready")
    }

    static var notificationTestBody: String {
        t("notification.test.body", "Realm, record, and $WOC alerts can reach this Mac.")
    }

    static var notificationMuteOneHour: String {
        t("notification.action.muteOneHour", "Mute for 1 hour")
    }

    static var notificationDisableAlert: String {
        t("notification.action.disable", "Disable this alert")
    }

    static var historyExportFailed: String {
        t("history.export.failed", "Couldn't export player history")
    }

    static func appVersion(_ version: String, build: String) -> String {
        String(format: t("settings.about.version", "Version %@ · Build %@"), version, build)
    }
}

/// Non-localizable glyphs (status dots + the no-value em-dash) used by the menu-bar label and
/// the count/stat displays — a single home so the symbols aren't re-typed.
enum Glyph {
    static let statusLoading = "🟡"
    static let statusOnline = "🟢"
    static let statusOffline = "🔴"
    static let statusCached = "🟠"
    static let noValue = "—"
}

/// Shared $WOC formatting so the menu-bar label (WoCKit) and the header pill (SwiftUI) render
/// byte-identical fragments from one home.
enum CryptoFormat {
    /// "$<raw>" — the price fragment (raw is the exact String the API returned, e.g. "0.0005594").
    static func price(_ raw: String) -> String { "$\(raw)" }
    /// "+1.2%" / "-0.3%" — the signed 24h change: "+" on non-negative, one decimal place.
    static func signedChange(_ change: Double) -> String {
        "\(change >= 0 ? "+" : "")\(String(format: "%.1f", change))%"
    }

    /// Compact candle-chart price: ~4 significant figures in FIXED-POINT, so a ~0.00068 token reads
    /// as "0.0006831" rather than rounding to "0". The single home for the chart price-format
    /// literal (y-axis labels, hover tooltip, live price chip, the VoiceOver summary); wrap in
    /// `price(_:)` for the "$"-prefixed badge.
    ///
    /// Magnitude-scaled fixed point — NOT `"%.4g"`: C `%g` flips to scientific notation below 1e-4
    /// (e.g. a 6× decline to ~0.00005594 would render "5.594e-05" across every chart label), which
    /// is exactly the unreadable form a sub-cent price chart must avoid. `decimals = 3 - exp` keeps
    /// 4 sig figs as the price shrinks (capped at 12 so a near-zero value can't ask for an absurd
    /// width); non-finite/≤0 falls back to `%g` (renders "0"/"inf"/"nan" without trapping).
    static func chartPrice(_ value: Double) -> String {
        guard value > 0, value.isFinite else { return String(format: "%.4g", value) }
        let exp = Int(floor(log10(value)))
        let decimals = min(12, max(0, 3 - exp))
        return String(format: "%.\(decimals)f", value)
    }
}
