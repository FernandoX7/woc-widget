import SwiftUI

// MARK: - Popover

struct PopoverView: View {
    var store: StatusStore
    @State private var selectedPage: DashboardPage = .overview
    @State private var showingSettings = false
    @State private var communityStore: CommunityStore
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(store: StatusStore, initialPage: DashboardPage = .overview,
         initiallyShowingSettings: Bool = false) {
        self.store = store
        _selectedPage = State(initialValue: initialPage)
        _showingSettings = State(initialValue: initiallyShowingSettings)
        _communityStore = State(initialValue: CommunityStore(
            releaseObserver: { [weak store] releases, observedAt in
                store?.observeGameReleases(releases, at: observedAt)
            },
            now: { [weak store] in store?.currentDate ?? Date() }
        ))
    }

    var body: some View {
        ZStack {
            if showingSettings {
                SettingsPanel(store: store) { showingSettings = false }
                    .transition(.opacity)
            } else {
                dashboard
                    .transition(.opacity)
            }
        }
        // One fixed size for every page prevents anchor jumps and protects the documented
        // MenuBarExtra(.window) re-presentation/idle-CPU guardrail.
        .frame(width: Size.popoverDashboardWidth, height: Size.popoverHeight, alignment: .top)
        .background(
            ZStack {
                Gradients.popoverBG
                if !reduceTransparency { Rectangle().fill(.ultraThinMaterial) }
            }
        )
        .overlay(RoundedRectangle(cornerRadius: Radius.r14)
            .strokeBorder(Gradients.popoverStroke, lineWidth: LineWidth.w075))
        .clipShape(RoundedRectangle(cornerRadius: Radius.r14))
        .environment(\.colorScheme, .dark)
        .animation(reduceMotion ? nil : Motion.settings, value: showingSettings)
        #if !PREVIEW
        .onAppear {
            store.setPopoverVisible(true)
            store.reconcileLaunchAtLogin()
            Task {
                async let permission: Void = store.refreshNotificationAuthorizationStatus()
                async let feeds: Void = store.refreshVisibleContent()
                _ = await (permission, feeds)
            }
        }
        .onDisappear {
            store.setPopoverVisible(false)
            store.flushHistory()
        }
        #endif
        .onKeyPress(.escape) {
            if showingSettings {
                showingSettings = false
                return .handled
            }
            return .ignored
        }
    }

    private var dashboard: some View {
        VStack(spacing: 0) {
            HeaderView(store: store)
                .padding(.horizontal, Space.s16)
                .padding(.top, Space.s16)
                .padding(.bottom, Space.s10)

            DashboardPageSwitcher(selection: $selectedPage)
                .padding(.horizontal, Space.s16)
                .padding(.bottom, Space.s8)

            Group {
                switch selectedPage {
                case .overview:
                    OverviewPageView(store: store)
                case .market:
                    MarketPageView(store: store)
                case .community:
                    CommunityPageView(store: communityStore, statusStore: store)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

            FooterView(
                store: store,
                communityStore: communityStore,
                selectedPage: selectedPage,
                showingSettings: $showingSettings
            )
                .padding(.horizontal, Space.s16)
                .padding(.top, Space.s8)
                .padding(.bottom, Space.s16)
        }
    }
}
