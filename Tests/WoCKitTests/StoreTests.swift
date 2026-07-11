import Testing
import Foundation
@testable import WoCKit

// MARK: - Fakes

struct StubStatusService: StatusFetching, @unchecked Sendable {
    var response: StatusResponse?
    var error: FetchError?
    func fetchStatus() async throws -> StatusResponse {
        if let error { throw error }
        return response ?? StatusResponse(ok: true, realm: "R", playersOnline: 0, names: [])
    }
}

/// Status service whose response/error can be flipped between calls, to drive multi-step
/// store sequences (up→down→up transitions, peak progression).
final class MutableStatusService: StatusFetching, @unchecked Sendable {
    var response: StatusResponse?
    var error: FetchError?
    var fetchCount = 0
    func fetchStatus() async throws -> StatusResponse {
        fetchCount += 1
        if let error { throw error }
        return response ?? StatusResponse(ok: true, realm: "R", playersOnline: 0, names: [])
    }
}

struct StubCryptoService: CryptoFetching {
    func fetchQuote() async throws -> CryptoQuote { throw FetchError.decode }   // crypto disabled for these tests
}

/// Crypto service whose behavior can be flipped between calls, to exercise the best-effort path
/// (guardrail 7): a failure must leave the last price in place and never flip the realm to `.error`.
final class MutableCryptoService: CryptoFetching, @unchecked Sendable {
    var quote: CryptoQuote?
    var error: FetchError?
    var fetchCount = 0
    func fetchQuote() async throws -> CryptoQuote {
        fetchCount += 1
        if let error { throw error }
        guard let quote else { throw FetchError.decode }
        return quote
    }
}

struct StubCandleService: CandleFetching {
    var candles: [Candle] = []
    func fetchCandles(interval: CandleInterval, count: Int) async throws -> [Candle] { candles }
}

/// Candle service whose behavior can be flipped between calls, to exercise the best-effort path
/// (guardrail 7): a failure must leave the last candles in place and never flip the realm to error.
final class MutableCandleService: CandleFetching, @unchecked Sendable {
    var candles: [Candle]?
    var error: FetchError?
    func fetchCandles(interval: CandleInterval, count: Int) async throws -> [Candle] {
        if let error { throw error }
        return candles ?? []
    }
}

/// Candle service that records the (interval, count) it was asked for, so a test can assert the
/// store forwards the SELECTED candle width and the configured count (the stubs ignore both).
final class SpyCandleService: CandleFetching, @unchecked Sendable {
    var candles: [Candle] = []
    var lastInterval: CandleInterval?
    var lastCount: Int?
    var fetchCount = 0
    func fetchCandles(interval: CandleInterval, count: Int) async throws -> [Candle] {
        fetchCount += 1
        lastInterval = interval; lastCount = count
        return candles
    }
}

enum PersistenceTestError: Error { case load, save }

final class CountingPersistence: HistoryPersisting, @unchecked Sendable {
    private let lock = NSLock()
    private var storedToLoad: [Sample] = []
    private var storedSaveCount = 0
    private var storedLastSaved: [Sample] = []
    private var storedLoadError: Error?
    private var storedSaveError: Error?

    var toLoad: [Sample] {
        get { lock.withLock { storedToLoad } }
        set { lock.withLock { storedToLoad = newValue } }
    }
    var saveCount: Int { lock.withLock { storedSaveCount } }
    var lastSaved: [Sample] { lock.withLock { storedLastSaved } }
    var loadError: Error? {
        get { lock.withLock { storedLoadError } }
        set { lock.withLock { storedLoadError = newValue } }
    }
    var saveError: Error? {
        get { lock.withLock { storedSaveError } }
        set { lock.withLock { storedSaveError = newValue } }
    }

    func load() throws -> [Sample] {
        try lock.withLock {
            if let storedLoadError { throw storedLoadError }
            return storedToLoad
        }
    }
    func save(_ samples: [Sample]) throws {
        try lock.withLock {
            storedSaveCount += 1
            if let storedSaveError { throw storedSaveError }
            storedLastSaved = samples
        }
    }
}

/// A synchronous persistence fake with explicit async observation points. Blocking occurs only on
/// `HistoryPersistenceWorker`, never on the test's main actor, which makes startup/save races fully
/// deterministic without sleeps or scheduler assumptions.
final class ControlledHistoryPersistence: HistoryPersisting, @unchecked Sendable {
    private let lock = NSLock()
    private let loadGate = DispatchSemaphore(value: 0)
    private let saveGate = DispatchSemaphore(value: 0)
    private var loaded: [Sample]
    private var shouldBlockLoad: Bool
    private var blockedSavesRemaining: Int
    private var loadStarted = false
    private var saveAttempts = 0
    private var snapshots: [[Sample]] = []
    private var loadWaiters: [CheckedContinuation<Void, Never>] = []
    private var saveWaiters: [(target: Int, continuation: CheckedContinuation<Void, Never>)] = []

    init(load: [Sample], blockLoad: Bool = false, blockedSaveCount: Int = 0) {
        loaded = load
        shouldBlockLoad = blockLoad
        blockedSavesRemaining = blockedSaveCount
    }

    func load() throws -> [Sample] {
        let state = lock.withLock { () -> (Bool, [Sample], [CheckedContinuation<Void, Never>]) in
            loadStarted = true
            let waiters = loadWaiters
            loadWaiters.removeAll()
            return (shouldBlockLoad, loaded, waiters)
        }
        state.2.forEach { $0.resume() }
        if state.0 { loadGate.wait() }
        return state.1
    }

    func save(_ samples: [Sample]) throws {
        let state = lock.withLock { () -> (Bool, [CheckedContinuation<Void, Never>]) in
            saveAttempts += 1
            snapshots.append(samples)
            let shouldBlock = blockedSavesRemaining > 0
            if shouldBlock { blockedSavesRemaining -= 1 }
            let ready = saveWaiters.filter { $0.target <= saveAttempts }.map(\.continuation)
            saveWaiters.removeAll { $0.target <= saveAttempts }
            return (shouldBlock, ready)
        }
        state.1.forEach { $0.resume() }
        if state.0 { saveGate.wait() }
    }

    func waitUntilLoadStarts() async {
        await withCheckedContinuation { continuation in
            let resumeNow = lock.withLock {
                if loadStarted { return true }
                loadWaiters.append(continuation)
                return false
            }
            if resumeNow { continuation.resume() }
        }
    }

