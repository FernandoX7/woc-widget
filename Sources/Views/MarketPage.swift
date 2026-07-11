import SwiftUI
import AppKit

struct MarketPageView: View {
    @Bindable var store: StatusStore
    @State private var copiedContract = false
    @State private var copyFeedbackGeneration = 0
    @State private var selectedTimeframe = CryptoMarketTimeframe.twentyFourHours

    var body: some View {
        ScrollView {
            VStack(spacing: Space.s12) {
                marketSummary
                feedNotice
                CryptoChartCardView(store: store)
                marketMetrics
                marketActions
                Link(destination: AppLinks.geckoTerminal) {
                    Text(Str.marketDataSource)
                        .font(Typo.timestamp)
                        .foregroundStyle(Palette.textTert)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, Space.s16)
            .padding(.vertical, Space.s12)
        }
    }

    private var marketSummary: some View {
        VStack(spacing: Space.s10) {
            HStack(spacing: Space.s8) {
                Text(Str.marketSpot)
                    .font(Typo.sectionLabel)
                    .tracking(Tracking.t08)
                    .foregroundStyle(Palette.textSecond)
                Spacer()
                ContextualAlertButton(
                    isOn: effectiveRollingMarketAlerts,
                    authorizationState: store.notificationAuthorizationState,
                    visibleLabel: AppText.marketAlertSummary(
                        threshold: Int(store.cryptoAlertThreshold),
                        window: alertWindowLabel
                    ),
                    accessibilityLabel: AppText.marketAlertAccessibility(
                        threshold: Int(store.cryptoAlertThreshold),
                        window: alertWindowLabel
                    ),
                    onHelp: AppText.marketAlertDisableHelp,
                    offHelp: AppText.marketAlertEnableHelp,
                    requestAuthorization: { await store.requestNotificationAuthorization() }
                )
            }

            HStack(alignment: .firstTextBaseline, spacing: Space.s10) {
                Text(store.cryptoPrice.map(CryptoFormat.price) ?? Glyph.noValue)
                    .font(Typo.marketPrice)
                    .monospacedDigit()
                    .foregroundStyle(Palette.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                Spacer()
                if let change = selectedWindowChange {
                    Label(CryptoFormat.signedChange(change),
                          systemImage: change >= 0 ? "arrow.up.right" : "arrow.down.right")
                        .font(Typo.emphasis)
                        .monospacedDigit()
                        .foregroundStyle(change >= 0 ? Palette.green : Palette.red)
                        .accessibilityLabel(Text(AppText.marketWindowChange(
                            timeframe: timeframeLabel, change: change)))
                } else {
                    Text(Glyph.noValue)
                        .font(Typo.emphasis)
                        .foregroundStyle(Palette.textTert)
                        .accessibilityLabel(Text(Str.feedUnavailable))
                }
            }

            Divider().overlay(Palette.cardStroke)

            Picker(Str.marketTimeframe, selection: $selectedTimeframe) {
                ForEach(CryptoMarketTimeframe.allCases, id: \.rawValue) { timeframe in
                    Text(timeframeLabel(for: timeframe)).tag(timeframe)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .controlSize(.small)
            .accessibilityLabel(Str.marketTimeframe)
        }
        .padding(Space.s12)
        .glassCard()
    }

    @ViewBuilder
    private var feedNotice: some View {
        VStack(alignment: .leading, spacing: Space.s6) {
            HStack(spacing: Space.s6) {
                MarketFeedPill(title: Str.marketQuoteFeed, state: store.priceFeedState)
                MarketFeedPill(title: Str.marketChartFeed, state: store.candleFeedState)
                Spacer()
                if feedNeedsAttention {
                    Button(Str.feedRetry) {
                        Task {
                            async let quote: Void = store.refreshCrypto()
                            async let candles: Void = store.refreshCandles()
                            _ = await (quote, candles)
                        }
                    }
                    .buttonStyle(.plain)
                    .font(Typo.buttonLabel)
                    .foregroundStyle(Palette.cyan)
                }
            }

            if store.priceFeedState == .cached || store.candleFeedState == .cached {
                Label(cachedMessage, systemImage: "clock.badge.exclamationmark")
                    .font(Typo.timestamp)
                    .foregroundStyle(Palette.gold)
            } else if store.priceFeedState == .unavailable || store.candleFeedState == .unavailable {
                Label(Str.marketFeedUnavailableDetail, systemImage: "exclamationmark.triangle.fill")
                    .font(Typo.timestamp)
                    .foregroundStyle(Palette.red)
            }
        }
        .padding(.horizontal, Space.s10)
        .padding(.vertical, Space.s7)
        .background(RoundedRectangle(cornerRadius: Radius.r8).fill(Palette.card.opacity(Opacity.o55)))
        .overlay(RoundedRectangle(cornerRadius: Radius.r8).strokeBorder(Palette.cardStroke))
    }

    private var feedNeedsAttention: Bool {
        store.priceFeedState == .cached || store.priceFeedState == .unavailable
            || store.candleFeedState == .cached || store.candleFeedState == .unavailable
    }

    private var cachedMessage: String {
        if store.hasCachedCandlesForDifferentInterval, let loaded = store.loadedCandleInterval {
            return AppText.cachedCandles(interval: loaded.label)
        }
        let date = store.marketCachedAt
        return date.map { AppText.relativeUpdated($0, now: { store.currentDate }) }
            ?? String(localized: "feed.showingCached", defaultValue: "Showing cached data")
    }

    private var marketMetrics: some View {
        let quote = store.marketQuote
        let window = quote?.metrics(for: selectedTimeframe)
        return VStack(spacing: Space.s8) {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: Space.s8) {
                MarketMetric(
                    label: AppText.marketWindowVolume(timeframe: timeframeLabel),
                    value: Self.money(window?.volumeUSD)
                )
                MarketMetric(label: String(localized: "market.liquidity", defaultValue: "Liquidity"),
                             value: Self.money(quote?.liquidityUSD))
                MarketMetric(
                    label: AppText.marketWindowTransactions(timeframe: timeframeLabel),
                    value: Self.transactions(buys: window?.buys, sells: window?.sells)
                )
                MarketMetric(
                    label: quote?.marketCapUSD == nil
                        ? String(localized: "market.fdv", defaultValue: "Fully diluted value")
                        : String(localized: "market.marketCap", defaultValue: "Market cap"),
                    value: Self.money(quote?.marketCapUSD ?? quote?.fullyDilutedValuationUSD)
                )
            }
            if let buys = window?.buys, let sells = window?.sells,
               window?.transactionCount ?? 0 > 0 {
                MarketActivityBar(buys: buys, sells: sells, timeframe: timeframeLabel)
            }
        }
    }

    private var marketActions: some View {
        HStack(spacing: Space.s8) {
            QuickLink(title: Str.marketView, systemImage: "safari.fill",
                      destination: store.marketQuote?.pairURL ?? AppLinks.market, prominent: true)
            Button {
                NSPasteboard.general.clearContents()
                guard NSPasteboard.general.setString(AppLinks.tokenContract, forType: .string) else {
                    return
                }
                copyFeedbackGeneration += 1
                let generation = copyFeedbackGeneration
                copiedContract = true
                Task {
                    try? await Task.sleep(for: .seconds(2))
                    guard generation == copyFeedbackGeneration else { return }
                    copiedContract = false
                }
            } label: {
                VStack(spacing: Space.s4) {
                    Image(systemName: copiedContract ? "checkmark" : "doc.on.doc.fill")
                        .font(Typo.iconMedium)
                    Text(Str.actionCopyContract).font(Typo.pill).lineLimit(1)
                }
                .foregroundStyle(copiedContract ? Palette.green : Palette.textSecond)
                .frame(maxWidth: .infinity)
                .padding(.vertical, Space.s8)
                .overlay(RoundedRectangle(cornerRadius: Radius.r8).strokeBorder(Palette.cardStroke))
            }
            .buttonStyle(GlassButtonStyle(shape: RoundedRectangle(cornerRadius: Radius.r8)))
            .help(copiedContract ? Str.actionContractCopied : Str.actionCopyContract)
            .accessibilityLabel(copiedContract ? Str.actionContractCopied : Str.actionCopyContract)
        }
    }

    private var selectedWindowChange: Double? {
        let change = store.marketQuote?.metrics(for: selectedTimeframe)?.changePercent
        if selectedTimeframe == .twentyFourHours { return change ?? store.cryptoChange24h }
        return change
    }

    private var timeframeLabel: String { timeframeLabel(for: selectedTimeframe) }

    /// The master switch is only effective when at least one rolling direction is selected. If a
    /// person explicitly re-enables from the otherwise inert “both directions off” state, restore
    /// both directions; a deliberate one-sided gain/loss choice is preserved unchanged.
    private var effectiveRollingMarketAlerts: Binding<Bool> {
        Binding(
            get: {
                store.cryptoAlertsEnabled
                    && (store.tokenChangeGainAlertsEnabled || store.tokenChangeLossAlertsEnabled)
            },
            set: { enabled in
                if enabled {
                    store.cryptoAlertsEnabled = true
                    if !store.tokenChangeGainAlertsEnabled && !store.tokenChangeLossAlertsEnabled {
                        store.tokenChangeGainAlertsEnabled = true
                        store.tokenChangeLossAlertsEnabled = true
                    }
                } else {
                    store.cryptoAlertsEnabled = false
                }
            }
        )
    }

    private var alertWindowLabel: String {
        switch store.cryptoAlertWindow {
        case .oneHour: return AppText.compactDuration(seconds: 3_600)
        case .sixHours: return AppText.compactDuration(seconds: 21_600)
        case .twentyFourHours: return AppText.compactDuration(seconds: 86_400)
        }
    }

    private func timeframeLabel(for timeframe: CryptoMarketTimeframe) -> String {
        switch timeframe {
        case .fiveMinutes: return AppText.compactDuration(seconds: 300)
        case .oneHour: return AppText.compactDuration(seconds: 3_600)
        case .sixHours: return AppText.compactDuration(seconds: 21_600)
        case .twentyFourHours: return AppText.compactDuration(seconds: 86_400)
        }
    }

    private static func money(_ value: Double?) -> String {
        guard let value, value.isFinite, value >= 0 else { return Glyph.noValue }
        let (scaled, suffix): (Double, String)
        switch value {
        case 1_000_000...: (scaled, suffix) = (value / 1_000_000, "M")
        case 1_000...: (scaled, suffix) = (value / 1_000, "K")
        default: (scaled, suffix) = (value, "")
        }
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = AppConfig.Crypto.currencyCode
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 2
        return (formatter.string(from: NSNumber(value: scaled)) ?? Glyph.noValue) + suffix
    }

    private static func transactions(buys: Int?, sells: Int?) -> String {
        guard buys != nil || sells != nil else { return Glyph.noValue }
        return "\((buys ?? 0).formatted()) / \((sells ?? 0).formatted())"
    }
}

private struct MarketMetric: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text(verbatim: label).font(Typo.statLabel).foregroundStyle(Palette.textTert)
            Text(value)
                .font(Typo.statValue)
                .monospacedDigit()
                .foregroundStyle(Palette.textPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Space.s10)
        .glassCard()
    }
}

private struct MarketActivityBar: View {
    let buys: Int
    let sells: Int
    let timeframe: String

