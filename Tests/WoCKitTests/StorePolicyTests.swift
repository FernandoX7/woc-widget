import Foundation
import Testing
@testable import WoCKit

@Suite struct MarketFeedPolicyTests {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func policy() -> MarketFeedPolicy {
        MarketFeedPolicy(
            now: now,
            pricePollSeconds: 60,
            timerToleranceFraction: 0.1,
            requestTimeout: 12,
            candleFreshnessWindow: 300
        )
    }

    private func candles(
        lastSuccess: Date? = nil,
        lastAttempt: Date? = nil,
        errorMessage: String? = nil,
        isRefreshing: Bool = false,
        hasCandles: Bool = false,
        selectedInterval: CandleInterval = .fiveMin,
        loadedInterval: CandleInterval? = nil
    ) -> MarketFeedPolicy.CandleStatus {
        .init(
            lastSuccess: lastSuccess,
            lastAttempt: lastAttempt,
            errorMessage: errorMessage,
            isRefreshing: isRefreshing,
            hasCandles: hasCandles,
            selectedInterval: selectedInterval,
            loadedInterval: loadedInterval
        )
    }

    @Test func initialFeedsRemainIdleOrLoadingRatherThanUnavailable() {
        let loading = policy().evaluate(
            price: .init(lastSuccess: nil, errorMessage: nil, isRefreshing: true),
            candles: candles(isRefreshing: true)
        )
        #expect(loading.priceState == .loading)
        #expect(loading.candleState == .loading)
        #expect(loading.priceNeedsRefresh)
        #expect(loading.candlesNeedRefresh)
        #expect(loading.cachedAt == nil)
        #expect(loading.lastSuccess == nil)

        let idle = policy().evaluate(
            price: .init(lastSuccess: nil, errorMessage: nil, isRefreshing: false),
            candles: candles()
        )
        #expect(idle.priceState == .idle)
        #expect(idle.candleState == .idle)
    }

    @Test func exactFreshnessBoundariesAndFutureDatesRequireRefresh() {
        // Price freshness is 60 * 1.1 + 12 = 78 seconds; exact expiry is cached.
        let justFresh = policy().evaluate(
            price: .init(
                lastSuccess: now.addingTimeInterval(-77.999),
                errorMessage: nil,
                isRefreshing: false
            ),
            candles: candles(
                lastSuccess: now.addingTimeInterval(-299.999),
                lastAttempt: now.addingTimeInterval(-299.999),
                hasCandles: true,
                loadedInterval: .fiveMin
            )
        )
        #expect(justFresh.priceState == .live)
        #expect(justFresh.candleState == .live)
        #expect(!justFresh.priceNeedsRefresh)
        #expect(!justFresh.candlesNeedRefresh)

        let expired = policy().evaluate(
            price: .init(
                lastSuccess: now.addingTimeInterval(-78),
                errorMessage: nil,
                isRefreshing: false
            ),
            candles: candles(
                lastSuccess: now.addingTimeInterval(-300),
                lastAttempt: now.addingTimeInterval(-300),
                hasCandles: true,
                loadedInterval: .fiveMin
            )
        )
        #expect(expired.priceState == .cached)
        #expect(expired.candleState == .cached)
        #expect(expired.priceNeedsRefresh)
        #expect(expired.candlesNeedRefresh)

        let future = policy().evaluate(
            price: .init(
                lastSuccess: now.addingTimeInterval(1),
                errorMessage: nil,
                isRefreshing: false
            ),
            candles: candles(
                lastSuccess: now.addingTimeInterval(1),
                lastAttempt: now.addingTimeInterval(1),
                hasCandles: true,
                loadedInterval: .fiveMin
            )
        )
        #expect(future.priceState == .cached)
        #expect(future.candleState == .cached)
    }

    @Test func cachedTimestampBelongsOnlyToCachedFeedsAndUsesTheOldestOne() {
        let priceDate = now.addingTimeInterval(-20)
        let candleDate = now.addingTimeInterval(-200)
        let bothCached = policy().evaluate(
            price: .init(lastSuccess: priceDate, errorMessage: "offline", isRefreshing: false),
            candles: candles(
                lastSuccess: candleDate,
                lastAttempt: now,
                errorMessage: "offline",
                hasCandles: true,
                loadedInterval: .fiveMin
            )
        )
        #expect(bothCached.priceState == .cached)
        #expect(bothCached.candleState == .cached)
        #expect(bothCached.cachedAt == candleDate)
        #expect(bothCached.lastSuccess == candleDate)

        let onlyCandlesCached = policy().evaluate(
            price: .init(lastSuccess: priceDate, errorMessage: nil, isRefreshing: false),
            candles: candles(
                lastSuccess: candleDate,
                lastAttempt: now,
                hasCandles: true,
                selectedInterval: .oneHour,
                loadedInterval: .fiveMin
            )
        )
        #expect(onlyCandlesCached.priceState == .live)
        #expect(onlyCandlesCached.candleState == .cached)
        #expect(onlyCandlesCached.cachedAt == candleDate)
    }