    func waitUntilSaveAttempt(_ target: Int) async {
        await withCheckedContinuation { continuation in
            let resumeNow = lock.withLock {
                if saveAttempts >= target { return true }
                saveWaiters.append((target, continuation))
                return false
            }
            if resumeNow { continuation.resume() }
        }
    }

    func releaseLoad() { loadGate.signal() }
    func releaseSave() { saveGate.signal() }
    var savedSnapshots: [[Sample]] { lock.withLock { snapshots } }
}

final class SpyNotifier: Notifier, @unchecked Sendable {
    var posts: [(title: String, body: String, id: String)] = []
    func post(title: String, body: String, id: String) { posts.append((title, body, id)) }
}

final class FakeNotificationAuthorizer: NotificationAuthorizing, @unchecked Sendable {
    var status: NotificationAuthorizationState
    var requestCount = 0
    var statusCount = 0
    init(status: NotificationAuthorizationState = .authorized) { self.status = status }
    func currentStatus() async -> NotificationAuthorizationState {
        statusCount += 1
        return status
    }
    func requestAuthorization() async -> NotificationAuthorizationState {
        requestCount += 1
        return status
    }
}

/// Controllable launch manager. `reported` is what `isEnabled` returns; `reflectWrites` decides
/// whether `setEnabled` updates `reported` (a successful register) or ignores it (`.requiresApproval`).
final class FakeLaunch: LaunchAtLoginManaging, @unchecked Sendable {
    var reported: Bool
    var reflectWrites: Bool
    init(reported: Bool = false, reflectWrites: Bool = true) {
        self.reported = reported; self.reflectWrites = reflectWrites
    }
    var isEnabled: Bool { reported }
    func setEnabled(_ enabled: Bool) { if reflectWrites { reported = enabled } }
}

// MARK: - Tests

@MainActor
@Suite struct StoreTests {
    /// Fresh, isolated UserDefaults per test.
    func makeDefaults(_ name: String, _ seed: [String: Any] = [:]) -> UserDefaults {
        let d = UserDefaults(suiteName: "woc.tests.\(name)")!
        d.removePersistentDomain(forName: "woc.tests.\(name)")
        for (k, v) in seed { d.set(v, forKey: k) }
        return d
    }

    func makeStore(defaults: UserDefaults,
                   status: any StatusFetching = StubStatusService(),
                   crypto: any CryptoFetching = StubCryptoService(),
                   candle: any CandleFetching = StubCandleService(),
                   persistence: any HistoryPersisting = CountingPersistence(),
                   notifier: SpyNotifier = .init(),
                   authorizer: FakeNotificationAuthorizer = .init(),
                   launch: FakeLaunch = .init(),
                   now: @escaping () -> Date = { Date(timeIntervalSince1970: 1_700_000_000) }) -> StatusStore {
        StatusStore(defaults: defaults, statusService: status, cryptoService: crypto,
                    candleService: candle, persistence: persistence, notifier: notifier,
                    notificationAuthorizer: authorizer, launch: launch, now: now)
    }

    @Test func normalizesCorruptedPollIntervalsOnLoad() {
        let d = makeDefaults("clampLoad", ["pollSeconds": 2.0, "cryptoPollSeconds": 0.0])
        let store = makeStore(defaults: d)
        #expect(store.pollSeconds == AppConfig.Poll.minimumSeconds)
        #expect(store.cryptoPollSeconds == PollInterval.thirtySeconds.seconds)
        #expect(d.double(for: .pollSeconds) == PollInterval.tenSeconds.seconds)
        #expect(d.double(for: .cryptoPollSeconds) == PollInterval.thirtySeconds.seconds)
    }

    @Test func clampsPollIntervalOnSet() {
        let store = makeStore(defaults: makeDefaults("clampSet"))
        store.pollSeconds = 3
        #expect(store.pollSeconds == AppConfig.Poll.minimumSeconds)
        store.pollSeconds = 300
        #expect(store.pollSeconds == 300)   // valid value untouched
    }

    @Test func launchToggleSnapsBackWhenApprovalPending() {
        // register() doesn't take effect (requiresApproval): isEnabled stays false.
        let launch = FakeLaunch(reported: false, reflectWrites: false)
        let store = makeStore(defaults: makeDefaults("launchSnap"), launch: launch)
        #expect(store.launchAtLogin == false)
        store.launchAtLogin = true            // user flips it on…
        #expect(store.launchAtLogin == false) // …but it reconciles back to the truthful state
    }

    @Test func launchToggleSticksWhenRegistrationSucceeds() {
        let launch = FakeLaunch(reported: false, reflectWrites: true)
        let store = makeStore(defaults: makeDefaults("launchStick"), launch: launch)
        store.launchAtLogin = true
        #expect(store.launchAtLogin == true)
        #expect(launch.reported == true)
    }

    @Test func failedFetchUpdatesAttemptNotSuccess() async {
        let store = makeStore(defaults: makeDefaults("lastAttempt"),
                              status: StubStatusService(error: .transport(URLError(.timedOut))))
        await store.refreshStatus()
        #expect(store.phase == .error)
        #expect(store.lastSuccess == nil)        // never marked successful
        #expect(store.lastAttempt != nil)
        #expect(store.isStale == true)           // so the on-open retry isn't suppressed
        #expect(store.errorMessage == "Server timed out")
    }

    @Test func successfulFetchSetsSuccessAndRecords() async {
        let persistence = CountingPersistence()
        let store = makeStore(defaults: makeDefaults("success"),
                              status: StubStatusService(response: StatusResponse(ok: true, realm: "R", playersOnline: 7, names: ["a"])),
                              persistence: persistence)
        await store.refreshStatus()
        await store.flushHistoryAndWait()
        #expect(store.phase == .ok)
        #expect(store.count == 7)
        #expect(store.lastSuccess != nil)
        #expect(persistence.saveCount == 1)      // first record flushes immediately
    }

    @Test func zeroPlayersOnHealthyResponseIsStillOnline() async {
        let store = makeStore(defaults: makeDefaults("zeroHealthy"),
                              status: StubStatusService(response: StatusResponse(
                                ok: true, realm: "R", playersOnline: 0)))
        await store.refreshStatus()
        #expect(store.realmAvailability == .healthy)
        #expect(store.isOnline == true)
        #expect(store.count == 0)
        #expect(store.hasLocalRecord)
    }

