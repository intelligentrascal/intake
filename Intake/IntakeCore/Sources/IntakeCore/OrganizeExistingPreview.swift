import Foundation

/// One eligible file mapped through `IngestPipeline.plan`, plus the on-disk
/// snapshot used to detect a change before Apply.
public struct OrganizePreviewItem: Identifiable, Equatable, Sendable {
    public var plan: IngestPlan
    /// Size at scan time — Apply re-checks this before touching the file.
    public var sizeAtPreview: Int64

    public var id: URL { plan.sourceURL }

    public init(plan: IngestPlan, sizeAtPreview: Int64) {
        self.plan = plan
        self.sizeAtPreview = sizeAtPreview
    }
}

/// Every eligible file bound for one destination folder.
public struct OrganizePreviewGroup: Identifiable, Equatable, Sendable {
    public var destinationFolderName: String
    public var destinationDirectory: URL
    public var isNewFolder: Bool
    public var items: [OrganizePreviewItem]

    public var id: URL { destinationDirectory }
    public var count: Int { items.count }

    public init(
        destinationFolderName: String,
        destinationDirectory: URL,
        isNewFolder: Bool,
        items: [OrganizePreviewItem]
    ) {
        self.destinationFolderName = destinationFolderName
        self.destinationDirectory = destinationDirectory
        self.isNewFolder = isNewFolder
        self.items = items
    }
}

/// What Organize Existing will do, before it does it: every eligible file
/// mapped to its destination and grouped by folder, plus every skipped file
/// with its reason. Building this never touches disk beyond reading it.
public struct OrganizeExistingPreview: Equatable, Sendable {
    public var groups: [OrganizePreviewGroup]
    public var skipped: [OrganizeExistingSkip]

    public var eligibleCount: Int {
        groups.reduce(0) { $0 + $1.items.count }
    }

    public var isEmpty: Bool {
        eligibleCount == 0
    }

    public init(groups: [OrganizePreviewGroup], skipped: [OrganizeExistingSkip]) {
        self.groups = groups
        self.skipped = skipped
    }
}

/// Builds an `OrganizeExistingPreview` from a scan by running every eligible
/// file through `IngestPipeline.plan`, simulating collisions against a
/// destination listing that starts from disk and grows as each simulated
/// file lands — so two files that would collide with each other, not just
/// with something already on disk, get distinct suffixes in the preview.
public enum OrganizeExistingPreviewBuilder: Sendable {
    public static func build(
        scan: OrganizeExistingScan,
        pipeline: IngestPipeline,
        fileManager: FileManager = .default
    ) -> OrganizeExistingPreview {
        // Case-insensitive, like APFS: seed each destination's simulated
        // listing from disk once, then add every simulated arrival to it.
        var simulatedNames: [URL: Set<String>] = [:]
        var newFolders: Set<URL> = []
        var order: [URL] = []
        var itemsByFolder: [URL: [OrganizePreviewItem]] = [:]
        var folderNames: [URL: String] = [:]

        func existingNames(in directory: URL) -> Set<String> {
            if let cached = simulatedNames[directory] {
                return cached
            }
            let names = (try? fileManager.contentsOfDirectory(atPath: directory.path)) ?? []
            let set = Set(names)
            simulatedNames[directory] = set
            if !fileManager.fileExists(atPath: directory.path) {
                newFolders.insert(directory)
            }
            return set
        }

        for url in scan.eligible {
            guard let plan = pipeline.plan(
                for: url,
                existingNamesInDestination: [],
                fileManager: fileManager
            ) else {
                continue
            }
            let destination = plan.destinationDirectory
            var current = existingNames(in: destination)
            let uniqueName = IngestPipeline.uniqued(fileName: plan.renamedFileName, among: current)
            current.insert(uniqueName)
            simulatedNames[destination] = current

            var finalPlan = plan
            finalPlan.renamedFileName = uniqueName
            finalPlan.destinationURL = destination.appendingPathComponent(uniqueName, isDirectory: false)
            finalPlan.isNewFolder = newFolders.contains(destination)

            let size = DownloadWriteGate.fileSize(at: url, fileManager: fileManager)
            let item = OrganizePreviewItem(plan: finalPlan, sizeAtPreview: size)

            if itemsByFolder[destination] == nil {
                order.append(destination)
                folderNames[destination] = plan.destinationFolderName
            }
            itemsByFolder[destination, default: []].append(item)
        }

        let groups = order.map { destination in
            OrganizePreviewGroup(
                destinationFolderName: folderNames[destination] ?? destination.lastPathComponent,
                destinationDirectory: destination,
                isNewFolder: newFolders.contains(destination),
                items: itemsByFolder[destination] ?? []
            )
        }

        return OrganizeExistingPreview(groups: groups, skipped: scan.skipped)
    }
}
