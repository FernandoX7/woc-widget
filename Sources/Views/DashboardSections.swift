import SwiftUI
import AppKit

// Dashboard sections as standalone structs so `@Observable` dependency tracking is scoped per
// section: a crypto-price tick re-renders only the header, the footer's 1-second tick re-renders
// only the footer, and the chart card re-renders only when range/interval/history change. Every
// token/value/string is moved verbatim from the prior computed-property version (guardrail 9).

// MARK: - Header

struct HeaderView: View {
    var store: StatusStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @ViewBuilder
    var body: some View {
        let countText = store.hasStatusResponse ? "\(store.count)" : Glyph.noValue
        if dynamicTypeSize.isAccessibilitySize {
            // At accessibility sizes the count, a long realm, quote, and badge cannot all share
            // one 440-point row. Stack only this header while the page bodies keep scrolling; the
            // default layout below stays pixel-identical and the popover's outer size stays fixed.
            VStack(alignment: .leading, spacing: Space.s6) {
                HStack(alignment: .center, spacing: Space.s8) {
                    realmTitle
                    Spacer(minLength: Space.s8)
                    StatusBadgeView(store: store)
                }
                HeaderMarketPill(store: store)
                countStatus(countText)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            HStack(alignment: .center, spacing: Space.s12) {
                VStack(alignment: .leading, spacing: Space.s1) {
                    HStack(alignment: .center, spacing: Space.s6) {
                        realmTitle

                        // Population and $WOC are the companion's two peer signals. Keep the market
                        // pill in place while it loads or is unavailable so the header never implies
                        // that one side of that pairing simply does not exist.
                        HeaderMarketPill(store: store)
                    }
                    countStatus(countText)
                }
                Spacer()
                StatusBadgeView(store: store)
            }
        }
    }

    private var realmTitle: some View {
        Text(store.realm.uppercased())
            .font(Typo.titleHeavy)
            .tracking(Tracking.t16)
            .foregroundStyle(Gradients.brandDiagonal)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
    }

    private func countStatus(_ countText: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Space.s7) {
            Text(countText)
                .font(Typo.count)
                .monospacedDigit()
                .foregroundStyle(Palette.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .contentTransition(.numericText())
                // Honor Reduce Motion: the digit-roll is the kind of motion that setting asks to
                // suppress. `nil` snaps the value instead; neither path runs while idle.
                .animation(reduceMotion ? nil : Motion.count, value: countText)
            Text(headerStatusLabel)
                .font(Typo.online)
                .foregroundStyle(Palette.textSecond)
                .offset(y: Size.onlineBaselineOffset)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(AppText.menuBarStatus(
            availability: store.realmAvailability,
            syncing: store.realmAvailability == .loading,
            count: store.response?.playersOnline
        )))
    }

    private var headerStatusLabel: LocalizedStringKey {
        switch store.realmAvailability {
        case .healthy:
            return Str.headerOnline
        case .loading:
            return Str.badgeSync
        case .serverReportedDown:
            return Str.badgeOffline
        case .unreachable:
            return store.hasStatusResponse ? Str.feedShowingCached : Str.feedUnavailable
        }
    }
}

private struct HeaderMarketPill: View {
    var store: StatusStore

    var body: some View {
        HStack(spacing: Space.s4) {
            switch store.priceFeedState {
            case .cached:
                Image(systemName: "clock.badge.exclamationmark")
                    .font(Typo.dot)
                    .foregroundStyle(Palette.gold)
                    .accessibilityHidden(true)
            case .idle, .loading:
                placeholder(systemImage: "clock", color: Palette.gold)
            case .unavailable:
                placeholder(systemImage: "wifi.exclamationmark", color: Palette.red)
            case .live:
                quote
            }

            if store.priceFeedState == .cached {
                quote
            }
        }
        .padding(.horizontal, Space.s6)
        .padding(.vertical, Space.s2)
        .glassPill(stroke: pillStroke)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(accessibilitySummary))
        .help(helpText)
    }

    @ViewBuilder
    private var quote: some View {
        if let price = store.cryptoPrice {
            Text(CryptoFormat.price(price))
                .font(Typo.sectionLabel)
                .foregroundStyle(Palette.textPrimary)
            if let change = store.cryptoChange24h {
                Text(CryptoFormat.signedChange(change))
                    .font(Typo.cryptoChange)
                    .foregroundStyle(change >= 0 ? Palette.green : Palette.red)
            }
        } else {
            Text(Str.marketTokenSymbol)
                .font(Typo.sectionLabel)
                .foregroundStyle(Palette.textSecond)
            Text(Glyph.noValue)
                .font(Typo.sectionLabel)
                .foregroundStyle(Palette.textTert)
        }
    }

