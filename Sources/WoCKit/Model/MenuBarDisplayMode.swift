import Foundation

/// Controls how much information the app reserves in the system menu bar.
///
/// The raw value is persisted in `UserDefaults`; user-facing labels live in the
/// String Catalog so this domain model remains SwiftUI-free.
enum MenuBarDisplayMode: String, CaseIterable, Identifiable, Sendable {
    case players
    case playersAndChange
    case token
    case full

    var id: String { rawValue }
}
