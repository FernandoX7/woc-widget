import Foundation

/// Renders an `AlertDecision` into a localized (title, body) pair from the String Catalog —
/// Foundation-only (no SwiftUI) since it feeds `UNMutableNotificationContent`. Text is
/// byte-identical to the original inline literals, while singular/plural sentences remain
/// independently localizable and prices retain the parsed Double's description.
enum AlertPresenter {
    private static func t(_ key: StaticString, _ fallback: String.LocalizationValue) -> String {
        String(localized: key, defaultValue: fallback, table: "Localizable", bundle: .main)
    }

    static func content(for decision: AlertDecision) -> (title: String, body: String) {
        switch decision {
        case .statusUp(let realm, let count):
            let body = count == 1
                ? t("alert.status.up.body.one", "1 player online now.")
                : String(format: t("alert.status.up.body.other", "%lld players online now."), count)
            return (String(format: t("alert.status.up.title", "✅ %@ is back"), realm), body)
        case .statusDown(let realm):
            return (String(format: t("alert.status.down.title", "⚠️ %@ looks down"), realm),
                    t("alert.status.down.body", "0 players online or the realm is unreachable."))
        case .peak(let realm, let count):
            return (String(format: t("alert.peak.title", "🏆 New peak on %@!"), realm),
                    String(format: t("alert.peak.body", "%lld players online — a new record."), count))
        case .cryptoPump(let percent, let price):
            return (t("alert.crypto.pump.title", "🚀 $WOC is Pumping!"),
                    String(format: t("alert.crypto.pump.body", "The price just surged %lld%% to $%@!"), percent, price))
        case .cryptoDump(let percent, let price):
            return (t("alert.crypto.dump.title", "📉 $WOC is Down"),
                    String(format: t("alert.crypto.dump.body", "The price dropped %lld%% to $%@."), percent, price))
        }
    }
}
