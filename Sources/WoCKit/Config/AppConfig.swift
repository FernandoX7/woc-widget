import Foundation
import UserNotifications

/// Single home for endpoints, timeouts, poll defaults, and the data/analytics constants.
/// View dimensions (popover/frame sizes, chart styling) live in the design system (`Layout`),
/// user-facing strings in the String Catalog (`AppText`/`Str`). No URL or numeric literal for
/// these concerns should appear in services, the store, or analytics.
enum AppConfig {

    // MARK: Endpoints
    enum API {
        /// Player count / realm status.
        static let statusURL = URL(string: "https://worldofclaudecraft.com/api/status")!

        /// $WOC price comes from a DexScreener pair. Kept as base + chain + pair address so the
        /// pair is named rather than buried in a URL.
        static let dexBase = "https://api.dexscreener.com/latest/dex/pairs"
        static let dexChain = "solana"
        /// Lowercase lookup value accepted by DexScreener. The service separately validates the
        /// canonical, case-sensitive address returned in the payload before trusting a quote.
        static let dexPairAddress = "5we9yjzpeqxcyl4jn9khjtsr48xzyh47xtar9kg3wy1p"
        static let dexCanonicalPairAddress = "5wE9YJzPeQxCYL4jN9KhjTSR48Xzyh47xTAR9kg3wy1p"
        static let dexTokenAddress = "3WjLscH2JsXLEFJZRA9z8ti8yRGxWGKbqymPd7UicRth"
        static let cryptoURL = URL(string: "\(dexBase)/\(dexChain)/\(dexPairAddress)")!

        /// Real OHLC candles for the $WOC chart come from GeckoTerminal (CoinGecko on-chain). Free,
        /// no API key. ⚠️ The pool address is CASE-SENSITIVE here — DexScreener lowercases it, which
        /// GeckoTerminal 404s on; this is the exact mixed case the API expects.
        static let geckoBase = "https://api.geckoterminal.com/api/v2/networks"
        static let geckoNetwork = "solana"
        static let geckoPool = "5wE9YJzPeQxCYL4jN9KhjTSR48Xzyh47xTAR9kg3wy1p"

        /// Applied to every request.
        static let requestTimeout: TimeInterval = 12
        /// Reject unexpectedly large public-feed payloads before decoding. Normal responses are
        /// measured in kilobytes; this ceiling leaves ample headroom for release notes while
        /// bounding schema abuse and accidental upstream error documents.
        static let maximumResponseBytes = 2 * 1024 * 1024

        /// DexScreener's API controls the pair URL rendered as a clickable market action. Keep
        /// that navigation on HTTPS and the expected service domain even if an upstream payload
        /// or injected service is compromised.
        static func validatedMarketURL(_ url: URL?) -> URL? {
            guard let url, url.scheme?.lowercased() == "https",
                  let host = url.host?.lowercased(),
                  host == "dexscreener.com" || host.hasSuffix(".dexscreener.com") else { return nil }
            return url
        }
        /// Always hit the network — these are live, fast-changing feeds and neither API documents
        /// conditional-request (ETag/If-None-Match) support, so 304 revalidation would buy nothing.
        /// Deliberate; bandwidth is trivial at the poll cadence.
        static let cachePolicy: URLRequest.CachePolicy = .reloadIgnoringLocalCacheData
    }

    // MARK: Crypto chart
    enum Crypto {
        static let currencyCode = "USD"
        /// How many candles to request/show. Sized for a glanceable menu popover: dense enough to read a
        /// trend, sparse enough that each candle is still a candle (not a 1px smear). At the 5m
        /// default that's a ~5h window. GeckoTerminal caps `limit` at 1000.
        static let candleCount = 60
        /// Candles are only refreshed while the popover is visible. Spot polling remains on its
        /// own selected cadence; this slower floor avoids downloading 60 bars every minute.
        static let visibleCandleRefreshSeconds: TimeInterval = 5 * 60
    }

    // MARK: Polling
    enum Poll {
        static let defaultPlayerSeconds: TimeInterval = 60
        static let defaultCryptoSeconds: TimeInterval = 60
        /// Floor a corrupted/0/negative persisted interval clamps to, so a bad value can't
        /// produce a tight-loop `Timer`.
        static let minimumSeconds: TimeInterval = 10
        /// Slack each repeating poll `Timer` is allowed (as a fraction of its interval) so macOS can
        /// coalesce the two pollers' wakeups instead of firing each at an exact instant — the
        /// recommended power posture for an always-on `LSUIElement`. Applied off the live interval,
        /// so a `didSet` restart picks up the new tolerance automatically.
        static let timerToleranceFraction = 0.1
    }

