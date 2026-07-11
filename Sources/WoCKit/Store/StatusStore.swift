import Foundation
import Observation

@MainActor
@Observable
final class StatusStore {
    static let shared = StatusStore()

    var response: StatusResponse?
    var phase: Phase = .loading
    var realmAvailability: RealmAvailability = .loading
    var errorMessage: String?
    /// Last *successful* fetch — drives the footer timestamp and `isStale`. (A failure updates
    /// `lastAttempt` only, so the footer no longer reads "updated just now" while OFFLINE and the
    /// on-open retry isn't suppressed by a failed attempt.)
    var lastSuccess: Date?
    /// Last fetch attempt, success or failure.
    var lastAttempt: Date?
    var isRefreshing = false
    var history: [Sample] = []
    /// Real OHLC candles for the $WOC chart, fetched ready-made from GeckoTerminal (oldest-first).
    var candles: [Candle] = []
    /// Interval which actually produced `candles`; never infer it from the current picker value.
    var loadedCandleInterval: CandleInterval?

    var cryptoPrice: String?
    var cryptoChange24h: Double?
    var marketQuote: CryptoQuote?
    var priceLastSuccess: Date?
    var priceLastAttempt: Date?
    var priceErrorMessage: String?
    var isPriceRefreshing = false
    var candleLastSuccess: Date?
    var candleLastAttempt: Date?
    var candleErrorMessage: String?
    var isCandlesRefreshing = false
    var isPopoverVisible = false
    var consecutiveStatusFailures = 0
    var historyPersistenceError: String?
    var notificationAuthorizationState: NotificationAuthorizationState = .unknown

    var range: ChartRange {
        didSet { defaults.set(range.rawValue, for: .chartRange) }
    }
    /// Candle width for the $WOC chart — independent of the player chart's `interval`/`range`.
    /// Changing it re-fetches at the new width. (Set in `init` BEFORE observers exist, so this
    /// `didSet` never fires during initialization — guardrail 5.)
    var cryptoInterval: CandleInterval {
        didSet {
            defaults.set(cryptoInterval.rawValue, for: .cryptoChartInterval)
            Task { await refreshCandles() }
        }
    }

    // Settings
    var alertsEnabled: Bool {
        didSet { defaults.set(alertsEnabled, for: .alertsEnabled) }
    }
    var peakAlertsEnabled: Bool {
        didSet { defaults.set(peakAlertsEnabled, for: .peakAlertsEnabled) }
    }
    var cryptoAlertsEnabled: Bool {
        didSet {
            defaults.set(cryptoAlertsEnabled, for: .cryptoAlertsEnabled)
            // The current rolling-window policy tracks disabled observations itself. Reset only
            // the frozen v1 baseline so a later downgrade cannot replay a move from the period in
            // which alerts were disabled; current alerts never read this compatibility value.
            if cryptoAlertsEnabled && !oldValue {
                lastAlertedPrice = 0
                lastAlertedPriceDate = nil
            }
        }
    }
    var tokenChangeGainAlertsEnabled: Bool {
        didSet { defaults.set(tokenChangeGainAlertsEnabled, for: .tokenChangeGainAlertsEnabled) }
    }
    var tokenChangeLossAlertsEnabled: Bool {
        didSet { defaults.set(tokenChangeLossAlertsEnabled, for: .tokenChangeLossAlertsEnabled) }
    }
    /// Rolling DexScreener window used by Alerts 2.0 gain/loss rules.
    var cryptoAlertWindow: TokenChangeAlertWindow {
        didSet { defaults.set(cryptoAlertWindow.rawValue, for: .cryptoAlertWindow) }
    }
    var populationThresholdAlertsEnabled: Bool {
        didSet { defaults.set(populationThresholdAlertsEnabled, for: .populationThresholdAlertsEnabled) }
    }
    var populationAlertThreshold: Int {
        didSet {
            let normalized = AppConfig.AdvancedAlert.normalizePopulation(populationAlertThreshold)
            if normalized != populationAlertThreshold { populationAlertThreshold = normalized; return }
            defaults.set(populationAlertThreshold, for: .populationAlertThreshold)
        }
    }
    var tokenPriceAboveAlertsEnabled: Bool {
        didSet { defaults.set(tokenPriceAboveAlertsEnabled, for: .tokenPriceAboveAlertsEnabled) }
    }
    var tokenPriceAboveTarget: Double {
        didSet {
            let normalized = AppConfig.AdvancedAlert.normalizePriceTarget(
                tokenPriceAboveTarget, fallback: AppConfig.AdvancedAlert.defaultPriceAboveTarget)
            if normalized != tokenPriceAboveTarget { tokenPriceAboveTarget = normalized; return }
            defaults.set(tokenPriceAboveTarget, for: .tokenPriceAboveTarget)
        }
    }
    var tokenPriceBelowAlertsEnabled: Bool {
        didSet { defaults.set(tokenPriceBelowAlertsEnabled, for: .tokenPriceBelowAlertsEnabled) }
    }
    var tokenPriceBelowTarget: Double {
        didSet {
            let normalized = AppConfig.AdvancedAlert.normalizePriceTarget(
                tokenPriceBelowTarget, fallback: AppConfig.AdvancedAlert.defaultPriceBelowTarget)
            if normalized != tokenPriceBelowTarget { tokenPriceBelowTarget = normalized; return }
            defaults.set(tokenPriceBelowTarget, for: .tokenPriceBelowTarget)
        }
    }
    var releaseAlertsEnabled: Bool {
        didSet {
            defaults.set(releaseAlertsEnabled, for: .releaseAlertsEnabled)
            guard releaseAlertsEnabled != oldValue else { return }
            // Re-enabling starts from a fresh snapshot instead of replaying releases that may have
            // shipped while monitoring was intentionally off.
            if releaseAlertsEnabled {
                advancedAlertState.releases.removeValue(forKey: AdvancedAlertRuleCatalog.release)
            }
            restartReleaseAlertTimer()
            if started, releaseAlertsEnabled {
                Task { await refreshReleaseAlertsTick() }
            }
        }
    }
    var advancedAlertCooldown: TimeInterval {
        didSet {
            let normalized = AppConfig.AdvancedAlert.normalizeCooldown(advancedAlertCooldown)
            if normalized != advancedAlertCooldown { advancedAlertCooldown = normalized; return }
            defaults.set(advancedAlertCooldown, for: .advancedAlertCooldown)
        }
    }
    var advancedAlertQuietHoursEnabled: Bool {
        didSet { defaults.set(advancedAlertQuietHoursEnabled, for: .advancedAlertQuietHoursEnabled) }
    }
    var advancedAlertQuietStartMinute: Int {
        didSet {
            let normalized = AdvancedAlertNormalization.minuteOfDay(advancedAlertQuietStartMinute)
            if normalized != advancedAlertQuietStartMinute { advancedAlertQuietStartMinute = normalized; return }
            defaults.set(advancedAlertQuietStartMinute, for: .advancedAlertQuietStartMinute)
        }
    }
    var advancedAlertQuietEndMinute: Int {
        didSet {
            let normalized = AdvancedAlertNormalization.minuteOfDay(advancedAlertQuietEndMinute)
            if normalized != advancedAlertQuietEndMinute { advancedAlertQuietEndMinute = normalized; return }
            defaults.set(advancedAlertQuietEndMinute, for: .advancedAlertQuietEndMinute)
        }
    }
    var launchAtLogin: Bool {
        didSet {
            guard !isReconciling else { return }   // re-entrancy guard: skip the reconcile write-back
            applyLaunchAtLogin(launchAtLogin)
            reconcileLaunchAtLogin()
        }
    }
    var menuBarDisplayMode: MenuBarDisplayMode {
        didSet { defaults.set(menuBarDisplayMode.rawValue, for: .menuBarDisplayMode) }
    }
    /// The first-run welcome is deliberately a simple persisted preference rather than app-flow
    /// state: dismissing the card never prompts for notification permission or starts any work.
    var welcomeDismissed: Bool {
        didSet { defaults.set(welcomeDismissed, for: .welcomeDismissed) }
    }

