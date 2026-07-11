import Foundation

/// Narrow release-feed seam used by both the on-demand Community page and the low-frequency
/// background release-alert monitor. Keeping it separate prevents an alert check from downloading
/// every Community feed.
protocol ReleaseFetching: Sendable {
    func fetchReleases(limit: Int) async throws -> ReleaseFeed
}

/// One-shot reads from World of ClaudeCraft's public API. Callers choose when to load/cache these
/// feeds; the service intentionally owns no timer or mutable polling state.
protocol CommunityFetching: ReleaseFetching {
    func fetchProjectStats() async throws -> ProjectStats
    func fetchLeaderboard(limit: Int) async throws -> LifetimeLeaderboard
    func fetchRealms() async throws -> RealmDirectory
}
struct CommunityService: CommunityFetching {
    static let productionBaseURL = URL(string: "https://worldofclaudecraft.com")!

    let http: HTTPClient
    let baseURL: URL

    init(http: HTTPClient = URLSession.shared, baseURL: URL = CommunityService.productionBaseURL) {
        self.http = http
        self.baseURL = baseURL
    }

    func fetchProjectStats() async throws -> ProjectStats {
        try await http.fetchDecoded(ProjectStats.self, from: endpoint(path: "api/project-stats"))
    }

    func fetchReleases(limit: Int) async throws -> ReleaseFeed {
        try await http.fetchDecoded(
            ReleaseFeed.self,
            from: endpoint(path: "api/releases", query: ["limit": String(max(1, limit))])
        )
    }

    func fetchLeaderboard(limit: Int) async throws -> LifetimeLeaderboard {
        try await http.fetchDecoded(
            LifetimeLeaderboard.self,
            from: endpoint(path: "api/leaderboard", query: ["limit": String(max(1, limit))])
        )
    }

    func fetchRealms() async throws -> RealmDirectory {
        try await http.fetchDecoded(RealmDirectory.self, from: endpoint(path: "api/realms"))
    }

    /// Internal rather than private so URL construction can be pinned by contract tests without
    /// making an actual network request.
    func endpoint(path: String, query: [String: String] = [:]) -> URL {
        var url = baseURL
        for component in path.split(separator: "/") {
            url.appendPathComponent(String(component))
        }
        guard !query.isEmpty else { return url }

        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        components.queryItems = query.keys.sorted().map { URLQueryItem(name: $0, value: query[$0]) }
        return components.url!
    }
}
