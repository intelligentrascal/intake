import Foundation

/// Size gate so Intake never renames or files a still-writing download.
public enum DownloadWriteGate: Sendable {
    public static func allowsOrganizeOrRename(size: Int64) -> Bool {
        size > 0
    }

    public static func fileSize(at url: URL, fileManager: FileManager = .default) -> Int64 {
        if let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) {
            return Int64(size)
        }
        if let attrs = try? fileManager.attributesOfItem(atPath: url.path),
           let size = attrs[.size] as? NSNumber
        {
            return size.int64Value
        }
        return 0
    }

    public static func allowsOrganizeOrRename(
        at url: URL,
        fileManager: FileManager = .default
    ) -> Bool {
        allowsOrganizeOrRename(size: fileSize(at: url, fileManager: fileManager))
    }
}

/// Case-insensitive identity: stem without a trailing ` N` collision suffix + extension.
public enum DownloadIdentity: Sendable {
    public static func key(forFileName name: String) -> String {
        let url = URL(fileURLWithPath: name)
        let ext = url.pathExtension
        let stem = ext.isEmpty ? name : String(name.dropLast(ext.count + 1))
        let stripped = stripTrailingCollisionSuffix(stem)
        let rebuilt = ext.isEmpty ? stripped : "\(stripped).\(ext)"
        return rebuilt.lowercased()
    }

    public static func hasCollisionSuffix(fileName: String) -> Bool {
        key(forFileName: fileName) != fileName.lowercased()
    }

    private static func stripTrailingCollisionSuffix(_ stem: String) -> String {
        // Intake/Finder uniqued suffix is ` N` starting at 2, typically 2–99.
        // Keep years (` 2024`) and ` 1` in the stem.
        guard let range = stem.range(of: #"\s+([2-9]|[1-9]\d)$"#, options: .regularExpression) else {
            return stem
        }
        let stripped = String(stem[..<range.lowerBound])
        return stripped.isEmpty ? stem : stripped
    }
}

public struct DownloadFileSnapshot: Equatable, Sendable {
    public var url: URL
    public var size: Int64

    public init(url: URL, size: Int64) {
        self.url = url.standardizedFileURL
        self.size = size
    }
}

/// Prefer the full file when an empty placeholder shares download identity
/// (Finder/Intake ` 2` collision twins).
public enum EmptyFullSiblingDedupe: Sendable {
    public static func emptyURLsSharingIdentityWithFull(
        _ files: [DownloadFileSnapshot]
    ) -> [URL] {
        let grouped = Dictionary(
            grouping: files,
            by: { DownloadIdentity.key(forFileName: $0.url.lastPathComponent) }
        )
        var result: [URL] = []
        for group in grouped.values {
            guard group.contains(where: { $0.size > 0 }) else { continue }
            for file in group where file.size <= 0 {
                result.append(file.url)
            }
        }
        return result.sorted {
            $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending
        }
    }

    public static func snapshots(
        in directory: URL,
        fileManager: FileManager = .default
    ) -> [DownloadFileSnapshot] {
        let keys: [URLResourceKey] = [.isDirectoryKey, .fileSizeKey]
        let items = (try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: keys,
            options: []
        )) ?? []
        return items.compactMap { url in
            let standardized = url.standardizedFileURL
            let isDirectory = (try? standardized.resourceValues(forKeys: [.isDirectoryKey]).isDirectory)
                ?? standardized.hasDirectoryPath
            if isDirectory {
                return nil
            }
            return DownloadFileSnapshot(
                url: standardized,
                size: DownloadWriteGate.fileSize(at: standardized, fileManager: fileManager)
            )
        }
    }

    /// Deletes empty placeholders that share identity with a **collision-suffixed**
    /// full file (`Foo 2.dmg` dropping empty `Foo.dmg`). Never deletes because an
    /// unsuffixed full file exists — that would abort a new `Foo 2` download.
    @discardableResult
    public static func removeEmptySiblings(
        of url: URL,
        in directory: URL,
        fileManager: FileManager = .default
    ) -> [URL] {
        removeEmptySiblings(
            of: url,
            among: snapshots(in: directory, fileManager: fileManager),
            fileManager: fileManager
        )
    }

    @discardableResult
    public static func removeEmptySiblings(
        of url: URL,
        among files: [DownloadFileSnapshot],
        fileManager: FileManager = .default
    ) -> [URL] {
        let source = url.standardizedFileURL
        guard DownloadWriteGate.fileSize(at: source, fileManager: fileManager) > 0 else {
            return []
        }
        // Only the collision-suffixed full copy (`Foo 2.dmg`) may drop an empty
        // original. Filing `Foo.dmg` must not delete a newly created `Foo 2.dmg`.
        guard DownloadIdentity.hasCollisionSuffix(fileName: source.lastPathComponent) else {
            return []
        }
        let key = DownloadIdentity.key(forFileName: source.lastPathComponent)
        var removed: [URL] = []
        for file in files {
            let candidate = file.url.standardizedFileURL
            if candidate == source { continue }
            guard DownloadIdentity.key(forFileName: candidate.lastPathComponent) == key else {
                continue
            }
            guard fileManager.fileExists(atPath: candidate.path) else { continue }
            guard DownloadWriteGate.fileSize(at: candidate, fileManager: fileManager) <= 0 else {
                continue
            }
            do {
                try fileManager.removeItem(at: candidate)
                removed.append(candidate)
            } catch {
                continue
            }
        }
        return removed.sorted {
            $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending
        }
    }
}
