import SwiftUI

/// Turns the local history into one calm, actionable answer instead of another wall of metrics.
/// The calculation remains deliberately transparent: it only describes observations recorded on
/// this Mac and withholds the percentile until the sample floor is met.
struct RealmRhythmCard: View {
    @Bindable var store: StatusStore
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        let rhythm = store.realmRhythm
        VStack(alignment: .leading, spacing: Space.s8) {
            HStack(spacing: Space.s6) {
                Label(Str.rhythmTitle, systemImage: "sparkles")
                    .font(Typo.sectionLabel)
                    .tracking(Tracking.t08)
                    .foregroundStyle(Palette.secondaryText(for: contrast))
                Spacer()
                busyAlertButton
            }

            if let percentile = rhythm.currentPercentile {
                Text(AppText.realmRhythmPercentile(percentile))
                    .font(Typo.emphasis)
                    .foregroundStyle(Palette.textPrimary)
            } else {
                VStack(alignment: .leading, spacing: Space.s2) {
                    Text(Str.rhythmBuilding)
                        .font(Typo.emphasis)
                        .foregroundStyle(Palette.textPrimary)
                    Text(Str.rhythmBuildingDetail)
                        .font(Typo.bodyRounded)
                        .foregroundStyle(Palette.secondaryText(for: contrast))
                }
            }

            HStack(spacing: Space.s8) {
                ProgressView(value: rhythm.coverageFraction)
                    .progressViewStyle(.linear)
                    .tint(Palette.cyan)
                    .accessibilityLabel(Str.rhythmCoverage)
                    .accessibilityValue(Text(AppText.realmRhythmCoverage(rhythm.coverageFraction)))
                Text(AppText.realmRhythmCoverage(rhythm.coverageFraction))
                    .font(Typo.timestamp)
                    .monospacedDigit()
                    .foregroundStyle(Palette.tertiaryText(for: contrast))
                    .fixedSize()
            }

            Text(Str.rhythmLocalFootnote)
                .font(Typo.placeholderHint)
                .foregroundStyle(Palette.tertiaryText(for: contrast))
        }
        .padding(Space.s12)
        .glassCard()
    }

    private var busyAlertButton: some View {
        let label = AppText.busyAlertThreshold(store.populationAlertThreshold)
        return ContextualAlertButton(
            isOn: $store.populationThresholdAlertsEnabled,
            authorizationState: store.notificationAuthorizationState,
            visibleLabel: label,
            accessibilityLabel: label,
            onHelp: AppText.busyAlertDisableHelp,
            offHelp: AppText.busyAlertEnableHelp,
            requestAuthorization: { await store.requestNotificationAuthorization() }
        )
    }
}
