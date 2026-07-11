import Foundation

/// A DexScreener activity window. Every ancillary value is optional because young or thinly
/// traded pairs do not always receive a complete set of rolling-window statistics.
struct CryptoMarketWindow: Sendable, Equatable {
    let changePercent: Double?
    let buys: Int?
    let sells: Int?
    let volumeUSD: Double?

    var transactionCount: Int? {
        guard buys != nil || sells != nil else { return nil }
        let sum = (buys ?? 0).addingReportingOverflow(sells ?? 0)
        return sum.overflow ? .max : sum.partialValue
    }
}

enum CryptoMarketTimeframe: String, CaseIterable, CodingKey, Sendable {
    case fiveMinutes = "m5"
    case oneHour = "h1"
    case sixHours = "h6"
    case twentyFourHours = "h24"
}

/// Domain value the store consumes — the DexScreener wire shape stays private to this file.
/// `price` and `change24h` deliberately preserve the original API used by `StatusStore`; the
/// remaining fields let richer market UI be added without another endpoint or request.
struct CryptoQuote: Sendable, Equatable {
    let price: String       // kept as the exact String the UI renders (e.g. "0.0005594")
    let change24h: Double
    let market: [CryptoMarketTimeframe: CryptoMarketWindow]
    let liquidityUSD: Double?
    let fullyDilutedValuationUSD: Double?
    let marketCapUSD: Double?
    let pairURL: URL?

    init(
        price: String,
        change24h: Double,
        market: [CryptoMarketTimeframe: CryptoMarketWindow] = [:],
        liquidityUSD: Double? = nil,
        fullyDilutedValuationUSD: Double? = nil,
        marketCapUSD: Double? = nil,
        pairURL: URL? = nil
    ) {
        self.price = price
        self.change24h = change24h
        self.market = market
        self.liquidityUSD = liquidityUSD
        self.fullyDilutedValuationUSD = fullyDilutedValuationUSD
        self.marketCapUSD = marketCapUSD
        self.pairURL = pairURL
    }

    func metrics(for timeframe: CryptoMarketTimeframe) -> CryptoMarketWindow? {
        market[timeframe]
    }
}

/// Fetches the $WOC price. Injectable; the live default talks to `AppConfig.API.cryptoURL`.
protocol CryptoFetching: Sendable {
    func fetchQuote() async throws -> CryptoQuote
}

struct CryptoService: CryptoFetching {
    let http: HTTPClient
    let endpoint: URL
    private let expectedChainID: String
    private let expectedPairAddress: String
    private let expectedTokenAddress: String

    init(
        http: HTTPClient = URLSession.shared,
        endpoint: URL = AppConfig.API.cryptoURL,
        expectedChainID: String = AppConfig.API.dexChain,
        expectedPairAddress: String = AppConfig.API.dexCanonicalPairAddress,
        expectedTokenAddress: String = AppConfig.API.dexTokenAddress
    ) {
        self.http = http
        self.endpoint = endpoint
        self.expectedChainID = expectedChainID
        self.expectedPairAddress = expectedPairAddress
        self.expectedTokenAddress = expectedTokenAddress
    }

    func fetchQuote() async throws -> CryptoQuote {
        let decoded = try await http.fetchDecoded(DexScreenerResponse.self, from: endpoint)
        guard let pair = decoded.selectPair(
            chainID: expectedChainID,
            pairAddress: expectedPairAddress,
            tokenAddress: expectedTokenAddress
        ) else {
            #if DEBUG
            print("[WoCKit] crypto: response contained no pair matching the configured market")
            #endif
            throw FetchError.decode
        }
        guard let change24h = pair.priceChange[.twentyFourHours] else {
            #if DEBUG
            print("[WoCKit] crypto: pair contained no numeric 24-hour change")
            #endif
            throw FetchError.decode
        }
        let market = Dictionary(uniqueKeysWithValues: CryptoMarketTimeframe.allCases.map { timeframe in
            let transactions = pair.transactions?[timeframe]
            return (
                timeframe,
                CryptoMarketWindow(
                    changePercent: pair.priceChange[timeframe],
                    buys: transactions?.buys,
                    sells: transactions?.sells,
                    volumeUSD: pair.volume?[timeframe]
                )
            )
        })

        return CryptoQuote(
            price: pair.priceUsd,
            change24h: change24h,
            market: market,
            liquidityUSD: pair.liquidity?.usd,
            fullyDilutedValuationUSD: pair.fdv,
            marketCapUSD: pair.marketCap,
            pairURL: AppConfig.API.validatedMarketURL(pair.url.flatMap(URL.init(string:)))
        )
    }
}

// MARK: - DexScreener wire shape (private)

private struct DexScreenerResponse: Decodable {
    /// `pairs` is DexScreener's documented response. `pair` remains a compatibility fallback
    /// because the live endpoint currently emits both and older fixtures/servers may emit one.
    let pairs: [DexPair]
    let pair: DexPair?

