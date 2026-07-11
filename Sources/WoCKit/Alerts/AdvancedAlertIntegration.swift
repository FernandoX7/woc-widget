import Foundation

/// Stable IDs shared by policy construction, notification metadata, action handling, and tests.
/// They deliberately do not include mutable settings such as a target or rolling window.
enum AdvancedAlertRuleCatalog {
    static let realmStatus = AdvancedAlertRuleID("realm-status")
    static let localRecord = AdvancedAlertRuleID("local-record")
    static let population = AdvancedAlertRuleID("population-threshold")
    static let tokenPriceAbove = AdvancedAlertRuleID("token-price-above")
    static let tokenPriceBelow = AdvancedAlertRuleID("token-price-below")
    static let tokenChangeGain = AdvancedAlertRuleID("token-change-gain")
    static let tokenChangeLoss = AdvancedAlertRuleID("token-change-loss")
    static let release = AdvancedAlertRuleID("game-release")
    static let all: Set<AdvancedAlertRuleID> = [realmStatus, localRecord, population,
                                                tokenPriceAbove, tokenPriceBelow,
                                                tokenChangeGain, tokenChangeLoss, release]
}

/// Metadata contract attached to advanced user notifications. The app delegate uses only these
/// stable strings; notification presentation remains fully testable without UserNotifications.
enum AdvancedNotificationContract {
    static let categoryIdentifier = "WOC_ADVANCED_ALERT"
    static let muteActionIdentifier = "WOC_ALERT_MUTE_ONE_HOUR"
    static let disableActionIdentifier = "WOC_ALERT_DISABLE_RULE"
    static let ruleIDUserInfoKey = "woc.alert.rule-id"
}

enum AdvancedAlertPresenter {
    private static func t(_ key: StaticString, _ fallback: String.LocalizationValue) -> String {
        String(localized: key, defaultValue: fallback, table: "Localizable", bundle: .main)
    }

    static func content(for decision: AdvancedAlertDecision) -> (title: String, body: String) {
        switch decision.payload {
        case .population(let direction, let count, let threshold):
            switch direction {
            case .above:
                let body = count == 1
                    ? String(format: t("alert.advanced.population.above.body.one",
                                       "1 player is online — your %lld-player alert was reached."),
                             threshold)
                    : String(format: t("alert.advanced.population.above.body.other",
                                       "%lld players are online — your %lld-player alert was reached."),
                             count, threshold)
                return (t("alert.advanced.population.above.title", "🌍 The realm is bustling"), body)
            case .below:
                let body = count == 1
                    ? String(format: t("alert.advanced.population.below.body.one",
                                       "1 player is online — below your %lld-player alert."), threshold)
                    : String(format: t("alert.advanced.population.below.body.other",
                                       "%lld players are online — below your %lld-player alert."),
                             count, threshold)
                return (t("alert.advanced.population.below.title", "🌙 The realm is quiet"), body)
            }

        case .tokenPrice(let direction, let price, let target):
            let priceText = CryptoFormat.price(CryptoFormat.chartPrice(price))
            let targetText = CryptoFormat.price(CryptoFormat.chartPrice(target))
            switch direction {
            case .above:
                return (t("alert.advanced.price.above.title", "🎯 $WOC target reached"),
                        String(format: t("alert.advanced.price.above.body",
                                         "$WOC is %@, at or above your %@ target."),
                               priceText, targetText))
            case .below:
                return (t("alert.advanced.price.below.title", "🎯 $WOC target reached"),
                        String(format: t("alert.advanced.price.below.body",
                                         "$WOC is %@, at or below your %@ target."),
                               priceText, targetText))
            }

        case .tokenChange(let direction, let window, let change, let threshold, let price):
            let titleWindow = localizedWindowAdjective(window)
            let duration = localizedWindowDuration(window)
            let priceText = CryptoFormat.price(CryptoFormat.chartPrice(price))
            switch direction {
            case .gain:
                return (String(format: t("alert.advanced.change.gain.title", "🚀 $WOC %@ move"),
                                      titleWindow),
                        String(format: t("alert.advanced.change.gain.body",
                                         "Up %.1f%% over %@ at %@ — above your %.1f%% alert."),
                               abs(change), duration, priceText, threshold))
            case .loss:
                return (String(format: t("alert.advanced.change.loss.title", "📉 $WOC %@ move"),
                                      titleWindow),
                        String(format: t("alert.advanced.change.loss.body",
                                         "Down %.1f%% over %@ at %@ — beyond your %.1f%% alert."),
                               abs(change), duration, priceText, threshold))
            }

        case .gameRelease(let release):
            let version = release.tag ?? release.name
                ?? t("alert.advanced.release.unknown", "new release")
            let title = String(format: t("alert.advanced.release.title", "✨ WoC %@ is here"), version)
            let body = release.summary ?? release.name
                ?? t("alert.advanced.release.body", "A new World of ClaudeCraft release is available.")
            return (title, body)
        }
    }

    private static func localizedWindowAdjective(_ window: TokenChangeAlertWindow) -> String {
        switch window {
        case .oneHour: return t("alert.window.1h", "1-hour")
        case .sixHours: return t("alert.window.6h", "6-hour")
        case .twentyFourHours: return t("alert.window.24h", "24-hour")
        }
    }

    private static func localizedWindowDuration(_ window: TokenChangeAlertWindow) -> String {
        switch window {
        case .oneHour: return t("alert.window.duration.1h", "1 hour")
        case .sixHours: return t("alert.window.duration.6h", "6 hours")
        case .twentyFourHours: return t("alert.window.duration.24h", "24 hours")
        }
    }
}
