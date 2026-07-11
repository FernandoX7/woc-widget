import Foundation

/// A lightweight, display-safe description of a feed failure. Keeping the underlying `Error`
/// out of observable state makes snapshots `Sendable`/`Equatable` while still giving a section
/// enough context for diagnostics or tailored retry copy.
struct CommunityFeedError: Sendable, Equatable {
    let message: String

    init(message: String) {
        self.message = message
    }

    init(_ error: any Error) {
        let description = (error as NSError).localizedDescription
            .trimmingCharacters(in: .whitespacesAndNewlines)
        message = description.isEmpty ? "The feed is temporarily unavailable." : description
    }
}

enum CommunityFeedPhase: Sendable, Equatable {
    case idle
    case loading
    case loaded
    case cached
    case failed
}

/// The complete lifecycle of one independently refreshed Community endpoint.
///
/// A failed request intentionally retains `value` and `lastSuccess`, allowing the corresponding
/// section to stay useful while accurately identifying the age of its cached snapshot.
struct CommunityFeedState<Value: Sendable & Equatable>: Sendable, Equatable {
    private(set) var value: Value?
    private(set) var lastAttempt: Date?
    private(set) var lastSuccess: Date?
    private(set) var error: CommunityFeedError?
    private(set) var isLoading: Bool

    init(
        value: Value? = nil,
        lastAttempt: Date? = nil,
        lastSuccess: Date? = nil,
        error: CommunityFeedError? = nil,
        isLoading: Bool = false
    ) {
        self.value = value
        self.lastAttempt = lastAttempt
        self.lastSuccess = lastSuccess
        self.error = error
        self.isLoading = isLoading
    }

    var phase: CommunityFeedPhase {
        if isLoading { return .loading }
        if error != nil { return value == nil ? .failed : .cached }
        if value != nil { return .loaded }
        return .idle
    }

    var isShowingCachedValue: Bool { value != nil && error != nil }

    func isStale(at date: Date, cacheDuration: TimeInterval) -> Bool {
        guard error == nil, let lastSuccess else { return true }
        let age = date.timeIntervalSince(lastSuccess)
        return age < 0 || age >= max(0, cacheDuration)
    }

    func shouldRetry(
        at date: Date,
        cacheDuration: TimeInterval,
        failureRetryDuration: TimeInterval
    ) -> Bool {
        guard !isLoading else { return false }
        guard error != nil else { return isStale(at: date, cacheDuration: cacheDuration) }
        guard let lastAttempt else { return true }
        let age = date.timeIntervalSince(lastAttempt)
        return age < 0 || age >= max(0, failureRetryDuration)
    }

    mutating func beginLoading() {
        isLoading = true
    }

    mutating func resolve(_ value: Value, at date: Date) {
        self.value = value
        lastAttempt = date
        lastSuccess = date
        error = nil
        isLoading = false
    }

    mutating func reject(_ error: CommunityFeedError, at date: Date) {
        lastAttempt = date
        self.error = error
        isLoading = false
    }
}

/// Aggregate, privacy-safe project statistics exposed by the first-party API.
struct ProjectStats: Codable, Sendable, Equatable {
    let accountsCreated: Int?
    let playersOnline: Int?
    let realm: String?

    init(accountsCreated: Int? = nil, playersOnline: Int? = nil, realm: String? = nil) {
        self.accountsCreated = accountsCreated
        self.playersOnline = playersOnline
        self.realm = realm
    }

    enum CodingKeys: String, CodingKey {
        case accountsCreated = "accounts_created"
        case playersOnline = "players_online"
        case realm
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let accountsCreated = CommunityModelCoding.nonnegative(
            try? c.decode(Int.self, forKey: .accountsCreated))
        let playersOnline = CommunityModelCoding.nonnegative(
            try? c.decode(Int.self, forKey: .playersOnline))
        let realm = CommunityModelCoding.nonemptyText(
            try? c.decode(String.self, forKey: .realm))
        guard accountsCreated != nil || playersOnline != nil || realm != nil else {
            throw DecodingError.dataCorruptedError(
                forKey: .accountsCreated,
                in: c,
                debugDescription: "Project stats contains no usable typed fields"
            )
        }
        self.accountsCreated = accountsCreated
        self.playersOnline = playersOnline
        self.realm = realm
    }
}

