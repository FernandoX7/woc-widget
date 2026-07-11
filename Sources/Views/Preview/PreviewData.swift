#if PREVIEW
import Foundation

/// Owns the screenshot build's complete dependency graph. Nothing reachable from this graph uses
/// production defaults, files, network services, notifications, or launch-at-login integration.
@MainActor
enum PreviewComposition {
    static func makeStore() -> StatusStore {
        let scenario = PreviewScenario.current

        let store = StatusStore(
            defaults: PreviewDefaults(),
            statusService: PreviewStatusService(scenario: scenario),
            cryptoService: PreviewCryptoService(scenario: scenario),
            candleService: PreviewCandleService(scenario: scenario),
            persistence: PreviewHistoryStore(samples: PreviewFixture.history(for: scenario)),
            notifier: PreviewNotifier(),
            notificationAuthorizer: PreviewNotificationAuthorizer(scenario: scenario),
            launch: PreviewLaunchManager(),
            now: { PreviewFixture.referenceDate },
            alertTimeZone: TimeZone(secondsFromGMT: 0)!
        )
        store.seedPreviewData(for: scenario)
        return store
    }
}

private enum PreviewFixture {
    /// 2026-07-11 18:00:00 UTC. A literal instant keeps charts, relative timestamps, and alert
    /// identifiers stable across machines and preview runs.
    static let referenceDate = Date(timeIntervalSince1970: 1_783_792_800)

    static let history: [Sample] = {
        stride(from: 360, through: 0, by: -1).map { minutesAgo in
            let date = referenceDate.addingTimeInterval(Double(-minutesAgo) * 60)
            let base = 82.0
                + 14.0 * sin(Double(minutesAgo) / 30.0)
                + 5.0 * sin(Double(minutesAgo) / 7.0)
            let noise = Double(((minutesAgo * 17 + 11) % 7) - 3)
            return Sample(date: date, count: max(0, Int((base + noise).rounded())))
        }
    }()

    static let status = StatusResponse(
        ok: true,
        realm: "Claudemoon",
        playersOnline: history.last?.count ?? 83
    )

    static let cachedHistory = history.map {
        Sample(date: $0.date.addingTimeInterval(-cachedAge), count: $0.count)
    }

    static let cachedAge: TimeInterval = 2 * 60 * 60

    static func history(for scenario: PreviewScenario) -> [Sample] {
        switch scenario {
        case .loading, .emptyHistory: return []
        case .cachedOffline: return cachedHistory
        default: return history
        }
    }

    static let quote = CryptoQuote(
        price: "0.0005594",
        change24h: 47.59,
        market: [
            .fiveMinutes: CryptoMarketWindow(changePercent: 1.2, buys: 8, sells: 5, volumeUSD: 912),
            .oneHour: CryptoMarketWindow(changePercent: 6.8, buys: 72, sells: 48, volumeUSD: 9_420),
            .sixHours: CryptoMarketWindow(changePercent: 18.4, buys: 321, sells: 264, volumeUSD: 48_200),
            .twentyFourHours: CryptoMarketWindow(
                changePercent: 47.59, buys: 526, sells: 508, volumeUSD: 81_075),
        ],
        liquidityUSD: 71_688,
        fullyDilutedValuationUSD: 559_400,
        marketCapUSD: 559_400,
        pairURL: AppLinks.market
    )

    static func candles(interval: CandleInterval, count: Int) -> [Candle] {
        guard count > 0 else { return [] }
        var result: [Candle] = []
        var price = 0.00052
        for offset in stride(from: count - 1, through: 0, by: -1) {
            let date = referenceDate.addingTimeInterval(Double(-offset) * interval.seconds)
            let open = price
            let noise = Double(((offset * 13 + 5) % 7) - 3)
            let drift = 0.000008 * sin(Double(offset) / 6.0) + 0.0000015 * noise
            let close = max(0.00001, open + drift)
            let high = max(open, close) + 0.000002 * Double((offset * 5) % 4)
            let low = min(open, close) - 0.000002 * Double((offset * 3) % 4)
            result.append(Candle(date: date, open: open, high: high, low: low, close: close))
            price = close
        }
        return result
    }
}

private struct PreviewStatusService: StatusFetching {
    let scenario: PreviewScenario

    func fetchStatus() async throws -> StatusResponse {
        if scenario == .cachedOffline { throw URLError(.notConnectedToInternet) }
        return PreviewFixture.status
    }
}

private struct PreviewCryptoService: CryptoFetching {
    let scenario: PreviewScenario

    func fetchQuote() async throws -> CryptoQuote {
        if scenario == .cachedOffline || scenario == .chartOnly {
            throw URLError(.notConnectedToInternet)
        }
        return PreviewFixture.quote
    }
}

private struct PreviewCandleService: CandleFetching {
    let scenario: PreviewScenario

    func fetchCandles(interval: CandleInterval, count: Int) async throws -> [Candle] {
        if scenario == .cachedOffline || scenario == .quoteOnly {
            throw URLError(.notConnectedToInternet)
        }
        return PreviewFixture.candles(interval: interval, count: count)
    }
}

