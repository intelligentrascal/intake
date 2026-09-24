import Foundation

public struct CleanupScanner: Sendable {
    /// 24h of unchanged size/modification date marks a download abandoned.
    public static let abandonedDownloadInterval: TimeInterval = 24 * 60 * 60

    public var watchFolder: URL
    public var thresholdDays: Int
    public var includeWatchRoot: Bool
    public var snoozedUntil: [String: Date]
    public var ignorePolicy: DownloadIgnorePolicy
    public var managedFolderNames: Set<String>
    public var hashCache: DuplicateHashCache

    public init(
        watchFolder: URL,
        thresholdDays: Int,
        includeWatchRoot: Bool,
        snoozedUntil: [String: Date] = [:],
        ignorePolicy: DownloadIgnorePolicy = DownloadIgnorePolicy(),
        managedFolderNames: Set<String> = DefaultTaxonomy.managedFolderNames,
        hashCache: DuplicateHashCache = DuplicateHashCache()
    ) {
        self.watchFolder = watchFolder
        self.thresholdDays = thresholdDays
        self.includeWatchRoot = includeWatchRoot
        self.snoozedUntil = snoozedUntil
        self.ignorePolicy = ignorePolicy
        self.managedFolderNames = managedFolderNames
        self.hashCache = hashCache
    }

    /// Key used to look up/store a snooze for `url`. Symlink-resolved and
    /// standardized so a snooze recorded from one path form (e.g. `/tmp/...`)
    /// still matches a later scan that resolves to another (`/private/tmp/...`).
    public static func snoozeKey(for url: URL) -> String {
        url.resolvingSymlinksInPath().standardizedFileURL.path
    }

    public func candidates(
        now: Date = Date(),
        fileManager: FileManager = .default
    ) -> [CleanupCandidate] {
        let cutoff = now.addingTimeInterval(-TimeInterval(thresholdDays * 24 * 60 * 60))
        let files = collectFiles(fileManager: fileManager)
        let normalizedSnoozes = normalizedSnoozedUntil()

        var infos: [URL: FileInfo] = [:]
        for url in files {
            if let info = fileInfo(for: url, fileManager: fileManager) {
                infos[url] = info
            }
        }

        let duplicateOriginals = duplicateOriginals(among: infos, fileManager: fileManager)

        var results: [CleanupCandidate] = []
        for (url, info) in infos {
            if isSnoozed(url, normalizedSnoozes: normalizedSnoozes, now: now) {
                continue
            }
            if let original = duplicateOriginals[url] {
                results.append(
                    CleanupCandidate(
                        url: url,
                        byteCount: info.size,
                        lastUsed: info.lastUsed,
                        reason: .duplicate(of: original)
                    )
                )
                continue
            }
            if info.isIncompleteDownload {
                if now.timeIntervalSince(info.modificationDate) >= Self.abandonedDownloadInterval {
                    results.append(
                        CleanupCandidate(
                            url: url,
                            byteCount: info.size,
                            lastUsed: info.lastUsed,
                            reason: .abandonedDownload
                        )
                    )
                }
                continue
            }
            guard info.lastUsed <= cutoff else {
                continue
            }
            results.append(CleanupCandidate(url: url, byteCount: info.size, lastUsed: info.lastUsed))
        }
        return results.sorted { $0.lastUsed < $1.lastUsed }
    }

    public func snoozeDate(from now: Date = Date()) -> Date {
        now.addingTimeInterval(TimeInterval(thresholdDays * 24 * 60 * 60))
    }

    /// Normalizes stored snooze keys through the same symlink-resolving path
    /// used for lookups, so a key recorded from a different (but equivalent)
    /// path form — e.g. `/tmp/...` vs. the resolved `/private/tmp/...` — still
    /// matches. This is the fix for snoozed files reappearing after a scan.
    private func normalizedSnoozedUntil() -> [String: Date] {
        var result: [String: Date] = [:]
        for (path, until) in snoozedUntil {
            let key = Self.snoozeKey(for: URL(fileURLWithPath: path))
            if let existing = result[key], existing > until {
                continue
            }
            result[key] = until
        }
        return result
    }