    @Test func repeatedLocalNetworkErrorsNeverClaimRealmDownOrNotify() async {
        let service = MutableStatusService()
        let notifier = SpyNotifier()
        let store = makeStore(defaults: makeDefaults("localNotDown", ["allTimePeak": 100]),
                              status: service, notifier: notifier)
        service.response = StatusResponse(ok: true, realm: "R", playersOnline: 4)
        await store.refreshStatus()
        service.response = nil
        service.error = .transport(URLError(.notConnectedToInternet))
        await store.refreshStatus()
        await store.refreshStatus()
        #expect(store.realmAvailability == .unreachable(.localNetwork))
        #expect(store.consecutiveStatusFailures == 0)
        #expect(notifier.posts.isEmpty)
    }

    @Test func historyWritesAreCoalesced() async {
        let persistence = CountingPersistence()
        // Fixed clock → coalescing is purely sample-count driven (no 120s elapse).
        let store = makeStore(defaults: makeDefaults("coalesce"),
                              status: StubStatusService(response: StatusResponse(ok: true, realm: "R", playersOnline: 1, names: [])),
                              persistence: persistence,
                              now: { Date(timeIntervalSince1970: 1_700_000_000) })
        await store.refreshStatus()              // record #1 → flush (distantPast)
        await store.flushHistoryAndWait()
        #expect(persistence.saveCount == 1)
        for _ in 0..<10 { await store.refreshStatus() }   // records #2–#11 → coalesced, no flush
        #expect(persistence.saveCount == 1)
        for _ in 0..<2 { await store.refreshStatus() }    // record #12 hits the threshold → flush
        await store.flushHistoryAndWait()
        #expect(persistence.saveCount == 2)
    }

    @Test func startupLoadMergesASampleRecordedWhileDiskReadIsInFlight() async {
        let clock = Date(timeIntervalSince1970: 1_700_000_000)
        let diskSample = Sample(date: clock.addingTimeInterval(-60), count: 50)
        let persistence = ControlledHistoryPersistence(load: [diskSample], blockLoad: true)
        let notifier = SpyNotifier()
        let store = makeStore(
            defaults: makeDefaults("loadRecordRace", ["allTimePeak": 5, "peakAlertsEnabled": true]),
            status: StubStatusService(response: StatusResponse(
                ok: true, realm: "R", playersOnline: 7)),
            persistence: persistence,
            notifier: notifier,
            now: { clock }
        )

        await persistence.waitUntilLoadStarts()
        await store.refreshStatus()
        #expect(persistence.savedSnapshots.isEmpty) // never overwrite before disk state is known
        #expect(store.allTimePeak == 5) // peak evaluation waits for the retained baseline

        persistence.releaseLoad()
        await store.flushHistoryAndWait()

        #expect(store.history == [diskSample, Sample(date: clock, count: 7)])
        #expect(persistence.savedSnapshots.last == store.history)
        #expect(store.allTimePeak == 50)
        #expect(notifier.posts.isEmpty) // 7 was never misreported as a new record
    }

    @Test func sampleArrivingDuringSaveCannotBeClearedOrOverwrittenByOlderSnapshot() async {
        var clock = Date(timeIntervalSince1970: 1_700_000_000)
        let status = MutableStatusService()
        status.response = StatusResponse(ok: true, realm: "R", playersOnline: 1)
        let persistence = ControlledHistoryPersistence(load: [], blockedSaveCount: 1)
        let store = makeStore(
            defaults: makeDefaults("saveRecordRace", ["allTimePeak": 100]),
            status: status,
            persistence: persistence,
            now: { clock }
        )
        await store.flushHistoryAndWait() // finish the startup read before exercising save races

        await store.refreshStatus()
        await persistence.waitUntilSaveAttempt(1)
        clock = clock.addingTimeInterval(1)
        status.response = StatusResponse(ok: true, realm: "R", playersOnline: 2)
        await store.refreshStatus()

        persistence.releaseSave()
        await store.flushHistoryAndWait()

        let snapshots = persistence.savedSnapshots
        #expect(snapshots.count == 2)
        #expect(snapshots[0].map(\.count) == [1])
        #expect(snapshots[1].map(\.count) == [1, 2])
        #expect(store.history.map(\.count) == [1, 2])
    }

    // MARK: crypto best-effort (guardrail 7)

    @Test func cryptoSuccessSetsPrice() async {
        let crypto = MutableCryptoService()
        crypto.quote = CryptoQuote(price: "0.0005594", change24h: 47.59)
        let store = makeStore(defaults: makeDefaults("cryptoOK"), crypto: crypto)
        await store.refreshCrypto()
        #expect(store.cryptoPrice == "0.0005594")
        #expect(store.cryptoChange24h == 47.59)
        #expect(store.marketQuote?.price == "0.0005594")
        #expect(store.priceLastSuccess != nil)
        #expect(store.priceLastAttempt == store.priceLastSuccess)
        #expect(store.priceFeedState == .live)
        #expect(store.priceErrorMessage == nil)
        #expect(store.phase != .error)
    }

    @Test func cryptoFailureKeepsLastPriceAndNeverErrorsRealm() async {
        let crypto = MutableCryptoService()
        crypto.quote = CryptoQuote(price: "1.23", change24h: 5)
        let store = makeStore(defaults: makeDefaults("cryptoBestEffort"), crypto: crypto)
        await store.refreshCrypto()
        #expect(store.cryptoPrice == "1.23")
        // Now the feed breaks: the last price must remain and the realm must NOT flip to error.
        crypto.quote = nil
        crypto.error = .transport(URLError(.timedOut))
        await store.refreshCrypto()
        #expect(store.cryptoPrice == "1.23")     // unchanged
        #expect(store.priceFeedState == .cached)
        #expect(store.priceErrorMessage == "Server timed out")
        #expect(store.phase != .error)           // crypto failure never errors the realm
    }

    @Test func invalidCryptoNumbersAreRejectedAndDoNotSeedAlerts() async {
        let crypto = MutableCryptoService()
        crypto.quote = CryptoQuote(price: "nan", change24h: .infinity)
        let store = makeStore(defaults: makeDefaults("cryptoInvalid"), crypto: crypto)
        await store.refreshCrypto()
        #expect(store.cryptoPrice == nil)
        #expect(store.priceLastSuccess == nil)
        #expect(store.priceFeedState == .unavailable)
        #expect(store.lastAlertedPrice == 0)
    }