    private var buyFraction: Double {
        let sum = buys.addingReportingOverflow(sells)
        let total = sum.overflow ? Int.max : max(1, sum.partialValue)
        return min(1, max(0, Double(buys) / Double(total)))
    }

    var body: some View {
        VStack(spacing: Space.s6) {
            HStack {
                Text(AppText.marketBuyShare(buyFraction))
                    .foregroundStyle(Palette.green)
                Spacer()
                Text(AppText.marketSellShare(1 - buyFraction))
                    .foregroundStyle(Palette.red)
            }
            .font(Typo.statLabel)
            .monospacedDigit()

            GeometryReader { proxy in
                HStack(spacing: Space.s2) {
                    Capsule()
                        .fill(Palette.green.opacity(Opacity.o80))
                        .frame(width: max(3, proxy.size.width * buyFraction - 1))
                    Capsule()
                        .fill(Palette.red.opacity(Opacity.o80))
                }
            }
            .frame(height: Space.s6)
            .accessibilityHidden(true)
        }
        .padding(.horizontal, Space.s10)
        .padding(.vertical, Space.s8)
        .glassCard()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(AppText.marketActivityAccessibility(
            timeframe: timeframe, buys: buys, sells: sells)))
    }
}

private struct MarketFeedPill: View {
    let title: LocalizedStringKey
    let state: DataFeedState

    private var tint: Color {
        switch state {
        case .live: return Palette.green
        case .cached: return Palette.gold
        case .unavailable: return Palette.red
        case .idle, .loading: return Palette.cyan
        }
    }

    private var status: LocalizedStringKey {
        switch state {
        case .live: return Str.feedLive
        case .cached: return Str.feedCached
        case .unavailable: return Str.feedUnavailable
        case .idle: return Str.feedWaiting
        case .loading: return Str.feedLoading
        }
    }

    var body: some View {
        HStack(spacing: Space.s4) {
            if state == .loading {
                ProgressView().controlSize(.mini).tint(tint)
            } else {
                Circle().fill(tint).frame(width: Space.s6, height: Space.s6)
                    .accessibilityHidden(true)
            }
            Text(title).foregroundStyle(Palette.textSecond)
            Text(status).foregroundStyle(tint)
        }
        .font(Typo.statLabel)
        .padding(.horizontal, Space.s7)
        .padding(.vertical, Space.s4)
        .background(Capsule().fill(tint.opacity(Opacity.o08)))
        .accessibilityElement(children: .combine)
    }
}
