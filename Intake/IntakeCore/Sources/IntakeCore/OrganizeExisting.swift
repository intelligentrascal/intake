import Foundation

public enum OrganizeExistingCopy: Sendable {
    public static let menuTitle = "Organize Existing…"
    public static let organizeButton = "Organize"
    public static let cancelButton = "Cancel"
    public static let showActivityButton = "Show Activity"
    public static let confirmationThreshold = 10

    public static func confirmTitle(folderName: String) -> String {
        "Organize files already in \(folderName)?"
    }

    public static let confirmBody =
        "Intake will rename and file items sitting in the watch folder root using your current rules. Files already in category folders are left alone. You can follow every change in Activity."

    public static let pausedOneShotNote =
        "Automatic organizing is off. This one-shot still runs and does not turn watching back on."
}

public struct OrganizeExistingScan: Equatable, Sendable {
    public var eligible: [URL]
    public var skipped: [URL]

    public var needsConfirmation: Bool {
        eligible.count >= OrganizeExistingCopy.confirmationThreshold
    }

    public init(eligible: [URL], skipped: [URL]) {
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
        let keys: [URLResourceKey] = [.isDirectoryKey, .isRegularFileKey]
        let items = (try? fileManager.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: keys,
            options: []
        )) ?? []

        var eligible: [URL] = []
        var skipped: [URL] = []

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
                skipped.append(standardized)
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
            switch processOne(url, fileManager: fileManager, now: now) {
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

    /// Same rename → route → Activity path as live ingest, **without**
    /// Wait before organizing. Manual catch-up files immediately.
    public func processOne(
        _ url: URL,
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

        let pipeline = IngestPipeline(watchFolder: watchFolder, rules: rules)
        let planned = pipeline.plan(for: source)
        guard planned != nil else {
            return .notInWatchRoot
        }
        let existing = existingNames(in: planned?.destinationDirectory, fileManager: fileManager)
        guard let plan = pipeline.plan(for: source, existingNamesInDestination: existing) else {
            return .notInWatchRoot
        }

        do {
            let produced = try pipeline.apply(plan, fileManager: fileManager, now: now)
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

    private func existingNames(in directory: URL?, fileManager: FileManager) -> Set<String> {
        guard let directory else { return [] }
        let names = (try? fileManager.contentsOfDirectory(atPath: directory.path)) ?? []
        return Set(names)
    }
}