    @Test func invalidAncillaryMarketNumbersAreSanitizedWithoutDiscardingSpot() async {
        let crypto = MutableCryptoService()
        crypto.quote = CryptoQuote(
            price: "1.25", change24h: 2,
            market: [.twentyFourHours: CryptoMarketWindow(
                changePercent: .nan, buys: -1, sells: 3, volumeUSD: -.infinity)],
            liquidityUSD: -10, fullyDilutedValuationUSD: .infinity,
            marketCapUSD: 100, pairURL: URL(string: "file:///tmp/not-market"))
        let store = makeStore(defaults: makeDefaults("marketSanitize"), crypto: crypto)
        await store.refreshCrypto()
        #expect(store.cryptoPrice == "1.25")
        let day = store.marketQuote?.metrics(for: .twentyFourHours)
        #expect(day?.changePercent == nil)
        #expect(day?.buys == nil)
        #expect(day?.sells == 3)
        #expect(day?.volumeUSD == nil)
        #expect(store.marketQuote?.liquidityUSD == nil)
        #expect(store.marketQuote?.fullyDilutedValuationUSD == nil)
        #expect(store.marketQuote?.marketCapUSD == 100)
        #expect(store.marketQuote?.pairURL == nil)
    }

    // MARK: candle chart (real OHLC from GeckoTerminal, best-effort like the price path)

    @Test func candleFetchPopulatesChart() async {
        let candle = MutableCandleService()
        let t = Date(timeIntervalSince1970: 1_700_000_000)
        candle.candles = [Candle(date: t, open: 1, high: 2, low: 0.5, close: 1.5)]
        let store = makeStore(defaults: makeDefaults("candleOK"), candle: candle)
        await store.refreshCandles()
        #expect(store.candles.count == 1)
        #expect(store.candles.first?.close == 1.5)
        #expect(store.candles.first?.isUp == true)
        #expect(store.loadedCandleInterval == .fiveMin)
        #expect(store.chartCandles.count == 1)
        #expect(store.candleFeedState == .live)
    }

    @Test func candleFailureKeepsLastCandlesAndNeverErrorsRealm() async {
        let candle = MutableCandleService()
        candle.candles = [Candle(date: Date(timeIntervalSince1970: 1_700_000_000), open: 1, high: 2, low: 0.5, close: 1.5)]
        let store = makeStore(defaults: makeDefaults("candleBestEffort"), candle: candle)
        await store.refreshCandles()
        #expect(store.candles.count == 1)
        // Feed breaks: the last candles must remain and the realm must NOT flip to error.
        candle.candles = nil
        candle.error = .transport(URLError(.timedOut))
        await store.refreshCandles()
        #expect(store.candles.count == 1)        // unchanged
        #expect(store.candleFeedState == .cached)
        #expect(store.candleErrorMessage == "Server timed out")
        #expect(store.phase != .error)
    }

    @Test func cryptoIntervalSelectionPersists() {
        let d = makeDefaults("cryptoInterval")
        let store = makeStore(defaults: d)
        store.cryptoInterval = .fifteenMin
        #expect(d.integer(for: .cryptoChartInterval) == CandleInterval.fifteenMin.rawValue)
    }

    @Test func refreshCandlesRequestsSelectedIntervalAndCandleCount() async {
        let spy = SpyCandleService()
        spy.candles = [Candle(date: Date(timeIntervalSince1970: 1_700_000_000), open: 1, high: 2, low: 0.5, close: 1.5)]
        let d = makeDefaults("candleParams", ["cryptoChartInterval": CandleInterval.fifteenMin.rawValue])
        let store = makeStore(defaults: d, candle: spy)
        await store.refreshCandles()
        #expect(spy.lastInterval == .fifteenMin)               // the SELECTED width, not a default
        #expect(spy.lastCount == AppConfig.Crypto.candleCount) // the configured count
    }

    @Test func cachedCandlesFromOldIntervalAreNeverExposedAsSelectedChartData() async {
        let candle = MutableCandleService()
        candle.candles = [Candle(date: Date(timeIntervalSince1970: 1_700_000_000),
                                  open: 1, high: 2, low: 0.5, close: 1.5)]
        let store = makeStore(defaults: makeDefaults("candleProvenance"), candle: candle)
        await store.refreshCandles()
        #expect(store.loadedCandleInterval == .fiveMin)
        #expect(store.chartCandles.count == 1)

        candle.candles = nil
        candle.error = .transport(URLError(.timedOut))
        store.cryptoInterval = .oneHour
        // `didSet` starts a best-effort task, but provenance is truthful synchronously.
        #expect(store.loadedCandleInterval == .fiveMin)
        #expect(store.chartCandles.isEmpty)
        #expect(store.hasCachedCandlesForDifferentInterval)
        #expect(store.candleFeedState == .cached)
    }

    @Test func emptyCandleResponsePreservesLastCandles() async {
        let candle = MutableCandleService()
        candle.candles = [Candle(date: Date(timeIntervalSince1970: 1_700_000_000), open: 1, high: 2, low: 0.5, close: 1.5)]
        let store = makeStore(defaults: makeDefaults("candleEmpty"), candle: candle)
        await store.refreshCandles()
        #expect(store.candles.count == 1)
        // A valid but EMPTY 200 (no throw, plausible for an illiquid token) must NOT blank the chart
        // to the placeholder — the `!bars.isEmpty` guard keeps the last candles (guardrail 7).
        candle.candles = []
        await store.refreshCandles()
        #expect(store.candles.count == 1)
        #expect(store.phase != .error)
    }

    @Test func refreshCryptoTickFansOutPriceAndCandlesIndependently() async {
        let crypto = MutableCryptoService()
        let candle = MutableCandleService()
        let t = Date(timeIntervalSince1970: 1_700_000_000)
        // Price feed broken, candle feed healthy: one tick must still populate candles, leave the
        // price unset, and never error the realm (guardrails 4 + 7).
        crypto.error = .transport(URLError(.timedOut))
        candle.candles = [Candle(date: t, open: 1, high: 2, low: 0.5, close: 1.5)]
        let store = makeStore(defaults: makeDefaults("fanout"), crypto: crypto, candle: candle)
        store.isPopoverVisible = true
        await store.refreshCryptoTick()
        #expect(store.candles.count == 1)
        #expect(store.cryptoPrice == nil)
        #expect(store.phase != .error)
        // Inverse: price healthy, candle feed broken — price updates, last candles preserved.
        crypto.error = nil
        crypto.quote = CryptoQuote(price: "0.0005594", change24h: 1)
        candle.candles = nil
        candle.error = .transport(URLError(.timedOut))
        store.candleLastAttempt = nil // due now, so the visible tick independently retries bars
        await store.refreshCryptoTick()
        #expect(store.cryptoPrice == "0.0005594")
        #expect(store.candles.count == 1)
        #expect(store.phase != .error)
    }

