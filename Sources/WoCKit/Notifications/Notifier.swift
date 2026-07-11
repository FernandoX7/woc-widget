import Foundation
import UserNotifications

/// Foundation-only delivery envelope. Fakes that only care about text can rely on the protocol's
/// default implementation; the system notifier additionally maps category and metadata fields.
struct AppNotification: Sendable, Equatable {
    let title: String
    let body: String
    let id: String
    var categoryIdentifier: String?
    var userInfo: [String: String]

    init(title: String, body: String, id: String, categoryIdentifier: String? = nil,
         userInfo: [String: String] = [:]) {
        self.title = title
        self.body = body
        self.id = id
        self.categoryIdentifier = categoryIdentifier
        self.userInfo = userInfo
    }
}

/// Posts a user notification. Injectable so tests can use a fake (and so they never touch
/// `UNUserNotificationCenter.current()`, which traps outside an app bundle).
protocol Notifier: Sendable {
    /// `id` is the full per-fire identifier (kind prefix + timestamp).
    func post(title: String, body: String, id: String)
    func post(_ notification: AppNotification)
    func configure()
}

extension Notifier {
    func post(_ notification: AppNotification) {
        post(title: notification.title, body: notification.body, id: notification.id)
    }

    func configure() {}
}

struct UserNotificationNotifier: Notifier {
    func post(title: String, body: String, id: String) {
        post(AppNotification(title: title, body: body, id: id))
    }

    func post(_ notification: AppNotification) {
        let content = UNMutableNotificationContent()
        content.title = notification.title
        content.body = notification.body
        content.sound = .default
        if let category = notification.categoryIdentifier {
            content.categoryIdentifier = category
        }
        content.userInfo = notification.userInfo
        // The OS shows the app icon (the game crest) automatically — no file access needed.
        let request = UNNotificationRequest(identifier: notification.id, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    func configure() {
        let mute = UNNotificationAction(
            identifier: AdvancedNotificationContract.muteActionIdentifier,
            title: AppText.notificationMuteOneHour,
            options: []
        )
        let disable = UNNotificationAction(
            identifier: AdvancedNotificationContract.disableActionIdentifier,
            title: AppText.notificationDisableAlert,
            options: [.destructive]
        )
        let category = UNNotificationCategory(
            identifier: AdvancedNotificationContract.categoryIdentifier,
            actions: [mute, disable], intentIdentifiers: [], options: []
        )
        UNUserNotificationCenter.current().setNotificationCategories([category])
    }
}