struct ReleaseFeed: Codable, Sendable, Equatable {
    let repository: String?
    let releases: [GameRelease]

    init(repository: String? = nil, releases: [GameRelease] = []) {
        self.repository = repository
        self.releases = releases
    }

    enum CodingKeys: String, CodingKey {
        case repository = "repo"
        case releases
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        repository = CommunityModelCoding.nonemptyText(
            try? c.decode(String.self, forKey: .repository))
        releases = try c.decodeLossyArray(GameRelease.self, forKey: .releases)
    }
}

struct GameRelease: Codable, Sendable, Equatable {
    let id: Int?
    let tag: String?
    let name: String?
    let body: String?
    let url: URL?
    let isPrerelease: Bool
    let publishedAt: Date?

    init(
        id: Int? = nil,
        tag: String? = nil,
        name: String? = nil,
        body: String? = nil,
        url: URL? = nil,
        isPrerelease: Bool = false,
        publishedAt: Date? = nil
    ) {
        self.id = id
        self.tag = tag
        self.name = name
        self.body = body
        self.url = url
        self.isPrerelease = isPrerelease
        self.publishedAt = publishedAt
    }

    enum CodingKeys: String, CodingKey {
        case id, tag, name, body, url
        case isPrerelease = "prerelease"
        case publishedAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let id = CommunityModelCoding.nonnegative(try? c.decode(Int.self, forKey: .id))
        let tag = CommunityModelCoding.nonemptyText(try? c.decode(String.self, forKey: .tag))
        let name = CommunityModelCoding.nonemptyText(try? c.decode(String.self, forKey: .name))
        body = try? c.decode(String.self, forKey: .body)
        let url = CommunityModelCoding.httpsURL(from: try? c.decode(String.self, forKey: .url))
        guard id != nil || tag != nil || name != nil || url != nil else {
            throw DecodingError.dataCorruptedError(
                forKey: .id, in: c,
                debugDescription: "Release contains no usable identity"
            )
        }
        self.id = id
        self.tag = tag
        self.name = name
        self.url = url
        isPrerelease = (try? c.decode(Bool.self, forKey: .isPrerelease)) ?? false
        publishedAt = CommunityModelCoding.date(from: try? c.decode(String.self, forKey: .publishedAt))
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(id, forKey: .id)
        try c.encodeIfPresent(tag, forKey: .tag)
        try c.encodeIfPresent(name, forKey: .name)
        try c.encodeIfPresent(body, forKey: .body)
        try c.encodeIfPresent(url?.absoluteString, forKey: .url)
        try c.encode(isPrerelease, forKey: .isPrerelease)
        try c.encodeIfPresent(publishedAt.map(CommunityModelCoding.string(from:)), forKey: .publishedAt)
    }
}

struct LifetimeLeaderboard: Codable, Sendable, Equatable {
    let realm: String?
    let scope: String?
    let metric: String?
    let leaders: [LifetimeLeaderboardEntry]
    let page: Int?
    let pageCount: Int?
    let total: Int?
    let pageSize: Int?

    init(
        realm: String? = nil,
        scope: String? = nil,
        metric: String? = nil,
        leaders: [LifetimeLeaderboardEntry] = [],
        page: Int? = nil,
        pageCount: Int? = nil,
        total: Int? = nil,
        pageSize: Int? = nil
    ) {
        self.realm = realm
        self.scope = scope
        self.metric = metric
        self.leaders = leaders
        self.page = page
        self.pageCount = pageCount
        self.total = total
        self.pageSize = pageSize
    }

