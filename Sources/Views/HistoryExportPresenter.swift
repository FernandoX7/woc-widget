import AppKit
import Foundation
import UniformTypeIdentifiers

@MainActor
enum HistoryExportPresenter {
    /// Returns `true` only after the user chose a destination and the atomic write completed.
    /// Cancelling the save panel is an expected no-op, not a successful export.
    static func save(_ samples: [Sample], format: HistoryExportFormat) async throws -> Bool {
        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        panel.allowedContentTypes = [contentType(for: format)]
        panel.nameFieldStringValue = "woc-player-history.\(format.filenameExtension)"
        panel.title = String(localized: format == .csv ? "action.exportCSV" : "action.exportJSON")

        guard panel.runModal() == .OK, let url = panel.url else { return false }
        // Seven days at the fastest poll interval can be tens of thousands of rows. Keep the save
        // panel on AppKit's main actor, then serialize and write its immutable snapshot off-main.
        try await Task.detached(priority: .userInitiated) {
            let data = try HistoryExportFormatter.data(for: samples, as: format)
            try data.write(to: url, options: .atomic)
        }.value
        return true
    }

    private static func contentType(for format: HistoryExportFormat) -> UTType {
        switch format {
        case .csv: return .commaSeparatedText
        case .json: return .json
        }
    }
}
