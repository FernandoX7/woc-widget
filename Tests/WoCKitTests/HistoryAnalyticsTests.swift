import Testing
import Foundation
@testable import WoCKit

@Suite struct HistoryAnalyticsTests {
    @Test func automaticResolutionUsesOnlyTruthfulNamedIntervals() {
        #expect(ChartInterval.automatic(for: .oneHour) == .oneMin)
        #expect(ChartInterval.automatic(for: .sixHours) == .fiveMin)
        #expect(ChartInterval.automatic(for: .day) == .fiveMin)
        #expect(ChartInterval.automatic(for: .week) == .oneHour)
        for range in ChartRange.allCases {
            let interval = ChartInterval.automatic(for: range)
            #expect(range.seconds / interval.seconds <= AppConfig.History.chartMaxPoints)
        }
    }

    let fixedNow = Date(timeIntervalSince1970: 1_700_000_000)

    @Test func emptyHistoryYieldsNoSeries() {
        #expect(HistoryAnalytics(samples: []).series(range: .day, interval: .oneMin).isEmpty)
    }

    @Test func distinctMinuteBucketsSortedAscending() {
        let samples = [
            Sample(date: fixedNow, count: 10),
            Sample(date: fixedNow.addingTimeInterval(-60), count: 20),
            Sample(date: fixedNow.addingTimeInterval(-120), count: 30),
        ]
        let series = HistoryAnalytics(samples: samples, now: { fixedNow }).series(range: .oneHour, interval: .oneMin)
        #expect(series.count == 3)
        #expect(series.map(\.count) == [30, 20, 10])   // oldest → newest
    }

    @Test func bucketAveragesItsSamples() {
        // Two samples one second apart land in the same 1-minute bucket → mean.
        let samples = [
            Sample(date: fixedNow, count: 10),
            Sample(date: fixedNow.addingTimeInterval(-1), count: 20),
        ]
        let series = HistoryAnalytics(samples: samples, now: { fixedNow }).series(range: .oneHour, interval: .oneMin)
        #expect(series.count == 1)
        #expect(series[0].count == 15)
    }

    @Test func windowExcludesSamplesOlderThanRange() {
        let samples = [
            Sample(date: fixedNow, count: 5),
            Sample(date: fixedNow.addingTimeInterval(-7200), count: 99),   // 2h ago, outside a 1h range
        ]
        let series = HistoryAnalytics(samples: samples, now: { fixedNow }).series(range: .oneHour, interval: .oneMin)
        #expect(series.count == 1)
        #expect(series[0].count == 5)
    }

    @Test func neverExceedsPointCapAndDownsamples() {
        // 7 days of minutely samples through a 7-day range coarsens the bucket to ~300 points.
        var samples: [Sample] = []
        var t = fixedNow.addingTimeInterval(-7 * 24 * 3600)
        var i = 0
        while t <= fixedNow { samples.append(Sample(date: t, count: i % 50)); t = t.addingTimeInterval(60); i += 1 }
        #expect(samples.count > 10_000)
        let series = HistoryAnalytics(samples: samples, now: { fixedNow }).series(range: .week, interval: .oneMin)
        #expect(series.count <= 301)   // the 300-point cap holds
        #expect(series.count >= 290)   // and it actually downsampled (not ~10k points)
    }

    @Test func todayPeakUsesTodaysSamplesElseFallback() {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(secondsFromGMT: 0)!
        let today = fixedNow
        let withToday = HistoryAnalytics(samples: [
            Sample(date: today, count: 7),
            Sample(date: today.addingTimeInterval(-30), count: 12),
        ], now: { today }, calendar: utc)
        #expect(withToday.todayPeak(fallback: 99) == 12)

        let onlyYesterday = HistoryAnalytics(
            samples: [Sample(date: today.addingTimeInterval(-24 * 3600), count: 50)],
            now: { today }, calendar: utc)
        #expect(onlyYesterday.todayPeak(fallback: 99) == 99)
    }

    @Test func retentionCutoffIsSevenDaysBack() {
        let analytics = HistoryAnalytics(samples: [], now: { fixedNow })
        #expect(analytics.retentionCutoff() == fixedNow.addingTimeInterval(-7 * 24 * 3600))
    }

