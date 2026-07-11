import Foundation

/// Fetches real OHLC candles for the $WOC price chart. Injectable; the live default talks to
/// GeckoTerminal (the same seam shape as `CryptoService`). The wire shape stays private to this file.
protocol CandleFetching: Sendable {
    /// `count` most-recent bars at the given width, oldest-first.
    func fetchCandles(interval: CandleInterval, count: Int) async throws -> [Candle]
}

struct GeckoTerminalService: CandleFetching {
    let http: HTTPClient
    let base: String
    let network: String
    let pool: String

    init(http: HTTPClient = URLSession.shared,
         base: String = AppConfig.API.geckoBase,
         network: String = AppConfig.API.geckoNetwork,
         pool: String = AppConfig.API.geckoPool) {
        self.http = http
        self.base = base
        self.network = network
        self.pool = pool
    }

    func fetchCandles(interval: CandleInterval, count: Int) async throws -> [Candle] {
        let decoded = try await http.fetchDecoded(GeckoOHLCVResponse.self, from: endpoint(interval: interval, count: count))
        return Self.candles(from: decoded)
    }

    /// `…/networks/{network}/pools/{pool}/ohlcv/{timeframe}?aggregate=&limit=&currency=usd`.
    /// `currency=usd` so the candles match the DexScreener `priceUsd` shown elsewhere. We deliberately
    /// omit `include_empty_intervals=true`: filling no-trade gaps reintroduces the degenerate flat
    /// zero-volume candles that switching to real OHLCV was meant to avoid (see `Candle`).
    func endpoint(interval: CandleInterval, count: Int) -> URL {
        var c = URLComponents(string: "\(base)/\(network)/pools/\(pool)/ohlcv/\(interval.timeframe)")!
        c.queryItems = [
            URLQueryItem(name: "aggregate", value: String(interval.aggregate)),
            URLQueryItem(name: "limit", value: String(count)),
            URLQueryItem(name: "currency", value: "usd"),
        ]
        return c.url!
    }

    /// Pure wire→domain mapping (GeckoTerminal returns newest-first; charts want oldest-first).
    /// Each row is `[unixSeconds, open, high, low, close, volume]`; malformed/impossible rows are
    /// dropped. Duplicate timestamps occasionally occur in the live feed; the first valid row in
    /// the API payload wins deterministically, then the result is sorted oldest-first.
    static func candles(from response: GeckoOHLCVResponse) -> [Candle] {
        var byTimestamp: [TimeInterval: Candle] = [:]
        for row in response.data.attributes.ohlcvList {
            guard row.count >= 5 else { continue }
            let candle = Candle(date: Date(timeIntervalSince1970: row[0]),
                                open: row[1], high: row[2], low: row[3], close: row[4],
                                volume: row.count > 5 ? row[5] : 0)
            guard candle.isValid, byTimestamp[row[0]] == nil else { continue }
            byTimestamp[row[0]] = candle
        }
        return byTimestamp.values.sorted { $0.date < $1.date }
    }
}

// MARK: - GeckoTerminal wire shape

struct GeckoOHLCVResponse: Decodable {
    let data: Node
    struct Node: Decodable { let attributes: Attributes }
    struct Attributes: Decodable {
        let ohlcvList: [[Double]]
        enum CodingKeys: String, CodingKey { case ohlcvList = "ohlcv_list" }
    }
}
