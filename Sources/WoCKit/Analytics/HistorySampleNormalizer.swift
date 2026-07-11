import Foundation

/// Pure retention and representation repair for persisted player-count samples.
///
/// Persistence orchestration stays in `StatusStore`; this type only produces the frozen, sorted,
/// first-duplicate-wins representation the store has always written.
enum HistorySampleNormalizer {
    static func normalize(
        _ input: [Sample],
        relativeTo referenceDate: Date,
        retentionWindow: TimeInterval = AppConfig.History.retentionWindow,
        futureSampleTolerance: TimeInterval = AppConfig.History.futureSampleTolerance
    ) -> [Sample] {
        let cutoff = referenceDate.addingTimeInterval(-retentionWindow)
        let futureLimit = referenceDate.addingTimeInterval(futureSampleTolerance)
        var byDate: [Date: Sample] = [:]
        for sample in input {
            guard sample.count >= 0,
                  sample.date.timeIntervalSinceReferenceDate.isFinite,
                  sample.date >= cutoff,
                  sample.date <= futureLimit,
                  byDate[sample.date] == nil else { continue }
            byDate[sample.date] = sample
        }
        return byDate.values.sorted { $0.date < $1.date }
    }
}