    @ViewBuilder
    private func placeholder(systemImage: String, color: Color) -> some View {
        Image(systemName: systemImage)
            .font(Typo.dot)
            .foregroundStyle(color)
            .accessibilityHidden(true)
        Text(Str.marketTokenSymbol)
            .font(Typo.sectionLabel)
            .foregroundStyle(Palette.textSecond)
        Text(Glyph.noValue)
            .font(Typo.sectionLabel)
            .foregroundStyle(Palette.textTert)
    }

    private var pillStroke: Color {
        switch store.priceFeedState {
        case .cached, .idle, .loading: return Palette.gold.opacity(Opacity.o25)
        case .unavailable: return Palette.red.opacity(Opacity.o25)
        case .live: return Palette.cardStroke
        }
    }

    private var helpText: LocalizedStringKey {
        switch store.priceFeedState {
        case .idle, .loading: return Str.feedLoading
        case .unavailable: return Str.feedUnavailable
        case .cached: return Str.feedCached
        case .live: return Str.feedLive
        }
    }

    private var accessibilitySummary: String {
        switch store.priceFeedState {
        case .idle, .loading:
            return AppText.marketQuoteLoadingAccessibility
        case .unavailable:
            return AppText.marketQuoteUnavailableAccessibility
        case .live, .cached:
            guard let price = store.cryptoPrice else {
                return AppText.marketQuoteUnavailableAccessibility
            }
            return AppText.marketQuoteAccessibility(
                price: price,
                change24h: store.cryptoChange24h,
                cached: store.priceFeedState == .cached
            )
        }
    }
}

struct StatusBadgeView: View {
    var store: StatusStore
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let on = store.realmAvailability == .healthy
        let color: Color
        let label: LocalizedStringKey
        switch store.realmAvailability {
        case .healthy:
            color = Palette.cyan; label = Str.badgeLive
        case .loading:
            color = Palette.gold; label = Str.badgeSync
        case .serverReportedDown:
            color = Palette.red; label = Str.badgeOffline
        case .unreachable:
            color = store.hasStatusResponse ? Palette.gold : Palette.red
            label = store.hasStatusResponse ? Str.feedCached : Str.feedUnavailable
        }
        return HStack(spacing: Space.s5) {
            if on {
                Image(systemName: "circle.fill")
                    .font(Typo.dot)
                    .foregroundStyle(Gradients.brandDiagonal)
                    .shadow(color: Palette.cyan.opacity(Opacity.o80), radius: Shadow.badgeDotRadius)
                    .accessibilityHidden(true)   // decorative — the adjacent badge text states the status
                    // Only pulse while the popover is actually on screen. A perpetual animation here
                    // keeps MenuBarExtra(.window) re-measuring/re-presenting its content in a loop
                    // even while closed — the source of the steady ~40% idle CPU. Gating on
                    // scenePhase stops it when the popover is shut. NOTE: this `scenePhase == .active
                    // && !reduceMotion` gate is mirrored in `StatusDot` (Components.swift) — keep the
                    // two in lockstep (guardrail 1). This dot uses a fixed cyan glow; StatusDot's is
                    // color-derived, which is why they aren't a single shared view.
                    .symbolEffect(.pulse, options: .repeating, isActive: scenePhase == .active && !reduceMotion)
            } else {
                StatusDot(color: color, active: false)
            }
            Text(label)
                .font(Typo.badgeLabel)
                .tracking(Tracking.t08)
                .foregroundStyle(on ? AnyShapeStyle(Gradients.brandHorizontal) : AnyShapeStyle(color))
        }
        .padding(.horizontal, Space.s9)
        .padding(.vertical, Space.s6)
        .glassPill(stroke: color.opacity(on ? Opacity.o40 : Opacity.o25))
    }
}

// MARK: - Overview page