    // Records (persisted; history only keeps 7 days, so the all-time peak lives here)
    var allTimePeak: Int = 0
    var allTimePeakDate: Date?
    /// Legacy values retained only so existing installations can migrate without abruptly
    /// deleting defaults written by version 1. Alerts 2.0 uses rolling market windows instead.
    var lastAlertedPrice: Double = 0.0 {
        didSet { defaults.set(lastAlertedPrice, for: .lastAlertedPrice) }
    }
    var lastAlertedPriceDate: Date? {
        didSet {
            if let lastAlertedPriceDate { defaults.set(lastAlertedPriceDate, for: .lastAlertedPriceDate) }
            else { defaults.remove(.lastAlertedPriceDate) }
        }
    }

    @ObservationIgnored private var statusAlertState = StatusAlertState()
    @ObservationIgnored private var advancedAlertState = AdvancedAlertPolicyState()
    @ObservationIgnored private var advancedAlertMutes: [AdvancedAlertRuleID: Date] = [:]
    @ObservationIgnored private var baselineAlertLastDelivered: [AdvancedAlertRuleID: Date] = [:]
    @ObservationIgnored private var statusTimer: Timer?
    @ObservationIgnored private var cryptoTimer: Timer?
    @ObservationIgnored private var releaseAlertTimer: Timer?
    @ObservationIgnored private var statusInFlight = false
    @ObservationIgnored private var cryptoInFlight = false
    @ObservationIgnored private var releaseAlertInFlight = false
    @ObservationIgnored private var started = false
    @ObservationIgnored private var isReconciling = false   // launch-at-login write-back guard
    @ObservationIgnored private var pendingWrites = 0       // samples added since the last completed save
    @ObservationIgnored private var lastFlush = Date.distantPast
    @ObservationIgnored private var candlesInFlight = false
    @ObservationIgnored private var historyLoadTask: Task<Void, Never>?
    @ObservationIgnored private var historySaveTask: Task<Void, Never>?
    @ObservationIgnored private var historyLoadFinished = false
    @ObservationIgnored private var historyNeedsSave = false
    @ObservationIgnored private var historyRepairPending = false
    @ObservationIgnored private var historyFlushRequested = false
    @ObservationIgnored private var historySavingGeneration: UInt64?
    @ObservationIgnored private var pendingPeakObservations: [(count: Int, date: Date, realm: String)] = []
    /// Monotonically identifies the in-memory snapshot. A save may only clear dirty state when no
    /// sample or repair has changed this generation while disk I/O was in flight.
    @ObservationIgnored private var historyGeneration: UInt64 = 0

    // Injected collaborators (default-parameter injection; live defaults below).
    private let statusService: any StatusFetching
    private let cryptoService: any CryptoFetching
    private let candleService: any CandleFetching
    private let releaseService: any ReleaseFetching
    private let historyPersistence: HistoryPersistenceWorker
    private let notifier: any Notifier
    private let notificationAuthorizer: any NotificationAuthorizing
    private let launch: any LaunchAtLoginManaging
    private let now: () -> Date
    private let alertTimeZone: TimeZone
    private let defaults: UserDefaults

    /// How often the player count is polled. Clamped to a sane floor so a corrupted/0/negative
    /// persisted value can't produce a tight-loop `Timer`.
    var pollSeconds: TimeInterval {
        didSet {
            let normalized = Self.normalizePlayerPoll(pollSeconds)
            if normalized != pollSeconds { pollSeconds = normalized; return }
            defaults.set(pollSeconds, for: .pollSeconds)
            restartStatusTimer()
        }
    }

    /// How often the $WOC crypto price is polled — independent of the player poll.
    var cryptoPollSeconds: TimeInterval {
        didSet {
            let normalized = Self.normalizeCryptoPoll(cryptoPollSeconds)
            if normalized != cryptoPollSeconds { cryptoPollSeconds = normalized; return }
            defaults.set(cryptoPollSeconds, for: .cryptoPollSeconds)
            restartCryptoTimer()
        }
    }

    private static func normalizePlayerPoll(_ seconds: TimeInterval) -> TimeInterval {
        PollInterval.normalize(seconds, options: PollInterval.playerOptions, default: .oneMinute)
    }

    private static func normalizeCryptoPoll(_ seconds: TimeInterval) -> TimeInterval {
        PollInterval.normalize(seconds, options: PollInterval.cryptoOptions, default: .oneMinute)
    }

    var cryptoAlertThreshold: Double {
        didSet {
            let normalized = Self.normalizeCryptoThreshold(cryptoAlertThreshold)
            if normalized != cryptoAlertThreshold { cryptoAlertThreshold = normalized; return }
            defaults.set(cryptoAlertThreshold, for: .cryptoAlertThreshold)
        }
    }

    private static func normalizeCryptoThreshold(_ value: Double) -> Double {
        guard value.isFinite else { return AppConfig.CryptoAlert.defaultThresholdPercent }
        let clamped = min(max(value, AppConfig.CryptoAlert.sliderRange.lowerBound),
                          AppConfig.CryptoAlert.sliderRange.upperBound)
        let step = AppConfig.CryptoAlert.sliderStep
        return (clamped / step).rounded() * step
    }

