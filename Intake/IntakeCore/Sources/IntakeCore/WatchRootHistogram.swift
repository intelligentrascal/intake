import Foundation

public enum WatchRootHistogram: Sendable {
    /// Counts extensions of loose files in the watch-folder root only.
    /// Uses the same ignore policy as ingest. Does not read file contents.
    public static func counts(
        watchFolder: URL,
        ignorePolicy: DownloadIgnorePolicy = DownloadIgnorePolicy(),
        fileManager: FileManager = .default
    ) -> [String: Int] {
        let root = watchFolder.standardizedFileURL
        let items = (try? fileManager.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey],
            options: []
        )) ?? []

        var histogram: [String: Int] = [:]
        for url in items {
            let standardized = url.standardizedFileURL
            let isDirectory = (try? standardized.resourceValues(forKeys: [.isDirectoryKey]).isDirectory)
                ?? standardized.hasDirectoryPath
            if ignorePolicy.shouldIgnore(url: standardized, kind: .appeared, isDirectory: isDirectory) {
                continue
            }
            let ext = standardized.pathExtension.lowercased()
            guard !ext.isEmpty else { continue }
            histogram[ext, default: 0] += 1
        }
        return histogram
    }
}