    @Test func backgroundCryptoTickSkipsCandlesWhilePopoverIsClosed() async {
        let candle = SpyCandleService()
        candle.candles = [Candle(date: Date(timeIntervalSince1970: 1_700_000_000),
                                  open: 1, high: 2, low: 0.5, close: 1.5)]
        let store = makeStore(defaults: makeDefaults("closedCandles"), candle: candle)
        await store.refreshCryptoTick()
        #expect(candle.fetchCount == 0)

        store.isPopoverVisible = true
        await store.refreshCryptoTick()
        #expect(candle.fetchCount == 1)

        // Once fresh, another visible spot tick does not redownload the same 60 bars.
        await store.refreshCryptoTick()
        #expect(candle.fetchCount == 1)
    }

    // MARK: frozen menu-bar label format (guardrail 8)

    @Test func menuBarLabelLoadingOnlineErrorFormats() {
        let store = makeStore(defaults: makeDefaults("mbBasic"))
        #expect(store.menuBarLabel == "🟡 —")                 // loading is unknown, not measured zero
        store.response = StatusResponse(ok: true, realm: "R", playersOnline: 5, names: [])
        store.phase = .ok
        store.realmAvailability = .healthy
        #expect(store.menuBarLabel == "🟢 5")
        store.phase = .error
        store.realmAvailability = .unreachable(.timedOut)
        #expect(store.menuBarLabel == "🟠 5")
    }

    @Test func menuBarLabelWithCryptoPrefix() {
        let store = makeStore(defaults: makeDefaults("mbCrypto"))
        store.response = StatusResponse(ok: true, realm: "R", playersOnline: 7, names: [])
        store.phase = .ok
        store.realmAvailability = .healthy
        store.menuBarDisplayMode = .full
        store.cryptoPrice = "0.0005594"
        store.cryptoChange24h = 47.59
        store.priceLastSuccess = store.currentDate
        #expect(store.menuBarLabel == "$0.0005594 (+47.6%) 🟢 7")
        store.cryptoChange24h = -3.2
        #expect(store.menuBarLabel == "$0.0005594 (-3.2%) 🟢 7")
    }

    @Test func menuBarDisplayModesStayCompactAndPersist() {
        let defaults = makeDefaults("mbModes")
        let store = makeStore(defaults: defaults)
        store.response = StatusResponse(ok: true, realm: "R", playersOnline: 104)
        store.phase = .ok
        store.realmAvailability = .healthy
        store.cryptoPrice = "0.0005678"
        store.cryptoChange24h = 23.3
        store.priceLastSuccess = store.currentDate

        store.menuBarDisplayMode = .players
        #expect(store.menuBarLabel == "🟢 104")
        store.menuBarDisplayMode = .playersAndChange
        #expect(store.menuBarLabel == "🟢 104 · WOC +23.3%")
        store.menuBarDisplayMode = .token
        #expect(store.menuBarLabel == "$0.0005678 +23.3%")
        store.menuBarDisplayMode = .full
        #expect(store.menuBarLabel == "$0.0005678 (+23.3%) 🟢 104")
        #expect(defaults.string(for: .menuBarDisplayMode) == MenuBarDisplayMode.full.rawValue)
    }

    @Test func newInstallsDefaultToIntegratedPlayerAndWOCSignal() {
        let store = makeStore(defaults: makeDefaults("mbIntegratedDefault"))
        #expect(store.menuBarDisplayMode == .playersAndChange)
        store.response = StatusResponse(ok: true, realm: "R", playersOnline: 12)
        store.phase = .ok
        store.realmAvailability = .healthy
        store.cryptoPrice = "0.0005"
        store.cryptoChange24h = 4.2
        store.priceLastSuccess = store.currentDate
        #expect(store.menuBarLabel == "🟢 12 · WOC +4.2%")
    }

    // MARK: history prune-on-flush

    @Test func flushPrunesSamplesOlderThanRetentionWindow() async {
        let clock = Date(timeIntervalSince1970: 1_700_000_000)
        let persistence = CountingPersistence()
        let stale = Sample(date: clock.addingTimeInterval(-AppConfig.History.retentionWindow - 3600), count: 1)
        let fresh = Sample(date: clock.addingTimeInterval(-60), count: 2)
        persistence.toLoad = [stale, fresh]   // pre-sorted oldest-first, so the `history.first` guard fires
        let store = makeStore(defaults: makeDefaults("prune"),
                              status: StubStatusService(response: StatusResponse(ok: true, realm: "R", playersOnline: 9, names: [])),
                              persistence: persistence,
                              now: { clock })
        await store.flushHistoryAndWait()       // startup repair completes before the new sample
        await store.refreshStatus()            // appends one sample, then flushes (first record)
        await store.flushHistoryAndWait()
        #expect(persistence.saveCount == 2) // load repair + new-sample flush
        #expect(!persistence.lastSaved.contains { $0.date == stale.date })   // stale pruned
        #expect(persistence.lastSaved.contains { $0.date == fresh.date })    // fresh kept
        #expect(persistence.lastSaved.count == 2)                            // fresh + the new sample
    }

    // MARK: all-time-peak reconcile-on-load (init)

    @Test func reconcilesAllTimePeakUpFromRetainedHistoryOnLoad() async {
        let d = makeDefaults("peakUp", ["allTimePeak": 5])
        let persistence = CountingPersistence()
        let peakDate = Date(timeIntervalSince1970: 1_700_000_000 - 3600)
        persistence.toLoad = [Sample(date: peakDate, count: 50)]
        let store = makeStore(defaults: d, persistence: persistence)
        await store.flushHistoryAndWait()
        #expect(store.allTimePeak == 50)            // bumped to the retained high
        #expect(store.allTimePeakDate == peakDate)  // and its date recovered
        #expect(d.integer(for: .allTimePeak) == 50)
        #expect(d.date(for: .allTimePeakDate) == peakDate)
    }

    @Test func keepsPersistedPeakWhenRetainedHistoryIsLowerOnLoad() async {
        let d = makeDefaults("peakKeep", ["allTimePeak": 100])
        let persistence = CountingPersistence()
        persistence.toLoad = [Sample(date: Date(timeIntervalSince1970: 1_700_000_000), count: 9)]
        let store = makeStore(defaults: d, persistence: persistence)
        await store.flushHistoryAndWait()
        #expect(store.allTimePeak == 100)   // history max (9) < persisted (100) → unchanged
    }

