import Foundation
import Testing
@testable import WoCKit

private enum CommunityStubFeed: Sendable {
    case projectStats, releases, leaderboard, realms
}

private enum CommunityStubError: Error { case unavailable }

private struct CommunityCallCounts: Sendable, Equatable {
    var projectStats = 0
    var releases = 0
    var leaderboard = 0
    var realms = 0
}

private actor CommunityStoreServiceStub: CommunityFetching {
    private var failures: Set<CommunityStubFeed>
    private var releaseTag: String
    private var leaderName: String
    private var calls = CommunityCallCounts()

    init(
        failures: Set<CommunityStubFeed> = [],
        releaseTag: String = "v1.0.0",
        leaderName: String = "First"
    ) {
        self.failures = failures
        self.releaseTag = releaseTag
        self.leaderName = leaderName
    }

    func setFailures(_ failures: Set<CommunityStubFeed>) { self.failures = failures }
    func setReleaseTag(_ tag: String) { releaseTag = tag }
    func setLeaderName(_ name: String) { leaderName = name }
    func callCounts() -> CommunityCallCounts { calls }

    func fetchProjectStats() async throws -> ProjectStats {
        calls.projectStats += 1
        if failures.contains(.projectStats) { throw CommunityStubError.unavailable }
        return ProjectStats(accountsCreated: 48_156, playersOnline: 104, realm: "Claudemoon")
    }

    func fetchReleases(limit: Int) async throws -> ReleaseFeed {
        calls.releases += 1
        if failures.contains(.releases) { throw CommunityStubError.unavailable }
        return ReleaseFeed(
            repository: "owner/repo",
            releases: [GameRelease(id: 1, tag: releaseTag, name: "Release \(releaseTag)")]
        )
    }

    func fetchLeaderboard(limit: Int) async throws -> LifetimeLeaderboard {
        calls.leaderboard += 1
        if failures.contains(.leaderboard) { throw CommunityStubError.unavailable }
        return LifetimeLeaderboard(
            realm: "Claudemoon",
            leaders: [LifetimeLeaderboardEntry(rank: 1, name: leaderName, lifetimeXP: 100)]
        )
    }

    func fetchRealms() async throws -> RealmDirectory {
        calls.realms += 1
        if failures.contains(.realms) { throw CommunityStubError.unavailable }
        return RealmDirectory(
            currentRealm: "Claudemoon",
            realms: [
                GameRealm(name: "Archived", type: "Seasonal"),
                GameRealm(name: "Claudemoon", type: "Normal"),
            ]
        )
    }
}

@MainActor
@Suite struct CommunityStoreTests {
    private let baseDate = Date(timeIntervalSince1970: 1_700_000_000)

