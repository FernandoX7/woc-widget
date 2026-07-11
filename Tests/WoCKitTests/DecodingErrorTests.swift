import Testing
import Foundation
@testable import WoCKit

@Suite struct StatusResponseDecodingTests {
    private func decode(_ json: String) throws -> StatusResponse {
        try JSONDecoder().decode(StatusResponse.self, from: Data(json.utf8))
    }

    @Test func distinguishesUnavailableRosterAndDefaultsOkTrueWhenAbsent() throws {
        let r = try decode(#"{"players_online": 42}"#)
        #expect(r.playersOnline == 42)
        #expect(r.names == nil)     // absent means the endpoint does not expose this capability
        #expect(r.hasRosterCapability == false)
        #expect(r.ok == true)       // hardened: missing ok → true (no false "down" on a healthy 200)
        #expect(r.realm == nil)
    }

    @Test func decodesFullResponse() throws {
        let r = try decode(#"{"ok": false, "realm": "Claudemoon", "players_online": 3, "names": ["a","b"]}"#)
        #expect(r.ok == false)
        #expect(r.realm == "Claudemoon")
        #expect(r.playersOnline == 3)
        #expect(r.names == ["a", "b"])
    }

    @Test func throwsWhenCoreCountMissing() {
        #expect(throws: (any Error).self) {
            _ = try decode(#"{"ok": true, "names": []}"#)
        }
    }

    @Test func optionalRosterTypeCanDriftButPresentStatusTypeMustBeTruthful() throws {
        let r = try decode(#"{"players_online": 4, "names": 5, "realm": "  Claudemoon  "}"#)
        #expect(r.playersOnline == 4)
        #expect(r.ok == true)       // absent ok still defaults true
        #expect(r.names == nil)     // wrong-typed names → capability unavailable
        #expect(r.realm == "Claudemoon")
        #expect(throws: (any Error).self) {
            _ = try decode(#"{"players_online": 4, "ok": "yes"}"#)
        }
    }

    @Test func throwsWhenCoreCountWrongType() {
        #expect(throws: (any Error).self) {
            _ = try decode(#"{"players_online": "lots"}"#)   // core count must be a real Int
        }
    }

    @Test func throwsWhenCoreCountIsNegative() {
        #expect(throws: (any Error).self) {
            _ = try decode(#"{"players_online": -1}"#)
        }
    }
}

@Suite struct FetchErrorTests {
    @Test func mapsTransportCodes() {
        #expect(friendly(FetchError.transport(URLError(.notConnectedToInternet))) == "No internet connection")
        #expect(friendly(FetchError.transport(URLError(.networkConnectionLost))) == "No internet connection")
        #expect(friendly(FetchError.transport(URLError(.timedOut))) == "Server timed out")
        #expect(friendly(FetchError.transport(URLError(.cannotFindHost))) == "Can't reach server")
        #expect(friendly(FetchError.transport(URLError(.dnsLookupFailed))) == "Can't reach server")
        #expect(friendly(FetchError.transport(URLError(.badServerResponse))) == "Connection error")
    }

    @Test func mapsHttpAndDecodeAndUnknown() {
        #expect(friendly(FetchError.http(503)) == "Connection error")   // matches the old non-200 message
        #expect(friendly(FetchError.decode) == "Couldn't load status")  // matches the old decode-failure message
        #expect(friendly(CancellationError()) == "Couldn't load status")
    }

    @Test func classifiesLocalAndRemoteFailuresForOutageConfirmation() {
        #expect(FetchError.transport(URLError(.notConnectedToInternet)).statusFailureKind == .localNetwork)
        #expect(FetchError.transport(URLError(.timedOut)).statusFailureKind == .timedOut)
        #expect(FetchError.http(503).statusFailureKind == .serverError)
        #expect(FetchError.http(401).statusFailureKind == .invalidResponse)
        #expect(FetchError.responseTooLarge(bytes: 3, maximum: 2).statusFailureKind
                == .invalidResponse)
        #expect(StatusFailureKind.timedOut.countsTowardOutageConfirmation)
        #expect(!StatusFailureKind.localNetwork.countsTowardOutageConfirmation)
    }
}

@Suite struct HTTPClientBoundaryTests {
    @Test func rejectsOversizedSuccessfulResponsesBeforeDecoding() async {
        let http = FakeHTTP(body: Data(
            repeating: 0x20, count: AppConfig.API.maximumResponseBytes + 1))
        await #expect(throws: FetchError.self) {
            let _: StatusResponse = try await http.fetchDecoded(
                StatusResponse.self, from: URL(string: "https://example.invalid")!)
        }
    }
}

/// Minimal `HTTPClient` returning canned bytes + status, so `CryptoService` decoding is testable
/// without the network.
struct FakeHTTP: HTTPClient {
    var body: Data
    var status: Int = 200
    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        let url = request.url ?? URL(string: "https://example.invalid")!
        let resp = HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil)!
        return (body, resp)
    }
}

