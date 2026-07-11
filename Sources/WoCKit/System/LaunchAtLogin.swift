import Foundation
import ServiceManagement

/// Launch-at-login system integration, behind a seam so the store can be tested without touching
/// `SMAppService`. `SMAppService.mainApp.status` remains the single source of truth (no
/// UserDefaults mirror — guardrail 6).
protocol LaunchAtLoginManaging: Sendable {
    var isEnabled: Bool { get }
    /// Register/unregister; errors (most often `.requiresApproval`) are swallowed — the caller
    /// reconciles against `isEnabled` afterwards.
    func setEnabled(_ enabled: Bool)
}

struct SMAppLaunchManager: LaunchAtLoginManaging {
    var isEnabled: Bool { SMAppService.mainApp.status == .enabled }

    func setEnabled(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
        } catch {
            // Most often `.requiresApproval` (the user must allow it in System Settings →
            // General → Login Items). Nothing to do here; the toggle reflects the request.
        }
    }
}
