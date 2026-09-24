import Foundation

/// Persists the live Wait queue (`waitingForAge`) across relaunches, one queue
/// per watch folder profile. Only previously pending entries are restored —
/// never every file already in the watch root.
public enum WaitingForAgeStore: Sendable {
    /// The 1.2 single-folder queue key. Migrated into profile #1's key.
    public static let defaultsKey = "intake.waitingForAge"

    /// Queue key for one watch folder profile.
    public static func defaultsKey(forProfileID profileID: String) -> String {
        "\(defaultsKey).\(profileID)"
    }

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
        load(from: defaults, key: defaultsKey)
    }

    public static func load(from defaults: UserDefaults, profileID: String) -> [PendingStableFile] {
        load(from: defaults, key: defaultsKey(forProfileID: profileID))
    }

    public static func save(_ pending: [PendingStableFile], to defaults: UserDefaults) {
        save(pending, to: defaults, key: defaultsKey)
    }

    public static func save(
        _ pending: [PendingStableFile],
        to defaults: UserDefaults,
        profileID: String
    ) {
        save(pending, to: defaults, key: defaultsKey(forProfileID: profileID))
    }

    public static func clear(in defaults: UserDefaults) {
        defaults.removeObject(forKey: defaultsKey)
    }

    public static func clear(in defaults: UserDefaults, profileID: String) {
        defaults.removeObject(forKey: defaultsKey(forProfileID: profileID))
    }

    /// Moves the 1.2 single-folder queue into `profileID`'s queue, unless that
    /// profile already has one. The legacy key is removed either way, so the
    /// migration runs at most once.
    public static func migrateLegacyQueue(to profileID: String, in defaults: UserDefaults) {
        guard let legacy = defaults.data(forKey: defaultsKey) else { return }
        let key = defaultsKey(forProfileID: profileID)
        if defaults.data(forKey: key) == nil {
            defaults.set(legacy, forKey: key)
        }
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

    /// Keeps `profileID`'s stored entries that still exist as root files under `watchRoot`.
    public static func restoreExisting(
        from defaults: UserDefaults,
        profileID: String,
        watchRoot: URL,
        fileExists: (URL) -> Bool = { FileManager.default.fileExists(atPath: $0.path) }
    ) -> [PendingStableFile] {
        restoreExisting(
            stored: load(from: defaults, profileID: profileID),
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
        // Compare `.path` strings — `URL ==` can be false for equivalent file URLs.
        return stored.filter { item in
            let url = item.url.standardizedFileURL
            guard fileExists(url) else { return false }
            let parentPath = url.deletingLastPathComponent().standardizedFileURL.path
            return parentPath == root.path
        }
    }

    private static func load(from defaults: UserDefaults, key: String) -> [PendingStableFile] {
        guard let data = defaults.data(forKey: key) else { return [] }
        return (try? decode(data)) ?? []
    }

    private static func save(_ pending: [PendingStableFile], to defaults: UserDefaults, key: String) {
        if pending.isEmpty {
            defaults.removeObject(forKey: key)
            return
        }
        if let data = try? encode(pending) {
            defaults.set(data, forKey: key)
        }
    }
}
