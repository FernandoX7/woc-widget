import Foundation
import Observation

/// On-demand state for the Community page. Unlike the live status/spot feeds, these values never
/// justify another repeating timer: the page loads them when opened and reuses a short-lived cache.
@MainActor
@Observable
final class CommunityStore {
    enum Phase: Sendable, Equatable {
        case idle
        case loading
        case loaded
        case partial
        case failed
    }

    enum Feed: String, CaseIterable, Sendable {
        case projectStats
        case releases
        case leaderboard
        case realms
    }

    private(set) var projectStatsState = CommunityFeedState<ProjectStats>()
    private(set) var releasesState = CommunityFeedState<ReleaseFeed>()
    private(set) var leaderboardState = CommunityFeedState<LifetimeLeaderboard>()
    private(set) var realmsState = CommunityFeedState<RealmDirectory>()

    @ObservationIgnored private let service: any CommunityFetching
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private let cacheDuration: TimeInterval
    @ObservationIgnored private let failureRetryDuration: TimeInterval
    @ObservationIgnored private let releaseObserver: (@MainActor ([GameRelease], Date) -> Void)?
    @ObservationIgnored private var inFlight = false

    init(
        service: (any CommunityFetching)? = nil,
        cacheDuration: TimeInterval = 15 * 60,
        failureRetryDuration: TimeInterval = 60,
        releaseObserver: (@MainActor ([GameRelease], Date) -> Void)? = nil,
        now: @escaping () -> Date = Date.init
    ) {
        if let service {
            self.service = service
        } else {
            #if PREVIEW
            self.service = PreviewCommunityService(
                referenceDate: now(), scenario: PreviewScenario.current)
            #else
            self.service = CommunityService()
            #endif
        }
        self.cacheDuration = max(0, cacheDuration)
        self.failureRetryDuration = max(0, failureRetryDuration)
        self.releaseObserver = releaseObserver
        self.now = now

        #if PREVIEW
        // Preview builds must be instant, pixel-stable fixtures and must never depend on live
        // network availability. The default preview service is deterministic too, so manually
        // pressing Retry/refresh still stays entirely offline.
        let fixture = PreviewCommunityFixture(referenceDate: now())
        let scenario = PreviewScenario.current
        projectStatsState = Self.previewState(
            fixture.projectStats, scenario: scenario, at: fixture.referenceDate)
        releasesState = Self.previewState(
            fixture.releases, scenario: scenario, at: fixture.referenceDate)
        leaderboardState = Self.previewState(
            fixture.leaderboard, scenario: scenario, at: fixture.referenceDate)
        realmsState = Self.previewState(
            fixture.realms, scenario: scenario, at: fixture.referenceDate)
        #endif
    }

    // Compatibility accessors keep existing views simple while the typed states let each section
    // render its own loading, cached, error, and freshness treatment.
    var projectStats: ProjectStats? { projectStatsState.value }
    var releases: [GameRelease] { releasesState.value?.releases ?? [] }
    var leaderboard: [LifetimeLeaderboardEntry] { leaderboardState.value?.leaders ?? [] }
    var currentRealm: String? { realmsState.value?.currentRealm }
    var realms: [GameRealm] { realmsState.value?.realms ?? [] }

    var phase: Phase {
        let metadata = feedMetadata(at: now())
        if metadata.contains(where: \.isLoading) { return .loading }
        if metadata.allSatisfy({ $0.lastAttempt == nil }) { return .idle }
        let failureCount = metadata.filter(\.hasError).count
        if failureCount == Feed.allCases.count { return .failed }
        if failureCount > 0 || metadata.filter(\.hasValue).count != Feed.allCases.count {
            return .partial
        }
        return .loaded
    }

    var failedFeeds: Set<Feed> {
        Set(feedMetadata(at: now()).filter(\.hasError).map(\.feed))
    }

