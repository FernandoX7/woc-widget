import Foundation

/// A notification identity (its raw value is the original notification-id prefix — status up and
/// down deliberately share `"status"`). A fresh timestamp is appended per fire so repeated alerts
/// of the same kind aren't coalesced by the OS.
enum AlertKind: String {
    case status = "status"
    case peak = "peak"
    case cryptoPump = "crypto_pump"
    case cryptoDump = "crypto_dump"

    /// Unique per-fire notification id: `"<prefix>-<now.timeIntervalSince1970>"` (pure; the clock
    /// is injected so tests are deterministic).
    func requestID(now: () -> Date) -> String {
        "\(rawValue)-\(now().timeIntervalSince1970)"
    }
}

/// A snapshot of the three alert toggles, so the engine decides without touching the store.
struct AlertSettings {
    let statusEnabled: Bool   // alertsEnabled
    let peakEnabled: Bool     // peakAlertsEnabled
    let cryptoEnabled: Bool   // cryptoAlertsEnabled
}

/// What the engine decided should fire, with the payload needed to render it. Carries `kind` so
/// the caller can build the notification id.
enum AlertDecision: Equatable {
    case statusUp(realm: String, count: Int)
    case statusDown(realm: String)
    case peak(realm: String, count: Int)
    case cryptoPump(percent: Int, price: String)
    case cryptoDump(percent: Int, price: String)

    var kind: AlertKind {
        switch self {
        case .statusUp, .statusDown: return .status
        case .peak: return .peak
        case .cryptoPump: return .cryptoPump
        case .cryptoDump: return .cryptoDump
        }
    }
}
