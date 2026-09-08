import Foundation

public struct CleanupProcessor: Sendable {
    public static let ignorableEmptyFolderNames: Set<String> = [
        ".DS_Store",
        ".localized",
        "Icon\r",
    ]

    public var watchFolder: URL

    public init(watchFolder: URL) {
        self.watchFolder = watchFolder
    }

    public func fileAway(
        _ candidate: CleanupCandidate,
        to directory: URL,
        fileManager: FileManager = .default,
        now: Date = Date()
    ) throws -> ActivityEntry {
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let existing = Set((try? fileManager.contentsOfDirectory(atPath: directory.path)) ?? [])
        let uniqueName = IngestPipeline.uniqued(
            fileName: candidate.url.lastPathComponent,
            among: existing
        )
        let destination = directory.appendingPathComponent(uniqueName, isDirectory: false)
        try fileManager.moveItem(at: candidate.url, to: destination)
        return ActivityEntry(
            date: now,
            kind: .moved,
            detail: "Moved \(destination.lastPathComponent) to \(directory.lastPathComponent)",
            url: destination,
            fileName: destination.lastPathComponent,
            destinationFolder: directory.lastPathComponent
        )
    }

    public func delete(
        _ candidate: CleanupCandidate,
        fileManager: FileManager = .default,
        now: Date = Date()
    ) throws -> ActivityEntry {
        let name = candidate.url.lastPathComponent
        try fileManager.removeItem(at: candidate.url)
        return ActivityEntry(
            date: now,
            kind: .deleted,
            detail: "Deleted \(name)",
            fileName: name
        )
    }

    public func removeEmptyManagedFolders(
        fileManager: FileManager = .default,
        now: Date = Date()
    ) -> [ActivityEntry] {
        DefaultTaxonomy.managedFolderNames.sorted().compactMap { name in
            let folder = watchFolder.appendingPathComponent(name, isDirectory: true)
            guard isEmptyManagedFolder(folder, fileManager: fileManager) else {
                return nil
            }
            try? fileManager.removeItem(at: folder)
            guard !fileManager.fileExists(atPath: folder.path) else {
                return nil
            }
            return ActivityEntry(
                date: now,
                kind: .folderRemoved,
                detail: "Removed empty folder \(name)",
                fileName: name,
                destinationFolder: name
            )
        }
    }

    private func isEmptyManagedFolder(_ folder: URL, fileManager: FileManager) -> Bool {
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: folder.path, isDirectory: &isDirectory),
              isDirectory.boolValue
        else {
            return false
        }
        let names = (try? fileManager.contentsOfDirectory(atPath: folder.path)) ?? []
        return names.allSatisfy { Self.ignorableEmptyFolderNames.contains($0) }
    }
}