    @Test func initialRefreshLoadsEveryVisibleFeedAndStartsFreshCache() async {
        let service = CommunityStoreServiceStub()
        let store = CommunityStore(service: service, now: { self.baseDate })

        #expect(store.phase == .idle)
        #expect(store.isStale)
        #expect(!store.hasCachedContent)

        await store.refreshIfNeeded()

        #expect(store.phase == .loaded)
        #expect(store.failedFeeds.isEmpty)
        #expect(store.lastSuccess == baseDate)
        #expect(store.lastAttempt == baseDate)
        #expect(!store.isStale)
        #expect(store.hasCachedContent)
        #expect(store.projectStats?.accountsCreated == 48_156)
        #expect(store.releases.first?.tag == "v1.0.0")
        #expect(store.leaderboard.first?.name == "First")
        #expect(store.currentRealm == "Claudemoon")
        #expect(store.realms.first?.name == "Archived")
        #expect(store.projectStatsState.phase == .loaded)
        #expect(store.projectStatsState.lastAttempt == baseDate)
        #expect(store.projectStatsState.lastSuccess == baseDate)
        #expect(store.projectStatsState.error == nil)
        #expect(store.releasesState.phase == .loaded)
        #expect(store.leaderboardState.phase == .loaded)
        #expect(store.realmsState.phase == .loaded)
        let counts = await service.callCounts()
        #expect(counts == CommunityCallCounts(
            projectStats: 1, releases: 1, leaderboard: 1, realms: 1
        ))
    }

    @Test func refreshIfNeededHonorsCacheUntilExactExpiryBoundary() async {
        let service = CommunityStoreServiceStub()
        var currentDate = baseDate
        let store = CommunityStore(service: service, cacheDuration: 900, now: { currentDate })
        await store.refresh()

        currentDate = baseDate.addingTimeInterval(899)
        await store.refreshIfNeeded()
        let freshCounts = await service.callCounts()
        #expect(freshCounts.releases == 1)

        currentDate = baseDate.addingTimeInterval(900)
        #expect(store.isStale)
        await store.refreshIfNeeded()
        let expiredCounts = await service.callCounts()
        #expect(expiredCounts.releases == 2)
        #expect(store.lastSuccess == currentDate)
    }

    @Test func backwardClockInvalidatesCacheAndDoesNotExtendFailureCooldown() async {
        let service = CommunityStoreServiceStub()
        var currentDate = baseDate
        let store = CommunityStore(
            service: service,
            cacheDuration: 900,
            failureRetryDuration: 60,
            now: { currentDate }
        )
        await store.refresh()

        currentDate = baseDate.addingTimeInterval(-1)
        #expect(store.isStale)
        await store.refreshIfNeeded()
        var counts = await service.callCounts()
        #expect(counts.projectStats == 2)

        await service.setFailures([.leaderboard])
        currentDate = baseDate
        await store.refresh()
        #expect(store.failedFeeds == [.leaderboard])

        await service.setFailures([])
        currentDate = baseDate.addingTimeInterval(-2)
        await store.refreshIfNeeded()
        counts = await service.callCounts()
        #expect(counts.projectStats == 4)
        #expect(store.phase == .loaded)
    }

    @Test func partialRefreshKeepsFailedFeedCacheAndRetriesItOnNextVisit() async {
        let service = CommunityStoreServiceStub()
        var currentDate = baseDate
        let store = CommunityStore(service: service, cacheDuration: 60, now: { currentDate })
        await store.refresh()

        await service.setFailures([.leaderboard])
        await service.setReleaseTag("v2.0.0")
        currentDate = baseDate.addingTimeInterval(60)
        await store.refreshIfNeeded()

        #expect(store.phase == .partial)
        #expect(store.failedFeeds == [.leaderboard])
        #expect(store.releases.first?.tag == "v2.0.0")
        #expect(store.leaderboard.first?.name == "First") // successful cached value survives
        #expect(store.leaderboardState.phase == .cached)
        #expect(store.leaderboardState.isShowingCachedValue)
        #expect(store.leaderboardState.lastSuccess == baseDate)
        #expect(store.leaderboardState.lastAttempt == currentDate)
        #expect(store.leaderboardState.error != nil)
        #expect(store.releasesState.lastSuccess == currentDate)
        #expect(store.isShowingCachedContent)
        #expect(store.isStale) // a partial load never hides behind the normal cache window

        await service.setFailures([])
        await service.setLeaderName("Recovered")
        let beforeCooldown = await service.callCounts()
        await store.refreshIfNeeded()
        let duringCooldown = await service.callCounts()
        #expect(duringCooldown == beforeCooldown)

        currentDate = currentDate.addingTimeInterval(60)
        await store.refreshIfNeeded()

        #expect(store.phase == .loaded)
        #expect(store.failedFeeds.isEmpty)
        #expect(store.leaderboard.first?.name == "Recovered")
        #expect(!store.isStale)
    }

    @Test func totalFailureKeepsExistingSnapshotAndLastSuccess() async {
        let service = CommunityStoreServiceStub()
        var currentDate = baseDate
        let store = CommunityStore(service: service, cacheDuration: 10, now: { currentDate })
        await store.refresh()
        let successfulDate = store.lastSuccess

        await service.setFailures([.projectStats, .releases, .leaderboard, .realms])
        currentDate = baseDate.addingTimeInterval(10)
        await store.refresh()

        #expect(store.phase == .failed)
        #expect(store.failedFeeds.count == CommunityStore.Feed.allCases.count)
        #expect(store.lastSuccess == successfulDate)
        #expect(store.lastAttempt == currentDate)
        #expect(store.releases.first?.tag == "v1.0.0")
        #expect(store.leaderboard.first?.name == "First")
        #expect(store.isShowingCachedContent)
        #expect(store.isStale)
    }

    @Test func realmFailurePreservesCachedCurrentRealmAndDirectory() async {
        let service = CommunityStoreServiceStub()
        var currentDate = baseDate
        let store = CommunityStore(service: service, cacheDuration: 10, now: { currentDate })
        await store.refresh()

        await service.setFailures([.realms])
        currentDate = baseDate.addingTimeInterval(10)
        await store.refresh()

        #expect(store.phase == .partial)
        #expect(store.failedFeeds == [.realms])
        #expect(store.currentRealm == "Claudemoon")
        #expect(store.realms.map(\.name) == ["Archived", "Claudemoon"])
        #expect(store.isShowingCachedContent)
    }

    @Test func automaticRetryFetchesOnlyFailedFeedWhileHealthyFeedsRemainFresh() async {
        let service = CommunityStoreServiceStub()
        var currentDate = baseDate
        let store = CommunityStore(
            service: service,
            cacheDuration: 900,
            failureRetryDuration: 60,
            now: { currentDate }
        )
        await store.refresh()

        await service.setFailures([.leaderboard])
        currentDate = baseDate.addingTimeInterval(10)
        await store.refresh(.leaderboard)
        #expect(store.phase == .partial)

        var counts = await service.callCounts()
        #expect(counts == CommunityCallCounts(
            projectStats: 1, releases: 1, leaderboard: 2, realms: 1
        ))

        await service.setFailures([])
        await service.setLeaderName("Recovered")
        currentDate = baseDate.addingTimeInterval(69)
        await store.refreshIfNeeded()
        counts = await service.callCounts()
        #expect(counts.leaderboard == 2)

        currentDate = baseDate.addingTimeInterval(70)
        await store.refreshIfNeeded()
        counts = await service.callCounts()
        #expect(counts == CommunityCallCounts(
            projectStats: 1, releases: 1, leaderboard: 3, realms: 1
        ))
        #expect(store.leaderboard.first?.name == "Recovered")
        #expect(store.leaderboardState.lastSuccess == currentDate)
        #expect(store.phase == .loaded)
    }

    @Test func automaticRefreshFetchesOnlyIndividuallyStaleFeeds() async {
        let service = CommunityStoreServiceStub()
        var currentDate = baseDate
        let store = CommunityStore(service: service, cacheDuration: 900, now: { currentDate })
        await store.refresh()

        currentDate = baseDate.addingTimeInterval(100)
        await service.setReleaseTag("v2.0.0")
        await store.refresh(.releases)
        #expect(store.releasesState.lastSuccess == currentDate)
        #expect(store.lastSuccess == baseDate)

        currentDate = baseDate.addingTimeInterval(900)
        await store.refreshIfNeeded()

        let counts = await service.callCounts()
        #expect(counts == CommunityCallCounts(
            projectStats: 2, releases: 2, leaderboard: 2, realms: 2
        ))
        #expect(store.releasesState.lastSuccess == baseDate.addingTimeInterval(100))
        #expect(store.projectStatsState.lastSuccess == currentDate)
        #expect(store.lastSuccess == baseDate.addingTimeInterval(100))
    }

    @Test func explicitFailedFeedRetryDoesNotRefetchHealthySections() async {
        let service = CommunityStoreServiceStub(failures: [.releases, .realms])
        var currentDate = baseDate
        let store = CommunityStore(service: service, now: { currentDate })
        await store.refresh()
        #expect(store.failedFeeds == [.releases, .realms])

        await service.setFailures([])
        currentDate = baseDate.addingTimeInterval(1)
        await store.retryFailedFeeds()

        let counts = await service.callCounts()
        #expect(counts == CommunityCallCounts(
            projectStats: 1, releases: 2, leaderboard: 1, realms: 2
        ))
        #expect(store.failedFeeds.isEmpty)
        #expect(store.phase == .loaded)
    }

    @Test func aggregateFreshnessUsesOldestSuccessfulSectionTimestamp() async {
        let service = CommunityStoreServiceStub()
        var currentDate = baseDate
        let store = CommunityStore(service: service, now: { currentDate })
        await store.refresh()

        currentDate = baseDate.addingTimeInterval(30)
        await store.refresh(.releases)

        #expect(store.releasesState.lastSuccess == currentDate)
        #expect(store.leaderboardState.lastSuccess == baseDate)
        #expect(store.lastSuccess == baseDate)
        #expect(store.lastAttempt == currentDate)
    }

    @Test func releaseObserverReceivesOnlySuccessfulReleaseFeedsAndAttemptClock() async {
        let service = CommunityStoreServiceStub()
        var currentDate = baseDate
        var observedTags: [String?] = []
        var observedDates: [Date] = []
        let store = CommunityStore(
            service: service,
            releaseObserver: { releases, date in
                observedTags.append(releases.first?.tag)
                observedDates.append(date)
            },
            now: { currentDate }
        )

        await store.refresh()
        #expect(observedTags == ["v1.0.0"])
        #expect(observedDates == [baseDate])

        await service.setFailures([.releases])
        currentDate = baseDate.addingTimeInterval(30)
        await store.refresh()
        #expect(store.phase == .partial)
        #expect(observedTags == ["v1.0.0"])
        #expect(observedDates == [baseDate])
    }

    @Test func initialTotalFailureHasNoFalseSuccessOrCachedState() async {
        let service = CommunityStoreServiceStub(
            failures: [.projectStats, .releases, .leaderboard, .realms]
        )
        let store = CommunityStore(service: service, now: { self.baseDate })

        await store.refresh()

        #expect(store.phase == .failed)
        #expect(store.lastSuccess == nil)
        #expect(store.lastAttempt == baseDate)
        #expect(store.projectStatsState.phase == .failed)
        #expect(store.projectStatsState.lastSuccess == nil)
        #expect(store.projectStatsState.lastAttempt == baseDate)
        #expect(store.projectStatsState.error != nil)
        #expect(!store.hasCachedContent)
        #expect(!store.isShowingCachedContent)
        #expect(store.isStale)
    }

    @Test func communityAccessibilityCopyUsesLocalizedSemanticWords() {
        #expect(AppText.communityLevel(38) == "Level 38")
        #expect(AppText.communityLeaderAccessibility(rank: 1, name: "Tira", detail: "Hunter · Level 38")
                == "Rank 1, Tira, Hunter · Level 38")
        #expect(AppText.communityLeaderAccessibility(rank: 2, name: "Emberguard", detail: "")
                == "Rank 2, Emberguard")
    }

}
