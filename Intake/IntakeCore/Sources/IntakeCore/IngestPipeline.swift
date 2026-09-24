import Foundation

public struct IngestPlan: Equatable, Sendable {
    public var sourceURL: URL
    public var renamedFileName: String
    public var category: FileCategory
    public var destinationFolderName: String
    public var destinationDirectory: URL
    public var destinationURL: URL
    /// The file's source domain, when the where-from metadata on disk names one.
    public var sourceDomain: String?
    /// True when `destinationDirectory` did not exist on disk when this plan was made —
    /// applying it will create a new lazy folder.
    public var isNewFolder: Bool

    public var needsRename: Bool {
        sourceURL.lastPathComponent != renamedFileName
    }
}

public struct IngestPipeline: Sendable {
    public var watchFolder: URL
    public var rules: [RoutingRule]
    public var normalizer: FileNameNormalizer

    public init(
        watchFolder: URL,
        rules: [RoutingRule] = DefaultTaxonomy.rules,
        normalizer: FileNameNormalizer = FileNameNormalizer()
    ) {
        self.watchFolder = watchFolder
        self.rules = rules
        self.normalizer = normalizer
    }

    public func plan(
        for sourceURL: URL,
        existingNamesInDestination: Set<String> = [],
        fileManager: FileManager = .default
    ) -> IngestPlan? {
        let sourceFolder = sourceURL.deletingLastPathComponent().standardizedFileURL
        guard sourceFolder == watchFolder.standardizedFileURL else {
            return nil
        }

        let renamed = Self.uniqued(
            fileName: normalizer.proposedFileName(for: sourceURL),
            among: existingNamesInDestination
        )
        let facts = FileFacts.onDisk(at: sourceURL, fileManager: fileManager)
        let match = DefaultTaxonomy.matchingRule(for: facts, rules: rules)
        let category = match?.category ?? .other
        let destinationFolderName = match?.folderName ?? FileCategory.other.folderName
        let destinationDirectory = watchFolder.appendingPathComponent(
            destinationFolderName,
            isDirectory: true
        )
        let destinationURL = destinationDirectory.appendingPathComponent(
            renamed,
            isDirectory: false
        )
        let isNewFolder = !fileManager.fileExists(atPath: destinationDirectory.path)
        return IngestPlan(
            sourceURL: sourceURL,
            renamedFileName: renamed,
            category: category,
            destinationFolderName: destinationFolderName,
            destinationDirectory: destinationDirectory,
            destinationURL: destinationURL,
            sourceDomain: facts.sourceHost,
            isNewFolder: isNewFolder
        )
    }

    /// Local rename in the watch-folder root. Does not create category folders.
    /// Files already inside category folders are left alone.
    public func applyRenameInPlace(
        at sourceURL: URL,
        fileManager: FileManager = .default,
        now: Date = Date()
    ) throws -> (url: URL, entries: [ActivityEntry]) {
        let requested = sourceURL.standardizedFileURL
        let sourceFolder = requested.deletingLastPathComponent().standardizedFileURL
        guard sourceFolder == watchFolder.standardizedFileURL else {
            return (requested, [])
        }
        guard fileManager.fileExists(atPath: requested.path) else {
            return (requested, [])
        }
        // Work from the name on disk: a stale spelling must not collide with itself.
        let source = FileIdentity.onDiskURL(for: requested, fileManager: fileManager)
        // Never rename an empty placeholder (false-stable / still-writing download).
        guard DownloadWriteGate.allowsOrganizeOrRename(at: source, fileManager: fileManager) else {
            return (source, [])
        }
        EmptyFullSiblingDedupe.removeEmptySiblings(
            of: source,
            in: watchFolder,
            fileManager: fileManager
        )

        let proposed = normalizer.proposedFileName(for: source)
        if proposed == source.lastPathComponent {
            return (source, [])
        }

        // Only a *different* file may force a collision suffix.
        var existing = existingNames(in: watchFolder, fileManager: fileManager)
        existing.remove(source.lastPathComponent)
        let uniqueName = Self.uniqued(fileName: proposed, among: existing)
        let destination = watchFolder.appendingPathComponent(uniqueName, isDirectory: false)
        if destination.standardizedFileURL == source {
            return (source, [])
        }

        try fileManager.moveItem(at: source, to: destination)
        return (
            destination,
            [
                ActivityEntry(
                    date: now,
                    kind: .renamed,
                    detail: "Renamed \(source.lastPathComponent) to \(uniqueName)",
                    url: destination,
                    fileName: uniqueName,
                    beforePath: source.path,
                    afterPath: destination.path
                ),
            ]
        )
    }