    init(defaults: UserDefaults = .standard,
         statusService: any StatusFetching = StatusService(),
         cryptoService: any CryptoFetching = CryptoService(),
         candleService: any CandleFetching = GeckoTerminalService(),
         releaseService: (any ReleaseFetching)? = nil,
         persistence: any HistoryPersisting = FileHistoryStore(),
         notifier: any Notifier = UserNotificationNotifier(),
         notificationAuthorizer: any NotificationAuthorizing = SystemNotificationAuthorizer(),
         launch: any LaunchAtLoginManaging = SMAppLaunchManager(),
         now: @escaping () -> Date = Date.init,
         alertTimeZone: TimeZone = .autoupdatingCurrent) {
        self.statusService = statusService
        self.cryptoService = cryptoService
        self.candleService = candleService
        if let releaseService {
            self.releaseService = releaseService
        } else {
            #if PREVIEW
            self.releaseService = PreviewReleaseAlertService()
            #else
            self.releaseService = CommunityService()
            #endif
        }
        self.historyPersistence = HistoryPersistenceWorker(persistence: persistence)
        self.notifier = notifier
        self.notificationAuthorizer = notificationAuthorizer
        self.launch = launch
        self.now = now
        self.alertTimeZone = alertTimeZone
        self.defaults = defaults
        let d = defaults
        d.register(DefaultsRegistry.table)
        // Automatic chart resolution replaced the old interval picker. Keep normalizing the frozen
        // key so downgrades remain compatible, without carrying dead observable state at runtime.
        let legacyChartInterval = ChartInterval(rawValue: d.integer(for: .chartInterval)) ?? .fiveMin
        let range = ChartRange(rawValue: d.integer(for: .chartRange)) ?? .sixHours
        let cryptoInterval = CandleInterval(rawValue: d.integer(for: .cryptoChartInterval)) ?? .fiveMin
        self.range = range
        self.cryptoInterval = cryptoInterval
        self.alertsEnabled = d.bool(for: .alertsEnabled)
        self.peakAlertsEnabled = d.bool(for: .peakAlertsEnabled)
        self.cryptoAlertsEnabled = d.bool(for: .cryptoAlertsEnabled)
        self.tokenChangeGainAlertsEnabled = d.bool(for: .tokenChangeGainAlertsEnabled)
        self.tokenChangeLossAlertsEnabled = d.bool(for: .tokenChangeLossAlertsEnabled)
        self.cryptoAlertWindow = TokenChangeAlertWindow(
            rawValue: d.string(for: .cryptoAlertWindow) ?? "") ?? .oneHour
        self.populationThresholdAlertsEnabled = d.bool(for: .populationThresholdAlertsEnabled)
        self.populationAlertThreshold = AppConfig.AdvancedAlert.normalizePopulation(
            d.integer(for: .populationAlertThreshold))
        self.tokenPriceAboveAlertsEnabled = d.bool(for: .tokenPriceAboveAlertsEnabled)
        self.tokenPriceAboveTarget = AppConfig.AdvancedAlert.normalizePriceTarget(
            d.double(for: .tokenPriceAboveTarget),
            fallback: AppConfig.AdvancedAlert.defaultPriceAboveTarget)
        self.tokenPriceBelowAlertsEnabled = d.bool(for: .tokenPriceBelowAlertsEnabled)
        self.tokenPriceBelowTarget = AppConfig.AdvancedAlert.normalizePriceTarget(
            d.double(for: .tokenPriceBelowTarget),
            fallback: AppConfig.AdvancedAlert.defaultPriceBelowTarget)
        self.releaseAlertsEnabled = d.bool(for: .releaseAlertsEnabled)
        self.advancedAlertCooldown = AppConfig.AdvancedAlert.normalizeCooldown(
            d.double(for: .advancedAlertCooldown))
        self.advancedAlertQuietHoursEnabled = d.bool(for: .advancedAlertQuietHoursEnabled)
        self.advancedAlertQuietStartMinute = AdvancedAlertNormalization.minuteOfDay(
            d.integer(for: .advancedAlertQuietStartMinute))
        self.advancedAlertQuietEndMinute = AdvancedAlertNormalization.minuteOfDay(
            d.integer(for: .advancedAlertQuietEndMinute))
        self.menuBarDisplayMode = MenuBarDisplayMode(
            rawValue: d.string(for: .menuBarDisplayMode) ?? "") ?? .playersAndChange
        self.welcomeDismissed = d.bool(for: .welcomeDismissed)
        let savedPeak = max(0, d.integer(for: .allTimePeak))
        self.allTimePeak = savedPeak
        self.allTimePeakDate = savedPeak > 0 ? Self.validDate(d.date(for: .allTimePeakDate)) : nil

        let savedBaseline = d.double(for: .lastAlertedPrice)
        let savedBaselineDate = Self.validDate(d.date(for: .lastAlertedPriceDate))
        let baselineIsFresh = savedBaseline.isFinite && savedBaseline > 0
            && savedBaselineDate.map {
                let age = now().timeIntervalSince($0)
                return age >= 0 && age <= AppConfig.CryptoAlert.maximumBaselineAge
            } == true
        self.lastAlertedPrice = baselineIsFresh ? savedBaseline : 0
        self.lastAlertedPriceDate = baselineIsFresh ? savedBaselineDate : nil

        self.pollSeconds = Self.normalizePlayerPoll(d.double(for: .pollSeconds))
        self.cryptoPollSeconds = Self.normalizeCryptoPoll(d.double(for: .cryptoPollSeconds))
        self.cryptoAlertThreshold = Self.normalizeCryptoThreshold(d.double(for: .cryptoAlertThreshold))
        self.launchAtLogin = launch.isEnabled

        let clock = now()
        self.advancedAlertMutes = Self.loadAdvancedAlertMutes(from: d, now: clock)

        // Normalize every numeric/enum value back to disk. Property observers do not run during
        // initialization, so without this write-back a corrupted value would return next launch.
        d.set(legacyChartInterval.rawValue, for: .chartInterval)
        d.set(range.rawValue, for: .chartRange)
        d.set(cryptoInterval.rawValue, for: .cryptoChartInterval)
        d.set(allTimePeak, for: .allTimePeak)
        if let allTimePeakDate { d.set(allTimePeakDate, for: .allTimePeakDate) }
        else { d.remove(.allTimePeakDate) }
        d.set(pollSeconds, for: .pollSeconds)
        d.set(cryptoPollSeconds, for: .cryptoPollSeconds)
        d.set(cryptoAlertThreshold, for: .cryptoAlertThreshold)
        d.set(tokenChangeGainAlertsEnabled, for: .tokenChangeGainAlertsEnabled)
        d.set(tokenChangeLossAlertsEnabled, for: .tokenChangeLossAlertsEnabled)
        d.set(cryptoAlertWindow.rawValue, for: .cryptoAlertWindow)
        d.set(populationThresholdAlertsEnabled, for: .populationThresholdAlertsEnabled)
        d.set(populationAlertThreshold, for: .populationAlertThreshold)
        d.set(tokenPriceAboveAlertsEnabled, for: .tokenPriceAboveAlertsEnabled)
        d.set(tokenPriceAboveTarget, for: .tokenPriceAboveTarget)
        d.set(tokenPriceBelowAlertsEnabled, for: .tokenPriceBelowAlertsEnabled)
        d.set(tokenPriceBelowTarget, for: .tokenPriceBelowTarget)
        d.set(releaseAlertsEnabled, for: .releaseAlertsEnabled)
        d.set(advancedAlertCooldown, for: .advancedAlertCooldown)
        d.set(advancedAlertQuietHoursEnabled, for: .advancedAlertQuietHoursEnabled)
        d.set(advancedAlertQuietStartMinute, for: .advancedAlertQuietStartMinute)
        d.set(advancedAlertQuietEndMinute, for: .advancedAlertQuietEndMinute)
        persistAdvancedAlertMutes()
        d.set(menuBarDisplayMode.rawValue, for: .menuBarDisplayMode)
        d.set(lastAlertedPrice, for: .lastAlertedPrice)
        if let lastAlertedPriceDate { d.set(lastAlertedPriceDate, for: .lastAlertedPriceDate) }
        else { d.remove(.lastAlertedPriceDate) }
        loadHistory()
    }

