import Foundation
import Testing
@testable import WoCKit

@Suite struct ExtendedCryptoServiceTests {
    private func service(_ json: String) -> CryptoService {
        CryptoService(
            http: FakeHTTP(body: Data(json.utf8)),
            endpoint: URL(string: "https://example.invalid/pair")!
        )
    }

    @Test func decodesEveryUsefulDexScreenerMarketField() async throws {
        let json = #"""
        {
          "pairs": [{
            "chainId": "solana",
            "pairAddress": "5wE9YJzPeQxCYL4jN9KhjTSR48Xzyh47xTAR9kg3wy1p",
            "baseToken": {
              "address": "3WjLscH2JsXLEFJZRA9z8ti8yRGxWGKbqymPd7UicRth",
              "name": "World Of Claudecraft",
              "symbol": "WOC"
            },
            "quoteToken": {
              "address": "So11111111111111111111111111111111111111112",
              "name": "Wrapped SOL",
              "symbol": "SOL"
            },
            "priceUsd": "0.0005666",
            "priceChange": {"m5": 0.23, "h1": -2.71, "h6": 15.76, "h24": 23.05},
            "txns": {
              "m5": {"buys": 1, "sells": 2},
              "h1": {"buys": 30, "sells": 22},
              "h6": {"buys": 314, "sells": 260},
              "h24": {"buys": 532, "sells": 516}
            },
            "volume": {"m5": 77.18, "h1": 6984.42, "h6": 50082.73, "h24": 84007.14},
            "liquidity": {"usd": 71161.77, "base": 62482164, "quote": 459.8154},
            "fdv": 566648,
            "marketCap": 566647.5,
            "url": "https://dexscreener.com/solana/pair-id"
          }]
        }
        """#

        let quote = try await service(json).fetchQuote()

        #expect(quote.price == "0.0005666")
        #expect(quote.change24h == 23.05) // original StatusStore-facing API remains intact
        #expect(quote.metrics(for: .fiveMinutes)?.changePercent == 0.23)
        #expect(quote.metrics(for: .oneHour)?.buys == 30)
        #expect(quote.metrics(for: .sixHours)?.sells == 260)
        #expect(quote.metrics(for: .twentyFourHours)?.transactionCount == 1048)
        #expect(quote.metrics(for: .twentyFourHours)?.volumeUSD == 84007.14)
        #expect(quote.liquidityUSD == 71161.77)
        #expect(quote.fullyDilutedValuationUSD == 566648)
        #expect(quote.marketCapUSD == 566647.5)
        #expect(quote.pairURL?.absoluteString == "https://dexscreener.com/solana/pair-id")
    }

    @Test func documentedPairsArrayTakesPrecedenceOverCompatibilityAlias() async throws {
        let json = #"""
        {
          "pairs": [{
            "chainId": "solana",
            "pairAddress": "5wE9YJzPeQxCYL4jN9KhjTSR48Xzyh47xTAR9kg3wy1p",
            "baseToken": {"address": "3WjLscH2JsXLEFJZRA9z8ti8yRGxWGKbqymPd7UicRth"},
            "quoteToken": {"address": "So11111111111111111111111111111111111111112"},
            "priceUsd": "1.25",
            "priceChange": {"h24": 5}
          }],
          "pair": {
            "priceUsd": "999",
            "priceChange": {"h24": 99}
          }
        }
        """#

        let quote = try await service(json).fetchQuote()
        #expect(quote.price == "1.25")
        #expect(quote.change24h == 5)
    }

    @Test func selectsConfiguredIdentityFromMultipleDocumentedPairs() async throws {
        let json = #"""
        {
          "pairs": [
            {
              "chainId": "solana",
              "pairAddress": "WrongPool11111111111111111111111111111111111",
              "baseToken": {"address": "WrongToken1111111111111111111111111111111111"},
              "quoteToken": {"address": "So11111111111111111111111111111111111111112"},
              "priceUsd": "900",
              "priceChange": {"h24": 90}
            },
            {
              "chainId": "SOLANA",
              "pairAddress": "5wE9YJzPeQxCYL4jN9KhjTSR48Xzyh47xTAR9kg3wy1p",
              "baseToken": {"address": "3WjLscH2JsXLEFJZRA9z8ti8yRGxWGKbqymPd7UicRth"},
              "quoteToken": {"address": "So11111111111111111111111111111111111111112"},
              "priceUsd": "0.75",
              "priceChange": {"h24": -4}
            }
          ]
        }
        """#

        let quote = try await service(json).fetchQuote()
        #expect(quote.price == "0.75")
        #expect(quote.change24h == -4)
    }

    @Test func rejectsDocumentedPairWithConflictingConfiguredIdentity() async {
        let wrongIdentities = [
            #""chainId":"ethereum","pairAddress":"5wE9YJzPeQxCYL4jN9KhjTSR48Xzyh47xTAR9kg3wy1p","baseToken":{"address":"3WjLscH2JsXLEFJZRA9z8ti8yRGxWGKbqymPd7UicRth"},"quoteToken":{"address":"So11111111111111111111111111111111111111112"}"#,
            #""chainId":"solana","pairAddress":"WrongPool11111111111111111111111111111111111","baseToken":{"address":"3WjLscH2JsXLEFJZRA9z8ti8yRGxWGKbqymPd7UicRth"},"quoteToken":{"address":"So11111111111111111111111111111111111111112"}"#,
            #""chainId":"solana","pairAddress":"5wE9YJzPeQxCYL4jN9KhjTSR48Xzyh47xTAR9kg3wy1p","baseToken":{"address":"WrongToken1111111111111111111111111111111111"},"quoteToken":{"address":"So11111111111111111111111111111111111111112"}"#
        ]

        for identity in wrongIdentities {
            let json = #"{"pairs":[{\#(identity),"priceUsd":"1","priceChange":{"h24":1}}]}"#
            await #expect(throws: FetchError.self) {
                _ = try await service(json).fetchQuote()
            }
        }
    }

    @Test func fallsBackToMatchingCompatibilityPairWhenArrayHasNoMatch() async throws {
        let json = #"""
        {
          "pairs": [{
            "chainId": "ethereum",
            "pairAddress": "WrongPool11111111111111111111111111111111111",
            "baseToken": {"address": "WrongToken1111111111111111111111111111111111"},
            "quoteToken": {"address": "OtherToken1111111111111111111111111111111111"},
            "priceUsd": "900",
            "priceChange": {"h24": 90}
          }],
          "pair": {
            "chainId": "solana",
            "pairAddress": "5wE9YJzPeQxCYL4jN9KhjTSR48Xzyh47xTAR9kg3wy1p",
            "baseToken": {"address": "3WjLscH2JsXLEFJZRA9z8ti8yRGxWGKbqymPd7UicRth"},
            "quoteToken": {"address": "So11111111111111111111111111111111111111112"},
            "priceUsd": "0.50",
            "priceChange": {"h24": 3}
          }
        }
        """#

        let quote = try await service(json).fetchQuote()
        #expect(quote.price == "0.50")
        #expect(quote.change24h == 3)
    }

    @Test func malformedAncillaryFieldsDoNotDiscardCoreQuote() async throws {
        let json = #"""
        {
          "pair": {
            "priceUsd": "1.23",
            "priceChange": {"m5": "unknown", "h1": 2, "h24": 4.5},
            "txns": {"h1": {"buys": "many", "sells": 3}, "h24": false},
            "volume": {"h1": "unknown", "h24": 120},
            "liquidity": {"usd": "unknown"},
            "fdv": "unknown",
            "marketCap": null,
            "url": "not-a-canonical-web-url"
          }
        }
        """#

        let quote = try await service(json).fetchQuote()

        #expect(quote.price == "1.23")
        #expect(quote.change24h == 4.5)
        #expect(quote.metrics(for: .fiveMinutes)?.changePercent == nil)
        #expect(quote.metrics(for: .oneHour)?.buys == nil)
        #expect(quote.metrics(for: .oneHour)?.sells == 3)
        #expect(quote.metrics(for: .twentyFourHours)?.volumeUSD == 120)
        #expect(quote.liquidityUSD == nil)
        #expect(quote.fullyDilutedValuationUSD == nil)
        #expect(quote.marketCapUSD == nil)
        #expect(quote.pairURL == nil)
    }

    @Test func marketNavigationRejectsUnexpectedOrInsecureOrigins() async throws {
        for url in ["http://dexscreener.com/solana/pair", "https://example.com/pair"] {
            let json = #"{"pair":{"priceUsd":"1","priceChange":{"h24":1},"url":"\#(url)"}}"#
            #expect(try await service(json).fetchQuote().pairURL == nil)
        }
    }

    @Test func transactionCountIsNilWhenTheWindowHasNoTransactionData() {
        let absent = CryptoMarketWindow(changePercent: 2, buys: nil, sells: nil, volumeUSD: 3)
        let partial = CryptoMarketWindow(changePercent: nil, buys: 4, sells: nil, volumeUSD: nil)
        #expect(absent.transactionCount == nil)
        #expect(partial.transactionCount == 4)
        #expect(CryptoMarketWindow(changePercent: nil, buys: .max, sells: 1, volumeUSD: nil)
            .transactionCount == .max)
    }
}
