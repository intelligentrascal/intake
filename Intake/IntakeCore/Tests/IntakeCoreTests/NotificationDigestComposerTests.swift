import Foundation
import Testing
@testable import IntakeCore

struct NotificationDigestComposerTests {
    private func filed(
        name: String,
        folder: String,
        beforePath: String? = "/before/\(UUID().uuidString)",
        afterPath: String? = "/after/\(UUID().uuidString)"
    ) -> ActivityEntry {
        ActivityEntry(
            kind: .moved,
            detail: "Moved \(name) to \(folder)",
            fileName: name,
            destinationFolder: folder,
            beforePath: beforePath,
            afterPath: afterPath
        )
    }

    private func renamed(name: String) -> ActivityEntry {
        ActivityEntry(kind: .renamed, detail: "Renamed to \(name)", fileName: name)
    }

    private func error(_ detail: String) -> ActivityEntry {
        ActivityEntry(kind: .error, detail: detail, fileName: "x")
    }

    // MARK: Filed — single vs multiple

    @Test
    func singleFiledEntryOffersUndo() throws {
        let entry = filed(name: "Report.pdf", folder: "Documents")
        let digest = try #require(NotificationDigestComposer.filedDigest(entries: [entry]))
        #expect(digest.category == .filed)
        #expect(digest.title == "Filed 1 item")
        #expect(digest.body == "Report.pdf → Documents")
        #expect(digest.showsUndo == true)
        #expect(digest.undoActivityID == entry.id)
    }

    @Test
    func singleFiledEntryWithoutUndoablePathsHidesUndo() throws {
        let entry = filed(name: "Report.pdf", folder: "Documents", beforePath: nil, afterPath: nil)
        let digest = try #require(NotificationDigestComposer.filedDigest(entries: [entry]))
        #expect(digest.showsUndo == false)
    }

    @Test
    func multipleFiledEntriesCountByFolder() throws {
        let entries = [
            filed(name: "a.pdf", folder: "Documents"),
            filed(name: "b.pdf", folder: "Documents"),
            filed(name: "c.png", folder: "Images"),
        ]
        let digest = try #require(NotificationDigestComposer.filedDigest(entries: entries))
        #expect(digest.title == "Filed 3 items")
        #expect(digest.showsUndo == false)
        #expect(digest.undoActivityID == nil)
        #expect(digest.body.contains("Documents: 2"))
        #expect(digest.body.contains("Images: 1"))
    }

    @Test
    func twelveFilingsCountByFolder() throws {
        var entries: [ActivityEntry] = []
        for i in 0..<8 { entries.append(filed(name: "doc\(i).pdf", folder: "Documents")) }
        for i in 0..<4 { entries.append(filed(name: "img\(i).png", folder: "Images")) }
        let digest = try #require(NotificationDigestComposer.filedDigest(entries: entries))
        #expect(digest.title == "Filed 12 items")
        #expect(digest.body.contains("Documents: 8"))
        #expect(digest.body.contains("Images: 4"))
    }

    @Test
    func renameOnlyEntriesExcludedByDefault() {
        let entries = [renamed(name: "a.pdf"), renamed(name: "b.pdf")]
        #expect(NotificationDigestComposer.filedDigest(entries: entries) == nil)
    }

    @Test
    func renameOnlyEntriesIncludedWhenRequested() throws {
        let entries = [renamed(name: "a.pdf")]
        let digest = try #require(
            NotificationDigestComposer.filedDigest(entries: entries, includeRenameOnly: true)
        )
        #expect(digest.title == "Filed 1 item")
    }

    @Test
    func noFiledEntriesReturnsNil() {
        #expect(NotificationDigestComposer.filedDigest(entries: [error("boom")]) == nil)
    }

    // MARK: Errors — separate from filed, single vs multiple

    @Test
    func singleErrorDigest() throws {
        let digest = try #require(NotificationDigestComposer.errorDigest(entries: [error("Could not file a.pdf")]))
        #expect(digest.category == .errors)
        #expect(digest.title == "Intake error")
        #expect(digest.body == "Could not file a.pdf")
        #expect(digest.showsUndo == false)
    }

    @Test
    func multipleErrorsDigest() throws {
        let entries = [error("Could not file a.pdf"), error("Could not file b.pdf")]
        let digest = try #require(NotificationDigestComposer.errorDigest(entries: entries))
        #expect(digest.title == "2 errors")
        #expect(digest.body.contains("Could not file a.pdf"))
        #expect(digest.body.contains("Could not file b.pdf"))
    }

    @Test
    func errorsIgnoreNonErrorEntries() {
        #expect(NotificationDigestComposer.errorDigest(entries: [filed(name: "a", folder: "Documents")]) == nil)
    }

    @Test
    func mixedBatchComposesFiledAndErrorsSeparately() throws {
        let entries = [filed(name: "a.pdf", folder: "Documents"), error("Could not file b.pdf")]
        let filedDigest = try #require(NotificationDigestComposer.filedDigest(entries: entries))
        let errorsDigest = try #require(NotificationDigestComposer.errorDigest(entries: entries))
        #expect(filedDigest.category == .filed)
        #expect(errorsDigest.category == .errors)
    }

    // MARK: Cleanup

    @Test
    func cleanupDigestCountsByReason() throws {
        let candidates = [
            CleanupCandidate(url: URL(fileURLWithPath: "/a"), byteCount: 1, lastUsed: .distantPast, reason: .stale),
            CleanupCandidate(url: URL(fileURLWithPath: "/b"), byteCount: 1, lastUsed: .distantPast, reason: .stale),
            CleanupCandidate(
                url: URL(fileURLWithPath: "/c"),
                byteCount: 1,
                lastUsed: .distantPast,
                reason: .duplicate(of: URL(fileURLWithPath: "/orig"))
            ),
            CleanupCandidate(
                url: URL(fileURLWithPath: "/d"),
                byteCount: 1,
                lastUsed: .distantPast,
                reason: .abandonedDownload
            ),
            CleanupCandidate(
                url: URL(fileURLWithPath: "/e"),
                byteCount: 1,
                lastUsed: .distantPast,
                reason: .installed(appName: "Foo", appURL: URL(fileURLWithPath: "/Applications/Foo.app"))
            ),
        ]
        let digest = try #require(NotificationDigestComposer.cleanupDigest(candidates: candidates))
        #expect(digest.category == .cleanup)
        #expect(digest.title == "5 items ready for cleanup")
        #expect(digest.body.contains("Stale: 2"))
        #expect(digest.body.contains("Duplicate: 1"))
        #expect(digest.body.contains("Abandoned download: 1"))
        #expect(digest.body.contains("Installer: 1"))
        #expect(digest.showsUndo == false)
    }

    @Test
    func cleanupDigestSingularTitle() throws {
        let candidate = CleanupCandidate(url: URL(fileURLWithPath: "/a"), byteCount: 1, lastUsed: .distantPast)
        let digest = try #require(NotificationDigestComposer.cleanupDigest(candidates: [candidate]))
        #expect(digest.title == "1 item ready for cleanup")
    }

    @Test
    func emptyCleanupCandidatesReturnsNil() {
        #expect(NotificationDigestComposer.cleanupDigest(candidates: []) == nil)
    }
}
