import Foundation

/// Pure digest composer for IN-10 Notification digest. Turns a batch of
/// `ActivityEntry` rows (filed vs errors) or new `CleanupCandidate` items into
/// a title, body, and action set. Follows `FeedbackIssueComposer`'s pattern:
/// no `UserNotifications` import, no side effects, fully unit-testable.
public enum NotificationDigestComposer {
    /// Kinds that count as "filed" for the digest — an item actually landed in
    /// a destination folder. A local rename with no move is left out unless
    /// `includeRenameOnly` is set (rename-only entries are excluded by default,
    /// per settings).
    public static func filedDigest(
        entries: [ActivityEntry],
        includeRenameOnly: Bool = false
    ) -> NotificationDigest? {
        let relevant = entries.filter {
            $0.kind == .moved || (includeRenameOnly && $0.kind == .renamed)
        }
        guard !relevant.isEmpty else { return nil }

        if relevant.count == 1, let entry = relevant.first {
            let folder = entry.destinationFolder
            let body = folder.map { "\(entry.fileName) → \($0)" } ?? entry.fileName
            return NotificationDigest(
                category: .filed,
                title: "Filed 1 item",
                body: body,
                showsUndo: UndoService.makeAction(from: entry) != nil,
                undoActivityID: entry.id
            )
        }

        let counts = countsByFolder(relevant)
        let body = counts
            .map { "\($0.folder): \($0.count)" }
            .joined(separator: " · ")
        return NotificationDigest(
            category: .filed,
            title: "Filed \(relevant.count) items",
            body: body,
            showsUndo: false,
            undoActivityID: nil
        )
    }

    /// Destination-folder counts for a batch, sorted by count desc then name —
    /// exposed for tests and any future summary UI.
    public static func countsByFolder(
        _ entries: [ActivityEntry]
    ) -> [(folder: String, count: Int)] {
        var totals: [String: Int] = [:]
        for entry in entries {
            let folder = entry.destinationFolder ?? "Other"
            totals[folder, default: 0] += 1
        }
        return totals
            .map { (folder: $0.key, count: $0.value) }
            .sorted { lhs, rhs in
                lhs.count != rhs.count ? lhs.count > rhs.count : lhs.folder < rhs.folder
            }
    }

    /// Errors are always composed on their own — never merged with filed items.
    public static func errorDigest(entries: [ActivityEntry]) -> NotificationDigest? {
        let errors = entries.filter { $0.kind == .error }
        guard !errors.isEmpty else { return nil }

        if errors.count == 1, let entry = errors.first {
            return NotificationDigest(
                category: .errors,
                title: "Intake error",
                body: entry.detail,
                showsUndo: false,
                undoActivityID: nil
            )
        }

        let body = errors.map(\.detail).joined(separator: " · ")
        return NotificationDigest(
            category: .errors,
            title: "\(errors.count) errors",
            body: body,
            showsUndo: false,
            undoActivityID: nil
        )
    }

    /// New Cleanup items found by a scan, summarized once — callers pass only
    /// the candidates not previously notified.
    public static func cleanupDigest(candidates: [CleanupCandidate]) -> NotificationDigest? {
        guard !candidates.isEmpty else { return nil }

        var totals: [String: Int] = [:]
        for candidate in candidates {
            totals[candidate.reason.label, default: 0] += 1
        }
        let body = totals
            .sorted { lhs, rhs in
                lhs.value != rhs.value ? lhs.value > rhs.value : lhs.key < rhs.key
            }
            .map { "\($0.key): \($0.value)" }
            .joined(separator: " · ")

        let noun = candidates.count == 1 ? "item" : "items"
        return NotificationDigest(
            category: .cleanup,
            title: "\(candidates.count) \(noun) ready for cleanup",
            body: body,
            showsUndo: false,
            undoActivityID: nil
        )
    }
}