struct OverviewPageView: View {
    var store: StatusStore

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: Space.s12) {
                    if !store.welcomeDismissed {
                        WelcomeCard(store: store)
                    }
                    statusBanner
                    ChartCardView(store: store)
                    RealmRhythmCard(store: store)
                }
                .padding(.horizontal, Space.s16)
                .padding(.top, Space.s12)
            }

            HStack(spacing: Space.s8) {
                QuickLink(title: Str.actionPlay, systemImage: "play.fill",
                          destination: AppLinks.play, prominent: true)
                QuickLink(title: Str.actionWiki, systemImage: "book.closed.fill",
                          destination: AppLinks.wiki)
                QuickLink(title: Str.actionHighScores, systemImage: "trophy.fill",
                          destination: AppLinks.highScores)
            }
            .padding(.horizontal, Space.s16)
            .padding(.top, Space.s10)
        }
    }

    @ViewBuilder
    private var statusBanner: some View {
        switch store.realmAvailability {
        case .healthy:
            EmptyView()
        case .loading:
            if !store.hasStatusResponse {
                StatusMessageBanner(
                    title: Str.badgeSync,
                    detail: nil,
                    color: Palette.gold,
                    systemImage: "arrow.triangle.2.circlepath"
                ) { Task { await store.refreshStatus() } }
            }
        case .serverReportedDown:
            StatusMessageBanner(
                title: Str.badgeOffline,
                detail: store.errorMessage,
                color: Palette.red,
                systemImage: "exclamationmark.triangle.fill"
            ) { Task { await store.refreshStatus() } }
        case .unreachable:
            StatusMessageBanner(
                title: store.hasStatusResponse ? Str.feedShowingCached : Str.feedUnavailable,
                detail: store.errorMessage,
                color: store.hasStatusResponse ? Palette.gold : Palette.red,
                systemImage: "wifi.exclamationmark"
            ) { Task { await store.refreshStatus() } }
        }
    }
}

private struct StatusMessageBanner: View {
    let title: LocalizedStringKey
    let detail: String?
    let color: Color
    let systemImage: String
    let retry: () -> Void

    var body: some View {
        HStack(spacing: Space.s8) {
            Image(systemName: systemImage).foregroundStyle(color)
            VStack(alignment: .leading, spacing: Space.s1) {
                Text(title).font(Typo.rowLabel).foregroundStyle(Palette.textPrimary)
                if let detail {
                    Text(detail).font(Typo.timestamp).foregroundStyle(Palette.textTert)
                }
            }
            Spacer()
            Button(Str.feedRetry, action: retry)
                .buttonStyle(.plain)
                .font(Typo.buttonLabel)
                .foregroundStyle(color)
        }
        .padding(.horizontal, Space.s12)
        .padding(.vertical, Space.s8)
        .background(RoundedRectangle(cornerRadius: Radius.r8).fill(color.opacity(Opacity.o08)))
        .overlay(RoundedRectangle(cornerRadius: Radius.r8).strokeBorder(color.opacity(Opacity.o25)))
    }
}

// MARK: - Chart card

