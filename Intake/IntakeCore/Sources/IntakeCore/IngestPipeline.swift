import Foundation

public struct IngestPlan: Equatable, Sendable {
    public var sourceURL: URL
    public var renamedFileName: String
    public var category: FileCategory
    public var destinationFolderName: String
    public var destinationDirectory: URL
    public var destinationURL: URL

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
        existingNamesInDestination: Set<String> = []
    ) -> IngestPlan? {
        let sourceFolder = sourceURL.deletingLastPathComponent().standardizedFileURL
        guard sourceFolder == watchFolder.standardizedFileURL else {
            return nil
        }

        let renamed = Self.uniqued(
            fileName: normalizer.proposedFileName(for: sourceURL),
            among: existingNamesInDestination
        )
        let match = DefaultTaxonomy.matchingRule(for: sourceURL, rules: rules)
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
        return IngestPlan(
            sourceURL: sourceURL,
            renamedFileName: renamed,
            category: category,
            destinationFolderName: destinationFolderName,
            destinationDirectory: destinationDirectory,
            destinationURL: destinationURL
        )
    }

    /// Local rename in the watch-folder root. Does not create category folders.
    /// Files already inside category folders are left alone.
    public func applyRenameInPlace(
        at sourceURL: URL,
        fileManager: FileManager = .default,
        now: Date = Date()
    ) throws -> (url: URL, entries: [ActivityEntry]) {
        let source = sourceURL.standardizedFileURL
        let sourceFolder = source.deletingLastPathComponent().standardizedFileURL
        guard sourceFolder == watchFolder.standardizedFileURL else {
            return (source, [])
        }
        guard fileManager.fileExists(atPath: source.path) else {
            return (source, [])
        }

        let proposed = normalizer.proposedFileName(for: source)
        if proposed == source.lastPathComponent {
            return (source, [])
        }

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
                    fileName: uniqueName
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
        let source = sourceURL.standardizedFileURL
        let sourceFolder = source.deletingLastPathComponent().standardizedFileURL
        guard sourceFolder == watchFolder.standardizedFileURL else {
            return []
        }
        guard fileManager.fileExists(atPath: source.path) else {
            return []
        }

        let match = DefaultTaxonomy.matchingRule(for: source, rules: rules)
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
                destinationFolder: destinationFolderName
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

    public static func uniqued(fileName: String, among existing: Set<String>) -> String {
        if !existing.contains(fileName) {
            return fileName
        }
        let url = URL(fileURLWithPath: fileName)
        let ext = url.pathExtension
        let base = ext.isEmpty ? fileName : String(fileName.dropLast(ext.count + 1))
        var index = 2
        while true {
            let candidate = ext.isEmpty ? "\(base) \(index)" : "\(base) \(index).\(ext)"
            if !existing.contains(candidate) {
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
