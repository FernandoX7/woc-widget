import Foundation
import UserNotifications

/// UI-friendly authorization state, decoupled from UserNotifications so tests and settings do not
/// need to manufacture `UNNotificationSettings` instances.
enum NotificationAuthorizationState: Sendable, Equatable {
    case unknown
    case notDetermined
    case denied
    case authorized
    case provisional
    case ephemeral

    var canDeliver: Bool {
        switch self {
        case .authorized, .provisional, .ephemeral: return true
        case .unknown, .notDetermined, .denied: return false
        }
    }
}

protocol NotificationAuthorizing: Sendable {
    func currentStatus() async -> NotificationAuthorizationState
    func requestAuthorization() async -> NotificationAuthorizationState
}

struct SystemNotificationAuthorizer: NotificationAuthorizing {
    func currentStatus() async -> NotificationAuthorizationState {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        return Self.map(settings.authorizationStatus)
    }

    func requestAuthorization() async -> NotificationAuthorizationState {
        do {
            _ = try await UNUserNotificationCenter.current()
                .requestAuthorization(options: AppConfig.notificationAuthorizationOptions)
        } catch {
            // The authoritative follow-up status distinguishes a denial from a transient error.
        }
        return await currentStatus()
    }

    private static func map(_ status: UNAuthorizationStatus) -> NotificationAuthorizationState {
        switch status {
        case .notDetermined: return .notDetermined
        case .denied: return .denied
        case .authorized: return .authorized
        case .provisional: return .provisional
        case .ephemeral: return .ephemeral
        @unknown default: return .unknown
        }
    }
}