    /// Move into the matching lazy category folder. Preserves the current name
    /// except a collision suffix in the destination.
    public func applyRoute(
        at sourceURL: URL,
        fileManager: FileManager = .default,
        now: Date = Date()
    ) throws -> [ActivityEntry] {
        let requested = sourceURL.standardizedFileURL
        let sourceFolder = requested.deletingLastPathComponent().standardizedFileURL
        guard sourceFolder == watchFolder.standardizedFileURL else {
            return []
        }
        guard fileManager.fileExists(atPath: requested.path) else {
            return []
        }
        // File under the name on disk (keeps the rename's casing for stale URLs).
        let source = FileIdentity.onDiskURL(for: requested, fileManager: fileManager)
        // Never file an empty placeholder (false-stable / still-writing download).
        guard DownloadWriteGate.allowsOrganizeOrRename(at: source, fileManager: fileManager) else {
            return []
        }
        EmptyFullSiblingDedupe.removeEmptySiblings(
            of: source,
            in: watchFolder,
            fileManager: fileManager
        )

        let facts = FileFacts.onDisk(at: source, fileManager: fileManager)
        let match = DefaultTaxonomy.matchingRule(for: facts, rules: rules)
        let destinationFolderName = match?.folderName ?? FileCategory.other.folderName
        let destinationDirectory = watchFolder.appendingPathComponent(
            destinationFolderName,
            isDirectory: true
        )
        try fileManager.createDirectory(
            at: destinationDirectory,
            withIntermediateDirectories: true
        )

        let uniqueName = Self.uniqued(
            fileName: source.lastPathComponent,
            among: existingNames(in: destinationDirectory, fileManager: fileManager)
        )
        let destination = destinationDirectory.appendingPathComponent(
            uniqueName,
            isDirectory: false
        )
        try fileManager.moveItem(at: source, to: destination)
        return [
            ActivityEntry(
                date: now,
                kind: .moved,
                detail: "Moved \(destination.lastPathComponent) to \(destinationFolderName)",
                url: destination,
                fileName: destination.lastPathComponent,
                destinationFolder: destinationFolderName,
                beforePath: source.path,
                afterPath: destination.path,
                sourceDomain: facts.sourceHost
            ),
        ]
    }

    public func apply(
        _ plan: IngestPlan,
        fileManager: FileManager = .default,
        now: Date = Date()
    ) throws -> [ActivityEntry] {
        let renamed = try applyRenameInPlace(
            at: plan.sourceURL,
            fileManager: fileManager,
            now: now
        )
        var entries = renamed.entries
        entries.append(
            contentsOf: try applyRoute(at: renamed.url, fileManager: fileManager, now: now)
        )
        return entries
    }

    /// Names compare case-insensitively, like APFS: `report.pdf` holds `Report.pdf`.
    /// Callers remove the moving file's own name from `existing` first.
    public static func uniqued(fileName: String, among existing: Set<String>) -> String {
        let taken = Set(existing.map(FileIdentity.collisionKey(forFileName:)))
        func isTaken(_ name: String) -> Bool {
            taken.contains(FileIdentity.collisionKey(forFileName: name))
        }
        if !isTaken(fileName) {
            return fileName
        }
        let url = URL(fileURLWithPath: fileName)
        let ext = url.pathExtension
        let base = ext.isEmpty ? fileName : String(fileName.dropLast(ext.count + 1))
        var index = 2
        while true {
            let candidate = ext.isEmpty ? "\(base) \(index)" : "\(base) \(index).\(ext)"
            if !isTaken(candidate) {
                return candidate
            }
            index += 1
        }
    }

    private func existingNames(in directory: URL, fileManager: FileManager) -> Set<String> {
        guard let names = try? fileManager.contentsOfDirectory(atPath: directory.path) else {
            return []
        }
        return Set(names)
    }
}
