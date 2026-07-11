import Foundation

/// Supported persisted cooldown choices. Settings and normalization share this list so a picker
/// cannot offer a value the store will silently coerce to a different one.
enum AlertCooldownOption: CaseIterable, Identifiable, Sendable {
    case off
    case fifteenMinutes
    case oneHour
    case fourHours
    case oneDay

    var id: TimeInterval { seconds }

    var seconds: TimeInterval {
        switch self {
        case .off: return 0
        case .fifteenMinutes: return 15 * 60
        case .oneHour: return 60 * 60
        case .fourHours: return 4 * 60 * 60
        case .oneDay: return 24 * 60 * 60
        }
    }
}
