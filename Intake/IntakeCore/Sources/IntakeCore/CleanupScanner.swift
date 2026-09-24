import Foundation

public struct CleanupScanner: Sendable {
    /// 24h of unchanged size/modification date marks a download abandoned.
    public static let abandonedDownloadInterval: TimeInterval = 24 * 60 * 60

    /// Installer file extensions Cleanup checks against installed apps.
    public static let installerExtensions: Set<String> = ["dmg", "pkg", "mpkg"]

    public var watchFolder: URL
    public var thresholdDays: Int
    public var includeWatchRoot: Bool
    public var snoozedUntil: [String: Date]
    public var ignorePolicy: DownloadIgnorePolicy
    public var managedFolderNames: Set<String>
    public var hashCache: DuplicateHashCache
    /// Where installed apps are looked for when matching installer files —
    /// injected so tests can point at a fake Applications folder instead of
    /// the real `/Applications` and `~/Applications`.
    public var applicationsFolders: [URL]
    /// Currently mounted volumes (their URLs' last path components are the
    /// volume names) — installers whose disk image is already mounted are
    /// skipped rather than offered for cleanup.
    public var mountedVolumeURLs: [URL]
    public var packageReceiptResolver: PackageReceiptResolver
    /// The "arrival" date used for both installer files and installed apps
    /// when deciding whether an app is newer than its installer. Injectable
    /// so tests can fabricate an added-to-directory date, which isn't
    /// something a test can reliably set on disk. Defaults to
    /// `InstalledAppMatcher.defaultDate` (added-to-directory, then creation,
    /// then content-modification date).
    public var installDateProvider: @Sendable (URL, FileManager) -> Date

    public init(
        watchFolder: URL,
        thresholdDays: Int,
        includeWatchRoot: Bool,
        snoozedUntil: [String: Date] = [:],
        ignorePolicy: DownloadIgnorePolicy = DownloadIgnorePolicy(),
        managedFolderNames: Set<String> = DefaultTaxonomy.managedFolderNames,
        hashCache: DuplicateHashCache = DuplicateHashCache(),
        applicationsFolders: [URL] = InstalledAppMatcher.defaultApplicationsFolders(),
        mountedVolumeURLs: [URL] = [],
        packageReceiptResolver: PackageReceiptResolver = PackageReceiptResolver(),
        installDateProvider: @escaping @Sendable (URL, FileManager) -> Date = InstalledAppMatcher.defaultDate
    ) {
        self.watchFolder = watchFolder
        self.thresholdDays = thresholdDays
        self.includeWatchRoot = includeWatchRoot
        self.snoozedUntil = snoozedUntil
        self.ignorePolicy = ignorePolicy
        self.managedFolderNames = managedFolderNames
        self.hashCache = hashCache
        self.applicationsFolders = applicationsFolders
        self.mountedVolumeURLs = mountedVolumeURLs
        self.packageReceiptResolver = packageReceiptResolver
        self.installDateProvider = installDateProvider
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
        let installedApps = InstalledAppMatcher.installedApps(
            in: applicationsFolders,
            fileManager: fileManager,
            dateProvider: installDateProvider
        )

        var results: [CleanupCandidate] = []
        for (url, info) in infos {
            if isSnoozed(url, normalizedSnoozes: normalizedSnoozes, now: now) {
                continue
            }
            if isMountedInstallerImage(url) {
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
            if let match = installedAppMatch(
                for: url,
                installedApps: installedApps,
                fileManager: fileManager
            ) {
                results.append(
                    CleanupCandidate(
                        url: url,
                        byteCount: info.size,
                        lastUsed: info.lastUsed,
                        reason: .installed(appName: match.displayName, appURL: match.url)
                    )
                )
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

    /// True for a `.dmg` whose disk image is currently mounted — the user is
    /// actively using it, so it's skipped rather than offered for cleanup.
    /// Never mounts an image itself; it only compares names against the
    /// already-mounted volumes it was given.
    private func isMountedInstallerImage(_ url: URL) -> Bool {
        guard url.pathExtension.lowercased() == "dmg" else { return false }
        let target = InstalledAppMatcher.normalize(url.lastPathComponent)
        guard !target.isEmpty else { return false }
        return mountedVolumeURLs.contains { InstalledAppMatcher.normalize($0.lastPathComponent) == target }
    }

    /// The installed app an installer file matches, if its name (or, for
    /// `.pkg`/`.mpkg`, its install receipt) points at an app in
    /// `applicationsFolders` that's newer than the installer itself. Both
    /// sides of the comparison go through `installDateProvider` rather than
    /// raw content-modification date — see its doc comment for why.
    private func installedAppMatch(
        for url: URL,
        installedApps: [InstalledAppMatcher.InstalledApp],
        fileManager: FileManager
    ) -> InstalledAppMatcher.InstalledApp? {
        let ext = url.pathExtension.lowercased()
        guard Self.installerExtensions.contains(ext) else { return nil }
        let installerDate = installDateProvider(url, fileManager)

        if ext == "pkg" || ext == "mpkg",
           let receiptMatch = packageReceiptResolver.installedApp(
               forPackageAt: url,
               fileManager: fileManager,
               dateProvider: installDateProvider
           ),
           receiptMatch.date > installerDate
        {
            return receiptMatch
        }

        if let nameMatch = InstalledAppMatcher.bestMatch(forInstallerNamed: url.lastPathComponent, in: installedApps),
           nameMatch.date > installerDate
        {
            return nameMatch
        }
        return nil
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
