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

    /// Which namer produced a `renamed` row.
    public enum RenameSource: String, Sendable, Equatable, Codable {
        /// The local, deterministic `FileNameNormalizer` (Title Case).
        case titleCase
        /// The on-device content-aware namer (template + validator).
        case contentAware
    }

    public var id: UUID
    public var date: Date
    public var kind: Kind
    public var detail: String
    public var url: URL?
    public var fileName: String
    public var destinationFolder: String?
    /// Absolute path before Intake’s change (undo). Optional for older Activity rows.
    public var beforePath: String?
    /// Absolute path after Intake’s change (undo).
    public var afterPath: String?
    /// The file's source domain, when where-from metadata named one. Optional
    /// for older Activity rows and for files with no known source.
    public var sourceDomain: String?
    /// The watch folder profile this change came from. Optional: rows written
    /// before multiple watch folders have none and count as profile #1.
    public var watchFolderID: String?
    /// For `renamed` rows: who picked the name. Optional — older rows have none.
    public var renameSource: RenameSource?

    /// `watchFolderID`, with older rows defaulting to profile #1.
    public var effectiveWatchFolderID: String {
        watchFolderID ?? WatchFolderProfile.primaryID
    }

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
        destinationFolder: String? = nil,
        beforePath: String? = nil,
        afterPath: String? = nil,
        sourceDomain: String? = nil,
        watchFolderID: String? = nil,
        renameSource: RenameSource? = nil
    ) {
        self.id = id
        self.date = date
        self.kind = kind
        self.detail = detail
        self.url = url
        self.fileName = fileName ?? url?.lastPathComponent ?? detail
        self.destinationFolder = destinationFolder
        self.beforePath = beforePath
        self.afterPath = afterPath
        self.sourceDomain = sourceDomain
        self.watchFolderID = watchFolderID
        self.renameSource = renameSource
    }
}