    private func isSnoozed(_ url: URL, normalizedSnoozes: [String: Date], now: Date) -> Bool {
        guard let until = normalizedSnoozes[Self.snoozeKey(for: url)] else {
            return false
        }
        return until > now
    }

    /// Per-file facts pulled once per scan and shared across stale, duplicate
    /// and abandoned-download classification.
    private struct FileInfo {
        let size: Int64
        let modificationDate: Date
        let lastUsed: Date
        let dateAdded: Date
        let isIncompleteDownload: Bool
    }

    private func fileInfo(for url: URL, fileManager: FileManager) -> FileInfo? {
        let keys: Set<URLResourceKey> = [
            .isDirectoryKey,
            .isRegularFileKey,
            .fileSizeKey,
            .contentModificationDateKey,
            .contentAccessDateKey,
            .creationDateKey,
            .addedToDirectoryDateKey,
        ]
        let values = try? url.resourceValues(forKeys: keys)
        let isDirectory = values?.isDirectory ?? url.hasDirectoryPath
        let isIncompleteDownload = ignorePolicy.isIncompleteDownloadExtension(url: url)
        // Ignore everything the normal ingest ignore policy would (dotfiles,
        // chrome partial names, managed folder entries, …) but keep
        // incomplete-download extensions in play so they can still surface
        // as abandoned downloads below.
        if ignorePolicy.shouldIgnore(
            url: url,
            kind: .appeared,
            isDirectory: isDirectory,
            ignoringIncompleteDownloads: true
        ) {
            return nil
        }
        guard values?.isRegularFile ?? !isDirectory else {
            return nil
        }
        let modificationDate = values?.contentModificationDate ?? .distantPast
        // Listing a folder can bump access time on some volumes, so Linux
        // (and tests) key off modification date. macOS also consults access date.
        var dates: [Date] = [modificationDate]
        #if os(macOS)
        if let accessed = values?.contentAccessDate {
            dates.append(accessed)
        }
        #endif
        let lastUsed = dates.max() ?? values?.creationDate ?? .distantPast
        let dateAdded = values?.addedToDirectoryDate ?? values?.creationDate ?? lastUsed
        let byteCount = Int64(values?.fileSize ?? 0)
        return FileInfo(
            size: byteCount,
            modificationDate: modificationDate,
            lastUsed: lastUsed,
            dateAdded: dateAdded,
            isIncompleteDownload: isIncompleteDownload
        )
    }

    /// Maps each duplicate file to the original it copies. Files are grouped
    /// by size first, then confirmed with a content hash; within a matching
    /// hash group the original is the oldest by date added, then the file
    /// with the shortest name.
    private func duplicateOriginals(
        among infos: [URL: FileInfo],
        fileManager: FileManager
    ) -> [URL: URL] {
        let candidates = infos.filter { !$0.value.isIncompleteDownload }
        var bySize: [Int64: [URL]] = [:]
        for (url, info) in candidates {
            bySize[info.size, default: []].append(url)
        }

        var originals: [URL: URL] = [:]
        for (size, urls) in bySize where size > 0 && urls.count > 1 {
            var byHash: [String: [URL]] = [:]
            for url in urls {
                guard let info = infos[url] else { continue }
                guard let hash = hashCache.hash(
                    for: url,
                    size: info.size,
                    modified: info.modificationDate,
                    fileManager: fileManager
                ) else { continue }
                byHash[hash, default: []].append(url)
            }
            for (_, group) in byHash where group.count > 1 {
                let sorted = group.sorted { lhs, rhs in
                    let lhsInfo = infos[lhs]!
                    let rhsInfo = infos[rhs]!
                    if lhsInfo.dateAdded != rhsInfo.dateAdded {
                        return lhsInfo.dateAdded < rhsInfo.dateAdded
                    }
                    if lhs.lastPathComponent.count != rhs.lastPathComponent.count {
                        return lhs.lastPathComponent.count < rhs.lastPathComponent.count
                    }
                    return lhs.path < rhs.path
                }
                let original = sorted[0]
                for duplicate in sorted.dropFirst() {
                    originals[duplicate] = original
                }
            }
        }
        return originals
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
