import SwiftUI
import Charts
import Accessibility

// MARK: - Chart

/// A uniquely identified plotting value. `Sample.id` is its timestamp, but persisted feeds can
/// briefly contain duplicate timestamps while being migrated or merged. A positional id keeps the
/// chart stable, while `segment` explicitly tells Charts not to draw across an observation gap.
private struct PlayerPlotPoint: Identifiable {
    let id: Int
    let sample: Sample
    let segment: Int
}

struct PlayerChart: View {
    let data: [Sample]                  // computed once by the chart card and shared with the stats row
    let interval: ChartInterval         // selected aggregation interval
    let range: ChartRange               // drives date-aware axes and tooltip formatting
    let expectedSampleInterval: TimeInterval
    /// A caller-injected clock instant (the wall clock by default). A fixed end keeps a sparse
    /// first-run series in place instead of stretching a few observations across the range.
    let referenceDate: Date
    @State private var hover: Sample?
    @FocusState private var chartFocused: Bool
    @Environment(\.colorSchemeContrast) private var contrast

    init(data: [Sample], interval: ChartInterval, range: ChartRange,
         expectedSampleInterval: TimeInterval, referenceDate: Date = .now) {
        self.data = data
        self.interval = interval
        self.range = range
        self.expectedSampleInterval = expectedSampleInterval
        self.referenceDate = referenceDate
    }

    private var axisTimeFormat: Date.FormatStyle {
        switch range {
        case .oneHour, .sixHours:
            return .dateTime.hour().minute()
        case .day:
            return .dateTime.month(.abbreviated).day().hour()
        case .week:
            return .dateTime.month(.abbreviated).day()
        }
    }

    /// Tooltips always include the date. Even a six-hour window can cross midnight, and a precise
    /// inspection value should never make the listener infer which day a sample belongs to.
    private var tooltipTimeFormat: Date.FormatStyle {
        .dateTime.month(.abbreviated).day().hour().minute()
    }

    var body: some View {
        let plotted = data.filter {
            $0.date >= referenceDate.addingTimeInterval(-range.seconds)
                && $0.date <= referenceDate
        }
        Group {
            if plotted.count < ChartStyle.minPlotPoints {
                placeholder
            } else {
                chart(plotted)
            }
        }
        .overlay(alignment: .topTrailing) {
            coverageBadge
                .padding(.top, Space.s2)
                .padding(.trailing, Space.s4)
                .opacity(hover == nil ? 1 : 0)
        }
        .onChange(of: interval) { hover = nil }
        .onChange(of: range) { hover = nil }
        #if PREVIEW
        .onAppear { if hover == nil, plotted.count > 8 { hover = plotted[plotted.count - 7] } }
        #endif
    }

    /// Coverage deliberately means populated *chart windows*, not continuous uptime. One point in
    /// a five-minute average proves that window contains a local observation, but nothing more.
    /// Partial windows at either end are weighted by their actual overlap with the selected range.
    private var windowCoverage: Double {
        let width = interval.seconds
        guard width > 0, range.seconds > 0 else { return 0 }
        let start = referenceDate.addingTimeInterval(-range.seconds)
        let bucketIDs = Set(data.compactMap { sample -> Int64? in
            let raw = (sample.date.timeIntervalSince1970 / width).rounded(.down)
            guard raw.isFinite, raw >= Double(Int64.min), raw < Double(Int64.max) else { return nil }
            return Int64(raw)
        })
        let covered = bucketIDs.reduce(0.0) { result, bucketID in
            let bucketStart = Date(timeIntervalSince1970: Double(bucketID) * width)
            let bucketEnd = bucketStart.addingTimeInterval(width)
            let overlapStart = max(start, bucketStart)
            let overlapEnd = min(referenceDate, bucketEnd)
            return result + max(0, overlapEnd.timeIntervalSince(overlapStart))
        }
        return min(1, max(0, covered / range.seconds))
    }

    private var coverageBadge: some View {
        let percentage = Int((windowCoverage * 100).rounded())
        return HStack(spacing: Space.s4) {
            Image(systemName: "circle.dotted")
                .accessibilityHidden(true)
            Text("\(percentage)%")
                .monospacedDigit()
            Text(Str.chartWindowCoverage)
        }
        .font(Typo.statLabel)
        .foregroundStyle(Palette.secondaryText(for: contrast))
        .padding(.horizontal, Space.s6)
        .padding(.vertical, Space.s2)
        .background(Capsule().fill(Palette.chartAnnotationBG.opacity(Opacity.o90)))
        .overlay(Capsule().strokeBorder(Palette.cardStroke, lineWidth: LineWidth.w075))
        .help(Str.chartWindowCoverageHelp)
        .accessibilityElement(children: .combine)
    }

