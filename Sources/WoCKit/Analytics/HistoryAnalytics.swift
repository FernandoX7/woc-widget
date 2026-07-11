import Foundation

struct RealmRhythm: Sendable, Equatable {
    let sampleCount: Int
    let observedDuration: TimeInterval
    let coverageFraction: Double
    let currentPercentile: Int?
}

/// Pure, clock-injected analytics over a sample array — the prime deterministic test surface.
/// The bucket math (`max(interval.seconds, range.seconds / chartMaxPoints)`, the 300-point cap)
/// and `todayPeak` are byte-identical to the original `StatusStore` implementations; the only
/// change is that "now" is injected rather than read from `Date()` directly.
struct HistoryAnalytics {
    let samples: [Sample]
    var now: () -> Date = Date.init
    var calendar: Calendar = .current

    /// Samples within `range`, bucketed by `interval` (mean per bucket). The bucket auto-coarsens
    /// so the plot never exceeds ~`chartMaxPoints` points.
    func series(range: ChartRange, interval: ChartInterval) -> [Sample] {
        guard !samples.isEmpty else { return [] }
        let referenceDate = now()
        let start = referenceDate.addingTimeInterval(-range.seconds)
        let windowed = samples.filter { $0.date >= start }
        guard !windowed.isEmpty else { return [] }

        let bucket = max(interval.seconds, range.seconds / AppConfig.History.chartMaxPoints)
        var buckets: [TimeInterval: (sum: Double, n: Int)] = [:]
        for s in windowed {
            let key = (s.date.timeIntervalSince1970 / bucket).rounded(.down) * bucket
            var e = buckets[key] ?? (0, 0)
            e.sum += Double(s.count)
            e.n += 1
            buckets[key] = e
        }
        return buckets.map { key, v in
            Sample(date: Date(timeIntervalSince1970: key),
                   count: Self.clampedRoundedInteger(v.sum / Double(v.n)))
        }
        .sorted { $0.date < $1.date }
    }

    /// Peak count seen so far today; `fallback` (the live count) when today has no samples.
    func todayPeak(fallback: Int) -> Int {
        let referenceDate = now()
        return samples.filter { calendar.isDate($0.date, inSameDayAs: referenceDate) }
            .map(\.count).max() ?? fallback
    }

    /// Samples older than this are pruned (a 7-day retention window back from now).
    func retentionCutoff() -> Date { now().addingTimeInterval(-AppConfig.History.retentionWindow) }

    /// Mean of an already-bucketed series (rounded); `nil` when empty. Keeps the stats-row average
    /// in the same tested value type as the rest of the numeric logic.
    static func average(of series: [Sample]) -> Int? {
        guard !series.isEmpty else { return nil }
        let total = series.reduce(0.0) { $0 + Double($1.count) }
        return clampedRoundedInteger(total / Double(series.count))
    }

    /// Difference from an observation near the target time. The tolerance is explicit so callers
    /// can account for their real sampling cadence without accepting an arbitrarily old baseline.
    func change(over window: TimeInterval, currentCount: Int,
                baselineTolerance: TimeInterval) -> Int? {
        guard window.isFinite, window >= 0,
              baselineTolerance.isFinite, baselineTolerance >= 0 else { return nil }
        let target = now().addingTimeInterval(-window)
        guard let baseline = samples.min(by: { lhs, rhs in
            let left = abs(lhs.date.timeIntervalSince(target))
            let right = abs(rhs.date.timeIntervalSince(target))
            if left == right { return lhs.date > rhs.date }
            return left < right
        }), abs(baseline.date.timeIntervalSince(target)) <= baselineTolerance else { return nil }

        let difference = currentCount.subtractingReportingOverflow(baseline.count)
        guard !difference.overflow else { return currentCount >= baseline.count ? .max : .min }
        return difference.partialValue
    }

    /// Honest local-observation context for the selected range. Coverage is derived from the number
    /// of distinct successful samples and the real configured poll cadence, capped at the requested
    /// window. The percentile uses a midpoint rank so an entirely flat history reads as the 50th
    /// percentile rather than misleadingly claiming the current count beats every observation.
    func realmRhythm(range: ChartRange, currentCount: Int,
                     expectedSampleInterval: TimeInterval) -> RealmRhythm {
        let referenceDate = now()
        let start = referenceDate.addingTimeInterval(-range.seconds)
        let ordered = samples
            .filter { $0.date >= start && $0.date <= referenceDate && $0.count >= 0 }
            .sorted { $0.date < $1.date }
        var seenDates = Set<Date>()
        let windowed = ordered.filter { seenDates.insert($0.date).inserted }

        let cadence = expectedSampleInterval.isFinite && expectedSampleInterval > 0
            ? expectedSampleInterval : 0
        let observed = min(range.seconds, Double(windowed.count) * cadence)
        let coverage = range.seconds > 0 ? min(1, max(0, observed / range.seconds)) : 0

        let percentile: Int?
        if windowed.count >= AppConfig.History.rhythmMinimumSamples {
            let below = windowed.reduce(into: 0) { if $1.count < currentCount { $0 += 1 } }
            let equal = windowed.reduce(into: 0) { if $1.count == currentCount { $0 += 1 } }
            let midpointRank = (Double(below) + Double(equal) * 0.5) / Double(windowed.count)
            percentile = min(100, max(0, Int((midpointRank * 100).rounded())))
        } else {
            percentile = nil
        }

        return RealmRhythm(sampleCount: windowed.count, observedDuration: observed,
                           coverageFraction: coverage, currentPercentile: percentile)
    }

    private static func clampedRoundedInteger(_ value: Double) -> Int {
        guard value.isFinite else { return value.sign == .minus ? .min : .max }
        let rounded = value.rounded()
        // `Double(Int.max)` rounds to 2^63 on 64-bit platforms, so equality must clamp too.
        if rounded >= Double(Int.max) { return .max }
        if rounded <= Double(Int.min) { return .min }
        return Int(rounded)
    }
}

/// One history observation plus the continuous segment it belongs to. Keeping segmentation in
/// WoCKit makes the chart's no-fabricated-gaps rule deterministic and independently testable.
struct SegmentedHistorySample: Sendable, Equatable {
    let sample: Sample
    let segment: Int
}

enum HistorySegmentation {
    static func segment(_ samples: [Sample], bucketInterval: TimeInterval,
                        expectedSampleInterval: TimeInterval) -> [SegmentedHistorySample] {
        let ordered = samples.enumerated().sorted { lhs, rhs in
            if lhs.element.date == rhs.element.date { return lhs.offset < rhs.offset }
            return lhs.element.date < rhs.element.date
        }.map(\.element)
        guard !ordered.isEmpty else { return [] }

        let bucket = bucketInterval.isFinite ? max(0, bucketInterval) : 0
        let sampling = expectedSampleInterval.isFinite ? max(0, expectedSampleInterval) : 0
        let expectedStep = max(bucket, sampling)
        let gapThreshold = expectedStep * AppConfig.History.chartGapMultiplier

        var segment = 0
        var previousDate: Date?
        return ordered.map { sample in
            if let previousDate,
               sample.date.timeIntervalSince(previousDate) > gapThreshold {
                segment += 1
            }
            previousDate = sample.date
            return SegmentedHistorySample(sample: sample, segment: segment)
        }
    }
}
