import SwiftUI

/// SwiftUI-side user-facing strings as `LocalizedStringKey`s, resolved from the same
/// `Localizable` String Catalog at render time. Use as `Text(Str.x)` / `.help(Str.x)`.
enum Str {
    // Header / badge
    static let headerOnline: LocalizedStringKey = "header.online"
    static let badgeLive: LocalizedStringKey = "badge.live"
    static let badgeSync: LocalizedStringKey = "badge.sync"
    static let badgeOffline: LocalizedStringKey = "badge.offline"

    // Chart card
    static let chartTitle: LocalizedStringKey = "chart.title"
    static let cryptoChartTitle: LocalizedStringKey = "chart.cryptoTitle"
    static let chartRange: LocalizedStringKey = "chart.range"
    static let chartPlaceholderTitle: LocalizedStringKey = "chart.placeholder.title"
    static let chartPlaceholderSubtitle: LocalizedStringKey = "chart.placeholder.subtitle"

    // Stats

    // Footer
    static let footerRefresh: LocalizedStringKey = "footer.refresh"
    static let footerQuitHelp: LocalizedStringKey = "footer.quitHelp"
    static let footerSettingsHelp: LocalizedStringKey = "footer.settingsHelp"

    // Settings
    static let settingsTitle: LocalizedStringKey = "settings.title"
    static let settingsBackHelp: LocalizedStringKey = "settings.backHelp"
    static let settingsGeneral: LocalizedStringKey = "settings.general"
    static let settingsPlayerRefresh: LocalizedStringKey = "settings.playerRefresh"
    static let settingsCryptoRefresh: LocalizedStringKey = "settings.cryptoRefresh"
    static let settingsLaunchAtLogin: LocalizedStringKey = "settings.launchAtLogin"
    static let settingsServerAlerts: LocalizedStringKey = "settings.serverAlerts"
    static let settingsPeakAlerts: LocalizedStringKey = "settings.peakAlerts"
    static let settingsCrypto: LocalizedStringKey = "settings.crypto"
    static let settingsCryptoAlerts: LocalizedStringKey = "settings.cryptoAlerts"
    static let settingsThreshold: LocalizedStringKey = "settings.threshold"
    static let settingsDone: LocalizedStringKey = "settings.done"

    // App
    static let appTitle: LocalizedStringKey = "app.title"
}
