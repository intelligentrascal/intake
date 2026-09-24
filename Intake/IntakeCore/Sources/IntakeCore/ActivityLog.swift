import Foundation

public enum ActivityLog: Sendable {
    public static let maximumEntries = 200

    public static func inserting(_ entry: ActivityEntry, into entries: [ActivityEntry]) -> [ActivityEntry] {
        capped([entry] + entries)
    }

    public static func capped(_ entries: [ActivityEntry]) -> [ActivityEntry] {
        Array(entries.prefix(maximumEntries))
    }

    /// Entries from one watch folder, or all of them when `watchFolderID` is
    /// `nil`. Older rows without an id count as profile #1.
    public static func filtered(_ entries: [ActivityEntry], watchFolderID: String?) -> [ActivityEntry] {
        guard let watchFolderID else { return entries }
        return entries.filter { $0.effectiveWatchFolderID == watchFolderID }
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