    @Test func averageRoundsMeanAndIsNilWhenEmpty() {
        #expect(HistoryAnalytics.average(of: []) == nil)
        let s = [Sample(date: fixedNow, count: 10), Sample(date: fixedNow.addingTimeInterval(1), count: 15)]
        #expect(HistoryAnalytics.average(of: s) == 13)   // 12.5 → 13 (matches the old StatsRow math)
    }

    @Test func averagesExtremeCountsWithoutOverflowing() {
        let samples = [
            Sample(date: fixedNow, count: .max),
            Sample(date: fixedNow.addingTimeInterval(1), count: .max),
        ]
        #expect(HistoryAnalytics.average(of: samples) == .max)
        let series = HistoryAnalytics(samples: samples, now: { self.fixedNow })
            .series(range: .oneHour, interval: .oneMin)
        #expect(series.first?.count == .max)
    }

    @Test func shortChangeRequiresABaselineNearTheRequestedWindow() {
        let nearTarget = Sample(date: fixedNow.addingTimeInterval(-30 * 60 + 20), count: 80)
        let stale = Sample(date: fixedNow.addingTimeInterval(-6 * 3600), count: 10)
        let analytics = HistoryAnalytics(samples: [stale, nearTarget], now: { self.fixedNow })

        #expect(analytics.change(over: 30 * 60, currentCount: 95,
                                 baselineTolerance: 60) == 15)
        #expect(HistoryAnalytics(samples: [stale], now: { self.fixedNow })
            .change(over: 30 * 60, currentCount: 95, baselineTolerance: 60) == nil)
    }

    @Test func shortChangeClampsArithmeticOverflow() {
        let baseline = Sample(date: fixedNow.addingTimeInterval(-30 * 60), count: .max)
        let analytics = HistoryAnalytics(samples: [baseline], now: { self.fixedNow })
        #expect(analytics.change(over: 30 * 60, currentCount: .min,
                                 baselineTolerance: 1) == .min)
    }

    @Test func realmRhythmReportsCoverageAndWaitsForEnoughSamples() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let sparse = (0..<10).map {
            Sample(date: now.addingTimeInterval(Double(-$0) * 60), count: 20 + $0)
        }
        let insight = HistoryAnalytics(samples: sparse, now: { now }).realmRhythm(
            range: .oneHour, currentCount: 25, expectedSampleInterval: 60)

        #expect(insight.sampleCount == 10)
        #expect(insight.observedDuration == 600)
        #expect(abs(insight.coverageFraction - (1.0 / 6.0)) < 0.000_001)
        #expect(insight.currentPercentile == nil)
    }

    @Test func realmRhythmUsesMidpointPercentileAndCapsCoverage() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let flat = (0..<40).map {
            Sample(date: now.addingTimeInterval(Double(-$0) * 60), count: 42)
        }
        let insight = HistoryAnalytics(samples: flat, now: { now }).realmRhythm(
            range: .oneHour, currentCount: 42, expectedSampleInterval: 120)

        #expect(insight.coverageFraction == 1)
        #expect(insight.observedDuration == ChartRange.oneHour.seconds)
        #expect(insight.currentPercentile == 50)
    }

    @Test func segmentationBreaksSparseOutagesAndPreservesRegularCadence() {
        let regular = (0..<4).map { offset in
            Sample(date: fixedNow.addingTimeInterval(Double(offset) * 60), count: offset)
        }
        #expect(HistorySegmentation.segment(regular, bucketInterval: 60,
                                            expectedSampleInterval: 60).map(\.segment)
                == [0, 0, 0, 0])

        let sparse = [regular[0], Sample(date: fixedNow.addingTimeInterval(30 * 60), count: 9)]
        #expect(HistorySegmentation.segment(sparse, bucketInterval: 60,
                                            expectedSampleInterval: 60).map(\.segment)
                == [0, 1])
    }

    @Test func segmentationSortsInputAndUsesTheKnownPollingCadence() {
        let a = Sample(date: fixedNow, count: 1)
        let b = Sample(date: fixedNow.addingTimeInterval(5 * 60), count: 2)
        let duplicate = Sample(date: b.date, count: 3)
        let c = Sample(date: fixedNow.addingTimeInterval(20 * 60), count: 4)
        let result = HistorySegmentation.segment([c, duplicate, a, b], bucketInterval: 60,
                                                 expectedSampleInterval: 5 * 60)
        #expect(result.map(\.sample.date) == [a.date, b.date, duplicate.date, c.date])
        #expect(result.map(\.segment) == [0, 0, 0, 1])
    }
}
