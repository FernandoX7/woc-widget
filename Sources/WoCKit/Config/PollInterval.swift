import Foundation

/// The selectable poll intervals, mirroring `ChartInterval`/`ChartRange` so the settings pickers
/// iterate a typed list instead of ad-hoc inline arrays. The picker binds to a `TimeInterval`
/// (`pollSeconds`/`cryptoPollSeconds`), so each option tags its `.seconds`.
enum PollInterval: Int, CaseIterable, Identifiable {
    case tenSeconds = 10
    case thirtySeconds = 30
    case oneMinute = 60
    case fiveMinutes = 300
    case fifteenMinutes = 900

    var id: Int { rawValue }
    var seconds: TimeInterval { TimeInterval(rawValue) }
    var label: String {
        AppText.compactDuration(seconds: rawValue)
    }

    /// Player-refresh options: 10s / 30s / 1m / 5m.
    static let playerOptions: [PollInterval] = [.tenSeconds, .thirtySeconds, .oneMinute, .fiveMinutes]
    /// Crypto-refresh options: 30s / 1m / 5m / 15m.
    static let cryptoOptions: [PollInterval] = [.thirtySeconds, .oneMinute, .fiveMinutes, .fifteenMinutes]

    /// Coerces persisted/caller-provided numeric values onto an actual picker option. Values below
    /// the minimum land on the minimum; other unsupported finite values choose the nearest option
    /// (ties prefer the lower-power, longer interval). NaN/Inf fall back to the supplied default.
    static func normalize(_ seconds: TimeInterval,
                          options: [PollInterval],
                          default defaultInterval: PollInterval) -> TimeInterval {
        guard seconds.isFinite, !options.isEmpty else { return defaultInterval.seconds }
        return options.min { lhs, rhs in
            let leftDistance = abs(lhs.seconds - seconds)
            let rightDistance = abs(rhs.seconds - seconds)
            if leftDistance == rightDistance { return lhs.seconds > rhs.seconds }
            return leftDistance < rightDistance
        }?.seconds ?? defaultInterval.seconds
    }
}