    @Test func intervalMismatchNeedsRefreshButOnlyRealCachedBarsClaimCachedState() {
        let noBars = policy().evaluate(
            price: .init(lastSuccess: nil, errorMessage: nil, isRefreshing: false),
            candles: candles(
                lastSuccess: nil,
                lastAttempt: now,
                hasCandles: false,
                selectedInterval: .oneHour,
                loadedInterval: .fiveMin
            )
        )
        #expect(noBars.candlesNeedRefresh)
        #expect(noBars.candleState == .idle)

        let cachedBars = policy().evaluate(
            price: .init(lastSuccess: nil, errorMessage: nil, isRefreshing: false),
            candles: candles(
                lastSuccess: now,
                lastAttempt: now,
                hasCandles: true,
                selectedInterval: .oneHour,
                loadedInterval: .fiveMin
            )
        )
        #expect(cachedBars.candleState == .cached)
    }

    @Test func quoteSanitizationPreservesSpotAndDropsOnlyMalformedMetadata() {
        let trustedURL = URL(string: "https://dexscreener.com/solana/pair")!
        let quote = CryptoQuote(
            price: "0.0012300",
            change24h: -2.5,
            market: [
                .oneHour: CryptoMarketWindow(
                    changePercent: .nan,
                    buys: -1,
                    sells: 4,
                    volumeUSD: .infinity
                )
            ],
            liquidityUSD: -1,
            fullyDilutedValuationUSD: 2,
            marketCapUSD: .nan,
            pairURL: trustedURL
        )

        let result = MarketFeedPolicy.sanitizedQuote(quote)
        #expect(result?.price == "0.0012300")
        #expect(result?.change24h == -2.5)
        #expect(result?.market[.oneHour]?.changePercent == nil)
        #expect(result?.market[.oneHour]?.buys == nil)
        #expect(result?.market[.oneHour]?.sells == 4)
        #expect(result?.market[.oneHour]?.volumeUSD == nil)
        #expect(result?.liquidityUSD == nil)
        #expect(result?.fullyDilutedValuationUSD == 2)
        #expect(result?.marketCapUSD == nil)
        #expect(result?.pairURL == trustedURL)

        #expect(MarketFeedPolicy.sanitizedQuote(
            CryptoQuote(price: "0", change24h: 1)
        ) == nil)
        #expect(MarketFeedPolicy.sanitizedQuote(
            CryptoQuote(price: "1", change24h: .infinity)
        ) == nil)
        #expect(MarketFeedPolicy.sanitizedQuote(
            CryptoQuote(
                price: "1",
                change24h: 1,
                pairURL: URL(string: "https://example.com/not-the-market")
            )
        )?.pairURL == nil)
    }

    @Test func candleNormalizationSortsFiltersAndKeepsFirstDuplicate() {
        let earlier = now.addingTimeInterval(-300)
        let firstDuplicate = Candle(
            date: now, open: 1, high: 2, low: 0.5, close: 1.5, volume: 10)
        let laterDuplicate = Candle(
            date: now, open: 8, high: 9, low: 7, close: 8.5, volume: 20)
        let invalid = Candle(
            date: now.addingTimeInterval(-100), open: 2, high: 1, low: 0.5, close: 1.5)

        let result = MarketFeedPolicy.normalizedCandles([
            firstDuplicate,
            invalid,
            Candle(date: earlier, open: 1, high: 1, low: 1, close: 1),
            laterDuplicate,
        ])

        #expect(result.map(\.date) == [earlier, now])
        #expect(result.last == firstDuplicate)
    }
}

@Suite struct HistorySampleNormalizerTests {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    @Test func normalizationKeepsInclusiveBoundariesAndRepairsRepresentation() {
        let cutoff = now.addingTimeInterval(-100)
        let futureLimit = now.addingTimeInterval(10)
        let duplicateDate = now.addingTimeInterval(-20)
        let firstDuplicate = Sample(date: duplicateDate, count: 7)
        let invalidDate = Date(timeIntervalSinceReferenceDate: .nan)

        let result = HistorySampleNormalizer.normalize(
            [
                Sample(date: now.addingTimeInterval(-100.001), count: 1),
                firstDuplicate,
                Sample(date: cutoff, count: 2),
                Sample(date: duplicateDate, count: 99),
                Sample(date: now, count: -1),
                Sample(date: invalidDate, count: 3),
                Sample(date: futureLimit, count: 4),
                Sample(date: now.addingTimeInterval(10.001), count: 5),
            ],
            relativeTo: now,
            retentionWindow: 100,
            futureSampleTolerance: 10
        )

        #expect(result.map(\.date) == [cutoff, duplicateDate, futureLimit])
        #expect(result.map(\.count) == [2, 7, 4])
    }
}
