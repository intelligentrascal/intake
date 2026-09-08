import Foundation

public enum ActivityLog: Sendable {
    public static let maximumEntries = 200

    public static func inserting(_ entry: ActivityEntry, into entries: [ActivityEntry]) -> [ActivityEntry] {
        capped([entry] + entries)
    }

    public static func capped(_ entries: [ActivityEntry]) -> [ActivityEntry] {
        Array(entries.prefix(maximumEntries))
    }

    public static func encode(_ entries: [ActivityEntry]) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(entries)
    }

    public static func decode(_ data: Data) throws -> [ActivityEntry] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode([ActivityEntry].self, from: data)
    }
}
