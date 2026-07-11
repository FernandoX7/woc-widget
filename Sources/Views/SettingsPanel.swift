import SwiftUI
import AppKit

// MARK: - Inline Settings

struct SettingsPanel: View {
    @Bindable var store: StatusStore
    var onClose: () -> Void
    @State private var requestedLaunchAtLogin = false
    @State private var exportError: String?
    @State private var exportInFlight = false
    @State private var exportSucceeded = false
    @State private var notificationTestRequested = false
    @State private var showingClearHistoryConfirmation = false
    @State private var clearHistoryInFlight = false
    @State private var historyCleared = false

    var body: some View {
        VStack(spacing: Space.s10) {
            topBar

            ScrollView {
                VStack(spacing: Space.s10) {
                    appearanceSection
                    refreshSection
                    notificationSection
                    marketAlertSection
                    systemSection
                    dataPrivacySection
                    aboutSection
                }
                .padding(.vertical, Space.s2)
            }

            Text(Str.settingsAutoSaved)
                .font(Typo.timestamp)
                .foregroundStyle(Palette.textTert)

            doneButton
        }
        .padding(Space.s16)
        .confirmationDialog(
            Str.settingsClearHistoryConfirmationTitle,
            isPresented: $showingClearHistoryConfirmation,
            titleVisibility: .visible
        ) {
            Button(Str.settingsClearHistoryConfirm, role: .destructive) {
                clearLocalHistory()
            }
            Button(Str.settingsCancel, role: .cancel) {}
        } message: {
            Text(Str.settingsClearHistoryConfirmationMessage)
        }
    }

    private var topBar: some View {
        ZStack {
            Text(Str.settingsTitle)
                .font(Typo.titleHeavy)
                .tracking(Tracking.t18)
                .foregroundStyle(Gradients.brandHorizontal)
            HStack {
                Button(action: onClose) {
                    Image(systemName: "chevron.left")
                        .font(Typo.chevron)
                        .foregroundStyle(Palette.textSecond)
                        .frame(width: Size.iconButtonSide, height: Size.iconButtonSide)
                        .overlay(Circle().strokeBorder(Palette.cardStroke))
                }
                .buttonStyle(GlassButtonStyle(shape: Circle()))
                .help(Str.settingsBackHelp)
                .accessibilityLabel(Str.settingsBackHelp)
                Spacer()
            }
        }
    }