    private func chart(_ data: [Sample]) -> some View {
        let sorted = data.sorted { $0.date < $1.date }
        let domainStart = referenceDate.addingTimeInterval(-range.seconds)
        let points = HistorySegmentation.segment(
            sorted,
            bucketInterval: interval.seconds,
            expectedSampleInterval: expectedSampleInterval
        ).enumerated().map {
            PlayerPlotPoint(id: $0.offset, sample: $0.element.sample,
                            segment: $0.element.segment)
        }
        let segmentSizes = Dictionary(grouping: points, by: \.segment).mapValues(\.count)
        let counts = sorted.map(\.count)
        let minimum = counts.min() ?? 0
        let maximum = counts.max() ?? 1
        let lo = minimum < ChartStyle.yPadding ? 0 : minimum - ChartStyle.yPadding
        let upper = maximum.addingReportingOverflow(ChartStyle.yPadding)
        let hi = upper.overflow ? Int.max : upper.partialValue

        return Chart {
            ForEach(points) { point in
                playerMarks(point, baseline: lo,
                            isIsolated: segmentSizes[point.segment] == 1)
            }

            if let h = hover {
                RuleMark(x: .value("Time", h.date))
                    .foregroundStyle(Palette.secondaryText(for: contrast).opacity(Opacity.o80))
                    .lineStyle(StrokeStyle(lineWidth: LineWidth.w1, dash: ChartStyle.ruleDash))
                PointMark(x: .value("Time", h.date), y: .value("Players", h.count))
                    .foregroundStyle(Palette.cyan)
                    .symbolSize(ChartStyle.hoverSymbolSize)
                    .annotation(position: .top, spacing: Space.s6,
                                overflowResolution: .init(x: .fit(to: .chart), y: .fit(to: .chart))) {
                        VStack(spacing: Space.s1) {
                            Text("\(h.count)")
                                .font(Typo.emphasis)
                                .monospacedDigit()
                                .foregroundStyle(Palette.cyan)
                            Text(h.date, format: tooltipTimeFormat)
                                .font(Typo.annotationTime)
                                .foregroundStyle(Palette.secondaryText(for: contrast))
                        }
                        .padding(.horizontal, Space.s7).padding(.vertical, Space.s4)
                        .background(RoundedRectangle(cornerRadius: Radius.r7)
                            .fill(Palette.chartAnnotationBG))
                        .overlay(RoundedRectangle(cornerRadius: Radius.r7)
                            .strokeBorder(Palette.gold.opacity(Opacity.o35)))
                        .shadow(color: .black.opacity(Opacity.o45), radius: Shadow.annotationRadius, y: Shadow.annotationOffsetY)
                    }
            }
        }
        .chartXScale(domain: domainStart...referenceDate)
        .chartYScale(domain: lo...hi)
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: ChartStyle.axisDesiredCount)) { value in
                AxisGridLine().foregroundStyle(Palette.chartGrid(for: contrast))
                AxisValueLabel {
                    if let date = value.as(Date.self) {
                        Text(date, format: axisTimeFormat)
                            .font(Typo.axis)
                            .foregroundStyle(Palette.tertiaryText(for: contrast))
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: ChartStyle.axisDesiredCount)) { value in
                AxisGridLine().foregroundStyle(Palette.chartGrid(for: contrast))
                AxisValueLabel {
                    if let count = value.as(Int.self) {
                        Text(count, format: .number)
                            .font(Typo.axis)
                            .foregroundStyle(Palette.tertiaryText(for: contrast))
                    }
                }
            }
        }
        .chartOverlay { proxy in
            GeometryReader { geo in
                Rectangle().fill(.clear).contentShape(Rectangle())
                    .accessibilityHidden(true)
                    .onContinuousHover { phase in
                        switch phase {
                        case .active(let pt):
                            guard let plotFrame = proxy.plotFrame else { hover = nil; return }
                            let rect = geo[plotFrame]
                            let x = pt.x - rect.minX
                            guard x >= 0, x <= rect.width,
                                  let date = proxy.value(atX: x, as: Date.self) else { hover = nil; return }
                            hover = sorted.min {
                                abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date))
                            }
                        case .ended:
                            hover = nil
                        }
                    }
            }
        }
        // A focused chart mirrors pointer inspection with the arrow keys. This is useful both for
        // keyboard-only users and alongside VoiceOver's Audio Graph exploration.
        .focusable()
        .focused($chartFocused)
        .focusEffectDisabled()
        .overlay {
            RoundedRectangle(cornerRadius: Radius.r7)
                .strokeBorder(Palette.cyan.opacity(chartFocused ? Opacity.o30 : 0),
                              lineWidth: LineWidth.w1)
                .allowsHitTesting(false)
        }
        .onKeyPress(.leftArrow) {
            moveSelection(in: sorted, by: -1)
            return .handled
        }
        .onKeyPress(.rightArrow) {
            moveSelection(in: sorted, by: 1)
            return .handled
        }
        .onKeyPress(.escape) {
            guard hover != nil else { return .ignored }
            hover = nil
            return .handled
        }
        .accessibilityChartDescriptor(PlayerChartDescriptor(points: points, low: lo, high: hi,
                                                            rangeStart: domainStart,
                                                            rangeEnd: referenceDate,
                                                            dateFormat: tooltipTimeFormat))
    }

    /// A dedicated content builder keeps Swift's result-builder solver tractable in optimized
    /// preview builds. Mark order, values, and styling intentionally mirror the original inline
    /// representation exactly.
    @ChartContentBuilder
    private func playerMarks(_ point: PlayerPlotPoint, baseline: Int,
                             isIsolated: Bool) -> some ChartContent {
        let s = point.sample
        AreaMark(
            x: .value("Time", s.date),
            yStart: .value("Base", baseline),
            yEnd: .value("Players", s.count),
            series: .value("Observed segment", point.segment)
        )
        .interpolationMethod(.monotone)
        .foregroundStyle(Gradients.chartArea)

        LineMark(
            x: .value("Time", s.date),
            y: .value("Players", s.count),
            series: .value("Observed segment", point.segment)
        )
        .interpolationMethod(.monotone)
        .foregroundStyle(Gradients.brandHorizontal)
        .lineStyle(StrokeStyle(lineWidth: LineWidth.w6, lineCap: .round, lineJoin: .round))
        .blur(radius: Blur.glow)

        LineMark(
            x: .value("Time", s.date),
            y: .value("Players", s.count),
            series: .value("Observed segment", point.segment)
        )
        .interpolationMethod(.monotone)
        .foregroundStyle(Gradients.brandHorizontal)
        .lineStyle(StrokeStyle(lineWidth: LineWidth.w2, lineCap: .round, lineJoin: .round))

        // A single observation between two long gaps has no line to render. Keep it
        // visible as a point instead of silently dropping a truthful sample.
        if isIsolated {
            PointMark(x: .value("Time", s.date), y: .value("Players", s.count))
                .foregroundStyle(Palette.cyan)
                .symbolSize(ChartStyle.isolatedSymbolSize)
        }
    }

    private func moveSelection(in samples: [Sample], by offset: Int) {
        guard !samples.isEmpty else { return }
        let current = hover.flatMap { selected in
            samples.firstIndex { $0.date == selected.date && $0.count == selected.count }
        }
        let target: Int
        if let current {
            target = min(samples.count - 1, max(0, current + offset))
        } else {
            target = offset < 0 ? samples.count - 1 : 0
        }
        hover = samples[target]
    }

    private var placeholder: some View {
        ZStack {
            RoundedRectangle(cornerRadius: Radius.r8).fill(Color.white.opacity(Opacity.o02))
            VStack(spacing: Space.s4) {
                Image(systemName: "chart.xyaxis.line")
                    .font(Typo.placeholderIcon)
                    .foregroundStyle(Palette.tertiaryText(for: contrast))
                Text(Str.chartPlaceholderTitle)
                    .font(Typo.pill)
                    .foregroundStyle(Palette.secondaryText(for: contrast))
                Text(Str.chartPlaceholderSubtitle)
                    .font(Typo.placeholderHint)
                    .foregroundStyle(Palette.tertiaryText(for: contrast))
            }
        }
    }
}