/// A true in-memory `UserDefaults` implementation. StatusStore keeps its production preferences
/// API, while the preview process performs no CFPreferences reads or writes at all.
private final class PreviewDefaults: UserDefaults, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: Any] = [:]
    private var registeredValues: [String: Any] = [:]

    override func object(forKey defaultName: String) -> Any? {
        lock.lock()
        defer { lock.unlock() }
        return values[defaultName] ?? registeredValues[defaultName]
    }

    override func set(_ value: Any?, forKey defaultName: String) {
        lock.lock()
        defer { lock.unlock() }
        values[defaultName] = value
    }

    override func removeObject(forKey defaultName: String) {
        lock.lock()
        defer { lock.unlock() }
        values.removeValue(forKey: defaultName)
    }

    override func register(defaults registrationDictionary: [String: Any]) {
        lock.lock()
        defer { lock.unlock() }
        registeredValues.merge(registrationDictionary) { current, _ in current }
    }

    override func dictionaryRepresentation() -> [String: Any] {
        lock.lock()
        defer { lock.unlock() }
        return registeredValues.merging(values) { _, explicit in explicit }
    }
}

private final class PreviewHistoryStore: HistoryPersisting, @unchecked Sendable {
    private let lock = NSLock()
    private var samples: [Sample]

    init(samples: [Sample]) {
        self.samples = samples
    }

    func load() throws -> [Sample] {
        lock.lock()
        defer { lock.unlock() }
        return samples
    }

    func save(_ samples: [Sample]) throws {
        lock.lock()
        defer { lock.unlock() }
        self.samples = samples
    }
}

private struct PreviewNotifier: Notifier {
    func post(title: String, body: String, id: String) {}
}

private struct PreviewNotificationAuthorizer: NotificationAuthorizing {
    let scenario: PreviewScenario

    private var state: NotificationAuthorizationState {
        scenario == .notificationDenied ? .denied : .authorized
    }

    func currentStatus() async -> NotificationAuthorizationState { state }
    func requestAuthorization() async -> NotificationAuthorizationState { state }
}

private struct PreviewLaunchManager: LaunchAtLoginManaging {
    var isEnabled: Bool { false }
    func setEnabled(_ enabled: Bool) {}
}

private extension StatusStore {
    func seedPreviewData(for scenario: PreviewScenario) {
        let now = PreviewFixture.referenceDate
        let staleDate = now.addingTimeInterval(-PreviewFixture.cachedAge)

        history = PreviewFixture.history(for: scenario)
        response = nil
        phase = .loading
        realmAvailability = .loading
        errorMessage = nil
        lastSuccess = nil
        lastAttempt = nil
        isRefreshing = false
        consecutiveStatusFailures = 0
        historyPersistenceError = nil
        if let hi = history.max(by: { $0.count < $1.count }) {
            allTimePeak = hi.count
            allTimePeakDate = hi.date
        } else {
            allTimePeak = 0
            allTimePeakDate = nil
        }

        cryptoPrice = nil
        cryptoChange24h = nil
        marketQuote = nil
        priceLastSuccess = nil
        priceLastAttempt = nil
        priceErrorMessage = nil
        isPriceRefreshing = false
        candles = []
        loadedCandleInterval = nil
        candleLastSuccess = nil
        candleLastAttempt = nil
        candleErrorMessage = nil
        isCandlesRefreshing = false
        welcomeDismissed = scenario != .welcome

        if scenario == .loading {
            isRefreshing = true
            isPriceRefreshing = true
            isCandlesRefreshing = true
            notificationAuthorizationState = .unknown
            return
        }

        response = PreviewFixture.status
        phase = .ok
        realmAvailability = .healthy
        lastSuccess = now
        lastAttempt = now

        switch scenario {
        case .cachedOffline:
            phase = .error
            realmAvailability = .unreachable(.localNetwork)
            errorMessage = "This Mac is offline."
            lastSuccess = staleDate
            lastAttempt = now

            cryptoPrice = PreviewFixture.quote.price
            cryptoChange24h = PreviewFixture.quote.change24h
            marketQuote = PreviewFixture.quote
            priceLastSuccess = staleDate
            priceLastAttempt = now
            priceErrorMessage = "Market price is temporarily unavailable."

            candles = PreviewFixture.candles(interval: .fiveMin, count: AppConfig.Crypto.candleCount)
                .map { candle in
                    Candle(
                        date: candle.date.addingTimeInterval(-PreviewFixture.cachedAge),
                        open: candle.open,
                        high: candle.high,
                        low: candle.low,
                        close: candle.close,
                        volume: candle.volume
                    )
                }
            loadedCandleInterval = .fiveMin
            candleLastSuccess = staleDate
            candleLastAttempt = now
            candleErrorMessage = "Market chart is temporarily unavailable."

        case .quoteOnly:
            cryptoPrice = PreviewFixture.quote.price
            cryptoChange24h = PreviewFixture.quote.change24h
            marketQuote = PreviewFixture.quote
            priceLastSuccess = now
            priceLastAttempt = now
            candleLastAttempt = now
            candleErrorMessage = "Market chart is temporarily unavailable."

        case .chartOnly:
            priceLastAttempt = now
            priceErrorMessage = "Market price is temporarily unavailable."
            candles = PreviewFixture.candles(interval: .fiveMin, count: AppConfig.Crypto.candleCount)
            loadedCandleInterval = .fiveMin
            candleLastSuccess = now
            candleLastAttempt = now

        case .live, .welcome, .emptyHistory, .notificationDenied:
            cryptoPrice = PreviewFixture.quote.price
            cryptoChange24h = PreviewFixture.quote.change24h
            marketQuote = PreviewFixture.quote
            priceLastSuccess = now
            priceLastAttempt = now
            candles = PreviewFixture.candles(interval: .fiveMin, count: AppConfig.Crypto.candleCount)
            loadedCandleInterval = .fiveMin
            candleLastSuccess = now
            candleLastAttempt = now

        case .loading:
            break
        }

        notificationAuthorizationState = scenario == .notificationDenied ? .denied : .authorized
        if scenario == .notificationDenied {
            alertsEnabled = true
        }
    }
}
#endif
