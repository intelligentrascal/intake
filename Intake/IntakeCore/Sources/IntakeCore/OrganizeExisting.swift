import Foundation

public enum OrganizeExistingCopy: Sendable {
    public static let menuTitle = "Organize Existing…"
    public static let organizeButton = "Organize"
    public static let cancelButton = "Cancel"
    public static let showActivityButton = "Show Activity"

    public static func confirmTitle(folderName: String) -> String {
        "Organize files already in \(folderName)?"
    }

    public static let confirmTitleAllFolders = "Organize files already in your watch folders?"

    public static let confirmBody =
        "Intake will rename and file items sitting in the watch folder root using your current rules. Files already in category folders are left alone. You can follow every change in Activity."

    public static let pausedOneShotNote =
        "Automatic organizing is off. This one-shot still runs and does not turn watching back on."
}

/// Why a root file was left out of an Organize Existing run.
public enum OrganizeSkipReason: String, Equatable, Sendable, Codable {
    /// An in-progress download (partial extension, browser temp file, `Unconfirmed …`).
    case stillDownloading
    /// Ignored by policy: dotfile, a managed category folder, or similar.
    case ignored
    /// A zero-byte placeholder — a false-stable or still-writing download.
    case emptyPlaceholder
    /// The file was excluded by the user in the Organize Existing preview.
    case excluded
    /// The file changed (size differs from what the preview saw) between preview and apply.
    case changedSincePreview
    /// The file was moved or deleted between preview and apply.
    case missingSincePreview

    public var reasonText: String {
        switch self {
        case .stillDownloading: "Still downloading"
        case .ignored: "Ignored"
        case .emptyPlaceholder: "Empty placeholder"
        case .excluded: "Excluded"
        case .changedSincePreview: "Changed since preview"
        case .missingSincePreview: "No longer there"
        }
    }
}

/// A root file the scanner left out of `eligible`, with why.
public struct OrganizeExistingSkip: Equatable, Sendable {
    public var url: URL
    public var reason: OrganizeSkipReason

    public init(url: URL, reason: OrganizeSkipReason) {
        self.url = url
        self.reason = reason
    }
}

public struct OrganizeExistingScan: Equatable, Sendable {
    public var eligible: [URL]
    public var skipped: [OrganizeExistingSkip]

    public init(eligible: [URL], skipped: [OrganizeExistingSkip]) {
        self.eligible = eligible
        self.skipped = skipped
    }
}

public struct OrganizeExistingSummary: Equatable, Sendable {
    public var organized: Int
    public var skipped: Int
    public var errors: Int
    public var cancelled: Bool

    public init(organized: Int, skipped: Int, errors: Int, cancelled: Bool = false) {
        self.organized = organized
        self.skipped = skipped
        self.errors = errors
        self.cancelled = cancelled
    }

    public var doneMessage: String {
        "Organized \(organized). \(skipped) skipped. \(errors) errors."
    }
}

public struct OrganizeExistingScanner: Sendable {
    public var watchFolder: URL
    public var ignorePolicy: DownloadIgnorePolicy

    public init(
        watchFolder: URL,
        ignorePolicy: DownloadIgnorePolicy = DownloadIgnorePolicy()
    ) {
        self.watchFolder = watchFolder
        self.ignorePolicy = ignorePolicy
    }

    /// Lists **root-only** files. Directories (including Intake-managed category
    /// folders) are not entered, so filed items are left alone.
    public func scan(fileManager: FileManager = .default) -> OrganizeExistingScan {
        let root = watchFolder.standardizedFileURL
        let keys: [URLResourceKey] = [.isDirectoryKey, .isRegularFileKey, .fileSizeKey]
        let items = (try? fileManager.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: keys,
            options: []
        )) ?? []

        var eligible: [URL] = []
        var skipped: [OrganizeExistingSkip] = []

        let sorted = items.sorted {
            $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending
        }