    private var appearanceSection: some View {
        sectionCard(Str.settingsAppearance, systemImage: "menubar.rectangle") {
            VStack(alignment: .leading, spacing: Space.s6) {
                rowLabel(Str.settingsMenuBar)
                Picker("", selection: $store.menuBarDisplayMode) {
                    Text(Str.settingsMenuPlayersChange).tag(MenuBarDisplayMode.playersAndChange)
                    Text(Str.settingsMenuFull).tag(MenuBarDisplayMode.full)
                    Text(Str.settingsMenuPlayers).tag(MenuBarDisplayMode.players)
                    Text(Str.settingsMenuToken).tag(MenuBarDisplayMode.token)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .controlSize(.small)
                .accessibilityLabel(Str.settingsMenuBar)
            }
        }
    }

    private var refreshSection: some View {
        sectionCard(Str.settingsGeneral, systemImage: "arrow.triangle.2.circlepath") {
            VStack(alignment: .leading, spacing: Space.s12) {
                intervalPicker(Str.settingsPlayerRefresh,
                               selection: $store.pollSeconds,
                               options: PollInterval.playerOptions)
                intervalPicker(Str.settingsCryptoRefresh,
                               selection: $store.cryptoPollSeconds,
                               options: PollInterval.cryptoOptions)
            }
        }
    }

    private var notificationSection: some View {
        sectionCard(Str.settingsNotifications, systemImage: "bell.fill") {
            VStack(alignment: .leading, spacing: Space.s10) {
                notificationCategorySummary
                notificationPermissionRow
                Divider().overlay(Palette.cardStroke)
                categoryLabel(Str.settingsNotificationsRealmCategory,
                              systemImage: "person.2.fill", tint: Palette.cyan)
                toggleRow(Str.settingsServerAlerts, isOn: $store.alertsEnabled)
                toggleRow(Str.settingsPeakAlerts, isOn: $store.peakAlertsEnabled)
                toggleRow(Str.settingsPopulationAlerts,
                          isOn: $store.populationThresholdAlertsEnabled)
                if store.populationThresholdAlertsEnabled {
                    Stepper(value: $store.populationAlertThreshold,
                            in: AppConfig.AdvancedAlert.populationRange,
                            step: AppConfig.AdvancedAlert.populationStep) {
                        HStack {
                            Text(Str.settingsPopulationAtLeast)
                                .font(Typo.timestamp)
                                .foregroundStyle(Palette.textSecond)
                            Spacer()
                            Text("\(store.populationAlertThreshold)")
                                .font(Typo.thresholdValue)
                                .monospacedDigit()
                                .foregroundStyle(Palette.cyan)
                        }
                    }
                    .controlSize(.small)
                }
                Divider().overlay(Palette.cardStroke)
                categoryLabel(Str.settingsNotificationsGameCategory,
                              systemImage: "sparkles", tint: Palette.violet)
                toggleRow(Str.settingsReleaseAlerts, isOn: $store.releaseAlertsEnabled)
                Divider().overlay(Palette.cardStroke)
                categoryLabel(Str.settingsNotificationsDeliveryCategory,
                              systemImage: "clock.fill", tint: Palette.textSecond)
                alertCooldownPicker
                quietHoursControls
            }
        }
    }

    private var notificationCategorySummary: some View {
        VStack(alignment: .leading, spacing: Space.s4) {
            Text(Str.settingsNotificationsExplanation)
                .font(Typo.timestamp)
                .foregroundStyle(Palette.textSecond)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: Space.s12) {
                categoryLabel(Str.settingsNotificationsRealmCategory,
                              systemImage: "person.2.fill", tint: Palette.cyan)
                categoryLabel(Str.settingsNotificationsGameCategory,
                              systemImage: "sparkles", tint: Palette.violet)
                categoryLabel(Str.settingsNotificationsMarketCategory,
                              systemImage: "chart.line.uptrend.xyaxis", tint: Palette.gold)
            }
        }
    }

    private func categoryLabel(_ title: LocalizedStringKey, systemImage: String,
                               tint: Color) -> some View {
        Label(title, systemImage: systemImage)
            .font(Typo.timestamp)
            .foregroundStyle(tint)
    }

