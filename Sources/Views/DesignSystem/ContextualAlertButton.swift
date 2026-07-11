import SwiftUI

/// A small, consistent alert control that can sit beside the data it governs. The preference and
/// macOS delivery permission are deliberately represented as separate states: when permission is
/// denied, an enabled alert stays enabled and the control truthfully shows that delivery is
/// blocked instead of silently rewriting the user's choice.
struct ContextualAlertButton: View {
    @Binding var isOn: Bool
    let authorizationState: NotificationAuthorizationState
    let visibleLabel: String?
    let accessibilityLabel: String
    let onHelp: String
    let offHelp: String
    let requestAuthorization: () async -> Void

    @Environment(\.colorSchemeContrast) private var contrast

    private var isDeliveryBlocked: Bool {
        isOn && authorizationState == .denied
    }

    private var needsPermission: Bool {
        isOn && authorizationState == .notDetermined
    }

    private var isCheckingPermission: Bool {
        isOn && authorizationState == .unknown
    }

    private var tint: Color {
        if isDeliveryBlocked || needsPermission || isCheckingPermission { return Palette.gold }
        return isOn ? Palette.cyan : Palette.secondaryText(for: contrast)
    }

    private var systemImage: String {
        if isDeliveryBlocked { return "bell.slash.fill" }
        if needsPermission { return "bell.badge.fill" }
        if isCheckingPermission { return "bell.badge" }
        return isOn ? "bell.fill" : "bell"
    }

    var body: some View {
        Button {
            // Existing preferences may already be on before macOS has ever been asked. Clicking
            // that gold badge is an explicit request to allow delivery; it does not turn the rule
            // off first or trigger a prompt merely because the view appeared.
            if needsPermission {
                Task { await requestAuthorization() }
                return
            }
            guard !isCheckingPermission else { return }
            let enabling = !isOn
            isOn = enabling
            // The system prompt is tied only to this explicit enable action. Merely rendering the
            // control, refreshing feeds, or restoring an enabled preference never prompts.
            if enabling && authorizationState == .notDetermined {
                Task { await requestAuthorization() }
            }
        } label: {
            HStack(spacing: Space.s5) {
                Image(systemName: systemImage)
                    .accessibilityHidden(true)
                if let visibleLabel {
                    Text(visibleLabel)
                        .lineLimit(1)
                }
            }
            .font(Typo.pill)
            .foregroundStyle(tint)
            .padding(.horizontal, visibleLabel == nil ? Space.s7 : Space.s8)
            .padding(.vertical, Space.s5)
            .background(Capsule().fill(tint.opacity(Opacity.o08)))
            .overlay(Capsule().strokeBorder(
                isOn ? tint.opacity(Opacity.o30) : Palette.cardStroke))
        }
        .buttonStyle(GlassButtonStyle(shape: Capsule()))
        .help(helpText)
        .accessibilityLabel(Text(accessibilityLabel))
        .accessibilityValue(Text(accessibilityValue))
    }

    private var helpText: String {
        if isDeliveryBlocked { return AppText.contextualAlertPermissionDeniedHelp }
        if needsPermission { return AppText.contextualAlertPermissionNeededHelp }
        if isCheckingPermission { return AppText.contextualAlertPermissionCheckingHelp }
        return isOn ? onHelp : offHelp
    }

    private var accessibilityValue: String {
        if isDeliveryBlocked { return AppText.contextualAlertBlockedValue }
        if needsPermission { return AppText.contextualAlertPermissionNeededValue }
        if isCheckingPermission { return AppText.contextualAlertPermissionCheckingValue }
        return isOn ? AppText.accessibilityOn : AppText.accessibilityOff
    }
}
