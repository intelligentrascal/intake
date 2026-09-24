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

    /// Best on-disk URL to reveal for an Activity row.
    ///
    /// Rename rows keep the path at rename time. After a later move (or another
    /// rename), that path is gone and `NSWorkspace.activateFileViewerSelecting`
    /// silently does nothing. Follow `beforePath` / `afterPath` through newer
    /// rows until a path that still exists is found.
    public static func revealURL(
        for entry: ActivityEntry,
        in entries: [ActivityEntry],
        fileExists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }
    ) -> URL? {
        var visited: Set<UUID> = []
        return resolveRevealURL(for: entry, in: entries, fileExists: fileExists, visited: &visited)
    }

    /// Parent folder of the last known path, when the file itself is gone.
    public static func revealFallbackDirectory(
        for entry: ActivityEntry,
        fileExists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }
    ) -> URL? {
        let paths = [entry.afterPath, entry.url?.path, entry.beforePath].compactMap { $0 }
        for path in paths {
            let parent = URL(fileURLWithPath: path).deletingLastPathComponent()
            if fileExists(parent.path) {
                return parent
            }
        }
        return nil
    }

    private static func resolveRevealURL(
        for entry: ActivityEntry,
        in entries: [ActivityEntry],
        fileExists: (String) -> Bool,
        visited: inout Set<UUID>
    ) -> URL? {
        guard visited.insert(entry.id).inserted else { return nil }

        let candidates = [entry.url?.path, entry.afterPath, entry.beforePath].compactMap { $0 }
        for path in candidates where fileExists(path) {
            return URL(fileURLWithPath: path)
        }

        // Stale location: a later rename/move may list this path as its beforePath.
        let anchors = [entry.afterPath, entry.url?.path].compactMap { $0 }
        for anchor in anchors {
            if let next = entries.first(where: { other in
                other.id != entry.id
                    && other.beforePath == anchor
                    && (other.kind == .moved || other.kind == .renamed)
            }) {
                if let resolved = resolveRevealURL(
                    for: next,
                    in: entries,
                    fileExists: fileExists,
                    visited: &visited
                ) {
                    return resolved
                }
            }
        }
        return nil
    }
}