    @Test func clearHistoryWaitsForLoadAndPersistsAnEmptyCompatibleSnapshot() async {
        let d = makeDefaults("historyClear", ["allTimePeak": 100])
        let persistence = CountingPersistence()
        persistence.toLoad = [Sample(date: Date(timeIntervalSince1970: 1_700_000_000), count: 42)]
        let store = makeStore(defaults: d, persistence: persistence)

        await store.clearHistoryAndWait()

        #expect(store.history.isEmpty)
        #expect(store.allTimePeak == 0)
        #expect(store.allTimePeakDate == nil)
        #expect(d.object(forKey: DefaultsKey.allTimePeak.rawValue) == nil)
        #expect(d.object(forKey: DefaultsKey.allTimePeakDate.rawValue) == nil)
        #expect(persistence.lastSaved.isEmpty)
    }

    @Test func historyLoadSortsDeduplicatesAndPrunesInvalidSamples() async {
        let clock = Date(timeIntervalSince1970: 1_700_000_000)
        let persistence = CountingPersistence()
        let a = Sample(date: clock.addingTimeInterval(-30), count: 3)
        let b = Sample(date: clock.addingTimeInterval(-60), count: 2)
        persistence.toLoad = [a, Sample(date: b.date, count: 99), b,
                              Sample(date: clock, count: -1),
                              Sample(date: clock.addingTimeInterval(600), count: 4)]
        let store = makeStore(defaults: makeDefaults("historyNormalize"),
                              persistence: persistence, now: { clock })
        await store.flushHistoryAndWait()
        #expect(store.history.map(\.date) == [b.date, a.date])
        #expect(store.history.map(\.count) == [99, 3]) // first duplicate deterministically wins
        #expect(persistence.saveCount == 1)             // repaired representation written back
    }

    @Test func historyPersistenceFailuresAreObservableAndRetried() async {
        let persistence = CountingPersistence()
        persistence.loadError = PersistenceTestError.load
        let store = makeStore(defaults: makeDefaults("historyErrors"),
                              status: StubStatusService(response: StatusResponse(
                                ok: true, realm: "R", playersOnline: 1)),
                              persistence: persistence)
        await store.flushHistoryAndWait()
        #expect(store.historyPersistenceError == "Couldn't load saved player history")

        persistence.loadError = nil
        persistence.saveError = PersistenceTestError.save
        await store.refreshStatus()
        await store.flushHistoryAndWait()
        #expect(store.historyPersistenceError == "Couldn't save player history")
        #expect(persistence.saveCount == 1)

        persistence.saveError = nil
        await store.flushHistoryAndWait()
        #expect(persistence.saveCount == 2)
        #expect(store.historyPersistenceError == nil)
    }

    // MARK: store-level alert sequencing (the side-effects the pure AlertEngine tests can't reach)

    @Test func postsStatusDownThenUpAcrossTransitionsWithUniqueIds() async {
        var t = 1_700_000_000.0
        let status = MutableStatusService()
        let notifier = SpyNotifier()
        // High persisted peak so peak alerts never fire; crypto stays disabled (StubCryptoService).
        let d = makeDefaults("alertSeq", [
            "allTimePeak": 100_000,
            "advancedAlertCooldown": 0.0,
        ])
        let store = makeStore(defaults: d, status: status, notifier: notifier, now: { Date(timeIntervalSince1970: t) })

        // 1) First observation (up): seeds wasUp, posts nothing (skip-first-observation, invariant 8).
        status.response = StatusResponse(ok: true, realm: "Claudemoon", playersOnline: 7, names: [])
        await store.refreshStatus()
        #expect(notifier.posts.isEmpty)

        // 2) One down observation is visible immediately but does not notify yet.
        t += 60
        status.response = StatusResponse(ok: false, realm: "Claudemoon", playersOnline: 0, names: [])
        await store.refreshStatus()
        #expect(notifier.posts.isEmpty)
        #expect(store.realmAvailability == .serverReportedDown)
        #expect(store.consecutiveStatusFailures == 1)

        // 3) A second consecutive remote failure confirms the outage.
        t += 60
        await store.refreshStatus()
        #expect(notifier.posts.count == 1)
        #expect(notifier.posts[0].title == "⚠️ Claudemoon looks down")
        #expect(notifier.posts[0].id.hasPrefix("status-"))

        // 4) Recovers: one status-up alert, with a DISTINCT id (advanced clock → unique per fire).
        t += 60
        status.response = StatusResponse(ok: true, realm: "Claudemoon", playersOnline: 9, names: [])
        await store.refreshStatus()
        #expect(notifier.posts.count == 2)
        #expect(notifier.posts[1].title == "✅ Claudemoon is back")
        #expect(notifier.posts[1].body == "9 players online now.")
        #expect(notifier.posts[0].id != notifier.posts[1].id)   // invariant 8: unique id per fire
    }

    @Test func postsPeakOnlyOnANewHighWithPrior() async {
        var t = 1_700_000_000.0
        let status = MutableStatusService()
        let notifier = SpyNotifier()
        let store = makeStore(defaults: makeDefaults("peakSeq"), status: status, notifier: notifier,
                              now: { Date(timeIntervalSince1970: t) })
        await store.flushHistoryAndWait()

        // First-ever sample sets the record but must NOT post (no prior peak — invariant 8).
        status.response = StatusResponse(ok: true, realm: "R", playersOnline: 10, names: [])
        await store.refreshStatus()
        #expect(store.allTimePeak == 10)
        #expect(notifier.posts.isEmpty)

        // A higher sample posts the peak and bumps the record (status stays up → no status alert).
        t += 60
        status.response = StatusResponse(ok: true, realm: "R", playersOnline: 25, names: [])
        await store.refreshStatus()
        #expect(store.allTimePeak == 25)
        #expect(notifier.posts.count == 1)
        #expect(notifier.posts[0].title == "🏆 New peak on R!")
    }

    @Test func missingRollingMetricNeverFallsBackToLegacySpotAlerts() async {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let crypto = MutableCryptoService()
        let notifier = SpyNotifier()
        let defaults = makeDefaults("cryptoSeq", [
            "lastAlertedPrice": 1.0,
            "lastAlertedPriceDate": now,
        ])
        let store = makeStore(defaults: defaults, crypto: crypto, notifier: notifier,
                              now: { now })

        // No selected rolling observation means no alert. Falling back to spot-vs-baseline here
        // would bypass quiet hours, cooldowns, hysteresis, and per-rule notification actions.
        crypto.quote = CryptoQuote(price: "1.20", change24h: 20)
        await store.refreshCrypto()
        #expect(notifier.posts.isEmpty)
        #expect(store.lastAlertedPrice == 1.0)
        #expect(store.lastAlertedPriceDate == now)
    }

