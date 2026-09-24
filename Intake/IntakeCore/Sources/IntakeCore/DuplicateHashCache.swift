import CryptoKit
import Foundation

/// Caches content hashes for Cleanup's duplicate detection, keyed by path,
/// size and modification date so an unchanged file is never re-hashed.
/// Reference-typed storage so one instance can be kept across scans (e.g. by
/// `AppModel`) while `CleanupScanner` itself stays a plain value type.
public final class DuplicateHashCache: @unchecked Sendable {
    private struct Key: Hashable {
        let path: String
        let size: Int64
        let modified: Date
    }

    private let lock = NSLock()
    private var entries: [Key: String] = [:]

    public init() {}

    /// Returns the SHA-256 hex digest of `url`'s contents, from cache when
    /// `size`/`modified` still match a prior read, otherwise reads the file.
    public func hash(
        for url: URL,
        size: Int64,
        modified: Date,
        fileManager: FileManager = .default
    ) -> String? {
        let key = Key(path: url.path, size: size, modified: modified)
        lock.lock()
        if let cached = entries[key] {
            lock.unlock()
            return cached
        }
        lock.unlock()

        guard let digest = Self.sha256(of: url, fileManager: fileManager) else {
            return nil
        }
        lock.lock()
        entries[key] = digest
        lock.unlock()
        return digest
    }

    private static func sha256(of url: URL, fileManager: FileManager) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else {
            return nil
        }
        defer { try? handle.close() }
        var hasher = SHA256()
        while true {
            let chunk = handle.readData(ofLength: 1 << 20)
            if chunk.isEmpty {
                break
            }
            hasher.update(data: chunk)
        }
        let digest = hasher.finalize()
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