struct ChartCardView: View {
    @Bindable var store: StatusStore
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        // The range drives an automatic minimum-resolution series. This keeps the compact chart
        // honest: every shown label is the named interval actually used for the buckets.
        let resolution = ChartInterval.automatic(for: store.range)
        let data = store.series(range: store.range, interval: resolution)
        VStack(alignment: .leading, spacing: Space.s9) {
            HStack {
                Text(Str.chartTitle)
                    .font(Typo.sectionLabel)
                    .tracking(Tracking.t08)
                    .foregroundStyle(Palette.textSecond)
                Spacer()
                Text(AppText.chartResolution(resolution.label))
                    .font(Typo.timestamp)
                    .foregroundStyle(Palette.textTert)
            }
            pickerRow(title: Str.chartRange) {
                Picker("", selection: $store.range) {
                    ForEach(ChartRange.allCases) { Text($0.label).tag($0) }
                }
                .accessibilityLabel(Str.chartRange)
            }

            PlayerChart(data: data, interval: resolution, range: store.range,
                        expectedSampleInterval: store.pollSeconds,
                        referenceDate: store.currentDate)
                .frame(height: Size.chartHeight)

            StatsRow(data: data, store: store)
        }
        .padding(Space.s12)
        .glassCard()
    }

    private func pickerRow<P: View>(title: LocalizedStringKey, @ViewBuilder _ picker: () -> P) -> some View {
        HStack(spacing: Space.s8) {
            Text(title)
                .font(Typo.pickerRowLabel)
                .tracking(Tracking.t06)
                .foregroundStyle(Palette.textTert)
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

struct StatsRow: View {
    let data: [Sample]
    var store: StatusStore

    var body: some View {
        let avg = HistoryAnalytics.average(of: data)
        let delta = store.thirtyMinuteChange
        return HStack(spacing: Space.s0) {
            StatBox(label: Str.statChange30m,
                    value: delta.map { "\($0 >= 0 ? "+" : "")\($0)" } ?? Glyph.noValue,
                    tint: (delta ?? 0) >= 0 ? Palette.cyan : Palette.red)
            StatDivider()
            StatBox(label: Str.statTodayHigh,
                    value: store.hasPopulationHistory ? "\(store.todayPeak)" : Glyph.noValue)
            StatDivider()
            StatBox(label: Str.statLocalRecord,
                    value: store.hasLocalRecord ? "\(store.allTimePeak)" : Glyph.noValue,
                    tint: Palette.cyan)
            StatDivider()
            StatBox(label: Str.statRangeAverage, value: avg.map(String.init) ?? Glyph.noValue)
        }
    }

}

private struct StatDivider: View {
    var body: some View {
        Rectangle().fill(Palette.cardStroke).frame(width: Size.dividerWidth, height: Size.dividerHeight)
    }
}

// MARK: - Footer

struct FooterView: View {
    var store: StatusStore
    var communityStore: CommunityStore
    let selectedPage: DashboardPage
    @Binding var showingSettings: Bool

    var body: some View {
        HStack(spacing: Space.s10) {
            Button { Task { await refreshSelectedPage() } } label: {
                HStack(spacing: Space.s6) {
                    if refreshing {
                        ProgressView().controlSize(.small).scaleEffect(Size.progressScale)
                            .frame(width: Size.progressSide, height: Size.progressSide)
                    } else {
                        Image(systemName: "arrow.clockwise").font(Typo.refreshIcon)
                    }
                    Text(Str.footerRefresh).font(Typo.buttonLabel)
                }
                .foregroundStyle(Palette.textPrimary)
                .padding(.horizontal, Space.s12).padding(.vertical, Space.s7)
                .overlay(Capsule().strokeBorder(Palette.cyan.opacity(Opacity.o30)))
            }
            .buttonStyle(GlassButtonStyle(shape: Capsule()))
            .disabled(refreshing)
            .keyboardShortcut("r", modifiers: .command)

            TimelineView(.periodic(from: .now, by: 1)) { _ in
                Text(AppText.relativeUpdated(lastUpdated, now: { store.currentDate }))
                    .font(Typo.timestamp)
                    .foregroundStyle(Palette.textTert)
            }

            Spacer()

            Button {
                showingSettings = true
            } label: {
                Image(systemName: "gearshape.fill")
                    .font(Typo.iconMedium)
                    .foregroundStyle(Palette.textSecond)
                    .frame(width: Size.iconButtonSide, height: Size.iconButtonSide)
                    .overlay(Circle().strokeBorder(Palette.cardStroke))
            }
            .buttonStyle(GlassButtonStyle(shape: Circle()))
            .help(Str.footerSettingsHelp)
            .accessibilityLabel(Str.footerSettingsHelp)
            .keyboardShortcut(",", modifiers: .command)

            Button { NSApplication.shared.terminate(nil) } label: {
                Image(systemName: "power")
                    .font(Typo.iconMedium)
                    .foregroundStyle(Palette.textSecond)
                    .frame(width: Size.iconButtonSide, height: Size.iconButtonSide)
                    .overlay(Circle().strokeBorder(Palette.cardStroke))
            }
            .buttonStyle(GlassButtonStyle(shape: Circle()))
            .help(Str.footerQuitHelp)
            .accessibilityLabel(Str.footerQuitHelp)
            .keyboardShortcut("q", modifiers: .command)
        }
    }

    /// The footer belongs to the selected destination, so both its activity indicator and its
    /// timestamp must describe that destination's feeds rather than whichever unrelated timer
    /// happened to finish most recently.
    private var refreshing: Bool {
        switch selectedPage {
        case .overview:
            return store.isRefreshing || store.isPriceRefreshing
        case .market:
            return store.isPriceRefreshing || store.isCandlesRefreshing
        case .community:
            return communityStore.phase == .loading
        }
    }

    private var lastUpdated: Date? {
        switch selectedPage {
        case .overview:
            // The overview deliberately keeps realm population and $WOC together. Its freshness
            // therefore reflects the older of the two visible live signals, never just whichever
            // request happened to finish most recently.
            return [store.lastSuccess, store.priceLastSuccess].compactMap { $0 }.min()
        case .market: return store.marketLastSuccess
        case .community: return communityStore.lastSuccess
        }
    }

    private func refreshSelectedPage() async {
        switch selectedPage {
        case .overview:
            async let status: Void = store.refreshStatus()
            async let quote: Void = store.refreshCrypto()
            _ = await (status, quote)
        case .market:
            async let price: Void = store.refreshCrypto()
            async let candles: Void = store.refreshCandles()
            _ = await (price, candles)
        case .community:
            await communityStore.refresh()
        }
    }
}
