import Foundation

/// On-disk identity for collision checks. APFS resolves names case- and
/// normalization-insensitively, so a name string alone cannot tell "the file
/// itself" from "a different file holding that name".
public enum FileIdentity: Sendable {
    /// Case-insensitive key used when deciding whether a name is taken.
    public static func collisionKey(forFileName name: String) -> String {
        name.lowercased()
    }

    public static func isSameFile(_ lhs: URL, _ rhs: URL) -> Bool {
        guard let left = identifier(for: lhs), let right = identifier(for: rhs) else {
            return false
        }
        return left.isEqual(right)
    }

    /// The directory entry that actually is `url`. A stale or differently-cased
    /// URL (e.g. a repeated stable event after a case-only rename) still opens the
    /// same file on APFS; this returns the spelling that is on disk now.
    public static func onDiskURL(for url: URL, fileManager: FileManager = .default) -> URL {
        let standardized = url.standardizedFileURL
        let directory = standardized.deletingLastPathComponent()
        let name = standardized.lastPathComponent
        guard let names = try? fileManager.contentsOfDirectory(atPath: directory.path) else {
            return standardized
        }
        if names.contains(name) {
            return standardized
        }
        let key = collisionKey(forFileName: name)
        for candidate in names where collisionKey(forFileName: candidate) == key {
            let candidateURL = directory.appendingPathComponent(candidate, isDirectory: false)
            if isSameFile(candidateURL, standardized) {
                return candidateURL.standardizedFileURL
            }
        }
        return standardized
    }

    private static func identifier(for url: URL) -> NSObject? {
        // Fresh URL: resource values cached on a listing URL can be stale.
        let fresh = URL(fileURLWithPath: url.path)
        return (try? fresh.resourceValues(forKeys: [.fileResourceIdentifierKey]))?
            .fileResourceIdentifier as? NSObject
    }
}