    /// The oldest successful cached section is the honest aggregate freshness value. A fresh
    /// releases response can no longer make an older leaderboard appear newly updated.
    var lastSuccess: Date? {
        feedMetadata(at: now()).filter(\.hasValue).compactMap(\.lastSuccess).min()
    }

    var lastAttempt: Date? {
        feedMetadata(at: now()).compactMap(\.lastAttempt).max()
    }

    var isStale: Bool {
        feedMetadata(at: now()).contains(where: \.isStale)
    }

    var hasCachedContent: Bool {
        projectStats != nil || !releases.isEmpty || !leaderboard.isEmpty
            || currentRealm != nil || !realms.isEmpty
    }

    var isShowingCachedContent: Bool {
        feedMetadata(at: now()).contains(where: \.isShowingCachedValue)
    }

    var currentDate: Date { now() }

    func refreshIfNeeded() async {
        let feeds = Set(feedMetadata(at: now()).filter(\.shouldRetry).map(\.feed))
        await refresh(feeds: feeds)
    }

    /// Refresh each public feed independently. A temporary leaderboard failure must not discard a
    /// healthy release or project-stat response, and cached sections remain visible on partial error.
    func refresh() async {
        await refresh(feeds: Set(Feed.allCases))
    }

    /// Refresh one section without disturbing healthy sibling feeds. This is the preferred target
    /// for a section-level Retry control.
    func refresh(_ feed: Feed) async {
        await refresh(feeds: [feed])
    }

    /// Retry only endpoints currently in an error state, respecting no cache cooldown because this
    /// method represents an explicit user action.
    func retryFailedFeeds() async {
        await refresh(feeds: failedFeeds)
    }

    private func refresh(feeds: Set<Feed>) async {
        guard !feeds.isEmpty else { return }
        guard !inFlight else { return }
        inFlight = true
        defer { inFlight = false }

        let previousProjectStatsState = projectStatsState
        let previousReleasesState = releasesState
        let previousLeaderboardState = leaderboardState
        let previousRealmsState = realmsState
        for feed in feeds { beginLoading(feed) }

        let service = self.service
        let results = await withTaskGroup(of: FeedFetchResult.self, returning: [FeedFetchResult].self) {
            group in
            for feed in feeds {
                group.addTask { await Self.fetch(feed, using: service) }
            }
            var values: [FeedFetchResult] = []
            for await result in group { values.append(result) }
            return values
        }
        guard !Task.isCancelled else {
            projectStatsState = previousProjectStatsState
            releasesState = previousReleasesState
            leaderboardState = previousLeaderboardState
            realmsState = previousRealmsState
            return
        }

        let attemptDate = now()
        var successfulReleases: [GameRelease]?

        for result in results {
            switch result {
            case .projectStats(.success(let value)):
                projectStatsState.resolve(value, at: attemptDate)
            case .projectStats(.failure(let error)):
                projectStatsState.reject(error, at: attemptDate)
            case .releases(.success(let value)):
                releasesState.resolve(value, at: attemptDate)
                successfulReleases = value.releases
            case .releases(.failure(let error)):
                releasesState.reject(error, at: attemptDate)
            case .leaderboard(.success(let value)):
                leaderboardState.resolve(value, at: attemptDate)
            case .leaderboard(.failure(let error)):
                leaderboardState.reject(error, at: attemptDate)
            case .realms(.success(let value)):
                realmsState.resolve(value, at: attemptDate)
            case .realms(.failure(let error)):
                realmsState.reject(error, at: attemptDate)
            }
        }
        #if PREVIEW
        // Screenshot builds are side-effect free: fixture refreshes must not seed or deliver a
        // release notification through the production observer.
        _ = successfulReleases
        #else
        if let successfulReleases {
            releaseObserver?(successfulReleases, attemptDate)
        }
        #endif
    }