    enum CodingKeys: String, CodingKey {
        case realm, scope, metric, leaders, page, pageCount, total, pageSize
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        realm = CommunityModelCoding.nonemptyText(try? c.decode(String.self, forKey: .realm))
        scope = CommunityModelCoding.nonemptyText(try? c.decode(String.self, forKey: .scope))
        metric = CommunityModelCoding.nonemptyText(try? c.decode(String.self, forKey: .metric))
        leaders = try c.decodeLossyArray(LifetimeLeaderboardEntry.self, forKey: .leaders)
        page = CommunityModelCoding.nonnegative(try? c.decode(Int.self, forKey: .page))
        pageCount = CommunityModelCoding.nonnegative(try? c.decode(Int.self, forKey: .pageCount))
        total = CommunityModelCoding.nonnegative(try? c.decode(Int.self, forKey: .total))
        pageSize = CommunityModelCoding.nonnegative(try? c.decode(Int.self, forKey: .pageSize))
    }
}

struct LifetimeLeaderboardEntry: Codable, Sendable, Equatable {
    let rank: Int?
    let name: String?
    let characterClass: String?
    let level: Int?
    let virtualLevel: Int?
    let lifetimeXP: Int?
    let prestigeRank: Int?

    init(
        rank: Int? = nil,
        name: String? = nil,
        characterClass: String? = nil,
        level: Int? = nil,
        virtualLevel: Int? = nil,
        lifetimeXP: Int? = nil,
        prestigeRank: Int? = nil
    ) {
        self.rank = rank
        self.name = name
        self.characterClass = characterClass
        self.level = level
        self.virtualLevel = virtualLevel
        self.lifetimeXP = lifetimeXP
        self.prestigeRank = prestigeRank
    }

    enum CodingKeys: String, CodingKey {
        case rank, name, level, virtualLevel, prestigeRank
        case characterClass = "cls"
        case lifetimeXP = "lifetimeXp"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        guard let name = CommunityModelCoding.nonemptyText(
            try? c.decode(String.self, forKey: .name)) else {
            throw DecodingError.dataCorruptedError(
                forKey: .name, in: c,
                debugDescription: "Leaderboard row has no usable player name"
            )
        }
        self.name = name
        rank = CommunityModelCoding.nonnegative(try? c.decode(Int.self, forKey: .rank))
        characterClass = CommunityModelCoding.nonemptyText(
            try? c.decode(String.self, forKey: .characterClass))
        level = CommunityModelCoding.nonnegative(try? c.decode(Int.self, forKey: .level))
        virtualLevel = CommunityModelCoding.nonnegative(
            try? c.decode(Int.self, forKey: .virtualLevel))
        lifetimeXP = CommunityModelCoding.nonnegative(try? c.decode(Int.self, forKey: .lifetimeXP))
        prestigeRank = CommunityModelCoding.nonnegative(
            try? c.decode(Int.self, forKey: .prestigeRank))
    }
}

struct RealmDirectory: Codable, Sendable, Equatable {
    let currentRealm: String?
    let realms: [GameRealm]
    let characterCountsByRealm: [String: Int]

    init(
        currentRealm: String? = nil,
        realms: [GameRealm] = [],
        characterCountsByRealm: [String: Int] = [:]
    ) {
        self.currentRealm = currentRealm
        self.realms = realms
        self.characterCountsByRealm = characterCountsByRealm
    }

    enum CodingKeys: String, CodingKey {
        case currentRealm = "current"
        case realms
        case characterCountsByRealm = "characters"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        currentRealm = CommunityModelCoding.nonemptyText(
            try? c.decode(String.self, forKey: .currentRealm))
        realms = try c.decodeLossyArray(GameRealm.self, forKey: .realms)
        characterCountsByRealm = try c.decode([String: Int].self, forKey: .characterCountsByRealm)
            .filter { !$0.key.isEmpty && $0.value >= 0 }
    }
}

struct GameRealm: Codable, Sendable, Equatable {
    let name: String?
    let serverURL: URL?
    let type: String?

