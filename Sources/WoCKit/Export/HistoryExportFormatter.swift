import Foundation

enum HistoryExportFormat: String, CaseIterable, Sendable {
    case csv
    case json

    var filenameExtension: String { rawValue }

    var contentType: String {
        switch self {
        case .csv: "text/csv"
        case .json: "application/json"
        }
    }
}

/// Pure history serialization. It never touches disk or presents UI, which keeps export behavior
/// deterministic and lets the menu app decide whether to share, save, or copy the resulting data.
struct HistoryExportFormatter: Sendable {
    static func data(
        for samples: [Sample],
        as format: HistoryExportFormat,
        prettyPrinted: Bool = true
    ) throws -> Data {
        switch format {
        case .csv:
            Data(csv(samples).utf8)
        case .json:
            try json(samples, prettyPrinted: prettyPrinted)
        }
    }

    static func csv(_ samples: [Sample]) -> String {
        let formatter = ISO8601DateFormatter()
        let rows = sorted(samples).map { sample in
            "\(formatter.string(from: sample.date)),\(sample.count)"
        }
        return (["timestamp,players_online"] + rows).joined(separator: "\r\n") + "\r\n"
    }

    static func json(_ samples: [Sample], prettyPrinted: Bool = true) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        var formatting: JSONEncoder.OutputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        if prettyPrinted { formatting.insert(.prettyPrinted) }
        encoder.outputFormatting = formatting
        return try encoder.encode(sorted(samples).map(HistoryExportRow.init))
    }

    private static func sorted(_ samples: [Sample]) -> [Sample] {
        samples.sorted {
            if $0.date == $1.date { return $0.count < $1.count }
            return $0.date < $1.date
        }
    }

}

private struct HistoryExportRow: Encodable {
    let timestamp: Date
    let playersOnline: Int

    init(_ sample: Sample) {
        timestamp = sample.date
        playersOnline = sample.count
    }

    enum CodingKeys: String, CodingKey {
        case timestamp
        case playersOnline = "players_online"
    }
}
