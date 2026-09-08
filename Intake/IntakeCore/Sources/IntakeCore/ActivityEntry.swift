import Foundation

public struct ActivityEntry: Identifiable, Equatable, Sendable {
    public enum Kind: String, Sendable, Equatable {
        case renamed
        case moved
        case skipped
        case error
    }

    public var id: UUID
    public var date: Date
    public var kind: Kind
    public var detail: String
    public var url: URL?

    public var menuTitle: String { detail }

    public init(
        id: UUID = UUID(),
        date: Date = Date(),
        kind: Kind,
        detail: String,
        url: URL? = nil
    ) {
        self.id = id
        self.date = date
        self.kind = kind
        self.detail = detail
        self.url = url
    }
}
