import Foundation

enum ChartInterval: Int, CaseIterable, Identifiable {
    case oneMin = 60
    case fiveMin = 300
    case fifteenMin = 900
    case thirtyMin = 1800
    case oneHour = 3600

    var id: Int { rawValue }
    var seconds: TimeInterval { TimeInterval(rawValue) }
    var label: String {
        AppText.compactDuration(seconds: rawValue)
    }
}

/// Candle width for the $WOC chart. Independent of the player chart's `ChartInterval` so the two
/// charts never share state, and constrained to the timeframes GeckoTerminal actually serves
/// (minute 1/5/15, hour 1/4) — a button can't request a candle the API can't produce. The visible
/// window follows from `AppConfig.Crypto.candleCount` bars at the chosen width. `rawValue` is the
/// bar's duration in seconds (the persisted key); `label` resolves through the shared localized
/// compact-duration vocabulary.
enum CandleInterval: Int, CaseIterable, Identifiable {
    case oneMin = 60
    case fiveMin = 300
    case fifteenMin = 900
    case oneHour = 3600
    case fourHour = 14400

    var id: Int { rawValue }
    var seconds: TimeInterval { TimeInterval(rawValue) }

    /// GeckoTerminal `ohlcv/{timeframe}` path segment.
    var timeframe: String {
        switch self {
        case .oneMin, .fiveMin, .fifteenMin: return "minute"
        case .oneHour, .fourHour: return "hour"
        }
    }

    /// GeckoTerminal `aggregate` query value (bars per `timeframe` unit).
    var aggregate: Int {
        switch self {
        case .oneMin: return 1
        case .fiveMin: return 5
        case .fifteenMin: return 15
        case .oneHour: return 1
        case .fourHour: return 4
        }
    }

    var label: String {
        AppText.compactDuration(seconds: rawValue)
    }
}

/// How far back the chart looks. Combined with `ChartInterval` (the bucket size).
enum ChartRange: Int, CaseIterable, Identifiable {
    case oneHour = 3600
    case sixHours = 21600
    case day = 86400
    case week = 604800

    var id: Int { rawValue }
    var seconds: TimeInterval { TimeInterval(rawValue) }
    var label: String {
        AppText.compactDuration(seconds: rawValue)
    }
}

extension ChartInterval {
    /// Smallest named resolution that stays within the chart's point budget for a full range.
    /// Choosing from the labels the UI can actually explain avoids claiming an opaque 72-second
    /// or 33.6-minute average when automatic downsampling is active.
    static func automatic(for range: ChartRange) -> ChartInterval {
        allCases.first {
            range.seconds / $0.seconds <= AppConfig.History.chartMaxPoints
        } ?? .oneHour
    }
}
