import SwiftUI
import Charts
import Accessibility

// MARK: - Card

/// The $WOC price card: a real OHLC candlestick chart (dexscreener-style) driven by candles the
/// store fetches from GeckoTerminal. Its candle-width picker binds to `store.cryptoInterval` —
/// independent of the player chart's range/interval, so the two charts never share state.
struct CryptoChartCardView: View {
    @Bindable var store: StatusStore
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s9) {
            HStack {
                Text(Str.cryptoChartTitle)
                    .font(Typo.sectionLabel)
                    .tracking(Tracking.t08)
                    .foregroundStyle(Palette.secondaryText(for: contrast))
                Spacer()
            }

            pickerRow(title: Str.chartCandleInterval) {
                Picker("", selection: $store.cryptoInterval) {
                    ForEach(CandleInterval.allCases) { Text($0.label).tag($0) }
                }
                .accessibilityLabel(Str.chartCandleInterval)
            }

            CryptoCandleChart(candles: store.chartCandles,
                              interval: store.cryptoInterval,
                              emptyState: candleEmptyState)
        }
        .padding(Space.s12)
        .glassCard()
    }

    private var candleEmptyState: CandleChartEmptyState {
        if store.isCandlesRefreshing { return .loading }
        if store.candleErrorMessage != nil || store.candleFeedState == .unavailable
            || store.hasCachedCandlesForDifferentInterval {
            return .unavailable
        }
        return .gathering
    }

    private func pickerRow<P: View>(title: LocalizedStringKey, @ViewBuilder _ picker: () -> P) -> some View {
        HStack(spacing: Space.s8) {
            Text(title)
                .font(Typo.pickerRowLabel)
                .tracking(Tracking.t06)
                .foregroundStyle(Palette.tertiaryText(for: contrast))
                .frame(width: dynamicTypeSize.isAccessibilitySize
                       ? Size.accessibilityPickerLabelWidth : Size.pickerLabelWidth,
                       alignment: .leading)
            picker()
                .pickerStyle(.segmented)
                .labelsHidden()
                .controlSize(.small)
        }
    }
}

// MARK: - Candlestick chart

/// A positional id prevents duplicate timestamps from confusing Swift Charts while an upstream
/// response is being normalized. The original candle remains the single source of OHLC truth.
private struct CandlePlotPoint: Identifiable {
    let id: Int
    let candle: Candle
}

enum CandleChartEmptyState: Equatable {
    case loading
    case unavailable
    case gathering
}

struct CryptoCandleChart: View {
    let candles: [Candle]
    let interval: CandleInterval        // drives the hover-reset + the axis/tooltip time format
    let emptyState: CandleChartEmptyState
    @State private var hover: Candle?
    @FocusState private var chartFocused: Bool
    @Environment(\.colorSchemeContrast) private var contrast

    init(candles: [Candle], interval: CandleInterval,
         emptyState: CandleChartEmptyState = .gathering) {
        self.candles = candles
        self.interval = interval
        self.emptyState = emptyState
    }

    /// Axis/tooltip time format. At `candleCount` bars the hour candles span days (1h ≈ 2.5 days,
    /// 4h ≈ 10 days), so HH:mm alone is ambiguous across days — include the date there; minute
    /// candles stay HH:mm. Same style for the axis labels and the hover tooltip so they agree.
    private var timeFormat: Date.FormatStyle {
        interval.seconds >= CandleInterval.oneHour.seconds
            ? .dateTime.month(.abbreviated).day().hour().minute()
            : .dateTime.hour().minute()
    }

    /// The inspection tooltip always includes the date because a precise value can cross midnight,
    /// even when the compact minute-candle axis only has room for time labels.
    private var tooltipTimeFormat: Date.FormatStyle {
        .dateTime.month(.abbreviated).day().hour().minute()
    }

    var body: some View {
        let sorted = candles.sorted { lhs, rhs in
            lhs.date == rhs.date ? lhs.close < rhs.close : lhs.date < rhs.date
        }
        return VStack(spacing: Space.s6) {
            if let displayed = hover ?? sorted.last {
                candleDetailStrip(displayed, isInspecting: hover != nil)
            }

            Group {
                if sorted.count < ChartStyle.minPlotPoints {
                    placeholder
                } else {
                    chart(sorted)
                }
            }
            .frame(height: Size.chartHeight)
        }
        .onChange(of: interval) { hover = nil }
        #if PREVIEW
        // Park the hover tooltip on a candle for screenshots, re-seeding from the live array each
        // time real candles replace the seeded ones (so the tooltip tracks the visible data).
        .onAppear { if candles.count > 8 { hover = candles[candles.count - 6] } }
        .onChange(of: candles.last?.date) { if candles.count > 8 { hover = candles[candles.count - 6] } }
        #endif
    }

