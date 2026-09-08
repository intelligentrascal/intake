import Foundation

public struct ActivityEntry: Identifiable, Equatable, Sendable, Codable {
    public enum Kind: String, Sendable, Equatable, Codable {
        case renamed
        case moved
        case skipped
        case error
        case deleted
        case folderRemoved
    }

    public var id: UUID
    public var date: Date
    public var kind: Kind
    public var detail: String
    public var url: URL?
    public var fileName: String
    public var destinationFolder: String?

    public var verb: String {
        switch kind {
        case .renamed: "Renamed"
        case .moved: "Moved"
        case .skipped: "Skipped"
        case .error: "Error"
        case .deleted: "Deleted"
        case .folderRemoved: "Removed"
        }
    }

    public var menuTitle: String {
        "\(fileName) · \(verb)"
    }

    public var systemImage: String {
        switch kind {
        case .moved: "checkmark.circle"
        case .renamed: "pencil"
        case .skipped: "forward"
        case .error: "exclamationmark.triangle"
        case .deleted: "trash"
        case .folderRemoved: "folder"
        }
    }

    public init(
        id: UUID = UUID(),
        date: Date = Date(),
        kind: Kind,
        detail: String,
        url: URL? = nil,
        fileName: String? = nil,
        destinationFolder: String? = nil
    ) {
        self.id = id
        self.date = date
        self.kind = kind
        self.detail = detail
        self.url = url
        self.fileName = fileName ?? url?.lastPathComponent ?? detail
        self.destinationFolder = destinationFolder
    }
}
