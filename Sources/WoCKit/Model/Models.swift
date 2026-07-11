import Foundation

struct StatusResponse: Codable, Sendable {
    let ok: Bool
    let realm: String?
    let playersOnline: Int
    /// `nil` means this API deployment does not expose roster data. An explicit empty array means
    /// the capability exists and no names were returned. Keeping those states distinct prevents a
    /// privacy-disabled roster from being presented as "0 online" while the aggregate count is >0.
    let names: [String]?

    enum CodingKeys: String, CodingKey {
        case ok, realm, names
        case playersOnline = "players_online"
    }

    /// Direct (memberwise-style) init, used by preview seeding and tests.
    init(ok: Bool, realm: String?, playersOnline: Int, names: [String]? = nil) {
        self.ok = ok
        self.realm = realm
        self.playersOnline = max(0, playersOnline)
        self.names = names
    }

    var hasRosterCapability: Bool { names != nil }
}

// Hardened decoding (in an extension so the memberwise init above is preserved): only the core
// `players_online` count is required — a parseable 200 is always "up". `names` remains `nil`
// when absent and `ok` defaults to `true`. A present but wrong-typed `ok` is a schema failure rather
// than evidence of health; the store classifies that as an invalid response and never confirms an
// outage from it.
extension StatusResponse {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let players = try c.decode(Int.self, forKey: .playersOnline)
        guard players >= 0 else {
            throw DecodingError.dataCorruptedError(forKey: .playersOnline, in: c,
                                                   debugDescription: "players_online cannot be negative")
        }
        self.playersOnline = players
        self.names = try? c.decode([String].self, forKey: .names)
        self.ok = try c.decodeIfPresent(Bool.self, forKey: .ok) ?? true
        self.realm = try c.decodeIfPresent(String.self, forKey: .realm).flatMap { value in
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
    }
}

struct Sample: Codable, Identifiable, Sendable, Equatable {
    let date: Date
    let count: Int
    var id: Date { date }
}

enum Phase: Sendable { case loading, ok, error }

/// Truthful realm state. In particular, a successful `ok: true` response with zero players is
/// healthy, while a local connectivity problem is not conflated with a server-reported outage.
enum RealmAvailability: Sendable, Equatable {
    case loading
    case healthy
    case serverReportedDown
    case unreachable(StatusFailureKind)
}

enum StatusFailureKind: Sendable, Equatable {
    case localNetwork
    case timedOut
    case serverUnreachable
    case serverError
    case invalidResponse
    case unknown

    /// Only failures which can reasonably indicate a remote outage participate in down-alert
    /// confirmation. A disconnected Mac and a schema problem must never claim the realm is down.
    var countsTowardOutageConfirmation: Bool {
        switch self {
        case .timedOut, .serverUnreachable, .serverError: return true
        case .localNetwork, .invalidResponse, .unknown: return false
        }
    }
}

/// Feed state shared by the spot-price and candle metadata. The cached/unavailable distinction
/// lets views retain useful prior data without presenting it as live.
enum DataFeedState: Sendable, Equatable {
    case idle
    case loading
    case live
    case cached
    case unavailable
}

/// One OHLC candle for the $WOC price chart. Fetched ready-made from GeckoTerminal (a real
/// per-bar open/high/low/close), NOT synthesized from spot polls — synthesizing candles from the
/// slow DexScreener spot price produced degenerate dojis. USD-denominated to match the
/// `priceUsd` the header pill and menu-bar label render.
struct Candle: Identifiable, Sendable, Equatable {
    let date: Date          // bar open time
    let open: Double
    let high: Double
    let low: Double
    let close: Double
    let volume: Double
    var id: Date { date }
    var isUp: Bool { close >= open }

    init(date: Date, open: Double, high: Double, low: Double, close: Double,
         volume: Double = 0) {
        self.date = date
        self.open = open
        self.high = high
        self.low = low
        self.close = close
        self.volume = volume
    }

    /// Domain validation applied both at the network boundary and again in the store so injected
    /// services cannot poison chart scaling with NaN/Inf, negative prices, or impossible OHLC.
    var isValid: Bool {
        let timestamp = date.timeIntervalSince1970
        guard timestamp.isFinite, timestamp > 0,
              open.isFinite, high.isFinite, low.isFinite, close.isFinite,
              open > 0, high > 0, low > 0, close > 0,
              low <= min(open, close), high >= max(open, close), low <= high else { return false }
        return volume.isFinite && volume >= 0
    }
}