    @Test func ancientPersistedCryptoBaselineIsReseededWithoutAlert() async {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let d = makeDefaults("oldBaseline", [
            "lastAlertedPrice": 1.0,
            "lastAlertedPriceDate": now.addingTimeInterval(
                -AppConfig.CryptoAlert.maximumBaselineAge - 1),
        ])
        let crypto = MutableCryptoService()
        crypto.quote = CryptoQuote(price: "2.0", change24h: 100)
        let notifier = SpyNotifier()
        let store = makeStore(defaults: d, crypto: crypto, notifier: notifier, now: { now })
        #expect(store.lastAlertedPrice == 0)
        await store.refreshCrypto()
        #expect(notifier.posts.isEmpty)
        #expect(store.lastAlertedPrice == 0)
        #expect(store.lastAlertedPriceDate == nil)
    }

    @Test func normalizesPersistedThresholdAndUnsupportedPollOptions() {
        let d = makeDefaults("numericNormalize", [
            "pollSeconds": 121.0,
            "cryptoPollSeconds": Double.infinity,
            "cryptoAlertThreshold": 500.0,
            "allTimePeak": -20,
        ])
        let store = makeStore(defaults: d)
        #expect(store.pollSeconds == 60) // nearest supported player option
        #expect(store.cryptoPollSeconds == AppConfig.Poll.defaultCryptoSeconds)
        #expect(store.cryptoAlertThreshold == 50)
        #expect(store.allTimePeak == 0)
        #expect(d.double(for: .cryptoAlertThreshold) == 50)
        #expect(d.integer(for: .allTimePeak) == 0)
    }