@Suite struct CryptoServiceTests {
    private func service(_ json: String, status: Int = 200) -> CryptoService {
        CryptoService(http: FakeHTTP(body: Data(json.utf8), status: status),
                      endpoint: URL(string: "https://example.invalid")!)
    }

    @Test func decodesValidPair() async throws {
        let q = try await service(#"{"pair":{"priceUsd":"0.0005594","priceChange":{"h24":47.59}}}"#).fetchQuote()
        #expect(q.price == "0.0005594")
        #expect(q.change24h == 47.59)
    }

    @Test func throwsDecodeWhenPairMissing() async {
        await #expect(throws: FetchError.self) { _ = try await service(#"{"pair":null}"#).fetchQuote() }
    }

    @Test func mapsNon200ToError() async {
        await #expect(throws: FetchError.self) { _ = try await service("{}", status: 503).fetchQuote() }
    }
}

@Suite struct GeckoTerminalServiceTests {
    private func service(_ json: String, status: Int = 200) -> GeckoTerminalService {
        GeckoTerminalService(http: FakeHTTP(body: Data(json.utf8), status: status),
                             base: "https://example.invalid/networks", network: "solana", pool: "POOL")
    }

    @Test func decodesAndSortsCandlesOldestFirst() async throws {
        // GeckoTerminal returns newest-first; the service must flip to oldest-first for charting.
        let json = #"{"data":{"attributes":{"ohlcv_list":[[200,1.2,1.5,1.1,1.3,9],[100,1.0,1.1,0.9,1.05,8]]}}}"#
        let candles = try await service(json).fetchCandles(interval: .fiveMin, count: 60)
        #expect(candles.count == 2)
        #expect(candles[0].date == Date(timeIntervalSince1970: 100))   // oldest first
        #expect(candles[1].date == Date(timeIntervalSince1970: 200))
        #expect(candles[0].open == 1.0)
        #expect(candles[1].high == 1.5)
        #expect(candles[1].isUp == true)   // close 1.3 >= open 1.2
    }

    @Test func dropsMalformedRows() async throws {
        let json = #"{"data":{"attributes":{"ohlcv_list":[[100,1.0,1.1,0.9],[200,1.2,1.5,1.1,1.3,9]]}}}"#
        let candles = try await service(json).fetchCandles(interval: .fiveMin, count: 60)
        #expect(candles.count == 1)        // the 4-element row is dropped, the valid one kept
        #expect(candles[0].close == 1.3)
    }

    @Test func dropsInvalidOHLCAndDeduplicatesTimestampsDeterministically() async throws {
        let json = #"{"data":{"attributes":{"ohlcv_list":[[100,1.0,1.2,0.9,1.1,8],[100,2.0,2.2,1.9,2.1,9],[200,1.0,0.8,0.9,1.1,4],[300,0,1,1,1,1]]}}}"#
        let candles = try await service(json).fetchCandles(interval: .fiveMin, count: 60)
        #expect(candles.count == 1)
        #expect(candles[0].date == Date(timeIntervalSince1970: 100))
        #expect(candles[0].open == 1.0) // first valid duplicate wins
        #expect(candles[0].volume == 8)
    }

    @Test func mapsNon200ToError() async {
        await #expect(throws: FetchError.self) {
            _ = try await service("{}", status: 503).fetchCandles(interval: .oneHour, count: 10)
        }
    }

    @Test func buildsCaseSensitivePoolEndpointWithAggregateAndLimit() {
        let svc = GeckoTerminalService(http: FakeHTTP(body: Data()), base: "https://b/networks",
                                       network: "solana", pool: "PoOl")
        let url = svc.endpoint(interval: .fifteenMin, count: 42).absoluteString
        #expect(url.contains("/solana/pools/PoOl/ohlcv/minute"))   // 15m → minute timeframe, case preserved
        #expect(url.contains("aggregate=15"))
        #expect(url.contains("limit=42"))
        #expect(url.contains("currency=usd"))
    }

    @Test func hourTimeframeForLongCandles() {
        let svc = GeckoTerminalService(http: FakeHTTP(body: Data()), base: "https://b/networks",
                                       network: "solana", pool: "P")
        #expect(svc.endpoint(interval: .fourHour, count: 10).absoluteString.contains("ohlcv/hour"))
        #expect(svc.endpoint(interval: .fourHour, count: 10).absoluteString.contains("aggregate=4"))
    }
}
