import Foundation
import Testing
@testable import WoCKit

final class AdvancedIntegrationNotifier: Notifier, @unchecked Sendable {
    var notifications: [AppNotification] = []
    var configureCount = 0

    func post(title: String, body: String, id: String) {
        notifications.append(AppNotification(title: title, body: body, id: id))
    }

    func post(_ notification: AppNotification) {
        notifications.append(notification)
    }

    func configure() { configureCount += 1 }
}

@MainActor
@Suite struct AdvancedAlertIntegrationTests {
    private final class Clock {
        var date: Date
        init(_ date: Date = Date(timeIntervalSince1970: 1_800_000_000)) { self.date = date }
    }

    private func defaults(_ name: String, _ seed: [DefaultsKey: Any] = [:]) -> UserDefaults {
        let suite = "woc.advanced-integration.\(name)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        for (key, value) in seed { defaults.set(value, forKey: key.rawValue) }
        return defaults
    }

    private func store(defaults: UserDefaults, status: any StatusFetching = StubStatusService(),
                       crypto: any CryptoFetching = StubCryptoService(),
                       notifier: AdvancedIntegrationNotifier = .init(),
                       clock: Clock = .init()) -> StatusStore {
        StatusStore(defaults: defaults, statusService: status, cryptoService: crypto,
                    candleService: StubCandleService(), persistence: CountingPersistence(),
                    notifier: notifier,
                    notificationAuthorizer: FakeNotificationAuthorizer(status: .authorized),
                    launch: FakeLaunch(), now: { clock.date },
                    alertTimeZone: TimeZone(secondsFromGMT: 0)!)
    }

    private func quote(price: String, oneHourChange: Double? = nil,
                       sixHourChange: Double? = nil,
                       dayChange: Double? = nil) -> CryptoQuote {
        var market: [CryptoMarketTimeframe: CryptoMarketWindow] = [:]
        if let oneHourChange {
            market[.oneHour] = CryptoMarketWindow(changePercent: oneHourChange, buys: nil,
                                                  sells: nil, volumeUSD: nil)
        }
        if let sixHourChange {
            market[.sixHours] = CryptoMarketWindow(changePercent: sixHourChange, buys: nil,
                                                   sells: nil, volumeUSD: nil)
        }
        if let dayChange {
            market[.twentyFourHours] = CryptoMarketWindow(changePercent: dayChange, buys: nil,
                                                          sells: nil, volumeUSD: nil)
        }
        return CryptoQuote(price: price, change24h: dayChange ?? 0, market: market)
    }

    @Test func advancedPreferencesNormalizeOnLoadAndPersistOnChange() {
        let d = defaults("normalization", [
            .cryptoAlertWindow: "invalid",
            .populationAlertThreshold: -20,
            .tokenPriceAboveTarget: Double.nan,
            .tokenPriceBelowTarget: -1.0,
            .advancedAlertCooldown: 1_000.0,
            .advancedAlertQuietStartMinute: -60,
            .advancedAlertQuietEndMinute: 1_500,
        ])
        let subject = store(defaults: d)

        #expect(subject.cryptoAlertWindow == .oneHour)
        #expect(subject.populationAlertThreshold == 1)
        #expect(subject.tokenPriceAboveTarget == AppConfig.AdvancedAlert.defaultPriceAboveTarget)
        #expect(subject.tokenPriceBelowTarget == AppConfig.AdvancedAlert.defaultPriceBelowTarget)
        #expect(subject.advancedAlertCooldown == 15 * 60)
        #expect(subject.advancedAlertQuietStartMinute == 23 * 60)
        #expect(subject.advancedAlertQuietEndMinute == 60)

        subject.cryptoAlertWindow = .sixHours
        subject.populationThresholdAlertsEnabled = true
        subject.populationAlertThreshold = 250
        subject.releaseAlertsEnabled = false
        #expect(d.string(for: .cryptoAlertWindow) == TokenChangeAlertWindow.sixHours.rawValue)
        #expect(d.bool(for: .populationThresholdAlertsEnabled))
        #expect(d.integer(for: .populationAlertThreshold) == 250)
        #expect(!d.bool(for: .releaseAlertsEnabled))
    }