    private enum CodingKeys: String, CodingKey { case pairs, pair }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        pairs = (try? c.decode([DexPair].self, forKey: .pairs)) ?? []
        pair = try? c.decode(DexPair.self, forKey: .pair)
    }

    func selectPair(chainID: String, pairAddress: String, tokenAddress: String) -> DexPair? {
        // Prefer the documented array even while the compatibility alias is present. Within a
        // multi-pair response, the most completely verified candidate wins rather than API order.
        if let official = bestMatch(
            in: pairs,
            chainID: chainID,
            pairAddress: pairAddress,
            tokenAddress: tokenAddress
        ) {
            return official
        }

        guard let pair,
              pair.identityMatchScore(
                chainID: chainID,
                pairAddress: pairAddress,
                tokenAddress: tokenAddress
              ) != nil else { return nil }
        return pair
    }

    private func bestMatch(
        in candidates: [DexPair],
        chainID: String,
        pairAddress: String,
        tokenAddress: String
    ) -> DexPair? {
        candidates.compactMap { candidate -> (pair: DexPair, score: Int)? in
            guard let score = candidate.identityMatchScore(
                chainID: chainID,
                pairAddress: pairAddress,
                tokenAddress: tokenAddress
            ) else { return nil }
            return (candidate, score)
        }
        .max { $0.score < $1.score }?
        .pair
    }
}

private struct DexPair: Decodable {
    let chainId: String?
    let pairAddress: String?
    let baseToken: DexToken?
    let quoteToken: DexToken?
    let priceUsd: String
    let priceChange: DexRollingValues<Double>
    let transactions: DexRollingValues<DexTransactionCount>?
    let volume: DexRollingValues<Double>?
    let liquidity: DexLiquidity?
    let fdv: Double?
    let marketCap: Double?
    let url: String?

    enum CodingKeys: String, CodingKey {
        case chainId, pairAddress, baseToken, quoteToken
        case priceUsd, priceChange, volume, liquidity, fdv, marketCap, url
        case transactions = "txns"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        chainId = try? c.decode(String.self, forKey: .chainId)
        pairAddress = try? c.decode(String.self, forKey: .pairAddress)
        baseToken = try? c.decode(DexToken.self, forKey: .baseToken)
        quoteToken = try? c.decode(DexToken.self, forKey: .quoteToken)
        priceUsd = try c.decode(String.self, forKey: .priceUsd)
        priceChange = try c.decode(DexRollingValues<Double>.self, forKey: .priceChange)
        transactions = try? c.decode(DexRollingValues<DexTransactionCount>.self, forKey: .transactions)
        volume = try? c.decode(DexRollingValues<Double>.self, forKey: .volume)
        liquidity = try? c.decode(DexLiquidity.self, forKey: .liquidity)
        fdv = try? c.decode(Double.self, forKey: .fdv)
        marketCap = try? c.decode(Double.self, forKey: .marketCap)
        url = try? c.decode(String.self, forKey: .url)
    }

    /// Returns nil for a definite identity mismatch. Missing legacy fields are tolerated because
    /// they provide no evidence either way; present identifiers add confidence to selection.
    func identityMatchScore(chainID: String, pairAddress expectedPair: String,
                            tokenAddress expectedToken: String) -> Int? {
        var score = 0

        if let chainId {
            guard chainId.caseInsensitiveCompare(chainID) == .orderedSame else { return nil }
            score += 1
        }
        if let pairAddress {
            guard pairAddress == expectedPair else { return nil }
            score += 4
        }

        let baseAddress = baseToken?.address
        let quoteAddress = quoteToken?.address
        if baseAddress == expectedToken || quoteAddress == expectedToken {
            score += 2
        } else if baseAddress != nil, quoteAddress != nil {
            // Both sides are known, so the configured token is definitively absent.
            return nil
        }

        return score
    }
}

private struct DexToken: Decodable {
    let address: String
}

private struct DexTransactionCount: Decodable {
    let buys: Int?
    let sells: Int?

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        buys = try? c.decode(Int.self, forKey: .buys)
        sells = try? c.decode(Int.self, forKey: .sells)
    }

    private enum CodingKeys: String, CodingKey { case buys, sells }
}

private struct DexRollingValues<Value: Decodable>: Decodable {
    let m5: Value?
    let h1: Value?
    let h6: Value?
    let h24: Value?

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CryptoMarketTimeframe.self)
        m5 = try? c.decode(Value.self, forKey: .fiveMinutes)
        h1 = try? c.decode(Value.self, forKey: .oneHour)
        h6 = try? c.decode(Value.self, forKey: .sixHours)
        h24 = try? c.decode(Value.self, forKey: .twentyFourHours)
    }

    subscript(_ timeframe: CryptoMarketTimeframe) -> Value? {
        switch timeframe {
        case .fiveMinutes: m5
        case .oneHour: h1
        case .sixHours: h6
        case .twentyFourHours: h24
        }
    }
}

private struct DexLiquidity: Decodable {
    let usd: Double?

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        usd = try? c.decode(Double.self, forKey: .usd)
    }

    private enum CodingKeys: String, CodingKey { case usd }
}