    init(name: String? = nil, serverURL: URL? = nil, type: String? = nil) {
        self.name = name
        self.serverURL = serverURL
        self.type = type
    }

    enum CodingKeys: String, CodingKey {
        case name, type
        case serverURL = "url"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        guard let name = CommunityModelCoding.nonemptyText(
            try? c.decode(String.self, forKey: .name)) else {
            throw DecodingError.dataCorruptedError(
                forKey: .name, in: c,
                debugDescription: "Realm row has no usable name"
            )
        }
        self.name = name
        serverURL = CommunityModelCoding.httpsURL(from: try? c.decode(String.self, forKey: .serverURL))
        type = CommunityModelCoding.nonemptyText(try? c.decode(String.self, forKey: .type))
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(name, forKey: .name)
        try c.encodeIfPresent(serverURL?.absoluteString, forKey: .serverURL)
        try c.encodeIfPresent(type, forKey: .type)
    }
}

private enum CommunityModelCoding {
    static func nonemptyText(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else { return nil }
        return trimmed
    }

    static func nonnegative(_ value: Int?) -> Int? {
        value.flatMap { $0 >= 0 ? $0 : nil }
    }

    static func httpsURL(from raw: String?) -> URL? {
        guard let raw, !raw.isEmpty, let url = URL(string: raw),
              url.scheme?.lowercased() == "https",
              url.host != nil else { return nil }
        return url
    }

    static func date(from raw: String?) -> Date? {
        guard let raw else { return nil }
        let formatter = ISO8601DateFormatter()
        if let date = formatter.date(from: raw) { return date }
        formatter.formatOptions.insert(.withFractionalSeconds)
        return formatter.date(from: raw)
    }

    static func string(from date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }
}

private extension KeyedDecodingContainer {
    func decodeLossyArray<Element: Decodable>(
        _ type: Element.Type,
        forKey key: Key
    ) throws -> [Element] {
        let decoded = try decode(LossyArray<Element>.self, forKey: key)
        guard decoded.elementCount == 0 || !decoded.elements.isEmpty else {
            throw DecodingError.dataCorruptedError(
                forKey: key,
                in: self,
                debugDescription: "Nonempty collection contains no decodable rows"
            )
        }
        return decoded.elements
    }
}

/// Keeps one malformed item from discarding every otherwise valid row in a public feed.
private struct LossyArray<Element: Decodable>: Decodable {
    let elements: [Element]
    let elementCount: Int

    init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        var values: [Element] = []
        var elementCount = 0
        while !container.isAtEnd {
            elementCount += 1
            do {
                let value = try container.decode(Element.self)
                values.append(value)
            } catch let elementError {
                do {
                    _ = try container.decode(DiscardedJSON.self)
                } catch {
                    throw elementError
                }
            }
        }
        elements = values
        self.elementCount = elementCount
    }
}

/// A recursive JSON sink used only to advance a lossy unkeyed container past a bad element.
private struct DiscardedJSON: Decodable {
    private struct AnyKey: CodingKey {
        let stringValue: String
        let intValue: Int?
        init?(stringValue: String) { self.stringValue = stringValue; intValue = nil }
        init?(intValue: Int) { stringValue = String(intValue); self.intValue = intValue }
    }

    init(from decoder: Decoder) throws {
        if var array = try? decoder.unkeyedContainer() {
            while !array.isAtEnd { _ = try array.decode(DiscardedJSON.self) }
            return
        }
        if let object = try? decoder.container(keyedBy: AnyKey.self) {
            for key in object.allKeys { _ = try object.decode(DiscardedJSON.self, forKey: key) }
            return
        }
        let value = try decoder.singleValueContainer()
        if value.decodeNil() { return }
        if (try? value.decode(Bool.self)) != nil { return }
        if (try? value.decode(Double.self)) != nil { return }
        if (try? value.decode(String.self)) != nil { return }
        throw DecodingError.dataCorruptedError(in: value, debugDescription: "Unsupported JSON value")
    }
}