    func dismissWelcome() {
        welcomeDismissed = true
    }

    private static func validDate(_ date: Date?) -> Date? {
        guard let date, date.timeIntervalSinceReferenceDate.isFinite else { return nil }
        return date
    }

    private static func loadAdvancedAlertMutes(from defaults: UserDefaults, now: Date)
    -> [AdvancedAlertRuleID: Date] {
        guard now.timeIntervalSinceReferenceDate.isFinite,
              let raw = defaults.dictionary(for: .advancedAlertMutes) else { return [:] }
        var result: [AdvancedAlertRuleID: Date] = [:]
        for (key, value) in raw {
            let seconds: Double?
            if let number = value as? NSNumber { seconds = number.doubleValue }
            else if let double = value as? Double { seconds = double }
            else { seconds = nil }
            guard let seconds, seconds.isFinite else { continue }
            let id = AdvancedAlertRuleID(key)
            let until = Date(timeIntervalSince1970: seconds)
            guard AdvancedAlertRuleCatalog.all.contains(id), until > now else { continue }
            result[id] = until
        }
        return result
    }

    private func persistAdvancedAlertMutes() {
        let encoded = Dictionary(uniqueKeysWithValues: advancedAlertMutes.map {
            ($0.key.rawValue, $0.value.timeIntervalSince1970)
        })
        if encoded.isEmpty { defaults.remove(.advancedAlertMutes) }
        else { defaults.set(encoded, for: .advancedAlertMutes) }
    }

    var count: Int { response?.playersOnline ?? 0 }
    var hasStatusResponse: Bool { response != nil }
    var realm: String { response?.realm ?? AppText.realmFallback }
    var isOnline: Bool {
        realmAvailability == .healthy
            || (realmAvailability == .loading && phase == .ok && response?.ok == true)
    }
    var isStale: Bool {
        guard let lastSuccess else { return true }
        let age = now().timeIntervalSince(lastSuccess)
        return age < 0 || age > AppConfig.stalenessWindow
    }
    /// Peak player count seen so far today (from the retained history).
    var todayPeak: Int { HistoryAnalytics(samples: history, now: now).todayPeak(fallback: count) }
    var hasPopulationHistory: Bool { !history.isEmpty }
    var hasLocalRecord: Bool { allTimePeak > 0 || allTimePeakDate != nil || hasPopulationHistory }
    var currentDate: Date { now() }
    var thirtyMinuteChange: Int? {
        let tolerance = max(
            AppConfig.History.shortChangeMinimumTolerance,
            pollSeconds * AppConfig.History.shortChangePollToleranceMultiplier
        )
        return HistoryAnalytics(samples: history, now: now).change(
            over: AppConfig.History.shortChangeWindow,
            currentCount: count,
            baselineTolerance: tolerance
        )
    }

    var realmRhythm: RealmRhythm {
        HistoryAnalytics(samples: history, now: now).realmRhythm(
            range: range, currentCount: count, expectedSampleInterval: pollSeconds)
    }

    /// Safe chart input: cached bars from another selection remain available for provenance but
    /// are never rendered under the newly selected interval label.
    var chartCandles: [Candle] {
        loadedCandleInterval == cryptoInterval ? candles : []
    }

    var hasCachedCandlesForDifferentInterval: Bool {
        !candles.isEmpty && loadedCandleInterval != nil && loadedCandleInterval != cryptoInterval
    }

    var priceFeedState: DataFeedState {
        marketFeedSnapshot.priceState
    }

    var candleFeedState: DataFeedState {
        marketFeedSnapshot.candleState
    }

    /// Oldest successful timestamp among feeds currently presented as cached. This keeps a fresh
    /// spot quote from lending its timestamp to stale candles (and vice versa).
    var marketCachedAt: Date? {
        marketFeedSnapshot.cachedAt
    }

    /// Conservative market-page timestamp: when both feeds have succeeded, report the older one.
    var marketLastSuccess: Date? {
        marketFeedSnapshot.lastSuccess
    }

    private var marketFeedSnapshot: MarketFeedPolicy.Snapshot {
        MarketFeedPolicy(now: now(), pricePollSeconds: cryptoPollSeconds).evaluate(
            price: .init(
                lastSuccess: priceLastSuccess,
                errorMessage: priceErrorMessage,
                isRefreshing: isPriceRefreshing
            ),
            candles: .init(
                lastSuccess: candleLastSuccess,
                lastAttempt: candleLastAttempt,
                errorMessage: candleErrorMessage,
                isRefreshing: isCandlesRefreshing,
                hasCandles: !candles.isEmpty,
                selectedInterval: cryptoInterval,
                loadedInterval: loadedCandleInterval
            )
        )
    }

    var notificationsAuthorized: Bool { notificationAuthorizationState.canDeliver }
    var notificationsBlocked: Bool {
        notificationAuthorizationState == .denied
            && (alertsEnabled || peakAlertsEnabled || cryptoAlertsEnabled
                || populationThresholdAlertsEnabled || tokenPriceAboveAlertsEnabled
                || tokenPriceBelowAlertsEnabled || releaseAlertsEnabled)
    }

    var menuBarLabel: String {
        menuBarPresentation.label
    }

    /// Spoken equivalent of `menuBarLabel` for VoiceOver — semantic status words instead of the
    /// colored emoji dots, with the crypto price/change preserved.
    var menuBarAccessibilityLabel: String {
        menuBarPresentation.accessibilityLabel
    }

    private var menuBarPresentation: MenuBarPresentation {
        MenuBarFormatter.presentation(
            mode: menuBarDisplayMode,
            count: response?.playersOnline,
            availability: realmAvailability,
            phase: phase,
            isOnline: isOnline,
            price: cryptoPrice,
            change24h: cryptoChange24h,
            priceState: priceFeedState
        )
    }

    func start() {
        guard !started else { return }
        started = true
        notifier.configure()
        // Read permission state silently; the actual system prompt is only shown after an explicit
        // user action through `requestNotificationAuthorization()`.
        Task {
            async let permission: Void = refreshNotificationAuthorizationStatus()
            async let feeds: Void = refreshBackgroundFeeds()
            _ = await (permission, feeds)
        }
        if releaseAlertsEnabled {
            Task { await refreshReleaseAlertsTick() }
        }
        restartStatusTimer()
        restartCryptoTimer()
        restartReleaseAlertTimer()
    }

    func refreshNotificationAuthorizationStatus() async {
        notificationAuthorizationState = await notificationAuthorizer.currentStatus()
    }

    @discardableResult
    func requestNotificationAuthorization() async -> NotificationAuthorizationState {
        let status = await notificationAuthorizer.requestAuthorization()
        notificationAuthorizationState = status
        return status
    }