    // MARK: History persistence + retention
    enum History {
        static let directoryName = "WoCWidget"
        static let fileName = "history.json"
        /// Samples older than this are pruned. The chart range never exceeds this window.
        static let retentionWindow: TimeInterval = 7 * 24 * 3600   // 7 days
        /// The plot is downsampled so it never exceeds this many points; this same value is the
        /// bucket-coarsening divisor in `HistoryAnalytics.series`. Must stay `Double` so
        /// `range.seconds / chartMaxPoints` is byte-identical to the original `range.seconds / 300`.
        static let chartMaxPoints: Double = 300
        /// Writes are coalesced — the array is flushed to disk after this many new samples or this
        /// many seconds (whichever first), plus on resign-active/terminate. Avoids the prior
        /// re-encode-and-rewrite-everything-every-poll churn.
        static let flushEverySamples = 12
        static let flushEverySeconds: TimeInterval = 120
        /// Small tolerance for clock corrections; samples farther in the future are corrupt.
        static let futureSampleTolerance: TimeInterval = 5 * 60
        /// Population-change context shown in the overview. A baseline must be close to the target
        /// time; an observation from before a sleep/wake gap must never masquerade as a 30-minute
        /// comparison.
        static let shortChangeWindow: TimeInterval = 30 * 60
        static let shortChangeMinimumTolerance: TimeInterval = 60
        static let shortChangePollToleranceMultiplier = 2.0
        /// A spacing beyond this multiple of the expected bucket/poll cadence starts a new chart
        /// segment instead of drawing a line across observations that do not exist.
        static let chartGapMultiplier = 1.75
        /// Realm-rhythm percentile copy needs enough independent observations to avoid turning a
        /// few startup samples into a confident-sounding comparison.
        static let rhythmMinimumSamples = 30
    }

    // MARK: Freshness
    /// The on-open refresh fires when the last success is older than this.
    static let stalenessWindow: TimeInterval = 20

    // MARK: Crypto alerts
    enum CryptoAlert {
        static let defaultThresholdPercent: Double = 10
        static let sliderRange: ClosedRange<Double> = 1...50
        static let sliderStep: Double = 1
        /// A persisted baseline older than this is reseeded from the next quote without alerting.
        /// This prevents an app reopened weeks later from announcing an ancient move as new.
        static let maximumBaselineAge: TimeInterval = 24 * 3600
    }

    enum Alert {
        /// Require repeated remote-failure observations before claiming the realm looks down.
        static let outageConfirmationPolls = 2
    }

    /// New releases are rare, so their alert feed uses a deliberately slow, highly tolerant
    /// cadence independent of the live player and market pollers.
    enum ReleaseAlert {
        static let pollSeconds: TimeInterval = 30 * 60
        static let timerTolerance: TimeInterval = 3 * 60
        /// A wider snapshot prevents several releases published between checks from being
        /// rediscovered later; the alert policy consumes all identities and announces only newest.
        static let fetchLimit = 10
    }

    // MARK: Alerts 2.0
    enum AdvancedAlert {
        static let defaultPopulationThreshold = 125
        static let populationRange = 1...10_000
        static let populationStep = 5

        // Disabled until explicitly enabled; these are only sensible starting points for the
        // target fields, not product claims about where the market will trade.
        static let defaultPriceAboveTarget = 0.001
        static let defaultPriceBelowTarget = 0.00025
        static let minimumPriceTarget = 0.000000000001
        static let maximumPriceTarget = 1_000_000.0

        static let defaultCooldown = AlertCooldownOption.oneHour.seconds
        static let cooldownOptions = AlertCooldownOption.allCases.map(\.seconds)
        static let muteDuration: TimeInterval = 60 * 60
        static let defaultQuietStartMinute = 22 * 60
        static let defaultQuietEndMinute = 7 * 60

        static func normalizePopulation(_ value: Int) -> Int {
            min(max(value, populationRange.lowerBound), populationRange.upperBound)
        }

        static func normalizePriceTarget(_ value: Double, fallback: Double) -> Double {
            guard value.isFinite, value > 0 else { return fallback }
            return min(max(value, minimumPriceTarget), maximumPriceTarget)
        }

        static func normalizeCooldown(_ value: TimeInterval) -> TimeInterval {
            guard value.isFinite else { return defaultCooldown }
            return cooldownOptions.min(by: { abs($0 - value) < abs($1 - value) }) ?? defaultCooldown
        }
    }

    // MARK: Notifications
    static let notificationAuthorizationOptions: UNAuthorizationOptions = [.alert, .sound]
}
