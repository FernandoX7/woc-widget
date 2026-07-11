import Foundation

/// Pure validation and freshness policy for the two independent $WOC market feeds.
///
/// Keeping this outside `StatusStore` makes the boundary rules deterministic and directly
/// testable without constructing a main-actor store. It deliberately owns no timers, tasks, or
/// mutable state; the store remains the sole coordinator of network requests and observations.
struct MarketFeedPolicy: Sendable {
    struct PriceStatus: Sendable {
        let lastSuccess: Date?
        let errorMessage: String?
        let isRefreshing: Bool
    }

    struct CandleStatus: Sendable {
        let lastSuccess: Date?
        let lastAttempt: Date?
        let errorMessage: String?
        let isRefreshing: Bool
        let hasCandles: Bool
        let selectedInterval: CandleInterval
        let loadedInterval: CandleInterval?
    }

    struct Snapshot: Sendable, Equatable {
        let priceState: DataFeedState
        let candleState: DataFeedState
        let cachedAt: Date?
        let lastSuccess: Date?
        let priceNeedsRefresh: Bool
        let candlesNeedRefresh: Bool
    }

    let now: Date
    let priceFreshnessWindow: TimeInterval
    let candleFreshnessWindow: TimeInterval

    init(
        now: Date,
        pricePollSeconds: TimeInterval,
        timerToleranceFraction: Double = AppConfig.Poll.timerToleranceFraction,
        requestTimeout: TimeInterval = AppConfig.API.requestTimeout,
        candleFreshnessWindow: TimeInterval = AppConfig.Crypto.visibleCandleRefreshSeconds
    ) {
        self.now = now
        self.priceFreshnessWindow = pricePollSeconds * (1 + timerToleranceFraction)
            + requestTimeout
        self.candleFreshnessWindow = candleFreshnessWindow
    }

    func evaluate(price: PriceStatus, candles: CandleStatus) -> Snapshot {
        let priceIsStale = isStale(since: price.lastSuccess, window: priceFreshnessWindow)
        let priceNeedsRefresh = price.errorMessage != nil || priceIsStale

        let intervalsMatch = candles.loadedInterval == candles.selectedInterval
        let hasCachedCandlesForDifferentInterval = candles.hasCandles
            && candles.loadedInterval != nil
            && !intervalsMatch
        let candlesNeedRefresh = !intervalsMatch
            || isStale(since: candles.lastAttempt, window: candleFreshnessWindow)

        let priceState: DataFeedState
        if price.errorMessage != nil {
            priceState = price.lastSuccess == nil ? .unavailable : .cached
        } else if price.lastSuccess != nil {
            priceState = priceIsStale ? .cached : .live
        } else {
            priceState = price.isRefreshing ? .loading : .idle
        }

        let candleState: DataFeedState
        if candles.errorMessage != nil || hasCachedCandlesForDifferentInterval {
            candleState = candles.lastSuccess == nil ? .unavailable : .cached
        } else if candles.lastSuccess != nil {
            candleState = candlesNeedRefresh ? .cached : .live
        } else {
            candleState = candles.isRefreshing ? .loading : .idle
        }

        var cachedDates: [Date] = []
        if priceState == .cached, let lastSuccess = price.lastSuccess {
            cachedDates.append(lastSuccess)
        }
        if candleState == .cached, let lastSuccess = candles.lastSuccess {
            cachedDates.append(lastSuccess)
        }

        return Snapshot(
            priceState: priceState,
            candleState: candleState,
            cachedAt: cachedDates.min(),
            lastSuccess: [price.lastSuccess, candles.lastSuccess].compactMap { $0 }.min(),
            priceNeedsRefresh: priceNeedsRefresh,
            candlesNeedRefresh: candlesNeedRefresh
        )
    }

    /// A missing timestamp is stale by definition. Future timestamps are also stale so a clock
    /// correction cannot suppress refreshes indefinitely. The exact boundary is intentionally
    /// stale (`>=`), matching the polling policy used before this extraction.
    private func isStale(since date: Date?, window: TimeInterval) -> Bool {
        guard let date else { return true }
        let age = now.timeIntervalSince(date)
        return age < 0 || age >= window
    }

    /// Validates an injected/network quote while retaining a valid spot price if only optional
    /// market metadata is malformed.
    static func sanitizedQuote(_ quote: CryptoQuote) -> CryptoQuote? {
        guard let price = Double(quote.price), price.isFinite, price > 0,
              quote.change24h.isFinite else { return nil }

        var market: [CryptoMarketTimeframe: CryptoMarketWindow] = [:]
        for (timeframe, window) in quote.market {
            let change = window.changePercent.flatMap { $0.isFinite ? $0 : nil }
            let buys = window.buys.flatMap { $0 >= 0 ? $0 : nil }
            let sells = window.sells.flatMap { $0 >= 0 ? $0 : nil }
            let volume = window.volumeUSD.flatMap { $0.isFinite && $0 >= 0 ? $0 : nil }
            market[timeframe] = CryptoMarketWindow(
                changePercent: change,
                buys: buys,
                sells: sells,
                volumeUSD: volume
            )
        }

        func nonnegativeFinite(_ value: Double?) -> Double? {
            value.flatMap { $0.isFinite && $0 >= 0 ? $0 : nil }
        }

        return CryptoQuote(
            price: quote.price,
            change24h: quote.change24h,
            market: market,
            liquidityUSD: nonnegativeFinite(quote.liquidityUSD),
            fullyDilutedValuationUSD: nonnegativeFinite(quote.fullyDilutedValuationUSD),
            marketCapUSD: nonnegativeFinite(quote.marketCapUSD),
            pairURL: AppConfig.API.validatedMarketURL(quote.pairURL)
        )
    }

    /// Removes invalid and duplicate candles and returns the stable oldest-first representation
    /// expected by chart consumers. The first candle for a timestamp deterministically wins.
    static func normalizedCandles(_ input: [Candle]) -> [Candle] {
        var byDate: [Date: Candle] = [:]
        for candle in input where candle.isValid && byDate[candle.date] == nil {
            byDate[candle.date] = candle
        }
        return byDate.values.sorted { $0.date < $1.date }
    }
}
