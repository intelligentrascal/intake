import Foundation

/// One notification worth of content, plus which actions it should offer.
/// Built by `NotificationDigestComposer` — pure, no `UserNotifications` import
/// so it stays testable without a running notification center.
public struct NotificationDigest: Equatable, Sendable {
    public enum Category: String, Sendable, Equatable {
        case filed
        case errors
        case cleanup
    }

    public var category: Category
    public var title: String
    public var body: String
    /// Show Activity is always offered by the app; this only controls Undo.
    public var showsUndo: Bool
    /// Set only when the digest covers exactly one undoable entry.
    public var undoActivityID: UUID?

    public init(
        category: Category,
        title: String,
        body: String,
        showsUndo: Bool = false,
        undoActivityID: UUID? = nil
    ) {
        self.category = category
        self.title = title
        self.body = body
        self.showsUndo = showsUndo
        self.undoActivityID = undoActivityID
    }
}
