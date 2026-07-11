import Foundation
import Testing
@testable import WoCKit

@Suite struct FileHistoryStoreTests {
    private func temporaryURL(_ name: String) -> (directory: URL, file: URL) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("woc-history-tests-\(UUID().uuidString)", isDirectory: true)
        return (directory, directory.appendingPathComponent(name))
    }

    @Test func roundTripCreatesParentAndKeepsFrozenArrayFormat() throws {
        let location = temporaryURL("history.json")
        defer { try? FileManager.default.removeItem(at: location.directory) }
        let store = FileHistoryStore(url: location.file)
        let samples = [
            Sample(date: Date(timeIntervalSince1970: 1_700_000_000), count: 4),
            Sample(date: Date(timeIntervalSince1970: 1_700_000_060), count: 7),
        ]

        try store.save(samples)

        #expect(FileManager.default.fileExists(atPath: location.file.path))
        #expect(try store.load() == samples)
        let object = try JSONSerialization.jsonObject(with: Data(contentsOf: location.file))
        let rows = object as? [[String: Any]]
        #expect(rows?.count == 2)
        #expect(rows?.first?["count"] as? Int == 4)
        #expect((rows?.first?["date"] as? String)?.contains("T") == true)
    }

    @Test func corruptPrimaryRecoversAndRepairsFromLastKnownGoodBackup() throws {
        let location = temporaryURL("history.json")
        defer { try? FileManager.default.removeItem(at: location.directory) }
        let store = FileHistoryStore(url: location.file)
        let first = [Sample(date: Date(timeIntervalSince1970: 1_700_000_000), count: 3)]
        let second = [Sample(date: Date(timeIntervalSince1970: 1_700_000_060), count: 8)]
        try store.save(first)
        try store.save(second) // first becomes the backup
        #expect(FileManager.default.fileExists(atPath: store.backupURL.path))
        try Data("truncated".utf8).write(to: location.file)

        #expect(try store.load() == first)
        #expect(try store.load() == first) // primary was repaired, not just recovered in memory
    }

    @Test func corruptPrimaryNeverOverwritesValidBackupDuringSave() throws {
        let location = temporaryURL("history.json")
        defer { try? FileManager.default.removeItem(at: location.directory) }
        let store = FileHistoryStore(url: location.file)
        let knownGood = [Sample(date: Date(timeIntervalSince1970: 1_700_000_000), count: 2)]
        let newer = [Sample(date: Date(timeIntervalSince1970: 1_700_000_060), count: 5)]
        try store.save(knownGood)
        try store.save(newer)
        try Data("bad primary".utf8).write(to: location.file)

        let newest = [Sample(date: Date(timeIntervalSince1970: 1_700_000_120), count: 9)]
        try store.save(newest)
        try Data("bad again".utf8).write(to: location.file)

        #expect(try store.load() == knownGood)
    }

    @Test func missingPrimaryCanRecoverFromBackup() throws {
        let location = temporaryURL("history.json")
        defer { try? FileManager.default.removeItem(at: location.directory) }
        let store = FileHistoryStore(url: location.file)
        let first = [Sample(date: Date(timeIntervalSince1970: 1_700_000_000), count: 1)]
        let second = [Sample(date: Date(timeIntervalSince1970: 1_700_000_060), count: 2)]
        try store.save(first)
        try store.save(second)
        try FileManager.default.removeItem(at: location.file)

        #expect(try store.load() == first)
    }

    @Test func emptySavePermanentlyRemovesPrimaryAndRecoverySnapshot() throws {
        let location = temporaryURL("history.json")
        defer { try? FileManager.default.removeItem(at: location.directory) }
        let store = FileHistoryStore(url: location.file)
        let first = [Sample(date: Date(timeIntervalSince1970: 1_700_000_000), count: 4)]
        let second = [Sample(date: Date(timeIntervalSince1970: 1_700_000_060), count: 7)]
        try store.save(first)
        try store.save(second)
        #expect(FileManager.default.fileExists(atPath: location.file.path))
        #expect(FileManager.default.fileExists(atPath: store.backupURL.path))

        try store.save([])

        #expect(!FileManager.default.fileExists(atPath: location.file.path))
        #expect(!FileManager.default.fileExists(atPath: store.backupURL.path))
        #expect(try store.load().isEmpty)
    }

    @Test func rejectsOversizedReadsAndWritesBeforeDecoding() throws {
        let location = temporaryURL("history.json")
        defer { try? FileManager.default.removeItem(at: location.directory) }
        try FileManager.default.createDirectory(at: location.directory,
                                                withIntermediateDirectories: true)
        let store = FileHistoryStore(url: location.file, maximumFileBytes: 16)
        try Data(repeating: 0x20, count: 17).write(to: location.file)

        #expect(throws: HistoryFileError.noRecoverableSnapshot) {
            _ = try store.load()
        }
        #expect(throws: HistoryFileError.self) {
            try store.save([Sample(date: Date(timeIntervalSince1970: 1_700_000_000), count: 1)])
        }
    }

    @Test func corruptPrimaryAndBackupSurfaceFailure() throws {
        let location = temporaryURL("history.json")
        defer { try? FileManager.default.removeItem(at: location.directory) }
        try FileManager.default.createDirectory(at: location.directory,
                                                withIntermediateDirectories: true)
        let store = FileHistoryStore(url: location.file)
        try Data("bad".utf8).write(to: location.file)
        try Data("also bad".utf8).write(to: store.backupURL)

        #expect(throws: HistoryFileError.noRecoverableSnapshot) {
            _ = try store.load()
        }
    }
}