        for url in sorted {
            let standardized = url.standardizedFileURL
            let isDirectory = (try? standardized.resourceValues(forKeys: [.isDirectoryKey]).isDirectory)
                ?? standardized.hasDirectoryPath
            if isDirectory {
                continue
            }
            if ignorePolicy.shouldIgnore(url: standardized, kind: .appeared, isDirectory: false) {
                let reason: OrganizeSkipReason = ignorePolicy.isIncompleteDownloadExtension(url: standardized)
                    ? .stillDownloading
                    : .ignored
                skipped.append(OrganizeExistingSkip(url: standardized, reason: reason))
                continue
            }
            if !DownloadWriteGate.allowsOrganizeOrRename(at: standardized, fileManager: fileManager) {
                skipped.append(OrganizeExistingSkip(url: standardized, reason: .emptyPlaceholder))
                continue
            }
            eligible.append(standardized)
        }

        return OrganizeExistingScan(eligible: eligible, skipped: skipped)
    }
}

public struct OrganizeExistingProcessor: Sendable {
    public var watchFolder: URL
    public var rules: [RoutingRule]
    public var ignorePolicy: DownloadIgnorePolicy

    public init(
        watchFolder: URL,
        rules: [RoutingRule] = DefaultTaxonomy.rules,
        ignorePolicy: DownloadIgnorePolicy = DownloadIgnorePolicy()
    ) {
        self.watchFolder = watchFolder
        self.rules = rules
        self.ignorePolicy = ignorePolicy
    }

    public enum FileResult: Equatable, Sendable {
        case organized([ActivityEntry])
        case skipped(ActivityEntry)
        case error(ActivityEntry)
        case notInWatchRoot
    }

    public func process(
        urls: [URL],
        alreadySkipped: Int = 0,
        isCancelled: () -> Bool = { false },
        fileManager: FileManager = .default,
        now: Date = Date(),
        onProgress: ((Int, Int) -> Void)? = nil
    ) -> (summary: OrganizeExistingSummary, entries: [ActivityEntry]) {
        var organized = 0
        var skipped = alreadySkipped
        var errors = 0
        var entries: [ActivityEntry] = []
        var cancelled = false

        for (index, url) in urls.enumerated() {
            if isCancelled() {
                cancelled = true
                break
            }
            switch processOne(url, mode: .renameAndRoute, fileManager: fileManager, now: now) {
            case .organized(let produced):
                organized += 1
                entries.append(contentsOf: produced)
            case .skipped(let entry):
                skipped += 1
                entries.append(entry)
            case .error(let entry):
                errors += 1
                entries.append(entry)
            case .notInWatchRoot:
                skipped += 1
            }
            onProgress?(index + 1, urls.count)
        }

        return (
            OrganizeExistingSummary(
                organized: organized,
                skipped: skipped,
                errors: errors,
                cancelled: cancelled
            ),
            entries
        )
    }

