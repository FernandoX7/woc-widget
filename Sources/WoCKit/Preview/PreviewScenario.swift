#if PREVIEW
import Foundation

/// Canonical visual-QA fixture selected by `WOC_PREVIEW_STATE`.
///
/// Keep parsing here rather than scattering environment checks through views and stores. Every
/// scenario is fully synthetic, uses the same fixed clock, and has a small set of aliases so the
/// names used in design notes (`happy`, `offline`, `partial-market`) remain convenient.
enum PreviewScenario: String, CaseIterable, Sendable {
    case live
    case welcome
    case loading
    case cachedOffline = "cached-offline"
    case quoteOnly = "quote-only"
    case chartOnly = "chart-only"
    case emptyHistory = "empty-history"
    case notificationDenied = "notification-denied"

    static var current: Self {
        from(ProcessInfo.processInfo.environment["WOC_PREVIEW_STATE"])
    }

    static func from(_ selector: String?) -> Self {
        switch selector?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case nil, "", "happy", "live", "happy/live", "live/happy":
            return .live
        case "welcome", "first-run", "first-launch":
            return .welcome
        case "loading":
            return .loading
        case "cached", "offline", "cached-offline", "cached/offline", "offline/cached":
            return .cachedOffline
        case "partial-market", "quote-only", "quote-live", "quote-live-chart-unavailable":
            return .quoteOnly
        case "chart-only", "chart-live", "chart-live-quote-unavailable", "partial-market-chart":
            return .chartOnly
        case "empty-history":
            return .emptyHistory
        case "notification-denied", "notifications-denied", "permission-denied":
            return .notificationDenied
        default:
            return .live
        }
    }

    var hasPopulationHistory: Bool {
        switch self {
        case .loading, .emptyHistory: return false
        default: return true
        }
    }
}
#endif