    private func chart(_ candles: [Candle]) -> some View {
        let sorted = candles.sorted { lhs, rhs in
            lhs.date == rhs.date ? lhs.close < rhs.close : lhs.date < rhs.date
        }
        let points = sorted.enumerated().map { CandlePlotPoint(id: $0.offset, candle: $0.element) }

        // y-domain: the high–low span plus a proportional inset, so headroom looks the same
        // regardless of the token's absolute price. Floor the span only when the window is perfectly
        // flat so the domain can't collapse to zero height.
        let lo0 = sorted.map(\.low).min() ?? 0
        let hi0 = sorted.map(\.high).max() ?? 1
        let rawSpan = hi0 - lo0
        let flatBasis = hi0 > 0 ? hi0 : 1
        let span = rawSpan > 0 ? rawSpan : flatBasis * ChartStyle.candleFlatSpanFraction
        let pad = span * ChartStyle.candleYInsetFraction
        let domainLow = max(0, lo0 - pad)
        let domainHigh = hi0 + pad
        let last = sorted.last
        let lastColor = (last?.isUp ?? true) ? Palette.green : Palette.red
        let trendingUp = (last?.close ?? 0) >= (sorted.first?.close ?? 0)

        return Chart {
            ForEach(points) { point in
                let c = point.candle
                let color = c.isUp ? Palette.green : Palette.red

                // Wick: a thin high–low line.
                RuleMark(x: .value("Time", c.date),
                         yStart: .value("Low", c.low),
                         yEnd: .value("High", c.high))
                    .lineStyle(StrokeStyle(lineWidth: LineWidth.w1))
                    .foregroundStyle(color)

                // The outer body always represents the exact open–close extent.
                BarMark(x: .value("Time", c.date),
                        yStart: .value("Open", c.open),
                        yEnd: .value("Close", c.close),
                        width: .ratio(ChartStyle.candleBodyRatio))
                    .foregroundStyle(color)

                // Falling bodies are hollow as well as red, while rising bodies are filled as well
                // as green. The redundant shape treatment remains readable without color vision.
                if !c.isUp {
                    let lower = min(c.open, c.close)
                    let upper = max(c.open, c.close)
                    let inset = (upper - lower) * ChartStyle.candleHollowInsetFraction
                    BarMark(x: .value("Time", c.date),
                            yStart: .value("Body inner low", lower + inset),
                            yEnd: .value("Body inner high", upper - inset),
                            width: .ratio(ChartStyle.candleHollowInnerRatio))
                        .foregroundStyle(Palette.chartAnnotationBG)
                }
            }

            if let last {
                RuleMark(y: .value("Latest close", last.close))
                    .lineStyle(StrokeStyle(lineWidth: LineWidth.w1, dash: ChartStyle.ruleDash))
                    .foregroundStyle(lastColor.opacity(Opacity.o80))
                    // The price chip is an annotation on the rule itself, so it remains vertically
                    // attached to the value it names rather than floating at the card's top edge.
                    .annotation(position: .leading, alignment: .center, spacing: Space.s4,
                                overflowResolution: .init(x: .fit(to: .chart), y: .fit(to: .chart))) {
                        Text(AppText.candleClose(
                            interval: interval.label,
                            price: CryptoFormat.price(CryptoFormat.chartPrice(last.close))))
                            .font(Typo.candlePriceTag)
                            .padding(.horizontal, Space.s7)
                            .padding(.vertical, Space.s2)
                            .background(Capsule().fill(lastColor))
                            .foregroundStyle(Palette.onAccent)
                    }
            }

            if let h = hover {
                let hoverColor = h.isUp ? Palette.green : Palette.red
                RuleMark(x: .value("Time", h.date))
                    .foregroundStyle(Palette.secondaryText(for: contrast).opacity(Opacity.o80))
                    .lineStyle(StrokeStyle(lineWidth: LineWidth.w1, dash: ChartStyle.ruleDash))
                PointMark(x: .value("Time", h.date), y: .value("Close", h.close))
                    .foregroundStyle(hoverColor)
                    .symbolSize(ChartStyle.hoverSymbolSize)
            }
        }
        .chartYScale(domain: domainLow...domainHigh)
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: ChartStyle.axisDesiredCount)) { value in
                AxisGridLine().foregroundStyle(Palette.chartGrid(for: contrast))
                AxisValueLabel {
                    if let date = value.as(Date.self) {
                        Text(date, format: timeFormat)
                            .font(Typo.axis)
                            .foregroundStyle(Palette.tertiaryText(for: contrast))
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .trailing, values: .automatic(desiredCount: ChartStyle.axisDesiredCount)) { value in
                AxisGridLine().foregroundStyle(Palette.chartGrid(for: contrast))
                AxisValueLabel {
                    if let price = value.as(Double.self) {
                        Text(CryptoFormat.chartPrice(price))
                            .font(Typo.candleAxis)
                            .foregroundStyle(Palette.secondaryText(for: contrast))
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
        .accessibilityChartDescriptor(CryptoChartDescriptor(candles: sorted,
                                                            low: domainLow,
                                                            high: domainHigh,
                                                            dateFormat: tooltipTimeFormat,
                                                            trendingUp: trendingUp))
    }

    /// The inspection readout lives outside the plot and always occupies the same place. Pointer
    /// and keyboard selection replace the latest candle in-place, so the chart never jumps and no
    /// OHLC panel covers a price move the user is trying to inspect.
    private func candleDetailStrip(_ candle: Candle, isInspecting: Bool) -> some View {
        let color = candle.isUp ? Palette.green : Palette.red
        let change = candle.open == 0 ? 0 : ((candle.close - candle.open) / candle.open) * 100
        return VStack(spacing: Space.s4) {
            HStack(spacing: Space.s6) {
                Label {
                    Text(isInspecting ? Str.chartCandleSelected : Str.chartCandleLatest)
                } icon: {
                    Image(systemName: isInspecting ? "scope" : "clock")
                }
                .font(Typo.statLabel)
                .foregroundStyle(Palette.secondaryText(for: contrast))

                Spacer(minLength: Space.s4)

                Text(candle.date, format: tooltipTimeFormat)
                    .font(Typo.annotationTime)
                    .foregroundStyle(Palette.secondaryText(for: contrast))

                Label(CryptoFormat.signedChange(change),
                      systemImage: candle.isUp ? "arrow.up.right" : "arrow.down.right")
                    .font(Typo.cryptoChange)
                    .monospacedDigit()
                    .foregroundStyle(color)
            }

            HStack(spacing: Space.s8) {
                candleMetric(Str.chartMetricOpenShort, accessibility: Str.chartMetricOpen,
                             value: candle.open)
                candleMetric(Str.chartMetricHighShort, accessibility: Str.chartMetricHigh,
                             value: candle.high)
                candleMetric(Str.chartMetricLowShort, accessibility: Str.chartMetricLow,
                             value: candle.low)
                candleMetric(Str.chartMetricCloseShort, accessibility: Str.chartMetricClose,
                             value: candle.close, color: color)
            }
        }
        .padding(.horizontal, Space.s8)
        .padding(.vertical, Space.s6)
        .background(RoundedRectangle(cornerRadius: Radius.r7)
            .fill(Palette.chartAnnotationBG))
        .overlay(RoundedRectangle(cornerRadius: Radius.r7)
            .strokeBorder(color.opacity(Opacity.o25), lineWidth: LineWidth.w075))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(AppText.candlePointAccessibility(
            date: candle.date.formatted(tooltipTimeFormat),
            open: CryptoFormat.chartPrice(candle.open),
            high: CryptoFormat.chartPrice(candle.high),
            low: CryptoFormat.chartPrice(candle.low),
            close: CryptoFormat.chartPrice(candle.close),
            isUp: candle.isUp,
            change: abs(change).formatted(.number.precision(.fractionLength(1)))))
    }

    private func candleMetric(_ label: LocalizedStringKey,
                              accessibility: LocalizedStringKey,
                              value: Double,
                              color: Color = Palette.textPrimary) -> some View {
        HStack(spacing: Space.s2) {
            Text(label)
                .font(Typo.statLabel)
                .foregroundStyle(Palette.tertiaryText(for: contrast))
                .accessibilityLabel(accessibility)
            Text(CryptoFormat.chartPrice(value))
                .font(Typo.axis)
                .monospacedDigit()
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func moveSelection(in candles: [Candle], by offset: Int) {
        guard !candles.isEmpty else { return }
        let current = hover.flatMap { selected in
            candles.firstIndex { $0 == selected }
        }
        let target: Int
        if let current {
            target = min(candles.count - 1, max(0, current + offset))
        } else {
            target = offset < 0 ? candles.count - 1 : 0
        }
        hover = candles[target]
    }

    private var placeholder: some View {
        ZStack {
            RoundedRectangle(cornerRadius: Radius.r8).fill(Color.white.opacity(Opacity.o02))
            VStack(spacing: Space.s4) {
                if emptyState == .loading {
                    ProgressView()
                        .controlSize(.small)
                        .tint(Palette.cyan)
                        .accessibilityHidden(true)
                } else {
                    Image(systemName: emptyState == .unavailable
                          ? "wifi.exclamationmark" : "chart.bar.xaxis")
                        .font(Typo.placeholderIcon)
                        .foregroundStyle(emptyState == .unavailable
                                         ? Palette.red : Palette.tertiaryText(for: contrast))
                        .accessibilityHidden(true)
                }
                Text(placeholderTitle)
                    .font(Typo.pill)
                    .foregroundStyle(Palette.secondaryText(for: contrast))
                Text(placeholderSubtitle)
                    .font(Typo.placeholderHint)
                    .foregroundStyle(Palette.tertiaryText(for: contrast))
            }
        }
    }

    private var placeholderTitle: LocalizedStringKey {
        switch emptyState {
        case .loading: Str.chartCandleLoadingTitle
        case .unavailable: Str.chartCandleUnavailableTitle
        case .gathering: Str.chartCandleGatheringTitle
        }
    }

    private var placeholderSubtitle: LocalizedStringKey {
        switch emptyState {
        case .loading: Str.chartCandleLoadingSubtitle
        case .unavailable: Str.chartCandleUnavailableSubtitle
        case .gathering: Str.chartCandleGatheringSubtitle
        }
    }
}

// MARK: - Audio Graph / VoiceOver descriptor

private struct CryptoChartDescriptor: AXChartDescriptorRepresentable {
    let candles: [Candle]
    let low: Double
    let high: Double
    let dateFormat: Date.FormatStyle
    let trendingUp: Bool

    func makeChartDescriptor() -> AXChartDescriptor {
        let firstTime = candles.first?.date.timeIntervalSince1970 ?? 0
        let lastTime = candles.last?.date.timeIntervalSince1970 ?? firstTime + 1
        let xAxis = AXNumericDataAxisDescriptor(
            title: AppText.chartAxisTime,
            range: firstTime...max(firstTime + 1, lastTime),
            gridlinePositions: []
        ) { value in
            Date(timeIntervalSince1970: value).formatted(dateFormat)
        }

        func priceAxis(_ title: String) -> AXNumericDataAxisDescriptor {
            AXNumericDataAxisDescriptor(title: title,
                                        range: low...max(low.nextUp, high),
                                        gridlinePositions: []) { value in
                CryptoFormat.price(CryptoFormat.chartPrice(value))
            }
        }

        let values = candles.map { candle in
            let change = candle.open == 0 ? 0 : ((candle.close - candle.open) / candle.open) * 100
            let label = AppText.candlePointAccessibility(
                date: candle.date.formatted(dateFormat),
                open: CryptoFormat.chartPrice(candle.open),
                high: CryptoFormat.chartPrice(candle.high),
                low: CryptoFormat.chartPrice(candle.low),
                close: CryptoFormat.chartPrice(candle.close),
                isUp: candle.isUp,
                change: abs(change).formatted(.number.precision(.fractionLength(1))))
            return AXDataPoint(x: candle.date.timeIntervalSince1970,
                               y: candle.close,
                               additionalValues: [.number(candle.open), .number(candle.high), .number(candle.low)],
                               label: label)
        }
        let series = AXDataSeriesDescriptor(name: AppText.chartCandleSeries,
                                            isContinuous: false,
                                            dataPoints: values)
        let latest = candles.last?.close ?? 0
        let visibleHigh = candles.map(\.high).max() ?? high
        let visibleLow = candles.map(\.low).min() ?? low

        return AXChartDescriptor(
            title: String(localized: "chart.cryptoTitle", defaultValue: "$WOC price", table: "Localizable"),
            summary: AppText.cryptoChartAccessibility(latest: latest, high: visibleHigh,
                                                       low: visibleLow, up: trendingUp),
            xAxis: xAxis,
            yAxis: priceAxis(AppText.chartAxisClosePrice),
            additionalAxes: [priceAxis(AppText.chartAxisOpenPrice),
                             priceAxis(AppText.chartAxisHighPrice),
                             priceAxis(AppText.chartAxisLowPrice)],
            series: [series]
        )
    }
}
