import Foundation

/// Disk persistence for the sample history. Injectable so the store can be exercised with an
/// in-memory fake in tests. (The $WOC candle chart is fetched fresh from GeckoTerminal each poll,
/// so it needs no on-disk history — there is deliberately no crypto counterpart here.)
protocol HistoryPersisting: Sendable {
    func load() throws -> [Sample]
    func save(_ samples: [Sample]) throws
}

/// Serializes the blocking persistence implementation away from `StatusStore`'s main-actor
/// executor. Keeping this adapter specific to history avoids introducing a general-purpose I/O
/// framework while ensuring a load and subsequent saves can never overlap or reorder.
actor HistoryPersistenceWorker {
    enum LoadResult: Sendable {
        case success([Sample])
        case failure
    }

    enum SaveResult: Sendable {
        case success
        case failure
    }

    private let persistence: any HistoryPersisting

    init(persistence: any HistoryPersisting) {
        self.persistence = persistence
    }

    func load() -> LoadResult {
        do { return .success(try persistence.load()) }
        catch { return .failure }
    }

    func save(_ samples: [Sample]) -> SaveResult {
        do {
            try persistence.save(samples)
            return .success
        } catch {
            return .failure
        }
    }
}

/// The live store: a frozen iso8601-encoded `[Sample]` JSON at
/// `Application Support/WoCWidget/history.json` (guardrail 6 — format unchanged).
struct FileHistoryStore: HistoryPersisting {
    let url: URL
    let maximumFileBytes: Int

    init(url: URL = FileHistoryStore.defaultURL,
         maximumFileBytes: Int = 16 * 1024 * 1024) {
        self.url = url
        self.maximumFileBytes = max(1, maximumFileBytes)
    }

    /// Last-known-good snapshot. The public/frozen `history.json` representation remains unchanged;
    /// this sidecar only exists so a truncated or externally corrupted primary can recover.
    var backupURL: URL { url.appendingPathExtension("backup") }

    static var defaultURL: URL {
        let fm = FileManager.default
        let dir = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(AppConfig.History.directoryName, isDirectory: true)
        // Directory creation belongs to `save`, which the persistence worker executes off-main.
        // A read of a never-created directory already has the desired empty-history semantics.
        return dir.appendingPathComponent(AppConfig.History.fileName)
    }

    func load() throws -> [Sample] {
        let fm = FileManager.default
        let hasPrimary = fm.fileExists(atPath: url.path)
        let hasBackup = fm.fileExists(atPath: backupURL.path)
        guard hasPrimary || hasBackup else { return [] }

        if hasPrimary, let primary = try? decoded(at: url) { return primary }

        // A valid backup is more useful than surfacing a primary decode failure. Best-effort
        // restoration means subsequent launches also recover even before the next scheduled save.
        if hasBackup, let recovered = try? decoded(at: backupURL) {
            if let data = try? checkedData(at: backupURL) {
                try? data.write(to: url, options: .atomic)
            }
            return recovered
        }

        throw HistoryFileError.noRecoverableSnapshot
    }

    private func decoded(at fileURL: URL) throws -> [Sample] {
        let data = try checkedData(at: fileURL)
        return try decoded(data)
    }

    private func decoded(_ data: Data) throws -> [Sample] {
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        return try dec.decode([Sample].self, from: data)
    }

    private func checkedData(at fileURL: URL) throws -> Data {
        let values = try fileURL.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
        guard values.isRegularFile == true else { throw HistoryFileError.notARegularFile }
        if let size = values.fileSize, size > maximumFileBytes {
            throw HistoryFileError.fileTooLarge(bytes: size, maximum: maximumFileBytes)
        }
        return try Data(contentsOf: fileURL, options: .mappedIfSafe)
    }

    func save(_ samples: [Sample]) throws {
        let fm = FileManager.default

        // An empty snapshot is the durable representation of the user's explicit Clear History
        // action. Remove both copies instead of rotating the old primary into the recovery
        // sidecar; otherwise data described as permanently deleted could be restored on launch.
        if samples.isEmpty {
            var firstRemovalError: Error?
            for fileURL in [url, backupURL] where fm.fileExists(atPath: fileURL.path) {
                do {
                    try fm.removeItem(at: fileURL)
                } catch {
                    if firstRemovalError == nil { firstRemovalError = error }
                }
            }
            if let firstRemovalError { throw firstRemovalError }
            return
        }

        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        let data = try enc.encode(samples)
        guard data.count <= maximumFileBytes else {
            throw HistoryFileError.fileTooLarge(bytes: data.count, maximum: maximumFileBytes)
        }

        try fm.createDirectory(at: url.deletingLastPathComponent(),
                               withIntermediateDirectories: true)

        // Preserve only a decodable primary. If the primary is already corrupt, overwriting the
        // last-known-good backup would destroy the sole recovery path.
        if fm.fileExists(atPath: url.path),
           let previous = try? checkedData(at: url),
           (try? decoded(previous)) != nil {
            try previous.write(to: backupURL, options: .atomic)
        }
        try data.write(to: url, options: .atomic)
    }
}

enum HistoryFileError: Error, Equatable {
    case notARegularFile
    case fileTooLarge(bytes: Int, maximum: Int)
    case noRecoverableSnapshot
}
