import Foundation

public struct CleanupScanner: Sendable {
    public var watchFolder: URL
    public var thresholdDays: Int
    public var includeWatchRoot: Bool
    public var snoozedUntil: [String: Date]
    public var ignorePolicy: DownloadIgnorePolicy
    public var managedFolderNames: Set<String>

    public init(
        watchFolder: URL,
        thresholdDays: Int,
        includeWatchRoot: Bool,
        snoozedUntil: [String: Date] = [:],
        ignorePolicy: DownloadIgnorePolicy = DownloadIgnorePolicy(),
        managedFolderNames: Set<String> = DefaultTaxonomy.managedFolderNames
    ) {
        self.watchFolder = watchFolder
        self.thresholdDays = thresholdDays
        self.includeWatchRoot = includeWatchRoot
        self.snoozedUntil = snoozedUntil
        self.ignorePolicy = ignorePolicy
        self.managedFolderNames = managedFolderNames
    }

    public func candidates(
        now: Date = Date(),
        fileManager: FileManager = .default
    ) -> [CleanupCandidate] {
        let cutoff = now.addingTimeInterval(-TimeInterval(thresholdDays * 24 * 60 * 60))
        return collectFiles(fileManager: fileManager)
            .compactMap { url in
                candidate(for: url, cutoff: cutoff, now: now, fileManager: fileManager)
            }
            .sorted { $0.lastUsed < $1.lastUsed }
    }

    public func snoozeDate(from now: Date = Date()) -> Date {
        now.addingTimeInterval(TimeInterval(thresholdDays * 24 * 60 * 60))
    }

    private func candidate(
        for url: URL,
        cutoff: Date,
        now: Date,
        fileManager: FileManager
    ) -> CleanupCandidate? {
        if let until = snoozedUntil[url.path], until > now {
            return nil
        }
        let keys: Set<URLResourceKey> = [
            .isDirectoryKey,
            .isRegularFileKey,
            .fileSizeKey,
            .contentModificationDateKey,
            .contentAccessDateKey,
            .creationDateKey,
        ]
        let values = try? url.resourceValues(forKeys: keys)
        let isDirectory = values?.isDirectory ?? url.hasDirectoryPath
        if ignorePolicy.shouldIgnore(url: url, kind: .appeared, isDirectory: isDirectory) {
            return nil
        }
        guard values?.isRegularFile ?? !isDirectory else {
            return nil
        }
        // Listing a folder can bump access time on some volumes, so Linux
        // (and tests) key off modification date. macOS also consults access date.
        var dates: [Date] = []
        if let modified = values?.contentModificationDate {
            dates.append(modified)
        }
        #if os(macOS)
        if let accessed = values?.contentAccessDate {
            dates.append(accessed)
        }
        #endif
        let lastUsed = dates.max() ?? values?.creationDate ?? .distantPast
        guard lastUsed <= cutoff else {
            return nil
        }
        let byteCount = Int64(values?.fileSize ?? 0)
        return CleanupCandidate(url: url, byteCount: byteCount, lastUsed: lastUsed)
    }

    private func collectFiles(fileManager: FileManager) -> [URL] {
        var urls: [URL] = []
        if includeWatchRoot {
            urls.append(contentsOf: files(in: watchFolder, fileManager: fileManager))
        }
        for name in managedFolderNames.sorted() {
            let folder = watchFolder.appendingPathComponent(name, isDirectory: true)
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: folder.path, isDirectory: &isDirectory),
                  isDirectory.boolValue
            else {
                continue
            }
            urls.append(contentsOf: files(in: folder, fileManager: fileManager))
        }
        return urls
    }

    private func files(in directory: URL, fileManager: FileManager) -> [URL] {
        let contents = (try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey],
            options: []
        )) ?? []
        return contents.filter { url in
            let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? url.hasDirectoryPath
            return !isDirectory
        }
    }
}
