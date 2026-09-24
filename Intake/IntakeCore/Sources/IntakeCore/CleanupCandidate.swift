import Foundation

public struct CleanupCandidate: Identifiable, Equatable, Sendable {
    /// Why a file showed up in the Cleanup queue. Non-stale reasons skip the
    /// stale-days threshold entirely — being a duplicate or an abandoned
    /// download is reason enough on its own.
    public enum Reason: Equatable, Sendable {
        /// Not opened or modified for the configured threshold.
        case stale
        /// Same size and content hash as `of`, which is kept as the original.
        case duplicate(of: URL)
        /// An incomplete-download extension whose size and modification date
        /// haven't changed for 24 hours.
        case abandonedDownload
        /// A mounted/extracted installer whose app already exists elsewhere.
        /// Detection lands in a follow-up ticket; this defines the case shape.
        case installed(appName: String, appURL: URL)
    }

    public var url: URL
    public var byteCount: Int64
    public var lastUsed: Date
    public var reason: Reason

    public var id: URL { url }

    public init(url: URL, byteCount: Int64, lastUsed: Date, reason: Reason = .stale) {
        self.url = url
        self.byteCount = byteCount
        self.lastUsed = lastUsed
        self.reason = reason
    }
}

extension CleanupCandidate.Reason {
    /// Short label for the Cleanup queue's Reason column.
    public var label: String {
        switch self {
        case .stale:
            return "Stale"
        case .duplicate:
            return "Duplicate"
        case .abandonedDownload:
            return "Abandoned download"
        case .installed:
            return "Installer"
        }
    }

    /// The file this candidate duplicates, when applicable.
    public var duplicateOf: URL? {
        if case .duplicate(let original) = self {
            return original
        }
        return nil
    }
}
