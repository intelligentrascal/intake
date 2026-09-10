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

    public func apply(
        _ plan: IngestPlan,
        fileManager: FileManager = .default,
        now: Date = Date()
    ) throws -> [ActivityEntry] {
        var current = plan.sourceURL
        var entries: [ActivityEntry] = []

        if plan.needsRename {
            let renamedURL = current
                .deletingLastPathComponent()
                .appendingPathComponent(plan.renamedFileName, isDirectory: false)
            try fileManager.moveItem(at: current, to: renamedURL)
            current = renamedURL
            entries.append(
                ActivityEntry(
                    date: now,
                    kind: .renamed,
                    detail: "Renamed \(plan.sourceURL.lastPathComponent) to \(plan.renamedFileName)",
                    url: current,
                    fileName: plan.renamedFileName
                )
            )
        }

        try fileManager.createDirectory(
            at: plan.destinationDirectory,
            withIntermediateDirectories: true
        )

        var destination = plan.destinationURL
        if fileManager.fileExists(atPath: destination.path) {
            let uniqueName = Self.uniqued(
                fileName: plan.renamedFileName,
                among: existingNames(in: plan.destinationDirectory, fileManager: fileManager)
            )
            destination = plan.destinationDirectory.appendingPathComponent(
                uniqueName,
                isDirectory: false
            )
        }

        try fileManager.moveItem(at: current, to: destination)
        entries.append(
            ActivityEntry(
                date: now,
                kind: .moved,
                detail: "Moved \(destination.lastPathComponent) to \(plan.destinationFolderName)",
                url: destination,
                fileName: destination.lastPathComponent,
                destinationFolder: plan.destinationFolderName
            )
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
