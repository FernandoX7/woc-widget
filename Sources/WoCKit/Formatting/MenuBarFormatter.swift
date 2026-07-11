import Foundation

struct MenuBarPresentation: Sendable, Equatable {
    let label: String
    let accessibilityLabel: String
}

/// Pure formatting for the two representations of the menu-bar item. Keeping visible and spoken
/// output together prevents VoiceOver from claiming a cached count is offline or announcing data
/// that the selected compact mode does not display.
enum MenuBarFormatter {
    static func presentation(
        mode: MenuBarDisplayMode,
        count: Int?,
        availability: RealmAvailability,
        phase: Phase,
        isOnline: Bool,
        price: String?,
        change24h: Double?,
        priceState: DataFeedState
    ) -> MenuBarPresentation {
        let countText = count.map(String.init) ?? Glyph.noValue
        let players = "\(statusGlyph(availability: availability, phase: phase, isOnline: isOnline, hasCount: count != nil)) \(countText)"
        let status = AppText.menuBarStatus(
            availability: availability,
            syncing: availability == .loading && phase == .loading,
            count: count
        )
        let freshPrice = priceState == .live ? price : nil
        let visibleChange = change24h.map(CryptoFormat.signedChange)

        switch mode {
        case .players:
            return MenuBarPresentation(label: players, accessibilityLabel: status)
        case .playersAndChange:
            guard freshPrice != nil, let change24h, let visibleChange else {
                return MenuBarPresentation(label: players, accessibilityLabel: status)
            }
            return MenuBarPresentation(
                label: "\(players) · WOC \(visibleChange)",
                accessibilityLabel: AppText.menuBarAccessibility(
                    status: status, change24h: change24h)
            )
        case .token:
            guard let freshPrice else {
                return MenuBarPresentation(label: players, accessibilityLabel: status)
            }
            return MenuBarPresentation(
                label: [CryptoFormat.price(freshPrice), visibleChange]
                    .compactMap { $0 }.joined(separator: " "),
                accessibilityLabel: AppText.menuBarTokenAccessibility(
                    price: freshPrice, change24h: change24h)
            )
        case .full:
            guard let freshPrice else {
                return MenuBarPresentation(label: players, accessibilityLabel: status)
            }
            let crypto = visibleChange.map { "\(CryptoFormat.price(freshPrice)) (\($0))" }
                ?? CryptoFormat.price(freshPrice)
            return MenuBarPresentation(
                label: "\(crypto) \(players)",
                accessibilityLabel: AppText.menuBarAccessibility(
                    status: status, price: freshPrice, change24h: change24h)
            )
        }
    }

    private static func statusGlyph(availability: RealmAvailability, phase: Phase,
                                    isOnline: Bool, hasCount: Bool) -> String {
        if isOnline { return Glyph.statusOnline }
        switch availability {
        case .loading: return phase == .loading ? Glyph.statusLoading : Glyph.statusOffline
        case .healthy: return Glyph.statusOnline
        case .serverReportedDown: return Glyph.statusOffline
        case .unreachable: return hasCount ? Glyph.statusCached : Glyph.statusOffline
        }
    }
}
