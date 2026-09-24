import Foundation

public struct CleanupProcessor: Sendable {
    public static let ignorableEmptyFolderNames: Set<String> = [
        ".DS_Store",
        ".localized",
        "Icon\r",
    ]

    public var watchFolder: URL
    public var managedFolderNames: Set<String>

    public init(
        watchFolder: URL,
        managedFolderNames: Set<String> = DefaultTaxonomy.managedFolderNames
    ) {
        self.watchFolder = watchFolder
        self.managedFolderNames = managedFolderNames
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
        var entries: [ActivityEntry] = []

        // First, remove empty date subfolders within managed folders
        for managedName in managedFolderNames.sorted() {
            let managedFolder = watchFolder.appendingPathComponent(managedName, isDirectory: true)
            entries.append(
                contentsOf: removeEmptyDateSubfolders(
                    in: managedFolder,
                    fileManager: fileManager,
                    now: now
                )
            )
        }

        // Then remove the managed folders themselves if they're empty
        for name in managedFolderNames.sorted() {
            let folder = watchFolder.appendingPathComponent(name, isDirectory: true)
            guard isEmptyManagedFolder(folder, fileManager: fileManager) else {
                continue
            }
            try? fileManager.removeItem(at: folder)
            guard !fileManager.fileExists(atPath: folder.path) else {
                continue
            }
            entries.append(
                ActivityEntry(
                    date: now,
                    kind: .folderRemoved,
                    detail: "Removed empty folder \(name)",
                    fileName: name,
                    destinationFolder: name
                )
            )
        }

        return entries
    }

    /// Recursively removes empty date subfolders (YYYY or YYYY-MM) within a managed folder.
    private func removeEmptyDateSubfolders(
        in folder: URL,
        fileManager: FileManager,
        now: Date
    ) -> [ActivityEntry] {
        var entries: [ActivityEntry] = []

        guard fileManager.fileExists(atPath: folder.path) else { return [] }

        let contents = (try? fileManager.contentsOfDirectory(atPath: folder.path)) ?? []
        for item in contents {
            guard !Self.ignorableEmptyFolderNames.contains(item) else { continue }

            let subfolder = folder.appendingPathComponent(item, isDirectory: true)
            var isDir: ObjCBool = false
            guard fileManager.fileExists(atPath: subfolder.path, isDirectory: &isDir),
                  isDir.boolValue
            else {
                continue
            }

            // Recursively check subfolders
            entries.append(
                contentsOf: removeEmptyDateSubfolders(
                    in: subfolder,
                    fileManager: fileManager,
                    now: now
                )
            )

            // After recursion, check if this folder is now empty
            if isEmptyFolder(subfolder, fileManager: fileManager) {
                try? fileManager.removeItem(at: subfolder)
                if !fileManager.fileExists(atPath: subfolder.path) {
                    entries.append(
                        ActivityEntry(
                            date: now,
                            kind: .folderRemoved,
                            detail: "Removed empty folder \(item)",
                            fileName: item,
                            destinationFolder: item
                        )
                    )
                }
            }
        }

        return entries
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

    private func isEmptyFolder(_ folder: URL, fileManager: FileManager) -> Bool {
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
