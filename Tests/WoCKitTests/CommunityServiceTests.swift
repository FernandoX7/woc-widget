import Foundation
import Testing
@testable import WoCKit

private actor RequestCapturingHTTP: HTTPClient {
    private let body: Data
    private var request: URLRequest?

    init(_ json: String) { body = Data(json.utf8) }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        self.request = request
        let response = HTTPURLResponse(
            url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil
        )!
        return (body, response)
    }

    func requestedURL() -> URL? { request?.url }
}

@Suite struct CommunityServiceTests {
    private func service(_ json: String, status: Int = 200) -> CommunityService {
        CommunityService(
            http: FakeHTTP(body: Data(json.utf8), status: status),
            baseURL: URL(string: "https://example.invalid/root")!
        )
    }

    @Test func decodesProjectStatsThroughInjectedHTTPClient() async throws {
        let stats = try await service(
            #"{"accounts_created":48156,"players_online":93,"realm":"Claudemoon"}"#
        ).fetchProjectStats()

        #expect(stats.accountsCreated == 48_156)
        #expect(stats.playersOnline == 93)
        #expect(stats.realm == "Claudemoon")
    }

    @Test func projectStatsTreatsChangingAncillaryTypesAsUnavailable() async throws {
        let stats = try await service(
            #"{"accounts_created":"many","players_online":93,"realm":false,"new_field":123}"#
        ).fetchProjectStats()

        #expect(stats.accountsCreated == nil)
        #expect(stats.playersOnline == 93)
        #expect(stats.realm == nil)
    }

