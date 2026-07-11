import Testing
import Foundation
@testable import WoCKit

// Pure formatting/accessor coverage. In `swift test` there's no compiled String Catalog on disk, so
// `String(localized:defaultValue:)` returns the `defaultValue` — these assert against that English
// fallback, exactly as the menu-bar a11y test does.

@Suite struct AppLinksTests {
    @Test func companionAndGameDestinationsStayDistinctAndSecure() {
        let companionLinks = [
            AppLinks.appRepository,
            AppLinks.appPrivacy,
            AppLinks.appLicense,
            AppLinks.appSupport,
        ]
        #expect(companionLinks.allSatisfy { $0.scheme == "https" })
        #expect(AppLinks.appRepository.host == "github.com")
        #expect(AppLinks.appRepository.path == "/FernandoX7/woc-widget")
        #expect(AppLinks.gameRepository != AppLinks.appRepository)
        #expect(AppLinks.gameRepository.path == "/levy-street/world-of-claudecraft")
    }
}

@Suite struct CryptoFormatTests {
    // The single most important crypto-chart fix: sub-cent prices must read in fixed point, never
    // flip to scientific notation (`%g` would render 0.00005594 as "5.594e-05" across every label).
    @Test func chartPriceKeepsSubCentReadableWithoutScientificNotation() {
        #expect(CryptoFormat.chartPrice(0.0005594) == "0.0005594")     // ~today's $WOC
        let tiny = CryptoFormat.chartPrice(0.00005594)                 // a 10× decline — the regression case
        #expect(!tiny.lowercased().contains("e"))
        #expect(tiny == "0.00005594")
    }

    @Test func chartPriceHandlesAboveOneAndZero() {
        #expect(CryptoFormat.chartPrice(1.5) == "1.500")               // 4 sig figs, fixed point
        #expect(!CryptoFormat.chartPrice(1.5).lowercased().contains("e"))
        #expect(CryptoFormat.chartPrice(0) == "0")                     // non-positive falls back, never traps
    }

    @Test func priceAndSignedChangeFragmentsAreStable() {
        #expect(CryptoFormat.price("0.0005594") == "$0.0005594")       // raw String preserved (guardrail 6/8)
        #expect(CryptoFormat.signedChange(47.59) == "+47.6%")
        #expect(CryptoFormat.signedChange(-3.0) == "-3.0%")
    }
}

@Suite struct AccessibilityTextTests {
    @Test func cryptoChartSummaryCarriesDirectionAndRange() {
        let up = AppText.cryptoChartAccessibility(latest: 0.0005594, high: 0.0006, low: 0.0005, up: true)
        #expect(up.contains("trending up"))
        #expect(up.contains("0.0005594"))                              // latest via chartPrice
        #expect(up.contains("high") && up.contains("low"))
        let down = AppText.cryptoChartAccessibility(latest: 0.0005, high: 0.0006, low: 0.0004, up: false)
        #expect(down.contains("trending down"))
    }

    @Test func playerChartSummaryCarriesLatestAndPeak() {
        let s = AppText.chartAccessibility(latest: 73, peak: 120)
        #expect(s.contains("73") && s.contains("120"))
    }

    @Test func aboutVersionKeepsVersionAndBuildDistinct() {
        #expect(AppText.appVersion("1.2.3", build: "45") == "Version 1.2.3 · Build 45")
    }

    @Test func contextualAlertCopyCarriesItsThresholdWindowAndBlockedDeliveryState() {
        #expect(AppText.marketAlertSummary(threshold: 12, window: "6h") == "12% · 6h")
        #expect(AppText.marketAlertAccessibility(threshold: 12, window: "6h")
                == "Market alerts, 12 percent over 6h")
        #expect(AppText.contextualAlertBlockedValue == "On, but blocked by macOS")
        #expect(AppText.contextualAlertPermissionDeniedHelp.contains("remains enabled"))
        #expect(AppText.contextualAlertPermissionNeededValue == "On, permission needed")
        #expect(AppText.contextualAlertPermissionCheckingValue == "On, checking permission")
        #expect(AppText.releaseAlertLabel == "Release alerts")
    }

    @Test func chartInspectionTextIsLocalizedThroughFoundationAccessors() {
        #expect(AppText.candleClose(interval: "5m", price: "$0.0005594")
                == "5m close $0.0005594")
        #expect(AppText.percentageAccessibility(12) == "12 percent")
        #expect(AppText.playerCountAccessibility(83) == "83 players")
        #expect(AppText.playerCountAccessibility(1) == "1 player")
        #expect(AppText.playerPointAccessibility(count: 83, date: "Jul 10 at 14:30")
                == "83 players, Jul 10 at 14:30")
        #expect(AppText.playerPointAccessibility(count: 1, date: "Jul 10 at 14:30")
                == "1 player, Jul 10 at 14:30")
        #expect(AppText.playerSeriesAccessibility(segment: nil) == "Players")
        #expect(AppText.playerSeriesAccessibility(segment: 2)
                == "Players, observed segment 2")
    }

    @Test func candlePointTextCarriesEveryOHLCValueAndDirection() {
        let text = AppText.candlePointAccessibility(
            date: "Jul 10 at 14:30", open: "0.0005500", high: "0.0005700",
            low: "0.0005400", close: "0.0005594", isUp: true, change: "1.7")
        #expect(text == "Jul 10 at 14:30; open 0.0005500, high 0.0005700, "
                + "low 0.0005400, close 0.0005594, up 1.7 percent")
    }
}

