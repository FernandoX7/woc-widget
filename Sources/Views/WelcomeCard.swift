import SwiftUI

/// A compact, non-blocking first-run orientation. It lives in the Overview flow so the user can
/// keep exploring immediately, and dismissal is the only action: this card never asks macOS for
/// notification permission or starts background work.
struct WelcomeCard: View {
    var store: StatusStore
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s10) {
            VStack(alignment: .leading, spacing: Space.s4) {
                Label(Str.welcomeEyebrow, systemImage: "sparkles")
                    .font(Typo.sectionLabel)
                    .tracking(Tracking.t08)
                    .foregroundStyle(Gradients.brandHorizontal)

                Text(Str.welcomeTitle)
                    .font(Typo.emphasis)
                    .foregroundStyle(Palette.textPrimary)

                Text(Str.welcomeSubtitle)
                    .font(Typo.bodyRounded)
                    .foregroundStyle(Palette.secondaryText(for: contrast))
                    .fixedSize(horizontal: false, vertical: true)
            }

            signalPair

            WelcomeNote(
                systemImage: "lock.macwindow",
                title: Str.welcomeHistoryTitle,
                detail: Str.welcomeHistoryDetail,
                tint: Palette.cyan
            )

            WelcomeNote(
                systemImage: "bell.badge",
                title: Str.welcomeAlertsTitle,
                detail: Str.welcomeAlertsDetail,
                tint: Palette.violet
            )

            HStack {
                Spacer()
                Button {
                    store.dismissWelcome()
                } label: {
                    HStack(spacing: Space.s6) {
                        Text(Str.welcomeDismiss)
                        Image(systemName: "arrow.right")
                            .accessibilityHidden(true)
                    }
                    .font(Typo.buttonLabel)
                    .foregroundStyle(Palette.onAccent)
                    .padding(.horizontal, Space.s12)
                    .padding(.vertical, Space.s7)
                    .background(Gradients.brandHorizontal, in: Capsule())
                }
                .buttonStyle(.plain)
                .help(Str.welcomeDismissHelp)
                .accessibilityHint(Str.welcomeDismissHelp)
            }
        }
        .padding(Space.s12)
        .glassCard()
        .overlay {
            RoundedRectangle(cornerRadius: Radius.r14)
                .strokeBorder(Gradients.brandHorizontal, lineWidth: LineWidth.w1)
                .opacity(Opacity.o25)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
        .accessibilityElement(children: .contain)
    }

    private var signalPair: some View {
        HStack(spacing: Space.s8) {
            WelcomeSignal(systemImage: "person.2.fill", title: Str.welcomeRealmSignal,
                          tint: Palette.cyan)

            Image(systemName: "link")
                .font(Typo.pill)
                .foregroundStyle(Palette.tertiaryText(for: contrast))
                .accessibilityHidden(true)

            WelcomeSignal(systemImage: "dollarsign.circle.fill", title: Str.welcomeMarketSignal,
                          tint: Palette.violet)
        }
        .padding(.horizontal, Space.s10)
        .padding(.vertical, Space.s8)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: Radius.r8)
                .fill(Palette.card.opacity(Opacity.o80))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.r8)
                .strokeBorder(Palette.cardStroke)
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Str.welcomeSignalsAccessibility)
    }
}

private struct WelcomeSignal: View {
    let systemImage: String
    let title: LocalizedStringKey
    let tint: Color

    var body: some View {
        HStack(spacing: Space.s5) {
            Image(systemName: systemImage)
                .foregroundStyle(tint)
                .accessibilityHidden(true)
            Text(title)
                .font(Typo.pill)
                .foregroundStyle(Palette.textPrimary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct WelcomeNote: View {
    let systemImage: String
    let title: LocalizedStringKey
    let detail: LocalizedStringKey
    let tint: Color
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        HStack(alignment: .top, spacing: Space.s8) {
            Image(systemName: systemImage)
                .font(Typo.iconMedium)
                .foregroundStyle(tint)
                .frame(width: Size.iconButtonSide)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: Space.s1) {
                Text(title)
                    .font(Typo.rowLabel)
                    .foregroundStyle(Palette.textPrimary)
                Text(detail)
                    .font(Typo.placeholderHint)
                    .foregroundStyle(Palette.secondaryText(for: contrast))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