// MARK: - Audio Graph / VoiceOver descriptor

private struct PlayerChartDescriptor: AXChartDescriptorRepresentable {
    let points: [PlayerPlotPoint]
    let low: Int
    let high: Int
    let rangeStart: Date
    let rangeEnd: Date
    let dateFormat: Date.FormatStyle

    func makeChartDescriptor() -> AXChartDescriptor {
        let samples = points.map(\.sample)
        let firstTime = rangeStart.timeIntervalSince1970
        let lastTime = max(firstTime + 1, rangeEnd.timeIntervalSince1970)
        let xAxis = AXNumericDataAxisDescriptor(
            title: AppText.chartAxisTime,
            range: firstTime...lastTime,
            gridlinePositions: []
        ) { value in
            Date(timeIntervalSince1970: value).formatted(dateFormat)
        }
        let yAxis = AXNumericDataAxisDescriptor(
            title: AppText.chartAxisPlayers,
            range: Double(low)...Double(max(low + 1, high)),
            gridlinePositions: []
        ) { value in
            AppText.playerCountAccessibility(Int(value.rounded()))
        }

        let grouped = Dictionary(grouping: points, by: \.segment)
        let series = grouped.keys.sorted().compactMap { segment -> AXDataSeriesDescriptor? in
            guard let segmentPoints = grouped[segment] else { return nil }
            let values = segmentPoints.map { point in
                let sample = point.sample
                return AXDataPoint(
                    x: sample.date.timeIntervalSince1970,
                    y: Double(sample.count),
                    label: AppText.playerPointAccessibility(
                        count: sample.count, date: sample.date.formatted(dateFormat))
                )
            }
            return AXDataSeriesDescriptor(name: AppText.playerSeriesAccessibility(
                segment: grouped.count > 1 ? segment + 1 : nil),
                                          isContinuous: values.count > 1,
                                          dataPoints: values)
        }

        return AXChartDescriptor(
            title: String(localized: "chart.title", defaultValue: "Players over time", table: "Localizable"),
            summary: AppText.chartAccessibility(latest: samples.last?.count ?? 0,
                                                peak: samples.map(\.count).max() ?? 0),
            xAxis: xAxis,
            yAxis: yAxis,
            series: series
        )
    }
}
