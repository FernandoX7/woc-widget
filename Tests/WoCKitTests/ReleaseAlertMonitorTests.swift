import Foundation
import Testing
@testable import WoCKit

private enum ReleaseMonitorTestError: Error { case unavailable }

private actor ReleaseMonitorServiceStub: ReleaseFetching {
    enum Outcome: Sendable {
        case releases([GameRelease])
        case failure
    }

    private var outcome: Outcome
    private var calls = 0
    private var requestedLimits: [Int] = []
    private var waiters: [(target: Int, continuation: CheckedContinuation<Void, Never>)] = []

    init(_ outcome: Outcome) { self.outcome = outcome }

    func setOutcome(_ outcome: Outcome) { self.outcome = outcome }
    func callCount() -> Int { calls }
    func limits() -> [Int] { requestedLimits }

    func waitUntilCallCount(_ target: Int) async {
        await withCheckedContinuation { continuation in
            if calls >= target {
                continuation.resume()
            } else {
                waiters.append((target, continuation))
            }
        }
    }

    func fetchReleases(limit: Int) async throws -> ReleaseFeed {
        calls += 1
        requestedLimits.append(limit)
        let ready = waiters.filter { $0.target <= calls }.map(\.continuation)
        waiters.removeAll { $0.target <= calls }
        ready.forEach { $0.resume() }

        switch outcome {
        case .releases(let releases):
            return ReleaseFeed(repository: "owner/repo", releases: releases)
        case .failure:
            throw ReleaseMonitorTestError.unavailable
        }
    }
}

private final class ReleaseMonitorNotifier: Notifier, @unchecked Sendable {
    var notifications: [AppNotification] = []

    func post(title: String, body: String, id: String) {
        notifications.append(AppNotification(title: title, body: body, id: id))
    }

    func post(_ notification: AppNotification) {
        notifications.append(notification)
    }
}

@MainActor
@Suite struct ReleaseAlertMonitorTests {
    private final class Clock {
        var date = Date(timeIntervalSince1970: 1_800_000_000)
    }

    private func defaults(_ name: String, releaseAlertsEnabled: Bool) -> UserDefaults {
        let suite = "woc.release-monitor.\(name)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        defaults.set(releaseAlertsEnabled, forKey: DefaultsKey.releaseAlertsEnabled.rawValue)
        defaults.set(0.0, forKey: DefaultsKey.advancedAlertCooldown.rawValue)
        return defaults
    }

    private func store(
        name: String,
        enabled: Bool = true,
        service: any ReleaseFetching,
        notifier: ReleaseMonitorNotifier = .init(),
        clock: Clock = .init()
    ) -> StatusStore {
        StatusStore(
            defaults: defaults(name, releaseAlertsEnabled: enabled),
            statusService: StubStatusService(),
            cryptoService: StubCryptoService(),
            candleService: StubCandleService(),
            releaseService: service,
            persistence: CountingPersistence(),
            notifier: notifier,
            notificationAuthorizer: FakeNotificationAuthorizer(status: .authorized),
            launch: FakeLaunch(),
            now: { clock.date },
            alertTimeZone: TimeZone(secondsFromGMT: 0)!
        )
    }