    /// Sends a user-initiated test through the same injected delivery seam as real alerts. Returns
    /// `false` without posting when system permission is not currently authorized.
    @discardableResult
    func postTestNotification(title: String, body: String) -> Bool {
        guard notificationsAuthorized else { return false }
        notifier.post(title: title, body: body,
                      id: "notification_test-\(now().timeIntervalSince1970)")
        return true
    }

    private func restartStatusTimer() {
        statusTimer?.invalidate()
        statusTimer = nil
        guard started else { return }
        let t = Timer(timeInterval: pollSeconds, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.refreshStatus() }
        }
        t.tolerance = pollSeconds * AppConfig.Poll.timerToleranceFraction   // let macOS coalesce wakeups
        RunLoop.main.add(t, forMode: .common)
        statusTimer = t
    }

    private func restartCryptoTimer() {
        cryptoTimer?.invalidate()
        cryptoTimer = nil
        guard started else { return }
        let t = Timer(timeInterval: cryptoPollSeconds, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.refreshCryptoTick() }
        }
        t.tolerance = cryptoPollSeconds * AppConfig.Poll.timerToleranceFraction
        RunLoop.main.add(t, forMode: .common)
        cryptoTimer = t
    }

    private func restartReleaseAlertTimer() {
        releaseAlertTimer?.invalidate()
        releaseAlertTimer = nil
        guard started, releaseAlertsEnabled else { return }
        let t = Timer(timeInterval: AppConfig.ReleaseAlert.pollSeconds, repeats: true) {
            [weak self] _ in
            Task { @MainActor in await self?.refreshReleaseAlertsTick() }
        }
        t.tolerance = AppConfig.ReleaseAlert.timerTolerance
        RunLoop.main.add(t, forMode: .common)
        releaseAlertTimer = t
    }

    /// Exposed internally so timer lifecycle can be verified without waiting for wall-clock time.
    var isReleaseAlertMonitoringActive: Bool {
        releaseAlertTimer?.isValid == true
    }

    /// One best-effort release check. Failures deliberately leave the alert policy untouched, so
    /// a failed request cannot masquerade as an empty feed or consume the next real release.
    func refreshReleaseAlertsTick() async {
        guard releaseAlertsEnabled, !releaseAlertInFlight else { return }
        releaseAlertInFlight = true
        defer { releaseAlertInFlight = false }
        do {
            let feed = try await releaseService.fetchReleases(limit: AppConfig.ReleaseAlert.fetchLimit)
            guard !Task.isCancelled, releaseAlertsEnabled else { return }
            observeGameReleases(feed.releases, at: now())
        } catch is CancellationError {
            return
        } catch {
            // Release alerts are an optional background enhancement. Status and market feeds must
            // remain unaffected, and the next tolerant timer tick retries naturally.
            return
        }
    }

    /// One background crypto tick. Spot remains live at the selected cadence, while the much
    /// heavier 60-bar candle request runs only when the popover is visible and its slower freshness
    /// window has elapsed.
    func refreshCryptoTick() async {
        let shouldFetchCandles = isPopoverVisible && candlesNeedRefresh
        async let price: Void = refreshCrypto()
        if shouldFetchCandles {
            async let bars: Void = refreshCandles()
            _ = await (price, bars)
        } else {
            await price
        }
    }

    /// Manual refresh (the footer button): pull every feed at once.
    func refresh() async {
        async let s: Void = refreshStatus()
        async let p: Void = refreshCrypto()
        async let c: Void = refreshCandles()
        _ = await (s, p, c)
    }

    /// Lightweight launch/background refresh. Candles intentionally wait for a popover open,
    /// interval change, or explicit manual refresh.
    private func refreshBackgroundFeeds() async {
        async let status: Void = refreshStatus()
        async let price: Void = refreshCrypto()
        _ = await (status, price)
    }

    /// Explicit full refresh for visible UI. Kept separate so popover lifecycle wiring doesn't
    /// accidentally become coupled to the background spot timer implementation.
    func refreshVisibleContent() async {
        async let status: Void = refreshStatusIfNeeded()
        async let price: Void = refreshPriceIfNeeded()
        async let candles: Void = refreshCandlesIfNeeded()
        _ = await (status, price, candles)
    }

    private func refreshStatusIfNeeded() async {
        guard isStale else { return }
        await refreshStatus()
    }

    private func refreshPriceIfNeeded() async {
        guard priceNeedsRefresh else { return }
        await refreshCrypto()
    }

    private func refreshCandlesIfNeeded() async {
        guard isPopoverVisible, candlesNeedRefresh else { return }
        await refreshCandles()
    }

    /// Lifecycle hook for `MenuBarExtra(.window)`. Opening fetches candles when missing/stale;
    /// closing immediately stops future candle ticks without affecting spot/player polling.
    func setPopoverVisible(_ visible: Bool) {
        guard visible != isPopoverVisible else { return }
        isPopoverVisible = visible
        if visible, candlesNeedRefresh {
            Task { await refreshCandles() }
        }
    }

    private var candlesNeedRefresh: Bool {
        marketFeedSnapshot.candlesNeedRefresh
    }

    private var priceNeedsRefresh: Bool {
        marketFeedSnapshot.priceNeedsRefresh
    }

    /// Fetch the player count / realm status. Drives `isRefreshing` (the spinner).
    func refreshStatus() async {
        if statusInFlight { return }
        statusInFlight = true
        isRefreshing = true
        defer { statusInFlight = false; isRefreshing = false }
        do {
            let decoded = try await statusService.fetchStatus()
            // State is set plainly (no `withAnimation`): an animated store mutation makes
            // MenuBarExtra(.window) re-measure and re-present its content in a loop (~40% idle
            // CPU even with the popover shut). Views animate value-driven instead — the header
            // count uses `.animation(.snappy, value:)`/`.contentTransition`. See guardrail 1.
            self.response = decoded
            self.phase = .ok
            self.realmAvailability = decoded.ok ? .healthy : .serverReportedDown
            self.errorMessage = nil
            let stamp = now()
            self.lastSuccess = stamp
            self.lastAttempt = stamp
            record(count: decoded.playersOnline, at: stamp)
            checkPeak(count: decoded.playersOnline, at: stamp, realm: realm)
            evaluateAlerts(observation: decoded.ok
                           ? .healthy
                           : .failure(countsTowardOutage: true), at: stamp)
            evaluateAdvancedAlerts(population: decoded.playersOnline, at: stamp)
        } catch is CancellationError {
            return
        } catch {
            self.phase = .error
            self.errorMessage = friendly(error)
            let stamp = now()
            self.lastAttempt = stamp   // NOT lastSuccess — keep the footer/staleness honest
            let kind = (error as? FetchError)?.statusFailureKind ?? .unknown
            self.realmAvailability = .unreachable(kind)
            evaluateAlerts(observation: .failure(
                countsTowardOutage: kind.countsTowardOutageConfirmation), at: stamp)
        }
    }

    /// Fetch the $WOC price. Best-effort: a failure leaves the last price in place and
    /// never flips the realm into an error state.
    func refreshCrypto() async {
        if cryptoInFlight { return }
        cryptoInFlight = true
        isPriceRefreshing = true
        defer { cryptoInFlight = false; isPriceRefreshing = false }
        do {
            let fetched = try await cryptoService.fetchQuote()
            guard let quote = MarketFeedPolicy.sanitizedQuote(fetched) else {
                throw FetchError.decode
            }
            let stamp = now()
            // Plain assignment (no `withAnimation`) — see the note in refreshStatus; this crypto
            // path is what tipped the popover into a perpetual re-present loop. Guardrail 1.
            self.cryptoPrice = quote.price
            self.cryptoChange24h = quote.change24h
            self.marketQuote = quote
            self.priceLastAttempt = stamp
            self.priceLastSuccess = stamp
            self.priceErrorMessage = nil
            self.evaluateAdvancedAlerts(quote: quote, at: stamp)
        } catch is CancellationError {
            return
        } catch {
            // Retain the last valid quote, but make its cached nature observable.
            self.priceLastAttempt = now()
            self.priceErrorMessage = feedFriendly(error, fallback: "Couldn't update market price")
        }
    }

    /// Fetch real OHLC candles for the chart. Best-effort like `refreshCrypto` (guardrail 7): a
    /// failure leaves the last candles in place and never flips the realm to `.error`. Plain
    /// assignment (no `withAnimation`) so `MenuBarExtra(.window)` doesn't re-present (guardrail 1).
    func refreshCandles() async {
        if candlesInFlight { return }
        candlesInFlight = true
        isCandlesRefreshing = true
        defer { candlesInFlight = false; isCandlesRefreshing = false }
        // Trailing-coalesce to the LATEST selection. The synchronous guard above drops a
        // *same-parameter* overlap (guardrail 4); but if the candle width changes mid-await (the
        // picker's `cryptoInterval` didSet) the chart must not be stranded on the old width until
        // the next tick — loop until the width we fetched matches the current pick.
        var requested: CandleInterval
        repeat {
            requested = cryptoInterval
            do {
                let fetched = try await candleService.fetchCandles(
                    interval: requested, count: AppConfig.Crypto.candleCount)
                let bars = MarketFeedPolicy.normalizedCandles(fetched)
                guard !bars.isEmpty else { throw FeedValidationError.noUsableData }
                let stamp = now()
                self.candleLastAttempt = stamp
                self.candles = bars
                self.loadedCandleInterval = requested
                self.candleLastSuccess = stamp
                self.candleErrorMessage = nil
            } catch is CancellationError {
                return
            } catch {
                // Keep cached bars and their loaded interval. `chartCandles` prevents them from
                // appearing under a different current selection.
                self.candleLastAttempt = now()
                self.candleErrorMessage = feedFriendly(error, fallback: "Couldn't update chart")
            }
        } while requested != cryptoInterval
    }

    private enum FeedValidationError: Error { case noUsableData }

    private func feedFriendly(_ error: Error, fallback: String) -> String {
        guard let fetch = error as? FetchError else { return fallback }
        switch fetch {
        case .responseTooLarge, .decode: return fallback
        case .transport, .http: return fetch.friendlyMessage
        }
    }

    // MARK: Alerts & records

    /// Confirm repeated remote failures before firing a down transition. A healthy `ok` response is
    /// up even at zero players; local-network/schema errors never alter confirmed realm state.
    private func evaluateAlerts(observation: StatusAlertObservation, at date: Date) {
        pruneExpiredAdvancedAlertMutes(at: date)
        let settings = AlertSettings(
            statusEnabled: baselineAlertCanDeliver(
                AdvancedAlertRuleCatalog.realmStatus, preference: alertsEnabled, at: date),
            peakEnabled: false,
            cryptoEnabled: false
        )
        let r = AlertEngine.evaluateStatus(state: statusAlertState,
                                           observation: observation,
                                           requiredFailures: AppConfig.Alert.outageConfirmationPolls,
                                           realm: realm, count: count,
                                           settings: settings)
        statusAlertState = r.state
        consecutiveStatusFailures = r.state.consecutiveRemoteFailures
        if let decision = r.decision {
            baselineAlertLastDelivered[AdvancedAlertRuleCatalog.realmStatus] = date
            post(decision, ruleID: AdvancedAlertRuleCatalog.realmStatus, firedAt: date)
        }
    }

    /// Track the all-time peak; alert when a new record is set (but not on the first sample ever).
    private func checkPeak(count: Int, at date: Date, realm observedRealm: String) {
        // The retained history may contain a higher baseline than UserDefaults (for example after
        // defaults restoration). Defer peak evaluation until that baseline is known so a status
        // response racing startup I/O can never emit a false record notification.
        guard historyLoadFinished else {
            pendingPeakObservations.append((count, date, observedRealm))
            return
        }
        pruneExpiredAdvancedAlertMutes(at: date)
        let settings = AlertSettings(
            statusEnabled: false,
            peakEnabled: baselineAlertCanDeliver(
                AdvancedAlertRuleCatalog.localRecord, preference: peakAlertsEnabled, at: date),
            cryptoEnabled: false
        )
        let r = AlertEngine.evaluatePeak(count: count, at: date, currentPeak: allTimePeak,
                                         currentPeakDate: allTimePeakDate, realm: observedRealm,
                                         settings: settings)
        if r.peak != allTimePeak {                                  // persist only on a new high
            allTimePeak = r.peak
            allTimePeakDate = r.peakDate
            defaults.set(r.peak, for: .allTimePeak)
            if let d = r.peakDate { defaults.set(d, for: .allTimePeakDate) }
        }
        if let decision = r.decision {
            baselineAlertLastDelivered[AdvancedAlertRuleCatalog.localRecord] = date
            post(decision, ruleID: AdvancedAlertRuleCatalog.localRecord, firedAt: date)
        }
    }

    private func baselineAlertCanDeliver(_ id: AdvancedAlertRuleID, preference: Bool,
                                         at date: Date) -> Bool {
        let rule = advancedRuleConfiguration(id, preference: preference)
        return AdvancedAlertDeliveryGate.suppressionReason(
            rule: rule,
            at: date,
            quietHours: configuredQuietHours,
            lastDeliveredAt: baselineAlertLastDelivered[id]
        ) == nil
    }

    /// Successful CommunityStore release observations enter through this narrow seam. The first
    /// feed seeds the current releases silently; only a later unseen identity can notify.
    func observeGameReleases(_ releases: [GameRelease], at date: Date) {
        evaluateAdvancedAlerts(releases: releases, at: date)
    }

    private func evaluateAdvancedAlerts(population: Int? = nil, quote: CryptoQuote? = nil,
                                        releases: [GameRelease]? = nil, at date: Date) {
        let result = AdvancedAlertPolicyEngine.evaluate(
            policies: advancedAlertPolicies(at: date), state: advancedAlertState,
            observation: AdvancedAlertObservation(observedAt: date, population: population,
                                                   quote: quote, releases: releases))
        advancedAlertState = result.state
        for decision in result.decisions { post(decision) }
    }

    private func advancedAlertPolicies(at date: Date) -> AdvancedAlertPolicySet {
        pruneExpiredAdvancedAlertMutes(at: date)

        let populationHysteresis = max(1, populationAlertThreshold / 20)
        let priceAboveHysteresis = tokenPriceAboveTarget * 0.02
        let priceBelowHysteresis = tokenPriceBelowTarget * 0.02
        let rollingHysteresis = min(cryptoAlertThreshold, max(1, cryptoAlertThreshold * 0.2))

        return AdvancedAlertPolicySet(
            population: [PopulationThresholdAlertPolicy(
                rule: advancedRuleConfiguration(AdvancedAlertRuleCatalog.population,
                                                preference: populationThresholdAlertsEnabled),
                direction: .above, threshold: populationAlertThreshold,
                hysteresis: populationHysteresis
            )],
            tokenPrices: [
                TokenPriceTargetAlertPolicy(
                    rule: advancedRuleConfiguration(AdvancedAlertRuleCatalog.tokenPriceAbove,
                                                    preference: tokenPriceAboveAlertsEnabled),
                    direction: .above, target: tokenPriceAboveTarget,
                    hysteresis: priceAboveHysteresis
                ),
                TokenPriceTargetAlertPolicy(
                    rule: advancedRuleConfiguration(AdvancedAlertRuleCatalog.tokenPriceBelow,
                                                    preference: tokenPriceBelowAlertsEnabled),
                    direction: .below, target: tokenPriceBelowTarget,
                    hysteresis: priceBelowHysteresis
                ),
            ],
            tokenChanges: [
                TokenRollingChangeAlertPolicy(
                    rule: advancedRuleConfiguration(
                        AdvancedAlertRuleCatalog.tokenChangeGain,
                        preference: cryptoAlertsEnabled && tokenChangeGainAlertsEnabled),
                    window: cryptoAlertWindow, direction: .gain,
                    thresholdPercent: cryptoAlertThreshold,
                    hysteresisPercent: rollingHysteresis
                ),
                TokenRollingChangeAlertPolicy(
                    rule: advancedRuleConfiguration(
                        AdvancedAlertRuleCatalog.tokenChangeLoss,
                        preference: cryptoAlertsEnabled && tokenChangeLossAlertsEnabled),
                    window: cryptoAlertWindow, direction: .loss,
                    thresholdPercent: cryptoAlertThreshold,
                    hysteresisPercent: rollingHysteresis
                ),
            ],
            releases: [NewGameReleaseAlertPolicy(
                rule: advancedRuleConfiguration(AdvancedAlertRuleCatalog.release,
                                                preference: releaseAlertsEnabled)
            )],
            quietHours: configuredQuietHours
        )
    }

    private func advancedRuleConfiguration(_ id: AdvancedAlertRuleID, preference: Bool)
    -> AdvancedAlertRuleConfiguration {
        // Unknown/not-determined remain eligible so the OS is the final gate; an explicit denial
        // is operationally disabled and Settings offers the recovery path.
        let postingAllowed = notificationAuthorizationState != .denied
        return AdvancedAlertRuleConfiguration(
            id: id,
            isEnabled: preference && postingAllowed && advancedAlertMutes[id] == nil,
            cooldown: advancedAlertCooldown
        )
    }

    private var configuredQuietHours: AlertQuietHours? {
        advancedAlertQuietHoursEnabled
            ? AlertQuietHours(startMinuteOfDay: advancedAlertQuietStartMinute,
                              endMinuteOfDay: advancedAlertQuietEndMinute,
                              timeZone: alertTimeZone)
            : nil
    }

    private func pruneExpiredAdvancedAlertMutes(at date: Date) {
        let previousCount = advancedAlertMutes.count
        advancedAlertMutes = advancedAlertMutes.filter { $0.value > date }
        if advancedAlertMutes.count != previousCount { persistAdvancedAlertMutes() }
    }

    /// Entry point used by `AppDelegate` for actions attached to an advanced notification.
    func handleAdvancedNotificationAction(identifier: String, ruleID rawRuleID: String) {
        let id = AdvancedAlertRuleID(rawRuleID)
        guard AdvancedAlertRuleCatalog.all.contains(id) else { return }

        switch identifier {
        case AdvancedNotificationContract.muteActionIdentifier:
            advancedAlertMutes[id] = now().addingTimeInterval(AppConfig.AdvancedAlert.muteDuration)
            persistAdvancedAlertMutes()
        case AdvancedNotificationContract.disableActionIdentifier:
            disableAdvancedAlert(id)
        default:
            break
        }
    }

    private func disableAdvancedAlert(_ id: AdvancedAlertRuleID) {
        switch id {
        case AdvancedAlertRuleCatalog.realmStatus:
            alertsEnabled = false
        case AdvancedAlertRuleCatalog.localRecord:
            peakAlertsEnabled = false
        case AdvancedAlertRuleCatalog.population:
            populationThresholdAlertsEnabled = false
        case AdvancedAlertRuleCatalog.tokenPriceAbove:
            tokenPriceAboveAlertsEnabled = false
        case AdvancedAlertRuleCatalog.tokenPriceBelow:
            tokenPriceBelowAlertsEnabled = false
        case AdvancedAlertRuleCatalog.tokenChangeGain:
            tokenChangeGainAlertsEnabled = false
        case AdvancedAlertRuleCatalog.tokenChangeLoss:
            tokenChangeLossAlertsEnabled = false
        case AdvancedAlertRuleCatalog.release:
            releaseAlertsEnabled = false
        default:
            break
        }
    }

    /// Localize a decision and hand it to the notifier with a unique per-fire id.
    private func post(_ decision: AlertDecision, ruleID: AdvancedAlertRuleID, firedAt: Date) {
        let content = AlertPresenter.content(for: decision)
        notifier.post(AppNotification(
            title: content.title,
            body: content.body,
            id: decision.kind.requestID(now: { firedAt }),
            categoryIdentifier: AdvancedNotificationContract.categoryIdentifier,
            userInfo: [AdvancedNotificationContract.ruleIDUserInfoKey: ruleID.rawValue]
        ))
    }

    private func post(_ decision: AdvancedAlertDecision) {
        let content = AdvancedAlertPresenter.content(for: decision)
        notifier.post(AppNotification(
            title: content.title,
            body: content.body,
            id: "advanced-\(decision.ruleID.rawValue)-\(decision.firedAt.timeIntervalSince1970)",
            categoryIdentifier: AdvancedNotificationContract.categoryIdentifier,
            userInfo: [AdvancedNotificationContract.ruleIDUserInfoKey: decision.ruleID.rawValue]
        ))
    }

    private func applyLaunchAtLogin(_ enabled: Bool) {
        launch.setEnabled(enabled)
    }

    /// Re-read the real `SMAppService` status and write the toggle back if it disagrees — so a
    /// `.requiresApproval` (item still pending in System Settings) shows OFF instead of a lie, and
    /// the toggle self-corrects once the user approves (called again from `PopoverView.onAppear`).
    /// The `isReconciling` guard makes the write-back a single non-recursive assignment.
    func reconcileLaunchAtLogin() {
        let actual = launch.isEnabled
        guard actual != launchAtLogin else { return }
        isReconciling = true
        launchAtLogin = actual
        isReconciling = false
    }

    // MARK: History

    private func record(count: Int, at date: Date) {
        history.append(Sample(date: date, count: count))
        pendingWrites += 1
        historyNeedsSave = true
        historyGeneration &+= 1
        // Coalesced flush — see `flushHistory`. Avoids re-encoding/atomically rewriting the entire
        // array on every poll (multi-MB churn at the 10s setting).
        if pendingWrites >= AppConfig.History.flushEverySamples
            || now().timeIntervalSince(lastFlush) >= AppConfig.History.flushEverySeconds {
            flushHistory()
        }
    }

    /// Request an asynchronous flush. The serial persistence worker does all file access away from
    /// the main actor; this method only snapshots already-in-memory state. A request made while the
    /// startup load is running is held until the loaded and newly-recorded samples are merged.
    func flushHistory() {
        // The in-flight snapshot already contains every current change. Awaiting it is sufficient;
        // a duplicate lifecycle callback must not turn one failed attempt into a tight retry loop.
        if historySaveTask != nil, historySavingGeneration == historyGeneration { return }
        historyFlushRequested = true
        startHistorySaveIfPossible()
    }

    /// Flush and await every save requested by this call. Lifecycle code uses this before
    /// termination; tests use it as a deterministic drain point. A failed save remains dirty but
    /// returns after the requested attempt so an unavailable volume cannot trap app termination.
    func flushHistoryAndWait() async {
        var attemptedGeneration: UInt64?
        flushHistory()
        while true {
            if let historyLoadTask {
                await historyLoadTask.value
                continue
            }
            if let historySaveTask {
                let generation = historySavingGeneration
                await historySaveTask.value
                attemptedGeneration = generation
                continue
            }
            // Main-actor reentrancy permits a status result to append a sample while disk I/O is
            // awaited. Drain that newer generation too, but attempt any failed generation only
            // once per call so termination cannot hang on a read-only/unavailable volume.
            guard historyNeedsSave, attemptedGeneration != historyGeneration else { return }
            flushHistory()
        }
    }

    /// User-initiated local-data reset. Await startup loading first so an older disk snapshot cannot
    /// reappear after the reset, then persist the empty frozen-format array through the same
    /// generation-aware worker used by normal history writes.
    func clearHistoryAndWait() async {
        if let historyLoadTask { await historyLoadTask.value }

        history.removeAll(keepingCapacity: false)
        pendingPeakObservations.removeAll(keepingCapacity: false)
        allTimePeak = 0
        allTimePeakDate = nil
        defaults.remove(.allTimePeak)
        defaults.remove(.allTimePeakDate)
        pendingWrites = 0
        historyRepairPending = false
        historyNeedsSave = true
        historyFlushRequested = true
        historyGeneration &+= 1
        await flushHistoryAndWait()
    }

    /// Samples within the selected range, bucketed by the selected interval. Delegated to the
    /// pure `HistoryAnalytics` value type (bucket math + 300-point cap unchanged).
    func series(range: ChartRange, interval: ChartInterval) -> [Sample] {
        HistoryAnalytics(samples: history, now: now).series(range: range, interval: interval)
    }

    private func loadHistory() {
        let worker = historyPersistence
        historyLoadTask = Task { [weak self] in
            let result = await worker.load()
            self?.finishHistoryLoad(result)
        }
    }

    private func finishHistoryLoad(_ result: HistoryPersistenceWorker.LoadResult) {
        historyLoadTask = nil
        historyLoadFinished = true
        let referenceDate = now()

        switch result {
        case .success(let loaded):
            let normalizedLoaded = HistorySampleNormalizer.normalize(
                loaded, relativeTo: referenceDate)
            reconcileAllTimePeak(from: normalizedLoaded)
            // Disk is ordered first so its representation deterministically wins an unlikely
            // duplicate timestamp; samples recorded while load was in flight are then retained.
            history = HistorySampleNormalizer.normalize(
                normalizedLoaded + history, relativeTo: referenceDate)
            historyPersistenceError = nil
            if normalizedLoaded != loaded {
                historyNeedsSave = true
                historyRepairPending = true
                historyGeneration &+= 1
                historyFlushRequested = true
            }
        case .failure:
            // Never erase samples that may have arrived while the blocking load was running.
            history = HistorySampleNormalizer.normalize(history, relativeTo: referenceDate)
            historyPersistenceError = "Couldn't load saved player history"
        }

        let deferredPeaks = pendingPeakObservations
        pendingPeakObservations.removeAll(keepingCapacity: false)
        for observation in deferredPeaks {
            checkPeak(count: observation.count, at: observation.date, realm: observation.realm)
        }
        startHistorySaveIfPossible()
    }

    private func startHistorySaveIfPossible() {
        guard historyLoadFinished, historySaveTask == nil else { return }
        guard historyFlushRequested else { return }
        guard historyNeedsSave else {
            historyFlushRequested = false
            return
        }

        historyFlushRequested = false
        let normalized = HistorySampleNormalizer.normalize(history, relativeTo: now())
        if normalized != history {
            history = normalized
            historyGeneration &+= 1
        }
        let snapshot = history
        let generation = historyGeneration
        let repairsLoadedRepresentation = historyRepairPending
        let worker = historyPersistence
        historySavingGeneration = generation
        historySaveTask = Task { [weak self] in
            let result = await worker.save(snapshot)
            self?.finishHistorySave(result, generation: generation,
                                    repairsLoadedRepresentation: repairsLoadedRepresentation)
        }
    }

    private func finishHistorySave(_ result: HistoryPersistenceWorker.SaveResult,
                                   generation: UInt64,
                                   repairsLoadedRepresentation: Bool) {
        historySaveTask = nil
        historySavingGeneration = nil
        switch result {
        case .success:
            lastFlush = now()
            historyPersistenceError = nil
            if repairsLoadedRepresentation { historyRepairPending = false }
            // A sample may have arrived while this snapshot was being written. Only the exact
            // current generation is clean; otherwise the newer in-memory state remains pending.
            if generation == historyGeneration {
                pendingWrites = 0
                historyNeedsSave = false
            }
        case .failure:
            historyPersistenceError = repairsLoadedRepresentation
                ? "Couldn't repair saved player history"
                : "Couldn't save player history"
            // Dirty state intentionally remains set so the next lifecycle flush retries.
        }
        startHistorySaveIfPossible()
    }

    private func reconcileAllTimePeak(from samples: [Sample]) {
        guard let hi = samples.max(by: { $0.count < $1.count }), hi.count > allTimePeak else {
            return
        }
        allTimePeak = hi.count
        allTimePeakDate = hi.date
        defaults.set(hi.count, for: .allTimePeak)
        defaults.set(hi.date, for: .allTimePeakDate)
    }

}

#if PREVIEW
/// Compile-time offline fallback for the screenshot app. `AppDelegate` never starts polling in a
/// preview build, but keeping the injected graph offline makes that guarantee resilient to future
/// lifecycle changes and manual test calls.
private struct PreviewReleaseAlertService: ReleaseFetching {
    func fetchReleases(limit: Int) async throws -> ReleaseFeed {
        ReleaseFeed(repository: "preview", releases: [])
    }
}
#endif