    @Test func enablingCryptoAlertsReseedsInsteadOfUsingDisabledPeriodBaseline() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let d = makeDefaults("toggleReseed", [
            "cryptoAlertsEnabled": false,
            "lastAlertedPrice": 1.0,
            "lastAlertedPriceDate": now,
        ])
        let store = makeStore(defaults: d, now: { now })
        #expect(store.lastAlertedPrice == 1)
        store.cryptoAlertsEnabled = true
        #expect(store.lastAlertedPrice == 0)
        #expect(store.lastAlertedPriceDate == nil)
    }

    // MARK: freshness / flush timing

    @Test func flushesOnElapsedTimeNotJustSampleCount() async {
        var t = 1_700_000_000.0
        let persistence = CountingPersistence()
        let store = makeStore(defaults: makeDefaults("timeFlush"),
                              status: StubStatusService(response: StatusResponse(ok: true, realm: "R", playersOnline: 1, names: [])),
                              persistence: persistence, now: { Date(timeIntervalSince1970: t) })
        await store.refreshStatus()          // record #1 → flush (lastFlush == distantPast)
        await store.flushHistoryAndWait()
        #expect(persistence.saveCount == 1)
        await store.refreshStatus()          // #2, #3: sub-threshold count, no time elapsed → coalesced
        await store.refreshStatus()
        #expect(persistence.saveCount == 1)
        t += AppConfig.History.flushEverySeconds + 1   // advance past the time threshold
        await store.refreshStatus()          // #4: time-based flush fires despite sub-threshold count
        await store.flushHistoryAndWait()
        #expect(persistence.saveCount == 2)
    }

    @Test func isStaleFlipsAtTheStalenessWindowBoundary() async {
        var t = 1_700_000_000.0
        let store = makeStore(defaults: makeDefaults("stale"),
                              status: StubStatusService(response: StatusResponse(ok: true, realm: "R", playersOnline: 1, names: [])),
                              now: { Date(timeIntervalSince1970: t) })
        await store.refreshStatus()                 // lastSuccess = T0
        #expect(store.isStale == false)
        t += AppConfig.stalenessWindow              // exactly the window → NOT stale yet (strict `>`)
        #expect(store.isStale == false)
        t += 1                                      // just past → stale (on-open retry not suppressed)
        #expect(store.isStale == true)

        t = 1_699_999_999                           // wall clock moved behind the successful sample
        #expect(store.isStale == true)
    }

    @Test func priceAndCandleFeedsBecomeCachedAtTheirOwnFreshnessBoundaries() async {
        var t = 1_700_000_000.0
        let crypto = MutableCryptoService()
        crypto.quote = CryptoQuote(price: "1.0", change24h: 2)
        let candle = MutableCandleService()
        candle.candles = [Candle(date: Date(timeIntervalSince1970: t - 300),
                                  open: 1, high: 2, low: 0.5, close: 1.5)]
        let store = makeStore(defaults: makeDefaults("feedFreshness"), crypto: crypto,
                              candle: candle, now: { Date(timeIntervalSince1970: t) })
        await store.refreshCrypto()
        await store.refreshCandles()
        #expect(store.priceFeedState == .live)
        #expect(store.candleFeedState == .live)

        t += store.cryptoPollSeconds * (1 + AppConfig.Poll.timerToleranceFraction)
            + AppConfig.API.requestTimeout
        #expect(store.priceFeedState == .cached)
        #expect(store.candleFeedState == .live)

        t = 1_700_000_000 + AppConfig.Crypto.visibleCandleRefreshSeconds
        #expect(store.candleFeedState == .cached)
    }

    @Test func visibleRefreshChecksEachFeedIndependently() async {
        var t = 1_700_000_000.0
        let status = MutableStatusService()
        status.response = StatusResponse(ok: true, realm: "R", playersOnline: 4)
        let crypto = MutableCryptoService()
        crypto.quote = CryptoQuote(price: "1.0", change24h: 2)
        let candle = SpyCandleService()
        candle.candles = [Candle(date: Date(timeIntervalSince1970: t - 300),
                                  open: 1, high: 2, low: 0.5, close: 1.5)]
        let store = makeStore(defaults: makeDefaults("independentVisibleRefresh"),
                              status: status, crypto: crypto, candle: candle,
                              now: { Date(timeIntervalSince1970: t) })
        await store.refresh()
        store.isPopoverVisible = true
        #expect(status.fetchCount == 1)
        #expect(crypto.fetchCount == 1)
        #expect(candle.fetchCount == 1)

        store.priceErrorMessage = "retry"
        await store.refreshVisibleContent()
        #expect(status.fetchCount == 1)
        #expect(crypto.fetchCount == 2)
        #expect(candle.fetchCount == 1)

        t += AppConfig.stalenessWindow + 1
        await store.refreshVisibleContent()
        #expect(status.fetchCount == 2)
        #expect(crypto.fetchCount == 2)
        #expect(candle.fetchCount == 1)

        store.lastSuccess = Date(timeIntervalSince1970: t)
        store.priceLastSuccess = Date(timeIntervalSince1970: t)
        store.candleLastAttempt = Date(timeIntervalSince1970:
            t - AppConfig.Crypto.visibleCandleRefreshSeconds)
        await store.refreshVisibleContent()
        #expect(status.fetchCount == 2)
        #expect(crypto.fetchCount == 2)
        #expect(candle.fetchCount == 2)
    }

    // MARK: accessibility label (the spoken menu-bar equivalent)

    @Test func menuBarAccessibilityLabelUsesStatusWordsAndCrypto() {
        #expect(AppText.menuBarStatus(online: true, syncing: false, count: 5) == "Online, 5 players")
        #expect(AppText.menuBarStatus(online: false, syncing: true, count: 0) == "Syncing")
        #expect(AppText.menuBarStatus(online: false, syncing: false, count: 0) == "Offline")

        let store = makeStore(defaults: makeDefaults("mbA11y"))
        store.response = StatusResponse(ok: true, realm: "R", playersOnline: 5, names: [])
        store.phase = .ok
        store.realmAvailability = .healthy
        #expect(store.menuBarAccessibilityLabel == "Online, 5 players")
        store.cryptoPrice = "0.0005594"
        store.cryptoChange24h = 47.59
        store.priceLastSuccess = store.currentDate
        store.menuBarDisplayMode = .full
        #expect(store.menuBarAccessibilityLabel == "World of ClaudeCraft. Online, 5 players. WOC spot price 0.0005594 dollars, up 47.6 percent over 24 hours.")
    }

    @Test func headerMarketPlaceholdersHaveSemanticAccessibilityCopy() {
        #expect(AppText.marketQuoteLoadingAccessibility == "$WOC market quote loading.")
        #expect(AppText.marketQuoteUnavailableAccessibility == "$WOC market quote unavailable.")
    }

    // MARK: notification authorization

    @Test func notificationPermissionIsReadSilentlyAndRequestedOnlyExplicitly() async {
        let authorizer = FakeNotificationAuthorizer(status: .notDetermined)
        let store = makeStore(defaults: makeDefaults("notificationPermission"),
                              authorizer: authorizer)
        await store.refreshNotificationAuthorizationStatus()
        #expect(store.notificationAuthorizationState == .notDetermined)
        #expect(authorizer.statusCount == 1)
        #expect(authorizer.requestCount == 0)

        authorizer.status = .authorized
        let result = await store.requestNotificationAuthorization()
        #expect(result == .authorized)
        #expect(store.notificationsAuthorized)
        #expect(authorizer.requestCount == 1)
    }

    @Test func deniedNotificationPermissionIsExposedAndSuppressesPosts() async {
        let service = MutableStatusService()
        let notifier = SpyNotifier()
        let authorizer = FakeNotificationAuthorizer(status: .denied)
        let store = makeStore(defaults: makeDefaults("notificationsDenied", ["allTimePeak": 100]),
                              status: service, notifier: notifier, authorizer: authorizer)
        await store.refreshNotificationAuthorizationStatus()
        #expect(store.notificationsBlocked)

        service.response = StatusResponse(ok: true, realm: "R", playersOnline: 2)
        await store.refreshStatus()
        service.response = StatusResponse(ok: false, realm: "R", playersOnline: 0)
        await store.refreshStatus()
        await store.refreshStatus()
        #expect(notifier.posts.isEmpty)
    }

    @Test func testNotificationUsesInjectedDeliveryOnlyWhenAuthorized() async {
        let notifier = SpyNotifier()
        let authorizer = FakeNotificationAuthorizer(status: .denied)
        let store = makeStore(defaults: makeDefaults("notificationTest"),
                              notifier: notifier, authorizer: authorizer)
        await store.refreshNotificationAuthorizationStatus()
        #expect(!store.postTestNotification(title: "Test", body: "Denied"))
        #expect(notifier.posts.isEmpty)

        authorizer.status = .authorized
        await store.refreshNotificationAuthorizationStatus()
        #expect(store.postTestNotification(title: "Test", body: "Delivered"))
        #expect(notifier.posts.count == 1)
        #expect(notifier.posts[0].title == "Test")
        #expect(notifier.posts[0].body == "Delivered")
        #expect(notifier.posts[0].id.hasPrefix("notification_test-"))
    }

    // MARK: first-run welcome

    @Test func welcomeIsVisibleWhenThePreferenceHasNeverBeenWritten() {
        let defaults = makeDefaults("welcomeDefault")
        let store = makeStore(defaults: defaults)

        #expect(DefaultsRegistry.table[DefaultsKey.welcomeDismissed.rawValue] as? Bool == false)
        #expect(store.welcomeDismissed == false)
    }

    @Test func dismissingWelcomePersistsWithoutRequestingNotificationPermission() {
        let defaults = makeDefaults("welcomeDismissal")
        let authorizer = FakeNotificationAuthorizer(status: .notDetermined)
        let store = makeStore(defaults: defaults, authorizer: authorizer)

        store.dismissWelcome()

        #expect(store.welcomeDismissed)
        #expect(defaults.bool(for: .welcomeDismissed))
        #expect(authorizer.requestCount == 0)

        let relaunchedStore = makeStore(defaults: defaults, authorizer: authorizer)
        #expect(relaunchedStore.welcomeDismissed)
        #expect(authorizer.requestCount == 0)
    }

    // MARK: chart selection plumbing

    @Test func seriesDelegatesToAnalyticsForTheSelectedRangeAndInterval() async {
        let clock = Date(timeIntervalSince1970: 1_700_000_000)
        let persistence = CountingPersistence()
        persistence.toLoad = [
            Sample(date: clock, count: 10),
            Sample(date: clock.addingTimeInterval(-60), count: 20),
            Sample(date: clock.addingTimeInterval(-7200), count: 99),   // outside a 1h range
        ]
        let store = makeStore(defaults: makeDefaults("series"), persistence: persistence, now: { clock })
        await store.flushHistoryAndWait()
        store.range = .oneHour
        let expected = HistoryAnalytics(samples: persistence.toLoad, now: { clock }).series(range: .oneHour, interval: .oneMin)
        #expect(store.series(range: .oneHour, interval: .oneMin).map(\.count) == expected.map(\.count))
        #expect(store.series(range: .oneHour, interval: .oneMin).map(\.date) == expected.map(\.date))
    }

    @Test func rangePersistsAndLegacyIntervalKeyRemainsNormalized() {
        let d = makeDefaults("chartPersist", ["chartInterval": -1])
        let store = makeStore(defaults: d)
        store.range = .week
        #expect(d.integer(for: .chartInterval) == ChartInterval.fiveMin.rawValue)
        #expect(d.integer(for: .chartRange) == ChartRange.week.rawValue)
    }
}