@Suite struct MenuBarFormatterTests {
    private func presentation(
        mode: MenuBarDisplayMode = .players,
        count: Int? = 7,
        availability: RealmAvailability = .healthy,
        price: String? = "0.0005594",
        change: Double? = 47.59,
        priceState: DataFeedState = .live
    ) -> MenuBarPresentation {
        MenuBarFormatter.presentation(
            mode: mode, count: count, availability: availability, phase: .ok,
            isOnline: availability == .healthy, price: price, change24h: change,
            priceState: priceState
        )
    }

    @Test func visibleAndSpokenOutputFollowEachSelectedMode() {
        #expect(presentation(mode: .players).label == "🟢 7")
        #expect(presentation(mode: .players).accessibilityLabel == "Online, 7 players")

        let change = presentation(mode: .playersAndChange)
        #expect(change.label == "🟢 7 · WOC +47.6%")
        #expect(change.accessibilityLabel.contains("WOC up 47.6 percent"))

        let token = presentation(mode: .token)
        #expect(token.label == "$0.0005594 +47.6%")
        #expect(token.accessibilityLabel.hasPrefix("WOC spot price"))
        #expect(!token.accessibilityLabel.contains("Online"))

        let full = presentation(mode: .full)
        #expect(full.label == "$0.0005594 (+47.6%) 🟢 7")
        #expect(full.accessibilityLabel.contains("Online, 7 players"))
        #expect(full.accessibilityLabel.contains("WOC spot price"))
    }

    @Test func cachedRealmIsNotSpokenAsOfflineAndCachedPriceIsOmitted() {
        let cached = presentation(mode: .full, count: 1,
                                  availability: .unreachable(.timedOut),
                                  priceState: .cached)
        #expect(cached.label == "🟠 1")
        #expect(cached.accessibilityLabel == "Cached, 1 player")

        let unavailable = presentation(mode: .token, count: nil,
                                       availability: .unreachable(.localNetwork),
                                       price: nil, change: nil, priceState: .unavailable)
        #expect(unavailable.label == "🔴 —")
        #expect(unavailable.accessibilityLabel == "Unavailable")
    }

    @Test func healthyZeroAndSingularCountsRemainSemantic() {
        #expect(presentation(count: 0).accessibilityLabel == "Online, 0 players")
        #expect(presentation(count: 1).accessibilityLabel == "Online, 1 player")
        #expect(AppText.marketQuoteAccessibility(
            price: "0.5", change24h: nil, cached: true).hasPrefix("Cached. WOC spot price"))
    }
}

@Suite struct RelativeUpdatedTests {
    private let base = Date(timeIntervalSince1970: 1_700_000_000)
    private func clock(_ delta: TimeInterval) -> () -> Date { { self.base.addingTimeInterval(delta) } }

    @Test func formatsEachBoundaryWithTheInjectedClock() {
        #expect(AppText.relativeUpdated(nil, now: clock(0)) == "never")
        #expect(AppText.relativeUpdated(base, now: clock(1)) == "updated just now")   // s < 2
        #expect(AppText.relativeUpdated(base, now: clock(45)) == "updated 45s ago")   // s < 60
        #expect(AppText.relativeUpdated(base, now: clock(120)) == "updated 2m ago")   // m < 60
        #expect(AppText.relativeUpdated(base, now: clock(7200)) == "updated 2h ago")  // hours
    }

    @Test func relativeDateUsesInjectedReferenceRatherThanWallClock() {
        let text = AppText.relativeDate(base.addingTimeInterval(-2 * 3600), now: clock(0))
        #expect(text.contains("2"))
        #expect(!text.hasPrefix("in "))
    }
}

@Suite struct CompactDurationTests {
    @Test func domainIntervalsShareLocalizedCompactLabels() {
        #expect(PollInterval.thirtySeconds.label == "30s")
        #expect(ChartInterval.thirtyMin.label == "30m")
        #expect(CandleInterval.fourHour.label == "4h")
        #expect(ChartRange.week.label == "7d")
        #expect(AlertCooldownOption.allCases.map(\.seconds)
                == AppConfig.AdvancedAlert.cooldownOptions)
    }
}
