import Foundation
import Testing
@testable import WoCKit

@Suite struct HistoryExportFormatterTests {
    private let earlier = Sample(date: Date(timeIntervalSince1970: 1_700_000_000), count: 91)
    private let later = Sample(date: Date(timeIntervalSince1970: 1_700_000_060), count: 104)

    @Test func csvUsesPortableHeadersUTCAndChronologicalOrder() {
        let csv = HistoryExportFormatter.csv([later, earlier])

        #expect(csv == "timestamp,players_online\r\n"
                + "2023-11-14T22:13:20Z,91\r\n"
                + "2023-11-14T22:14:20Z,104\r\n")
        #expect(csv.hasSuffix("\r\n"))
    }

    @Test func jsonUsesTheSameSemanticColumnsAndChronologicalOrder() throws {
        let data = try HistoryExportFormatter.json([later, earlier], prettyPrinted: false)
        let rows = try #require(JSONSerialization.jsonObject(with: data) as? [[String: Any]])

        #expect(rows.count == 2)
        #expect(rows[0]["timestamp"] as? String == "2023-11-14T22:13:20Z")
        #expect(rows[0]["players_online"] as? Int == 91)
        #expect(rows[1]["timestamp"] as? String == "2023-11-14T22:14:20Z")
        #expect(rows[1]["players_online"] as? Int == 104)
    }

    @Test func genericDataAPISelectsFormatAndExposesSaveMetadata() throws {
        let csvData = try HistoryExportFormatter.data(for: [earlier], as: .csv)
        let jsonData = try HistoryExportFormatter.data(for: [earlier], as: .json)

        #expect(String(decoding: csvData, as: UTF8.self).hasPrefix("timestamp,players_online"))
        #expect(try JSONSerialization.jsonObject(with: jsonData) is [[String: Any]])
        #expect(HistoryExportFormat.csv.filenameExtension == "csv")
        #expect(HistoryExportFormat.csv.contentType == "text/csv")
        #expect(HistoryExportFormat.json.filenameExtension == "json")
        #expect(HistoryExportFormat.json.contentType == "application/json")
    }

    @Test func exportsEmptyHistoryAsValidDocuments() throws {
        #expect(HistoryExportFormatter.csv([]) == "timestamp,players_online\r\n")
        #expect(String(decoding: try HistoryExportFormatter.json([], prettyPrinted: false), as: UTF8.self) == "[]")
    }
}