    private struct FeedMetadata {
        let feed: Feed
        let hasValue: Bool
        let lastAttempt: Date?
        let lastSuccess: Date?
        let hasError: Bool
        let isLoading: Bool
        let isShowingCachedValue: Bool
        let isStale: Bool
        let shouldRetry: Bool

        init<Value: Sendable & Equatable>(
            feed: Feed,
            state: CommunityFeedState<Value>,
            at date: Date,
            cacheDuration: TimeInterval,
            failureRetryDuration: TimeInterval
        ) {
            self.feed = feed
            hasValue = state.value != nil
            lastAttempt = state.lastAttempt
            lastSuccess = state.lastSuccess
            hasError = state.error != nil
            isLoading = state.isLoading
            isShowingCachedValue = state.isShowingCachedValue
            isStale = state.isStale(at: date, cacheDuration: cacheDuration)
            shouldRetry = state.shouldRetry(
                at: date,
                cacheDuration: cacheDuration,
                failureRetryDuration: failureRetryDuration
            )
        }
    }

    private func feedMetadata(at date: Date) -> [FeedMetadata] {
        [
            FeedMetadata(
                feed: .projectStats,
                state: projectStatsState,
                at: date,
                cacheDuration: cacheDuration,
                failureRetryDuration: failureRetryDuration
            ),
            FeedMetadata(
                feed: .releases,
                state: releasesState,
                at: date,
                cacheDuration: cacheDuration,
                failureRetryDuration: failureRetryDuration
            ),
            FeedMetadata(
                feed: .leaderboard,
                state: leaderboardState,
                at: date,
                cacheDuration: cacheDuration,
                failureRetryDuration: failureRetryDuration
            ),
            FeedMetadata(
                feed: .realms,
                state: realmsState,
                at: date,
                cacheDuration: cacheDuration,
                failureRetryDuration: failureRetryDuration
            ),
        ]
    }

    private func beginLoading(_ feed: Feed) {
        switch feed {
        case .projectStats: projectStatsState.beginLoading()
        case .releases: releasesState.beginLoading()
        case .leaderboard: leaderboardState.beginLoading()
        case .realms: realmsState.beginLoading()
        }
    }

    private enum FeedFetchResult: Sendable {
        case projectStats(FetchResult<ProjectStats>)
        case releases(FetchResult<ReleaseFeed>)
        case leaderboard(FetchResult<LifetimeLeaderboard>)
        case realms(FetchResult<RealmDirectory>)
    }

    private nonisolated static func fetch(
        _ feed: Feed,
        using service: any CommunityFetching
    ) async -> FeedFetchResult {
        switch feed {
        case .projectStats:
            return .projectStats(await capture { try await service.fetchProjectStats() })
        case .releases:
            return .releases(await capture { try await service.fetchReleases(limit: 3) })
        case .leaderboard:
            return .leaderboard(await capture { try await service.fetchLeaderboard(limit: 5) })
        case .realms:
            return .realms(await capture { try await service.fetchRealms() })
        }
    }

    private enum FetchResult<Value: Sendable>: Sendable {
        case success(Value)
        case failure(CommunityFeedError)
    }

    private nonisolated static func capture<Value: Sendable>(
        _ operation: @escaping @Sendable () async throws -> Value
    ) async -> FetchResult<Value> {
        do { return .success(try await operation()) }
        catch { return .failure(CommunityFeedError(error)) }
    }

    #if PREVIEW
    private static func previewState<Value: Sendable & Equatable>(
        _ value: Value,
        scenario: PreviewScenario,
        at date: Date
    ) -> CommunityFeedState<Value> {
        switch scenario {
        case .loading:
            return CommunityFeedState(lastAttempt: date, isLoading: true)
        case .cachedOffline:
            return CommunityFeedState(
                value: value,
                lastAttempt: date,
                lastSuccess: date.addingTimeInterval(-2 * 60 * 60),
                error: CommunityFeedError(message: "This Mac is offline.")
            )
        case .live, .welcome, .quoteOnly, .chartOnly, .emptyHistory, .notificationDenied:
            return CommunityFeedState(value: value, lastAttempt: date, lastSuccess: date)
        }
    }
    #endif
}

