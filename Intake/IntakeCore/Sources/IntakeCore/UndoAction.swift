import Foundation

/// One Intake-authored rename or move that can be reversed.
public struct UndoAction: Identifiable, Equatable, Sendable, Codable {
    public enum Kind: String, Sendable, Equatable, Codable {
        case rename
        case move
    }

    public var id: UUID
    public var activityID: UUID
    public var kind: Kind
    public var beforePath: String
    public var afterPath: String
    public var createdAt: Date
    /// Display name after the action (for toast).
    public var displayName: String
    /// Destination folder name when kind == .move (for toast).
    public var destinationFolder: String?

    public init(
        id: UUID = UUID(),
        activityID: UUID,
        kind: Kind,
        beforePath: String,
        afterPath: String,
        createdAt: Date = Date(),
        displayName: String,
        destinationFolder: String? = nil
    ) {
        self.id = id
        self.activityID = activityID
        self.kind = kind
        self.beforePath = beforePath
        self.afterPath = afterPath
        self.createdAt = createdAt
        self.displayName = displayName
        self.destinationFolder = destinationFolder
    }

    public var beforeURL: URL { URL(fileURLWithPath: beforePath) }
    public var afterURL: URL { URL(fileURLWithPath: afterPath) }
}

public enum UndoEligibility: Equatable, Sendable {
    case eligible
    case tooOld
    case missingFile
    case collision
    case notUndoable

    public var reason: String? {
        switch self {
        case .eligible: nil
        case .tooOld: UndoCopy.tooOld
        case .missingFile: UndoCopy.missingFile
        case .collision: UndoCopy.collision
        case .notUndoable: UndoCopy.notUndoable
        }
    }
}

public enum UndoCopy {
    public static let undo = "Undo"
    public static let tooOld = "Too old to undo"
    public static let missingFile = "Can’t undo — file not found."
    public static let collision = "Can’t undo — something else is using that name."
    public static let notUndoable = "Can’t undo this action."

    public static func toastRenamed(name: String) -> String {
        "Renamed to \(name)"
    }

    public static func toastMoved(folder: String) -> String {
        "Moved to \(folder)"
    }

    public static func toastFiled(name: String, folder: String) -> String {
        "Filed as \(name) in \(folder)"
    }
}

public enum UndoPerformResult: Equatable, Sendable {
    case success(restoredURL: URL)
    case failure(UndoEligibility)
}