    @Test func successfulTicksSeedThenNotifyOnlyForANewRelease() async throws {
        let v1 = GameRelease(id: 1, tag: "v1", name: "First")
        let v2 = GameRelease(id: 2, tag: "v2", name: "Second", body: "New dungeons")
        let service = ReleaseMonitorServiceStub(.releases([v1]))
        let notifier = ReleaseMonitorNotifier()
        let clock = Clock()
        let subject = store(name: "success", service: service, notifier: notifier, clock: clock)

        await subject.refreshReleaseAlertsTick()
        #expect(notifier.notifications.isEmpty)

        await service.setOutcome(.releases([v2, v1]))
        clock.date.addTimeInterval(1)
        await subject.refreshReleaseAlertsTick()

        let notification = try #require(notifier.notifications.first)
        #expect(notifier.notifications.count == 1)
        #expect(notification.title == "✨ WoC v2 is here")
        #expect(notification.body == "New dungeons")
        #expect(await service.callCount() == 2)
        #expect(await service.limits() == [AppConfig.ReleaseAlert.fetchLimit,
                                           AppConfig.ReleaseAlert.fetchLimit])
    }

    @Test func failedTickDoesNotSeedOrMutateReleaseObservationState() async {
        let v2 = GameRelease(id: 2, tag: "v2", name: "Second")
        let v3 = GameRelease(id: 3, tag: "v3", name: "Third")
        let service = ReleaseMonitorServiceStub(.failure)
        let notifier = ReleaseMonitorNotifier()
        let clock = Clock()
        let subject = store(name: "failure", service: service, notifier: notifier, clock: clock)

        await subject.refreshReleaseAlertsTick()
        #expect(notifier.notifications.isEmpty)

        await service.setOutcome(.releases([v2]))
        clock.date.addTimeInterval(1)
        await subject.refreshReleaseAlertsTick()
        #expect(notifier.notifications.isEmpty) // first successful response is still the seed

        await service.setOutcome(.releases([v3, v2]))
        clock.date.addTimeInterval(1)
        await subject.refreshReleaseAlertsTick()
        #expect(notifier.notifications.count == 1)
        #expect(notifier.notifications.first?.title == "✨ WoC v3 is here")
    }

    @Test func disabledMonitorNeitherSchedulesNorFetchesAndEnableStartsImmediately() async {
        let service = ReleaseMonitorServiceStub(.releases([
            GameRelease(id: 1, tag: "v1", name: "First")
        ]))
        let subject = store(name: "enable-disable", enabled: false, service: service)

        subject.start()
        #expect(!subject.isReleaseAlertMonitoringActive)
        await subject.refreshReleaseAlertsTick()
        #expect(await service.callCount() == 0)

        subject.releaseAlertsEnabled = true
        #expect(subject.isReleaseAlertMonitoringActive)
        await service.waitUntilCallCount(1)

        subject.releaseAlertsEnabled = false
        #expect(!subject.isReleaseAlertMonitoringActive)
        await subject.refreshReleaseAlertsTick()
        #expect(await service.callCount() == 1)
    }

    @Test func enabledMonitorSchedulesAndChecksImmediatelyOnStart() async {
        let service = ReleaseMonitorServiceStub(.releases([
            GameRelease(id: 1, tag: "v1", name: "First")
        ]))
        let subject = store(name: "start-enabled", service: service)

        subject.start()
        #expect(subject.isReleaseAlertMonitoringActive)
        await service.waitUntilCallCount(1)

        subject.releaseAlertsEnabled = false // invalidates the repeating timer before teardown
        #expect(!subject.isReleaseAlertMonitoringActive)
    }

    @Test func reenableReseedsInsteadOfReplayingReleasesFromDisabledPeriod() async {
        let v1 = GameRelease(id: 1, tag: "v1", name: "First")
        let v2 = GameRelease(id: 2, tag: "v2", name: "Second")
        let v3 = GameRelease(id: 3, tag: "v3", name: "Third")
        let service = ReleaseMonitorServiceStub(.releases([v1]))
        let notifier = ReleaseMonitorNotifier()
        let clock = Clock()
        let subject = store(name: "reseed", service: service, notifier: notifier, clock: clock)

        await subject.refreshReleaseAlertsTick()
        subject.releaseAlertsEnabled = false
        await service.setOutcome(.releases([v2, v1]))
        subject.releaseAlertsEnabled = true
        await subject.refreshReleaseAlertsTick()
        #expect(notifier.notifications.isEmpty)

        await service.setOutcome(.releases([v3, v2, v1]))
        clock.date.addTimeInterval(1)
        await subject.refreshReleaseAlertsTick()
        #expect(notifier.notifications.count == 1)
        #expect(notifier.notifications.first?.title == "✨ WoC v3 is here")
    }
}