    /// Applies exactly the chosen preview items (excluded ones never reach here).
    /// Re-checks each file before touching it: gone, or a size that no longer
    /// matches what the preview saw, is logged as `skipped` with a reason —
    /// never as an error. Otherwise runs the pipeline fresh, which recomputes
    /// the rename/collision suffix from the current disk state — the same
    /// simulation the preview used, so the result matches it when nothing changed.
    public func applyPreview(
        items: [OrganizePreviewItem],
        alreadySkipped: Int = 0,
        isCancelled: () -> Bool = { false },
        fileManager: FileManager = .default,
        now: Date = Date(),
        onProgress: ((Int, Int) -> Void)? = nil,
        onFileResult: ((FileResult) -> Void)? = nil
    ) -> (summary: OrganizeExistingSummary, entries: [ActivityEntry]) {
        var organized = 0
        var skipped = alreadySkipped
        var errors = 0
        var entries: [ActivityEntry] = []
        var cancelled = false
        let pipeline = IngestPipeline(watchFolder: watchFolder, rules: rules)

        for (index, item) in items.enumerated() {
            if isCancelled() {
                cancelled = true
                break
            }
            let source = item.plan.sourceURL
            let result: FileResult
            if !fileManager.fileExists(atPath: source.path) {
                result = .skipped(skipEntry(for: source, reason: .missingSincePreview, now: now))
            } else if DownloadWriteGate.fileSize(at: source, fileManager: fileManager)
                != item.sizeAtPreview
            {
                result = .skipped(skipEntry(for: source, reason: .changedSincePreview, now: now))
            } else if let freshPlan = pipeline.plan(for: source, fileManager: fileManager) {
                do {
                    let produced = try pipeline.apply(freshPlan, fileManager: fileManager, now: now)
                    result = .organized(produced)
                } catch {
                    result = .error(
                        ActivityEntry(
                            date: now,
                            kind: .error,
                            detail: "Could not file \(source.lastPathComponent): \(error.localizedDescription)",
                            url: source,
                            fileName: source.lastPathComponent
                        )
                    )
                }
            } else {
                result = .skipped(skipEntry(for: source, reason: .missingSincePreview, now: now))
            }

            switch result {
            case .organized(let produced):
                organized += 1
                entries.append(contentsOf: produced)
            case .skipped(let entry):
                skipped += 1
                entries.append(entry)
            case .error(let entry):
                errors += 1
                entries.append(entry)
            case .notInWatchRoot:
                skipped += 1
            }
            onFileResult?(result)
            onProgress?(index + 1, items.count)
        }

        return (
            OrganizeExistingSummary(
                organized: organized,
                skipped: skipped,
                errors: errors,
                cancelled: cancelled
            ),
            entries
        )
    }

    private func skipEntry(for url: URL, reason: OrganizeSkipReason, now: Date) -> ActivityEntry {
        ActivityEntry(
            date: now,
            kind: .skipped,
            detail: "Skipped \(url.lastPathComponent) — \(reason.reasonText.lowercased())",
            url: url,
            fileName: url.lastPathComponent
        )
    }

    /// Live ingest uses `renameInPlace` then, after Wait, `routeOnly`.
    /// Organize Existing and Rename-off filing still use `renameAndRoute`.
    public func processOne(
        _ url: URL,
        mode: IngestApplyMode = .renameAndRoute,
        stableAt: Date? = nil,
        fileManager: FileManager = .default,
        now: Date = Date()
    ) -> FileResult {
        let source = url.standardizedFileURL
        let isDirectory = (try? source.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
        if ignorePolicy.shouldIgnore(url: source, kind: .appeared, isDirectory: isDirectory) {
            return .skipped(
                ActivityEntry(
                    date: now,
                    kind: .skipped,
                    detail: "Skipped \(source.lastPathComponent)",
                    url: source,
                    fileName: source.lastPathComponent
                )
            )
        }
        if !DownloadWriteGate.allowsOrganizeOrRename(at: source, fileManager: fileManager) {
            return .skipped(
                ActivityEntry(
                    date: now,
                    kind: .skipped,
                    detail: "Skipped \(source.lastPathComponent)",
                    url: source,
                    fileName: source.lastPathComponent
                )
            )
        }

        let pipeline = IngestPipeline(watchFolder: watchFolder, rules: rules)
        guard pipeline.plan(for: source, stableAt: stableAt) != nil else {
            return .notInWatchRoot
        }

        do {
            let produced: [ActivityEntry]
            switch mode {
            case .renameInPlace:
                produced = try pipeline.applyRenameInPlace(
                    at: source,
                    fileManager: fileManager,
                    now: now
                ).entries
            case .routeOnly:
                produced = try pipeline.applyRoute(
                    at: source,
                    stableAt: stableAt,
                    fileManager: fileManager,
                    now: now
                )
            case .renameAndRoute:
                guard let plan = pipeline.plan(for: source, stableAt: stableAt) else {
                    return .notInWatchRoot
                }
                produced = try pipeline.apply(plan, stableAt: stableAt, fileManager: fileManager, now: now)
            }
            return .organized(produced)
        } catch {
            return .error(
                ActivityEntry(
                    date: now,
                    kind: .error,
                    detail: "Could not file \(source.lastPathComponent): \(error.localizedDescription)",
                    url: source,
                    fileName: source.lastPathComponent
                )
            )
        }
    }
}
