import SwiftUI
import AppKit
import UserNotifications

// MARK: - App

final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    private var terminationFlushInProgress = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        #if PREVIEW
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        #endif
        #if !PREVIEW
        UNUserNotificationCenter.current().delegate = self
        StatusStore.shared.start()
        #endif
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        #if !PREVIEW
        let userInfo = response.notification.request.content.userInfo
        if let ruleID = userInfo[AdvancedNotificationContract.ruleIDUserInfoKey] as? String {
            Task { @MainActor in
                StatusStore.shared.handleAdvancedNotificationAction(
                    identifier: response.actionIdentifier, ruleID: ruleID)
                completionHandler()
            }
            return
        }
        #endif
        completionHandler()
    }

    // Durability for coalesced history writes. Disk work runs on the persistence worker rather
    // than blocking the application delegate's main-actor callbacks.
    func applicationWillResignActive(_ notification: Notification) {
        #if !PREVIEW
        Task { @MainActor in
            await StatusStore.shared.flushHistoryAndWait()
        }
        #endif
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        #if PREVIEW
        return .terminateNow
        #else
        guard !terminationFlushInProgress else { return .terminateLater }
        terminationFlushInProgress = true
        Task { @MainActor in
            await StatusStore.shared.flushHistoryAndWait()
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
        #endif
    }
}

@main
struct WoCWidgetApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    #if PREVIEW
    @State private var store = PreviewComposition.makeStore()
    #else
    @State private var store = StatusStore.shared
    #endif

    var body: some Scene {
        #if PREVIEW
        WindowGroup(Str.appTitle) {
            PopoverView(store: store,
                        initialPage: PreviewDestination.current.page,
                        initiallyShowingSettings: PreviewDestination.current.showsSettings)
                .environment(\.dynamicTypeSize, PreviewTextSize.current)
        }
        .windowResizability(.contentSize)
        #else
        MenuBarExtra {
            PopoverView(store: store)
        } label: {
            Text(verbatim: store.menuBarLabel)
                .accessibilityLabel(store.menuBarAccessibilityLabel)
        }
        .menuBarExtraStyle(.window)
        #endif
    }
}

#if PREVIEW
/// Select a deterministic preview screen without mouse automation:
/// `WOC_PREVIEW_STATE=cached-offline WOC_PREVIEW_PAGE=community build/.../WoCWidget`.
/// Pages are overview/market/community/settings; scenario aliases live in `PreviewScenario`.
private enum PreviewDestination: String {
    case overview, market, community, settings

    static var current: Self {
        guard let value = ProcessInfo.processInfo.environment["WOC_PREVIEW_PAGE"]?.lowercased(),
              let destination = Self(rawValue: value) else { return .overview }
        return destination
    }

    var page: DashboardPage {
        switch self {
        case .overview, .settings: return .overview
        case .market: return .market
        case .community: return .community
        }
    }

    var showsSettings: Bool { self == .settings }
}

/// Optional accessibility-size override for deterministic layout checks:
/// `WOC_PREVIEW_TEXT_SIZE=accessibility5`. Production always follows the user's system setting.
private enum PreviewTextSize {
    static var current: DynamicTypeSize {
        switch ProcessInfo.processInfo.environment["WOC_PREVIEW_TEXT_SIZE"]?
            .lowercased() {
        case "xlarge": return .xLarge
        case "xxxlarge", "large": return .xxxLarge
        case "accessibility1": return .accessibility1
        case "accessibility2", "accessibility": return .accessibility2
        case "accessibility3": return .accessibility3
        case "accessibility4": return .accessibility4
        case "accessibility5", "maximum": return .accessibility5
        default: return .large
        }
    }
}
#endif