#if PREVIEW
/// Compile-time preview transport: the screenshot build cannot accidentally call production even
/// after a manual refresh. Kept in WoCKit so `CommunityStore()` is safe wherever it is constructed.
private struct PreviewCommunityService: CommunityFetching {
    let referenceDate: Date
    let scenario: PreviewScenario

    private func requireConnection() throws {
        if scenario == .cachedOffline { throw URLError(.notConnectedToInternet) }
    }

    func fetchProjectStats() async throws -> ProjectStats {
        try requireConnection()
        return PreviewCommunityFixture(referenceDate: referenceDate).projectStats
    }

    func fetchReleases(limit: Int) async throws -> ReleaseFeed {
        try requireConnection()
        let feed = PreviewCommunityFixture(referenceDate: referenceDate).releases
        return ReleaseFeed(repository: feed.repository, releases: Array(feed.releases.prefix(max(1, limit))))
    }

    func fetchLeaderboard(limit: Int) async throws -> LifetimeLeaderboard {
        try requireConnection()
        let board = PreviewCommunityFixture(referenceDate: referenceDate).leaderboard
        return LifetimeLeaderboard(
            realm: board.realm,
            scope: board.scope,
            metric: board.metric,
            leaders: Array(board.leaders.prefix(max(1, limit))),
            page: board.page,
            pageCount: board.pageCount,
            total: board.total,
            pageSize: min(max(1, limit), board.leaders.count)
        )
    }

    func fetchRealms() async throws -> RealmDirectory {
        try requireConnection()
        return PreviewCommunityFixture(referenceDate: referenceDate).realms
    }
}

private struct PreviewCommunityFixture {
    let referenceDate: Date

    var projectStats: ProjectStats {
        ProjectStats(accountsCreated: 48_156, playersOnline: 104, realm: "Claudemoon")
    }

    var releases: ReleaseFeed {
        ReleaseFeed(
            repository: "levy-street/world-of-claudecraft",
            releases: [
                GameRelease(
                    id: 351_405_040,
                    tag: "v0.23.0",
                    name: "World of ClaudeCraft v0.23.0",
                    body: "The biggest content release yet, with new game modes, heroic dungeons, "
                        + "and a personal bank vault.",
                    url: URL(string: "https://github.com/levy-street/world-of-claudecraft/releases/tag/v0.23.0"),
                    publishedAt: referenceDate.addingTimeInterval(-2 * 3600)
                )
            ]
        )
    }

    var leaderboard: LifetimeLeaderboard {
        let leaders = [
            LifetimeLeaderboardEntry(
                rank: 1, name: "Moonwarden", characterClass: "hunter", level: 20,
                virtualLevel: 38, lifetimeXP: 1_236_074, prestigeRank: 46
            ),
            LifetimeLeaderboardEntry(
                rank: 2, name: "Emberguard", characterClass: "warrior", level: 20,
                virtualLevel: 37, lifetimeXP: 1_195_854, prestigeRank: 44
            ),
            LifetimeLeaderboardEntry(
                rank: 3, name: "Valehunter", characterClass: "hunter", level: 20,
                virtualLevel: 36, lifetimeXP: 1_040_868, prestigeRank: 35
            ),
        ]
        return LifetimeLeaderboard(
            realm: "Claudemoon", scope: "realm", metric: "lifetimeXp", leaders: leaders,
            page: 0, pageCount: 1, total: leaders.count, pageSize: leaders.count
        )
    }

    var realms: RealmDirectory {
        RealmDirectory(
            currentRealm: "Claudemoon",
            realms: [GameRealm(name: "Claudemoon", type: "Normal")]
        )
    }
}
#endif
