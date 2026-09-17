import Foundation

/// Persists the live Wait queue (`waitingForAge`) across relaunches.
/// Only previously pending entries are restored — never every file already in the watch root.
public enum WaitingForAgeStore: Sendable {
    public static let defaultsKey = "intake.waitingForAge"

    public static func encode(_ pending: [PendingStableFile]) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(pending)
    }

    public static func decode(_ data: Data) throws -> [PendingStableFile] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode([PendingStableFile].self, from: data)
    }

    public static func load(from defaults: UserDefaults) -> [PendingStableFile] {
        guard let data = defaults.data(forKey: defaultsKey) else { return [] }
        return (try? decode(data)) ?? []
    }

    public static func save(_ pending: [PendingStableFile], to defaults: UserDefaults) {
        if pending.isEmpty {
            clear(in: defaults)
            return
        }
        if let data = try? encode(pending) {
            defaults.set(data, forKey: defaultsKey)
        }
    }

    public static func clear(in defaults: UserDefaults) {
        defaults.removeObject(forKey: defaultsKey)
    }

    /// Keeps stored entries that still exist as **root** files under `watchRoot`.
    public static func restoreExisting(
        from defaults: UserDefaults,
        watchRoot: URL,
        fileExists: (URL) -> Bool = { FileManager.default.fileExists(atPath: $0.path) }
    ) -> [PendingStableFile] {
        restoreExisting(
            stored: load(from: defaults),
            watchRoot: watchRoot,
            fileExists: fileExists
        )
    }

    public static func restoreExisting(
        stored: [PendingStableFile],
        watchRoot: URL,
        fileExists: (URL) -> Bool
    ) -> [PendingStableFile] {
        let root = watchRoot.standardizedFileURL
        return stored.filter { item in
            let url = item.url.standardizedFileURL
            guard fileExists(url) else { return false }
            return url.deletingLastPathComponent().standardizedFileURL == root
        }
    }
}
