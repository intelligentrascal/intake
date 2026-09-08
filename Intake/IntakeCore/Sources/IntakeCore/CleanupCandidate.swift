import Foundation

public struct CleanupCandidate: Identifiable, Equatable, Sendable {
    public var url: URL
    public var byteCount: Int64
    public var lastUsed: Date

    public var id: URL { url }

    public init(url: URL, byteCount: Int64, lastUsed: Date) {
        self.url = url
        self.byteCount = byteCount
        self.lastUsed = lastUsed
    }
}