    @Test func projectStatsRequiresAtLeastOneUsableTypedField() async {
        for json in [
            #"{}"#,
            #"{"accounts_created":"many","players_online":false,"realm":"   "}"#,
            #"{"accounts_created":-1,"players_online":-2}"#,
        ] {
            await #expect(throws: FetchError.self) {
                _ = try await service(json).fetchProjectStats()
            }
        }
    }

    @Test func decodesReleaseFeedDatesLinksAndSkipsMalformedRows() async throws {
        let json = #"""
        {
          "repo": "levy-street/world-of-claudecraft",
          "releases": [
            {
              "id": 351405040,
              "tag": "v0.23.0",
              "name": "World of ClaudeCraft v0.23.0",
              "body": "Highlights",
              "url": "https://github.com/levy-street/world-of-claudecraft/releases/tag/v0.23.0",
              "prerelease": false,
              "publishedAt": "2026-07-09T08:25:30Z"
            },
            42,
            {"id":"bad","tag":"v-next","url":"relative/path","publishedAt":"not-a-date"}
          ]
        }
        """#

        let feed = try await service(json).fetchReleases(limit: 3)

        #expect(feed.repository == "levy-street/world-of-claudecraft")
        #expect(feed.releases.count == 2)
        #expect(feed.releases[0].id == 351_405_040)
        #expect(feed.releases[0].tag == "v0.23.0")
        #expect(feed.releases[0].publishedAt == Date(timeIntervalSince1970: 1_783_585_530))
        #expect(feed.releases[0].url?.host == "github.com")
        #expect(feed.releases[1].tag == "v-next")
        #expect(feed.releases[1].id == nil)
        #expect(feed.releases[1].url == nil)
        #expect(feed.releases[1].publishedAt == nil)
    }

    @Test func acceptsFractionalISOReleaseTimestamp() async throws {
        let feed = try await service(
            #"{"releases":[{"tag":"v-next","publishedAt":"2026-07-09T08:25:30.123Z"}]}"#
        ).fetchReleases(limit: 1)

        #expect(feed.releases.first?.publishedAt != nil)
    }

    @Test func decodesLifetimeLeaderboardAndDefaultsBadOptionalFields() async throws {
        let json = #"""
        {
          "realm":"Claudemoon", "scope":"realm", "metric":"lifetimeXp",
          "leaders":[
            {"rank":1,"name":"Moonwarden","cls":"hunter","level":20,"virtualLevel":38,
             "lifetimeXp":1236074,"prestigeRank":46},
            {"rank":"second","name":"Emberguard","cls":7,"level":20}
          ],
          "page":0,"pageCount":1,"total":2,"pageSize":2
        }
        """#

        let board = try await service(json).fetchLeaderboard(limit: 2)

        #expect(board.realm == "Claudemoon")
        #expect(board.leaders.count == 2)
        #expect(board.leaders[0].characterClass == "hunter")
        #expect(board.leaders[0].lifetimeXP == 1_236_074)
        #expect(board.leaders[1].name == "Emberguard")
        #expect(board.leaders[1].rank == nil)
        #expect(board.leaders[1].characterClass == nil)
        #expect(board.total == 2)
    }

    @Test func requiredCollectionKeysMustBePresentArrays() async {
        await #expect(throws: FetchError.self) {
            _ = try await service(#"{"repo":"owner/repo"}"#).fetchReleases(limit: 1)
        }
        await #expect(throws: FetchError.self) {
            _ = try await service(#"{"releases":{}}"#).fetchReleases(limit: 1)
        }
        await #expect(throws: FetchError.self) {
            _ = try await service(#"{"realm":"Claudemoon"}"#).fetchLeaderboard(limit: 1)
        }
        await #expect(throws: FetchError.self) {
            _ = try await service(#"{"leaders":{}}"#).fetchLeaderboard(limit: 1)
        }
        await #expect(throws: FetchError.self) {
            _ = try await service(#"{"current":"Claudemoon"}"#).fetchRealms()
        }
        await #expect(throws: FetchError.self) {
            _ = try await service(#"{"realms":{}}"#).fetchRealms()
        }
        await #expect(throws: FetchError.self) {
            _ = try await service(#"{"realms":[]}"#).fetchRealms()
        }
        await #expect(throws: FetchError.self) {
            _ = try await service(#"{"realms":[],"characters":[]}"#).fetchRealms()
        }
    }

    @Test func nonemptyCollectionsWithNoDecodableRowsFailInsteadOfLookingEmpty() async {
        await #expect(throws: FetchError.self) {
            _ = try await service(#"{"releases":[42,false,{}]}"#).fetchReleases(limit: 2)
        }
        await #expect(throws: FetchError.self) {
            _ = try await service(#"{"leaders":[42,false,{}]}"#).fetchLeaderboard(limit: 2)
        }
        await #expect(throws: FetchError.self) {
            _ = try await service(#"{"realms":[42,false,{}],"characters":{}}"#).fetchRealms()
        }
    }

    @Test func mixedCollectionsKeepTheirDecodableRows() async throws {
        let leaderboard = try await service(
            #"{"leaders":[42,{"rank":1,"name":"Valid"}]}"#
        ).fetchLeaderboard(limit: 2)
        let realms = try await service(
            #"{"realms":[false,{"name":"Claudemoon"}],"characters":{}}"#
        ).fetchRealms()

        #expect(leaderboard.leaders.map(\.name) == ["Valid"])
        #expect(realms.realms.map(\.name) == ["Claudemoon"])
    }

    @Test func emptyRequiredCollectionsRemainValidSuccessfulResponses() async throws {
        let releases = try await service(#"{"releases":[]}"#).fetchReleases(limit: 1)
        let leaderboard = try await service(#"{"leaders":[]}"#).fetchLeaderboard(limit: 1)
        let realms = try await service(#"{"realms":[],"characters":{}}"#).fetchRealms()

        #expect(releases.releases.isEmpty)
        #expect(leaderboard.leaders.isEmpty)
        #expect(realms.realms.isEmpty)
    }

    @Test func decodesAnonymousRealmDirectory() async throws {
        let json = #"""
        {"current":"Claudemoon","realms":[
          {"name":"Claudemoon","url":"","type":"Normal"},
          {"name":"Test","url":"https://test.example/game","type":"Seasonal"}
        ],"characters":{"Claudemoon":2}}
        """#

        let directory = try await service(json).fetchRealms()

        #expect(directory.currentRealm == "Claudemoon")
        #expect(directory.realms.count == 2)
        #expect(directory.realms[0].serverURL == nil)
        #expect(directory.realms[1].serverURL?.absoluteString == "https://test.example/game")
        #expect(directory.characterCountsByRealm["Claudemoon"] == 2)
    }

    @Test func communityLinksRequireHTTPS() async throws {
        let feed = try await service(
            #"{"releases":[{"tag":"v1","url":"http://example.com/release"}]}"#
        ).fetchReleases(limit: 1)
        #expect(feed.releases.first?.url == nil)
    }

    @Test func constructsFirstPartyPaths() {
        let svc = service("{}")

        #expect(svc.endpoint(path: "api/project-stats").absoluteString ==
                "https://example.invalid/root/api/project-stats")
        #expect(svc.endpoint(path: "api/releases", query: ["limit": "1"]).absoluteString ==
                "https://example.invalid/root/api/releases?limit=1")
        #expect(svc.endpoint(path: "api/realms").absoluteString ==
                "https://example.invalid/root/api/realms")
    }

    @Test func clampsNonpositiveLimitsBeforeSendingRequest() async throws {
        let http = RequestCapturingHTTP(#"{"releases":[]}"#)
        let svc = CommunityService(http: http, baseURL: URL(string: "https://example.invalid")!)

        _ = try await svc.fetchReleases(limit: 0)

        let capturedURL = await http.requestedURL()
        let url = try #require(capturedURL)
        let items = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        #expect(items == [URLQueryItem(name: "limit", value: "1")])
    }

    @Test func mapsCommunityHTTPFailureThroughSharedTransportLayer() async {
        await #expect(throws: FetchError.self) {
            _ = try await service("{}", status: 503).fetchRealms()
        }
    }
}