    @Test func successfulPlayerObservationsDrivePopulationAlertWithNotificationMetadata() async throws {
        let service = MutableStatusService()
        let notifier = AdvancedIntegrationNotifier()
        let d = defaults("population", [
            .alertsEnabled: false,
            .peakAlertsEnabled: false,
            .populationThresholdAlertsEnabled: true,
            .populationAlertThreshold: 10,
            .advancedAlertCooldown: 0.0,
        ])
        let subject = store(defaults: d, status: service, notifier: notifier)

        service.response = StatusResponse(ok: true, realm: "Claudemoon", playersOnline: 9)
        await subject.refreshStatus()
        #expect(notifier.notifications.isEmpty)

        service.response = StatusResponse(ok: true, realm: "Claudemoon", playersOnline: 10)
        await subject.refreshStatus()
        let notification = try #require(notifier.notifications.first)
        #expect(notifier.notifications.count == 1)
        #expect(notification.title == "🌍 The realm is bustling")
        #expect(notification.body == "10 players are online — your 10-player alert was reached.")
        #expect(notification.categoryIdentifier == AdvancedNotificationContract.categoryIdentifier)
        #expect(notification.userInfo[AdvancedNotificationContract.ruleIDUserInfoKey]
                == AdvancedAlertRuleCatalog.population.rawValue)
        #expect(notification.id.hasPrefix("advanced-population-threshold-"))
    }

    @Test func richMarketQuoteUsesSelectedRollingWindowWithoutLegacyDuplicate() async {
        let service = MutableCryptoService()
        let notifier = AdvancedIntegrationNotifier()
        let d = defaults("rolling", [
            .cryptoAlertsEnabled: true,
            .cryptoAlertThreshold: 10.0,
            .cryptoAlertWindow: TokenChangeAlertWindow.oneHour.rawValue,
            .advancedAlertCooldown: 0.0,
        ])
        let subject = store(defaults: d, crypto: service, notifier: notifier)

        service.quote = quote(price: "0.5", oneHourChange: 9, dayChange: 80)
        await subject.refreshCrypto()
        service.quote = quote(price: "0.6", oneHourChange: 10, dayChange: 90)
        await subject.refreshCrypto()

        #expect(notifier.notifications.count == 1)
        #expect(notifier.notifications[0].title == "🚀 $WOC 1-hour move")
        #expect(notifier.notifications[0].body
                == "Up 10.0% over 1 hour at $0.6000 — above your 10.0% alert.")
        #expect(notifier.notifications[0].userInfo[AdvancedNotificationContract.ruleIDUserInfoKey]
                == AdvancedAlertRuleCatalog.tokenChangeGain.rawValue)
        #expect(subject.lastAlertedPrice == 0) // rich quotes never touch the v1 fallback baseline
    }

    @Test func absolutePriceTargetsObserveSuccessfulSpotQuotes() async {
        let service = MutableCryptoService()
        let notifier = AdvancedIntegrationNotifier()
        let d = defaults("price-target", [
            .cryptoAlertsEnabled: false,
            .tokenPriceAboveAlertsEnabled: true,
            .tokenPriceAboveTarget: 1.0,
            .advancedAlertCooldown: 0.0,
        ])
        let subject = store(defaults: d, crypto: service, notifier: notifier)

        service.quote = quote(price: "0.9", oneHourChange: 0)
        await subject.refreshCrypto()
        service.quote = quote(price: "1.0", oneHourChange: 0)
        await subject.refreshCrypto()

        #expect(notifier.notifications.count == 1)
        #expect(notifier.notifications[0].title == "🎯 $WOC target reached")
        #expect(notifier.notifications[0].body
                == "$WOC is $1.000, at or above your $1.000 target.")
    }

    @Test func releaseObservationsSeedThenDeliverAndDisableActionPersists() {
        let notifier = AdvancedIntegrationNotifier()
        let d = defaults("release", [
            .releaseAlertsEnabled: true,
            .advancedAlertCooldown: 0.0,
        ])
        let clock = Clock()
        let subject = store(defaults: d, notifier: notifier, clock: clock)
        let v1 = GameRelease(id: 1, tag: "v1", name: "First")
        let v2 = GameRelease(id: 2, tag: "v2", name: "Second", body: "New dungeons")

        subject.observeGameReleases([v1], at: clock.date)
        clock.date.addTimeInterval(1)
        subject.observeGameReleases([v2, v1], at: clock.date)
        #expect(notifier.notifications.count == 1)
        #expect(notifier.notifications[0].title == "✨ WoC v2 is here")
        #expect(notifier.notifications[0].body == "New dungeons")

        subject.handleAdvancedNotificationAction(
            identifier: AdvancedNotificationContract.disableActionIdentifier,
            ruleID: AdvancedAlertRuleCatalog.release.rawValue)
        #expect(!subject.releaseAlertsEnabled)
        #expect(!d.bool(for: .releaseAlertsEnabled))
    }

    @Test func muteActionPersistsPerRuleAndConsumesCrossingsUntilExpiry() async {
        let service = MutableStatusService()
        let notifier = AdvancedIntegrationNotifier()
        let d = defaults("mute", [
            .alertsEnabled: false,
            .peakAlertsEnabled: false,
            .populationThresholdAlertsEnabled: true,
            .populationAlertThreshold: 10,
            .advancedAlertCooldown: 0.0,
        ])
        let clock = Clock()
        let subject = store(defaults: d, status: service, notifier: notifier, clock: clock)

        service.response = StatusResponse(ok: true, realm: "R", playersOnline: 9)
        await subject.refreshStatus()
        clock.date.addTimeInterval(1)
        service.response = StatusResponse(ok: true, realm: "R", playersOnline: 10)
        await subject.refreshStatus()
        #expect(notifier.notifications.count == 1)

        subject.handleAdvancedNotificationAction(
            identifier: AdvancedNotificationContract.muteActionIdentifier,
            ruleID: AdvancedAlertRuleCatalog.population.rawValue)
        let muteValues = d.dictionary(for: .advancedAlertMutes)
        #expect(muteValues?[AdvancedAlertRuleCatalog.population.rawValue] != nil)

        clock.date.addTimeInterval(1)
        service.response = StatusResponse(ok: true, realm: "R", playersOnline: 9)
        await subject.refreshStatus()
        clock.date.addTimeInterval(1)
        service.response = StatusResponse(ok: true, realm: "R", playersOnline: 10)
        await subject.refreshStatus()
        #expect(notifier.notifications.count == 1)

        // Mute expiry does not replay the suppressed crossing. A fresh rearm/cross is required.
        clock.date.addTimeInterval(AppConfig.AdvancedAlert.muteDuration + 1)
        await subject.refreshStatus() // still high
        service.response = StatusResponse(ok: true, realm: "R", playersOnline: 9)
        await subject.refreshStatus()
        service.response = StatusResponse(ok: true, realm: "R", playersOnline: 10)
        await subject.refreshStatus()
        #expect(notifier.notifications.count == 2)
        #expect(d.dictionary(for: .advancedAlertMutes) == nil)
    }

    @Test func overnightQuietHoursSuppressCrossingWithoutDelayedDelivery() async throws {
        let service = MutableStatusService()
        let notifier = AdvancedIntegrationNotifier()
        let d = defaults("quiet", [
            .alertsEnabled: false,
            .peakAlertsEnabled: false,
            .populationThresholdAlertsEnabled: true,
            .populationAlertThreshold: 10,
            .advancedAlertCooldown: 0.0,
            .advancedAlertQuietHoursEnabled: true,
            .advancedAlertQuietStartMinute: 22 * 60,
            .advancedAlertQuietEndMinute: 7 * 60,
        ])
        let formatter = ISO8601DateFormatter()
        let clock = Clock(try #require(formatter.date(from: "2027-01-01T21:00:00Z")))
        let subject = store(defaults: d, status: service, notifier: notifier, clock: clock)

        service.response = StatusResponse(ok: true, realm: "R", playersOnline: 9)
        await subject.refreshStatus()
        clock.date = try #require(formatter.date(from: "2027-01-01T23:00:00Z"))
        service.response = StatusResponse(ok: true, realm: "R", playersOnline: 10)
        await subject.refreshStatus()
        #expect(notifier.notifications.isEmpty)

        clock.date = try #require(formatter.date(from: "2027-01-02T08:00:00Z"))
        await subject.refreshStatus() // no delayed notification while still high
        service.response = StatusResponse(ok: true, realm: "R", playersOnline: 9)
        await subject.refreshStatus()
        service.response = StatusResponse(ok: true, realm: "R", playersOnline: 10)
        await subject.refreshStatus()
        #expect(notifier.notifications.count == 1)
    }

    @Test func advancedPresenterProvidesLocalizedDomainCopy() {
        let at = Date(timeIntervalSince1970: 123)
        let loss = AdvancedAlertDecision(
            ruleID: AdvancedAlertRuleCatalog.tokenChangeLoss, firedAt: at,
            payload: .tokenChange(direction: .loss, window: .sixHours,
                                  changePercent: -12.34, thresholdPercent: 10,
                                  price: 0.0004))
        let content = AdvancedAlertPresenter.content(for: loss)
        #expect(content.title == "📉 $WOC 6-hour move")
        #expect(content.body
                == "Down 12.3% over 6 hours at $0.0004000 — beyond your 10.0% alert.")

        let onePlayer = AdvancedAlertDecision(
            ruleID: AdvancedAlertRuleCatalog.population, firedAt: at,
            payload: .population(direction: .above, count: 1, threshold: 1))
        #expect(AdvancedAlertPresenter.content(for: onePlayer).body
                == "1 player is online — your 1-player alert was reached.")
    }

    @Test func unknownNotificationActionsAndRuleIDsAreNoOps() {
        let d = defaults("unknown-action", [.releaseAlertsEnabled: true])
        let subject = store(defaults: d)
        subject.handleAdvancedNotificationAction(identifier: "unknown", ruleID: "game-release")
        subject.handleAdvancedNotificationAction(
            identifier: AdvancedNotificationContract.disableActionIdentifier,
            ruleID: "not-a-real-rule")
        #expect(subject.releaseAlertsEnabled)
        #expect(d.dictionary(for: .advancedAlertMutes) == nil)
    }

    @Test func realmAndRecordAlertsCarryStableActionMetadata() async throws {
        let service = MutableStatusService()
        let notifier = AdvancedIntegrationNotifier()
        let d = defaults("baseline-metadata", [
            .allTimePeak: 100_000,
            .advancedAlertCooldown: 0.0,
        ])
        let subject = store(defaults: d, status: service, notifier: notifier)

        service.response = StatusResponse(ok: true, realm: "R", playersOnline: 4)
        await subject.refreshStatus()
        service.response = StatusResponse(ok: false, realm: "R", playersOnline: 0)
        await subject.refreshStatus()
        await subject.refreshStatus()

        let down = try #require(notifier.notifications.first)
        #expect(down.id.hasPrefix("status-")) // frozen request-ID prefix
        #expect(down.categoryIdentifier == AdvancedNotificationContract.categoryIdentifier)
        #expect(down.userInfo[AdvancedNotificationContract.ruleIDUserInfoKey]
                == AdvancedAlertRuleCatalog.realmStatus.rawValue)

        subject.handleAdvancedNotificationAction(
            identifier: AdvancedNotificationContract.disableActionIdentifier,
            ruleID: AdvancedAlertRuleCatalog.realmStatus.rawValue)
        #expect(!subject.alertsEnabled)
        #expect(!d.bool(for: .alertsEnabled))

        let recordService = MutableStatusService()
        let recordNotifier = AdvancedIntegrationNotifier()
        let recordDefaults = defaults("record-metadata", [
            .alertsEnabled: false,
            .allTimePeak: 5,
            .advancedAlertCooldown: 0.0,
        ])
        let recordStore = store(defaults: recordDefaults, status: recordService,
                                notifier: recordNotifier)
        await recordStore.flushHistoryAndWait()
        recordService.response = StatusResponse(ok: true, realm: "R", playersOnline: 6)
        await recordStore.refreshStatus()

        let record = try #require(recordNotifier.notifications.first)
        #expect(record.id.hasPrefix("peak-"))
        #expect(record.userInfo[AdvancedNotificationContract.ruleIDUserInfoKey]
                == AdvancedAlertRuleCatalog.localRecord.rawValue)
    }

    @Test func quietRealmTransitionIsConsumedWithoutRecoveryReplay() async {
        let service = MutableStatusService()
        let notifier = AdvancedIntegrationNotifier()
        let d = defaults("realm-quiet", [
            .allTimePeak: 100_000,
            .advancedAlertCooldown: 0.0,
            .advancedAlertQuietHoursEnabled: true,
            .advancedAlertQuietStartMinute: 0,
            .advancedAlertQuietEndMinute: 0, // equal means all day
        ])
        let subject = store(defaults: d, status: service, notifier: notifier)

        service.response = StatusResponse(ok: true, realm: "R", playersOnline: 2)
        await subject.refreshStatus()
        service.response = StatusResponse(ok: false, realm: "R", playersOnline: 0)
        await subject.refreshStatus()
        await subject.refreshStatus()
        #expect(notifier.notifications.isEmpty)

        subject.advancedAlertQuietHoursEnabled = false
        service.response = StatusResponse(ok: true, realm: "R", playersOnline: 3)
        await subject.refreshStatus()
        #expect(notifier.notifications.isEmpty)
    }

    @Test func recordCooldownConsumesIntermediateRecordsAndAllowsANewOneAtExpiry() async {
        let service = MutableStatusService()
        let notifier = AdvancedIntegrationNotifier()
        let clock = Clock()
        let d = defaults("record-cooldown", [
            .alertsEnabled: false,
            .allTimePeak: 5,
            .advancedAlertCooldown: 15 * 60.0,
        ])
        let subject = store(defaults: d, status: service, notifier: notifier, clock: clock)
        await subject.flushHistoryAndWait()

        service.response = StatusResponse(ok: true, realm: "R", playersOnline: 6)
        await subject.refreshStatus()
        clock.date.addTimeInterval(1)
        service.response = StatusResponse(ok: true, realm: "R", playersOnline: 7)
        await subject.refreshStatus()
        #expect(notifier.notifications.count == 1)
        #expect(subject.allTimePeak == 7)

        clock.date.addTimeInterval(15 * 60 - 1)
        service.response = StatusResponse(ok: true, realm: "R", playersOnline: 8)
        await subject.refreshStatus()
        #expect(notifier.notifications.count == 2)
        #expect(subject.allTimePeak == 8)
    }

    @Test func disablingGainRuleLeavesLossRuleEnabledAndDeliverable() async {
        let service = MutableCryptoService()
        let notifier = AdvancedIntegrationNotifier()
        let d = defaults("direction-disable", [
            .cryptoAlertsEnabled: true,
            .advancedAlertCooldown: 0.0,
        ])
        let subject = store(defaults: d, crypto: service, notifier: notifier)
        subject.handleAdvancedNotificationAction(
            identifier: AdvancedNotificationContract.disableActionIdentifier,
            ruleID: AdvancedAlertRuleCatalog.tokenChangeGain.rawValue)

        #expect(!subject.tokenChangeGainAlertsEnabled)
        #expect(subject.tokenChangeLossAlertsEnabled)
        #expect(!d.bool(for: .tokenChangeGainAlertsEnabled))
        #expect(d.bool(for: .tokenChangeLossAlertsEnabled))

        service.quote = quote(price: "1.0", oneHourChange: -5, dayChange: 0)
        await subject.refreshCrypto()
        service.quote = quote(price: "0.9", oneHourChange: -10, dayChange: 0)
        await subject.refreshCrypto()

        #expect(notifier.notifications.count == 1)
        #expect(notifier.notifications[0].userInfo[AdvancedNotificationContract.ruleIDUserInfoKey]
                == AdvancedAlertRuleCatalog.tokenChangeLoss.rawValue)
    }

    @Test func persistedMutesDiscardUnknownExpiredAndNonfiniteEntries() {
        let clock = Clock()
        let validUntil = clock.date.addingTimeInterval(300).timeIntervalSince1970
        let d = defaults("mute-normalization", [
            .advancedAlertMutes: [
                AdvancedAlertRuleCatalog.population.rawValue: validUntil,
                "unknown-rule": validUntil,
                AdvancedAlertRuleCatalog.release.rawValue: clock.date.addingTimeInterval(-1)
                    .timeIntervalSince1970,
                AdvancedAlertRuleCatalog.tokenPriceAbove.rawValue: Double.nan,
            ],
        ])
        _ = store(defaults: d, clock: clock)

        let persisted = d.dictionary(for: .advancedAlertMutes)
        #expect(persisted?.count == 1)
        #expect((persisted?[AdvancedAlertRuleCatalog.population.rawValue] as? NSNumber)?.doubleValue
                == validUntil)
    }
}
