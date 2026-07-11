import Foundation

/// Every persisted `UserDefaults` key, declared once. The raw value IS the exact on-disk key
/// string (frozen — see guardrail 6); nothing else may type these as raw strings.
///
/// Note: there is deliberately **no** key for launch-at-login — `SMAppService.mainApp.status`
/// is the single source of truth there.
enum DefaultsKey: String {
    case alertsEnabled
    case peakAlertsEnabled
    case cryptoAlertsEnabled
    case tokenChangeGainAlertsEnabled
    case tokenChangeLossAlertsEnabled
    case chartInterval
    case chartRange
    case cryptoChartInterval
    case pollSeconds
    case cryptoPollSeconds
    case cryptoAlertThreshold
    case cryptoAlertWindow
    case populationThresholdAlertsEnabled
    case populationAlertThreshold
    case tokenPriceAboveAlertsEnabled
    case tokenPriceAboveTarget
    case tokenPriceBelowAlertsEnabled
    case tokenPriceBelowTarget
    case releaseAlertsEnabled
    case advancedAlertCooldown
    case advancedAlertQuietHoursEnabled
    case advancedAlertQuietStartMinute
    case advancedAlertQuietEndMinute
    case advancedAlertMutes
    case menuBarDisplayMode
    case welcomeDismissed
    case allTimePeak
    case allTimePeakDate
    case lastAlertedPrice
    case lastAlertedPriceDate
}

/// The `register(defaults:)` table — the home for ABSENT-key default values. Fixes a prior gap
/// without changing any effective default: `chartInterval` was never registered (it now registers
/// at its existing `?? .fiveMin` fallback). The `?? .fiveMin` / `?? .sixHours` fallbacks in
/// `StatusStore.init` are complementary, not redundant: `register` supplies a value when the key is
/// absent, while `??` guards a present-but-invalid value (e.g. a stored Int that maps to no case).
enum DefaultsRegistry {
    static let table: [String: Any] = [
        DefaultsKey.alertsEnabled.rawValue: true,
        DefaultsKey.peakAlertsEnabled.rawValue: true,
        DefaultsKey.cryptoAlertsEnabled.rawValue: true,
        DefaultsKey.tokenChangeGainAlertsEnabled.rawValue: true,
        DefaultsKey.tokenChangeLossAlertsEnabled.rawValue: true,
        DefaultsKey.chartInterval.rawValue: ChartInterval.fiveMin.rawValue,
        DefaultsKey.chartRange.rawValue: ChartRange.sixHours.rawValue,
        DefaultsKey.cryptoChartInterval.rawValue: CandleInterval.fiveMin.rawValue,
        DefaultsKey.pollSeconds.rawValue: AppConfig.Poll.defaultPlayerSeconds,
        DefaultsKey.cryptoPollSeconds.rawValue: AppConfig.Poll.defaultCryptoSeconds,
        DefaultsKey.cryptoAlertThreshold.rawValue: AppConfig.CryptoAlert.defaultThresholdPercent,
        DefaultsKey.cryptoAlertWindow.rawValue: TokenChangeAlertWindow.oneHour.rawValue,
        DefaultsKey.populationThresholdAlertsEnabled.rawValue: false,
        DefaultsKey.populationAlertThreshold.rawValue: AppConfig.AdvancedAlert.defaultPopulationThreshold,
        DefaultsKey.tokenPriceAboveAlertsEnabled.rawValue: false,
        DefaultsKey.tokenPriceAboveTarget.rawValue: AppConfig.AdvancedAlert.defaultPriceAboveTarget,
        DefaultsKey.tokenPriceBelowAlertsEnabled.rawValue: false,
        DefaultsKey.tokenPriceBelowTarget.rawValue: AppConfig.AdvancedAlert.defaultPriceBelowTarget,
        DefaultsKey.releaseAlertsEnabled.rawValue: true,
        DefaultsKey.advancedAlertCooldown.rawValue: AppConfig.AdvancedAlert.defaultCooldown,
        DefaultsKey.advancedAlertQuietHoursEnabled.rawValue: false,
        DefaultsKey.advancedAlertQuietStartMinute.rawValue: AppConfig.AdvancedAlert.defaultQuietStartMinute,
        DefaultsKey.advancedAlertQuietEndMinute.rawValue: AppConfig.AdvancedAlert.defaultQuietEndMinute,
        // Keep the two signals together for new installs; compact single-signal modes remain
        // available as an explicit personal preference.
        DefaultsKey.menuBarDisplayMode.rawValue: MenuBarDisplayMode.playersAndChange.rawValue,
        // A missing key means the calm Overview welcome has not been dismissed yet. This applies
        // equally to a brand-new install and an existing install upgrading from a version that did
        // not have the welcome, so everyone sees the explanation once without a migration write.
        DefaultsKey.welcomeDismissed.rawValue: false,
    ]
}

/// Typed accessors so call sites never pass a raw key string. A thin extension — deliberately
/// NOT a `@propertyWrapper` (a wrapper would write during `init`, tripping guardrail 5).
extension UserDefaults {
    func register(_ table: [String: Any]) { register(defaults: table) }

    func bool(for key: DefaultsKey) -> Bool { bool(forKey: key.rawValue) }
    func integer(for key: DefaultsKey) -> Int { integer(forKey: key.rawValue) }
    func double(for key: DefaultsKey) -> Double { double(forKey: key.rawValue) }
    func date(for key: DefaultsKey) -> Date? { object(forKey: key.rawValue) as? Date }
    func string(for key: DefaultsKey) -> String? { string(forKey: key.rawValue) }
    func dictionary(for key: DefaultsKey) -> [String: Any]? {
        dictionary(forKey: key.rawValue)
    }

    func set(_ value: Bool, for key: DefaultsKey) { set(value, forKey: key.rawValue) }
    func set(_ value: Int, for key: DefaultsKey) { set(value, forKey: key.rawValue) }
    func set(_ value: Double, for key: DefaultsKey) { set(value, forKey: key.rawValue) }
    func set(_ value: Date, for key: DefaultsKey) { set(value, forKey: key.rawValue) }
    func set(_ value: String, for key: DefaultsKey) { set(value, forKey: key.rawValue) }
    func set(_ value: [String: Double], for key: DefaultsKey) { set(value, forKey: key.rawValue) }
    func remove(_ key: DefaultsKey) { removeObject(forKey: key.rawValue) }
}