    @ViewBuilder
    private var notificationPermissionRow: some View {
        switch store.notificationAuthorizationState {
        case .unknown:
            HStack {
                ProgressView().controlSize(.small)
                Text(Str.settingsNotificationsChecking)
                    .font(Typo.timestamp)
                    .foregroundStyle(Palette.textTert)
            }
        case .notDetermined:
            SettingsActionRow(
                title: Str.settingsNotificationsAllow,
                systemImage: "bell.badge.fill",
                tint: Palette.cyan
            ) {
                Task { await store.requestNotificationAuthorization() }
            }
        case .denied:
            VStack(alignment: .leading, spacing: Space.s6) {
                HStack(alignment: .top, spacing: Space.s8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(Palette.gold)
                        .accessibilityHidden(true)
                    Text(store.notificationsBlocked
                         ? Str.settingsNotificationsBlockedAlerts
                         : Str.settingsNotificationsDenied)
                        .font(Typo.timestamp)
                        .foregroundStyle(Palette.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(Space.s8)
                .background(RoundedRectangle(cornerRadius: Radius.r8)
                    .fill(Palette.gold.opacity(Opacity.o08)))
                .overlay(RoundedRectangle(cornerRadius: Radius.r8)
                    .strokeBorder(Palette.gold.opacity(Opacity.o30)))
                SettingsActionRow(
                    title: Str.settingsNotificationsOpen,
                    systemImage: "gearshape.fill",
                    tint: Palette.gold
                ) { NSWorkspace.shared.open(AppLinks.notificationSettings) }
            }
        case .authorized, .provisional, .ephemeral:
            SettingsActionRow(
                title: Str.settingsNotificationsTest,
                systemImage: "paperplane.fill",
                tint: Palette.green
            ) {
                notificationTestRequested = store.postTestNotification(
                    title: AppText.notificationTestTitle,
                    body: AppText.notificationTestBody
                )
            }
            if notificationTestRequested {
                Label(Str.settingsNotificationsTestRequested,
                      systemImage: "checkmark.circle.fill")
                    .font(Typo.timestamp)
                    .foregroundStyle(Palette.green)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var marketAlertSection: some View {
        sectionCard(Str.settingsCrypto, systemImage: "chart.line.uptrend.xyaxis") {
            VStack(alignment: .leading, spacing: Space.s10) {
                Text(Str.settingsMarketAlertsExplanation)
                    .font(Typo.timestamp)
                    .foregroundStyle(Palette.textSecond)
                    .fixedSize(horizontal: false, vertical: true)
                toggleRow(Str.settingsCryptoAlerts, isOn: $store.cryptoAlertsEnabled)
                if store.cryptoAlertsEnabled {
                    VStack(alignment: .leading, spacing: Space.s6) {
                        HStack(spacing: Space.s12) {
                            Toggle(isOn: $store.tokenChangeGainAlertsEnabled) {
                                rowLabel(Str.settingsGainAlerts)
                            }
                            Toggle(isOn: $store.tokenChangeLossAlertsEnabled) {
                                rowLabel(Str.settingsLossAlerts)
                            }
                        }
                        .toggleStyle(.switch)
                        .controlSize(.small)
                        .tint(Palette.cyan)

                        rowLabel(Str.settingsRollingWindow)
                        Picker("", selection: $store.cryptoAlertWindow) {
                            Text(Str.settingsWindow1h).tag(TokenChangeAlertWindow.oneHour)
                            Text(Str.settingsWindow6h).tag(TokenChangeAlertWindow.sixHours)
                            Text(Str.settingsWindow24h).tag(TokenChangeAlertWindow.twentyFourHours)
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .controlSize(.small)
                        .accessibilityLabel(Str.settingsRollingWindow)

                        HStack {
                            rowLabel(Str.settingsThreshold)
                            Spacer()
                            Text("\(Int(store.cryptoAlertThreshold))%")
                                .font(Typo.thresholdValue)
                                .monospacedDigit()
                                .foregroundStyle(Palette.cyan)
                        }
                        Slider(value: $store.cryptoAlertThreshold,
                               in: AppConfig.CryptoAlert.sliderRange,
                               step: AppConfig.CryptoAlert.sliderStep)
                            .controlSize(.small)
                            .tint(Palette.cyan)
                            .accessibilityLabel(Str.settingsThreshold)
                            .accessibilityValue(Text(AppText.percentageAccessibility(
                                Int(store.cryptoAlertThreshold))))
                    }
                }

                Divider().overlay(Palette.cardStroke)
                rowLabel(Str.settingsPriceTargets)
                priceTargetRow(Str.settingsPriceAbove,
                               isOn: $store.tokenPriceAboveAlertsEnabled,
                               target: $store.tokenPriceAboveTarget)
                priceTargetRow(Str.settingsPriceBelow,
                               isOn: $store.tokenPriceBelowAlertsEnabled,
                               target: $store.tokenPriceBelowTarget)
            }
        }
    }

    private var alertCooldownPicker: some View {
        HStack {
            rowLabel(Str.settingsCooldown)
            Spacer()
            Picker("", selection: $store.advancedAlertCooldown) {
                ForEach(AlertCooldownOption.allCases) { option in
                    Text(cooldownLabel(option)).tag(option.seconds)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .controlSize(.small)
            .frame(width: Size.settingsControlWidth)
            .accessibilityLabel(Str.settingsCooldown)
        }
    }

    private func cooldownLabel(_ option: AlertCooldownOption) -> LocalizedStringKey {
        switch option {
        case .off: return Str.settingsCooldownOff
        case .fifteenMinutes: return Str.settingsCooldown15m
        case .oneHour: return Str.settingsCooldown1h
        case .fourHours: return Str.settingsCooldown4h
        case .oneDay: return Str.settingsCooldown1d
        }
    }

    private var quietHoursControls: some View {
        VStack(alignment: .leading, spacing: Space.s6) {
            toggleRow(Str.settingsQuietHours, isOn: $store.advancedAlertQuietHoursEnabled)
            if store.advancedAlertQuietHoursEnabled {
                HStack(spacing: Space.s8) {
                    compactTimePicker(Str.settingsQuietFrom, selection: quietStartBinding)
                    compactTimePicker(Str.settingsQuietTo, selection: quietEndBinding)
                }
            }
        }
    }

    private func compactTimePicker(_ title: LocalizedStringKey,
                                   selection: Binding<Date>) -> some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text(title).font(Typo.timestamp).foregroundStyle(Palette.textTert)
            DatePicker("", selection: selection, displayedComponents: .hourAndMinute)
                .labelsHidden()
                .controlSize(.small)
                .accessibilityLabel(title)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func priceTargetRow(_ title: LocalizedStringKey, isOn: Binding<Bool>,
                                target: Binding<Double>) -> some View {
        HStack(spacing: Space.s8) {
            Toggle(isOn: isOn) { rowLabel(title) }
                .toggleStyle(.switch)
                .controlSize(.small)
                .tint(Palette.cyan)
            Spacer()
            Text("$")
                .font(Typo.timestamp)
                .foregroundStyle(Palette.textTert)
            TextField("", value: target,
                      format: .number.precision(.significantDigits(1...8)))
                .textFieldStyle(.roundedBorder)
                .font(Typo.timestamp.monospacedDigit())
                .frame(width: Size.settingsControlWidth)
                .accessibilityLabel(title)
        }
    }

    private var quietStartBinding: Binding<Date> {
        alertTimeBinding(\.advancedAlertQuietStartMinute)
    }

    private var quietEndBinding: Binding<Date> {
        alertTimeBinding(\.advancedAlertQuietEndMinute)
    }

    private func alertTimeBinding(_ keyPath: ReferenceWritableKeyPath<StatusStore, Int>)
    -> Binding<Date> {
        Binding(
            get: {
                let minute = store[keyPath: keyPath]
                var calendar = Calendar(identifier: .gregorian)
                calendar.timeZone = .current
                return calendar.date(from: DateComponents(year: 2001, month: 1, day: 1,
                                                          hour: minute / 60,
                                                          minute: minute % 60)) ?? Date()
            },
            set: { date in
                var calendar = Calendar(identifier: .gregorian)
                calendar.timeZone = .current
                let components = calendar.dateComponents([.hour, .minute], from: date)
                store[keyPath: keyPath] = (components.hour ?? 0) * 60 + (components.minute ?? 0)
            }
        )
    }

    private var systemSection: some View {
        sectionCard(Str.settingsSystem, systemImage: "macwindow") {
            VStack(alignment: .leading, spacing: Space.s8) {
                Toggle(isOn: launchBinding) { rowLabel(Str.settingsLaunchAtLogin) }
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .tint(Palette.cyan)
                if requestedLaunchAtLogin && !store.launchAtLogin {
                    Text(Str.settingsApprovalRequired)
                        .font(Typo.timestamp)
                        .foregroundStyle(Palette.gold)
                    SettingsActionRow(
                        title: Str.settingsOpenLoginItems,
                        systemImage: "gearshape.fill",
                        tint: Palette.gold
                    ) { NSWorkspace.shared.open(AppLinks.loginItemsSettings) }
                }
            }
        }
    }

    private var dataPrivacySection: some View {
        sectionCard(Str.settingsDataPrivacy, systemImage: "hand.raised.fill") {
            VStack(alignment: .leading, spacing: Space.s10) {
                VStack(alignment: .leading, spacing: Space.s4) {
                    Label(Str.settingsLocalDataTitle, systemImage: "internaldrive.fill")
                        .font(Typo.rowLabel)
                        .foregroundStyle(Palette.cyan)
                    Text(Str.settingsLocalDataDetail)
                        .font(Typo.timestamp)
                        .foregroundStyle(Palette.textSecond)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Divider().overlay(Palette.cardStroke)

                VStack(alignment: .leading, spacing: Space.s4) {
                    rowLabel(Str.settingsExportHistoryTitle)
                    Text(Str.settingsExportHistoryDetail)
                        .font(Typo.timestamp)
                        .foregroundStyle(Palette.textTert)
                }
                HStack(spacing: Space.s8) {
                    exportButton(Str.actionExportCSV, format: .csv)
                    exportButton(Str.actionExportJSON, format: .json)
                }
                if let exportError {
                    Text(exportError).font(Typo.timestamp).foregroundStyle(Palette.red)
                }
                if exportSucceeded {
                    Label(Str.settingsExportSaved, systemImage: "checkmark.circle.fill")
                        .font(Typo.timestamp)
                        .foregroundStyle(Palette.green)
                }
                if let error = store.historyPersistenceError {
                    Text(error).font(Typo.timestamp).foregroundStyle(Palette.gold)
                }

                Divider().overlay(Palette.cardStroke)

                Button(role: .destructive) {
                    showingClearHistoryConfirmation = true
                } label: {
                    HStack(spacing: Space.s8) {
                        if clearHistoryInFlight {
                            ProgressView().controlSize(.small)
                        } else {
                            Image(systemName: "trash.fill")
                                .accessibilityHidden(true)
                        }
                        Text(Str.settingsClearHistory)
                            .font(Typo.buttonLabel)
                        Spacer()
                    }
                    .foregroundStyle(Palette.red)
                    .padding(.vertical, Space.s7)
                    .padding(.horizontal, Space.s8)
                    .overlay(RoundedRectangle(cornerRadius: Radius.r8)
                        .strokeBorder(Palette.red.opacity(Opacity.o30)))
                }
                .buttonStyle(.plain)
                .disabled(clearHistoryInFlight || !store.hasLocalRecord)

                Text(Str.settingsClearHistoryDetail)
                    .font(Typo.timestamp)
                    .foregroundStyle(Palette.textTert)
                    .fixedSize(horizontal: false, vertical: true)
                if historyCleared {
                    Label(Str.settingsHistoryCleared, systemImage: "checkmark.circle.fill")
                        .font(Typo.timestamp)
                        .foregroundStyle(Palette.green)
                }
            }
        }
    }

    private var aboutSection: some View {
        sectionCard(Str.settingsAbout, systemImage: "info.circle.fill") {
            VStack(alignment: .leading, spacing: Space.s10) {
                HStack(spacing: Space.s10) {
                    Image(systemName: "moon.stars.fill")
                        .font(Typo.placeholderIcon)
                        .foregroundStyle(Gradients.brandHorizontal)
                        .frame(width: Size.iconButtonSide, height: Size.iconButtonSide)
                        .background(Circle().fill(Palette.violet.opacity(Opacity.o20)))
                        .overlay(Circle().strokeBorder(Palette.cardStroke))
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: Space.s2) {
                        Text(Str.appTitle)
                            .font(Typo.emphasis)
                            .foregroundStyle(Palette.textPrimary)
                        Text(appVersionSummary)
                            .font(Typo.timestamp)
                            .monospacedDigit()
                            .foregroundStyle(Palette.textTert)
                    }
                }

                Text(Str.settingsAboutSubtitle)
                    .font(Typo.timestamp)
                    .foregroundStyle(Palette.textSecond)
                    .fixedSize(horizontal: false, vertical: true)

                Divider().overlay(Palette.cardStroke)

                VStack(alignment: .leading, spacing: Space.s4) {
                    Label(Str.settingsDataSourcesTitle, systemImage: "network")
                        .font(Typo.rowLabel)
                        .foregroundStyle(Palette.gold)
                    Text(Str.settingsDataSourcesDetail)
                        .font(Typo.timestamp)
                        .foregroundStyle(Palette.textSecond)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Text(Str.settingsAboutLinksDetail)
                    .font(Typo.timestamp)
                    .foregroundStyle(Palette.textTert)
                    .fixedSize(horizontal: false, vertical: true)

                LazyVGrid(
                    columns: [
                        GridItem(.flexible(), spacing: Space.s8),
                        GridItem(.flexible(), spacing: Space.s8),
                    ],
                    spacing: Space.s8
                ) {
                    SettingsLinkTile(title: Str.settingsPrivacy, systemImage: "hand.raised.fill",
                                     destination: AppLinks.appPrivacy, tint: Palette.cyan)
                    SettingsLinkTile(title: Str.settingsLicense, systemImage: "doc.text.fill",
                                     destination: AppLinks.appLicense, tint: Palette.textSecond)
                    SettingsLinkTile(title: Str.settingsSupport,
                                     systemImage: "questionmark.circle.fill",
                                     destination: AppLinks.appSupport, tint: Palette.gold)
                    SettingsLinkTile(title: Str.actionGitHub,
                                     systemImage: "chevron.left.forwardslash.chevron.right",
                                     destination: AppLinks.appRepository, tint: Palette.violet)
                }
            }
        }
    }

    private var launchBinding: Binding<Bool> {
        Binding(
            get: { store.launchAtLogin },
            set: { value in
                requestedLaunchAtLogin = value
                store.launchAtLogin = value
            }
        )
    }

    private var appVersionSummary: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString")
            as? String ?? Glyph.noValue
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion")
            as? String ?? Glyph.noValue
        return AppText.appVersion(version, build: build)
    }

    private func clearLocalHistory() {
        guard !clearHistoryInFlight else { return }
        clearHistoryInFlight = true
        historyCleared = false
        Task {
            await store.clearHistoryAndWait()
            clearHistoryInFlight = false
            historyCleared = store.historyPersistenceError == nil
        }
    }

    private func intervalPicker(_ title: LocalizedStringKey, selection: Binding<TimeInterval>,
                                options: [PollInterval]) -> some View {
        VStack(alignment: .leading, spacing: Space.s6) {
            rowLabel(title)
            Picker("", selection: selection) {
                ForEach(options) { Text($0.label).tag($0.seconds) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .controlSize(.small)
            .accessibilityLabel(title)
        }
    }

    private func exportButton(_ title: LocalizedStringKey, format: HistoryExportFormat) -> some View {
        Button {
            guard !exportInFlight else { return }
            exportInFlight = true
            exportSucceeded = false
            exportError = nil
            let snapshot = store.history
            Task {
                defer { exportInFlight = false }
                do {
                    exportSucceeded = try await HistoryExportPresenter.save(
                        snapshot, format: format)
                } catch {
                    exportSucceeded = false
                    exportError = AppText.historyExportFailed
                }
            }
        } label: {
            Text(title)
                .font(Typo.buttonLabel)
                .frame(maxWidth: .infinity)
                .padding(.vertical, Space.s7)
                .overlay(Capsule().strokeBorder(Palette.cardStroke))
        }
        .buttonStyle(GlassButtonStyle(shape: Capsule()))
        .disabled(exportInFlight)
    }

    private var doneButton: some View {
        Button(action: onClose) {
            Text(Str.settingsDone)
                .font(Typo.emphasis)
                .foregroundStyle(Palette.textPrimary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, Space.s9)
                .overlay(Capsule().strokeBorder(Gradients.doneStroke))
        }
        .buttonStyle(GlassButtonStyle(shape: Capsule()))
    }

    private func rowLabel(_ text: LocalizedStringKey) -> some View {
        Text(text).font(Typo.rowLabel).foregroundStyle(Palette.textPrimary.opacity(Opacity.o90))
    }

    private func toggleRow(_ title: LocalizedStringKey, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) { rowLabel(title) }
            .toggleStyle(.switch)
            .controlSize(.small)
            .tint(Palette.cyan)
    }

    private func sectionCard<C: View>(_ title: LocalizedStringKey, systemImage: String,
                                      @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: Space.s10) {
            Label(title, systemImage: systemImage)
                .font(Typo.sectionLabel)
                .tracking(Tracking.t08)
                .foregroundStyle(Palette.textSecond)
                .accessibilityAddTraits(.isHeader)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Space.s12)
        .glassCard()
    }
}

private struct SettingsActionRow: View {
    let title: LocalizedStringKey
    let systemImage: String
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Label(title, systemImage: systemImage)
                    .font(Typo.buttonLabel)
                Spacer()
                Image(systemName: "chevron.right").font(Typo.chevron)
            }
            .foregroundStyle(tint)
            .padding(.vertical, Space.s4)
        }
        .buttonStyle(.plain)
    }
}

private struct SettingsLinkTile: View {
    let title: LocalizedStringKey
    let systemImage: String
    let destination: URL
    let tint: Color

    var body: some View {
        Link(destination: destination) {
            HStack(spacing: Space.s6) {
                Image(systemName: systemImage)
                    .accessibilityHidden(true)
                Text(title)
                    .font(Typo.buttonLabel)
                Spacer(minLength: Space.s2)
                Image(systemName: "arrow.up.right")
                    .font(Typo.timestamp)
                    .accessibilityHidden(true)
            }
            .foregroundStyle(tint)
            .padding(.horizontal, Space.s8)
            .padding(.vertical, Space.s7)
            .overlay(RoundedRectangle(cornerRadius: Radius.r8)
                .strokeBorder(Palette.cardStroke))
        }
        .buttonStyle(GlassButtonStyle(shape: RoundedRectangle(cornerRadius: Radius.r8)))
        .accessibilityHint(Str.settingsOpensBrowser)
    }
}
