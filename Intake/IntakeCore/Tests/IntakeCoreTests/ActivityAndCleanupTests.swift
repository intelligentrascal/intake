import Foundation
import Testing
@testable import IntakeCore

struct ActivityLogTests {
    @Test
    func menuTitleUsesFilenameAndVerb() {
        let entry = ActivityEntry(
            kind: .moved,
            detail: "Moved Notes.md to Documents",
            url: URL(fileURLWithPath: "/tmp/Downloads/Documents/Notes.md"),
            fileName: "Notes.md",
            destinationFolder: "Documents"
        )
        #expect(entry.menuTitle == "Notes.md · Moved")
        #expect(entry.verb == "Moved")
        #expect(entry.systemImage == "checkmark.circle")
    }

    @Test
    func insertingCapsNewestFirst() {
        let seed = (0..<ActivityLog.maximumEntries).map { index in
            ActivityEntry(kind: .skipped, detail: "old \(index)", fileName: "old-\(index).txt")
        }
        let newest = ActivityEntry(kind: .moved, detail: "new", fileName: "New.pdf")
        let result = ActivityLog.inserting(newest, into: seed)
        #expect(result.count == ActivityLog.maximumEntries)
        #expect(result.first?.fileName == "New.pdf")
        #expect(result.last?.fileName == "old-\(ActivityLog.maximumEntries - 2).txt")
    }

    @Test
    func roundTripsThroughJSON() throws {
        let original = [
            ActivityEntry(
                kind: .renamed,
                detail: "Renamed a to b",
                url: URL(fileURLWithPath: "/tmp/b.pdf"),
                fileName: "b.pdf"
            ),
            ActivityEntry(
                kind: .error,
                detail: "Could not file mystery.bin",
                fileName: "mystery.bin"
            ),
        ]
        let data = try ActivityLog.encode(original)
        let decoded = try ActivityLog.decode(data)
        #expect(decoded.map(\.fileName) == ["b.pdf", "mystery.bin"])
        #expect(decoded.map(\.kind) == [.renamed, .error])
        #expect(decoded[0].url?.path == "/tmp/b.pdf")
    }
}

struct RulePersistenceTests {
    @Test
    func reappliesSavedEnabledFlagsOntoDefaultRules() {
        let saved = ["documents": false, "images": true]
        let rules = RulePersistence.applying(saved, to: DefaultTaxonomy.rules)
        let documents = rules.first { $0.category == .documents }
        let images = rules.first { $0.category == .images }
        #expect(documents?.isEnabled == false)
        #expect(images?.isEnabled == true)
        #expect(rules.first { $0.category == .video }?.isEnabled == true)
    }

    @Test
    func exportsEnabledFlagsByCategory() {
        var rules = DefaultTaxonomy.rules
        rules[0].isEnabled = false
        let flags = RulePersistence.enabledByCategory(from: rules)
        #expect(flags[rules[0].category.rawValue] == false)
        #expect(flags.count == rules.count)
    }
}

struct CleanupScannerTests {
    @Test
    func findsUntouchedFilesPastTheThreshold() throws {
        let fileManager = FileManager.default
        let root = try makeTempWatchFolder()
        defer { try? fileManager.removeItem(at: root) }

        let documents = root.appendingPathComponent("Documents", isDirectory: true)
        try fileManager.createDirectory(at: documents, withIntermediateDirectories: true)
        let stale = documents.appendingPathComponent("Old.pdf")
        let fresh = documents.appendingPathComponent("Fresh.pdf")
        try Data("stale".utf8).write(to: stale)
        try Data("fresh".utf8).write(to: fresh)

        let now = Date()
        try fileManager.setAttributes(
            [.modificationDate: now.addingTimeInterval(-40 * 24 * 3600)],
            ofItemAtPath: stale.path
        )
        try fileManager.setAttributes(
            [.modificationDate: now.addingTimeInterval(-2 * 24 * 3600)],
            ofItemAtPath: fresh.path
        )

        let scanner = CleanupScanner(
            watchFolder: root,
            thresholdDays: 30,
            includeWatchRoot: false
        )
        let found = scanner.candidates(now: now, fileManager: fileManager)
        #expect(found.map(\.url.lastPathComponent) == ["Old.pdf"])
    }

    @Test
    func includeWatchRootAddsLooseFilesAndSnoozeSkipsThem() throws {
        let fileManager = FileManager.default
        let root = try makeTempWatchFolder()
        defer { try? fileManager.removeItem(at: root) }

        let loose = root.appendingPathComponent("Loose.zip")
        try Data("zip".utf8).write(to: loose)
        let now = Date()
        try fileManager.setAttributes(
            [.modificationDate: now.addingTimeInterval(-90 * 24 * 3600)],
            ofItemAtPath: loose.path
        )

        let included = CleanupScanner(
            watchFolder: root,
            thresholdDays: 30,
            includeWatchRoot: true
        ).candidates(now: now, fileManager: fileManager)
        #expect(included.map(\.url.lastPathComponent) == ["Loose.zip"])

        let snoozed = CleanupScanner(
            watchFolder: root,
            thresholdDays: 30,
            includeWatchRoot: true,
            snoozedUntil: [loose.path: now.addingTimeInterval(30 * 24 * 3600)]
        ).candidates(now: now, fileManager: fileManager)
        #expect(snoozed.isEmpty)
    }

    @Test
    func activeIncompleteDownloadsAreNeverFlagged() throws {
        let fileManager = FileManager.default
        let root = try makeTempWatchFolder()
        defer { try? fileManager.removeItem(at: root) }
        let partial = root.appendingPathComponent("movie.mp4.crdownload")
        try Data("partial".utf8).write(to: partial)
        let now = Date()
        // Still receiving bytes a minute ago — nowhere near the 24h abandoned
        // threshold, and never counted as stale either.
        try fileManager.setAttributes(
            [.modificationDate: now.addingTimeInterval(-60)],
            ofItemAtPath: partial.path
        )
        let found = CleanupScanner(
            watchFolder: root,
            thresholdDays: 30,
            includeWatchRoot: true
        ).candidates(now: now, fileManager: fileManager)
        #expect(found.isEmpty)
    }

    @Test
    func abandonedDownloadUnchangedFor24HoursIsFlagged() throws {
        let fileManager = FileManager.default
        let root = try makeTempWatchFolder()
        defer { try? fileManager.removeItem(at: root) }
        let partial = root.appendingPathComponent("movie.mp4.crdownload")
        try Data("partial".utf8).write(to: partial)
        let now = Date()
        try fileManager.setAttributes(
            [.modificationDate: now.addingTimeInterval(-25 * 3600)],
            ofItemAtPath: partial.path
        )
        let found = CleanupScanner(
            watchFolder: root,
            thresholdDays: 30,
            includeWatchRoot: true
        ).candidates(now: now, fileManager: fileManager)
        #expect(found.map(\.url.lastPathComponent) == ["movie.mp4.crdownload"])
        #expect(found.first?.reason == .abandonedDownload)
    }

    @Test
    func abandonedDownloadBypassesTheStaleThreshold() throws {
        let fileManager = FileManager.default
        let root = try makeTempWatchFolder()
        defer { try? fileManager.removeItem(at: root) }
        let partial = root.appendingPathComponent("movie.mp4.part")
        try Data("partial".utf8).write(to: partial)
        let now = Date()
        try fileManager.setAttributes(
            [.modificationDate: now.addingTimeInterval(-25 * 3600)],
            ofItemAtPath: partial.path
        )
        // A threshold measured in months — the abandoned download still
        // shows up because non-stale reasons skip the stale-days threshold.
        let found = CleanupScanner(
            watchFolder: root,
            thresholdDays: 365,
            includeWatchRoot: true
        ).candidates(now: now, fileManager: fileManager)
        #expect(found.map(\.reason) == [.abandonedDownload])
    }

    @Test
    func duplicateContentIsFlaggedWithTheOldestAsOriginal() throws {
        let fileManager = FileManager.default
        let root = try makeTempWatchFolder()
        defer { try? fileManager.removeItem(at: root) }

        let documents = root.appendingPathComponent("Documents", isDirectory: true)
        try fileManager.createDirectory(at: documents, withIntermediateDirectories: true)
        let original = documents.appendingPathComponent("Report.pdf")
        let copy = documents.appendingPathComponent("Report (1).pdf")
        try Data("same bytes".utf8).write(to: original)
        try Data("same bytes".utf8).write(to: copy)

        let now = Date()
        try fileManager.setAttributes(
            [.creationDate: now.addingTimeInterval(-10 * 24 * 3600)],
            ofItemAtPath: original.path
        )
        try fileManager.setAttributes(
            [.creationDate: now.addingTimeInterval(-1 * 24 * 3600)],
            ofItemAtPath: copy.path
        )

        let found = CleanupScanner(
            watchFolder: root,
            thresholdDays: 365,
            includeWatchRoot: false
        ).candidates(now: now, fileManager: fileManager)

        #expect(found.map(\.url.lastPathComponent) == ["Report (1).pdf"])
        #expect(found.first?.reason.duplicateOf?.lastPathComponent == original.lastPathComponent)
    }

    @Test
    func sameSizeDifferentContentIsNotFlaggedAsDuplicate() throws {
        let fileManager = FileManager.default
        let root = try makeTempWatchFolder()
        defer { try? fileManager.removeItem(at: root) }

        let documents = root.appendingPathComponent("Documents", isDirectory: true)
        try fileManager.createDirectory(at: documents, withIntermediateDirectories: true)
        let first = documents.appendingPathComponent("A.bin")
        let second = documents.appendingPathComponent("B.bin")
        try Data("aaaaa".utf8).write(to: first)
        try Data("bbbbb".utf8).write(to: second)

        let found = CleanupScanner(
            watchFolder: root,
            thresholdDays: 365,
            includeWatchRoot: false
        ).candidates(now: Date(), fileManager: fileManager)

        #expect(found.isEmpty)
    }

    @Test
    func duplicateBypassesTheStaleThresholdAndSnoozeStillApplies() throws {
        let fileManager = FileManager.default
        let root = try makeTempWatchFolder()
        defer { try? fileManager.removeItem(at: root) }

        let documents = root.appendingPathComponent("Documents", isDirectory: true)
        try fileManager.createDirectory(at: documents, withIntermediateDirectories: true)
        let original = documents.appendingPathComponent("Report.pdf")
        let copy = documents.appendingPathComponent("Report (1).pdf")
        try Data("same bytes".utf8).write(to: original)
        try Data("same bytes".utf8).write(to: copy)

        let now = Date()
        try fileManager.setAttributes(
            [.creationDate: now.addingTimeInterval(-10 * 24 * 3600)],
            ofItemAtPath: original.path
        )
        try fileManager.setAttributes(
            [.creationDate: now.addingTimeInterval(-1 * 24 * 3600)],
            ofItemAtPath: copy.path
        )

        // Both files are brand new — well under a 365 day stale threshold —
        // yet the duplicate still surfaces.
        let found = CleanupScanner(
            watchFolder: root,
            thresholdDays: 365,
            includeWatchRoot: false
        ).candidates(now: now, fileManager: fileManager)
        #expect(found.map(\.url.lastPathComponent) == ["Report (1).pdf"])

        let snoozed = CleanupScanner(
            watchFolder: root,
            thresholdDays: 365,
            includeWatchRoot: false,
            snoozedUntil: [CleanupScanner.snoozeKey(for: copy): now.addingTimeInterval(30 * 24 * 3600)]
        ).candidates(now: now, fileManager: fileManager)
        #expect(snoozed.isEmpty)
    }

    private func makeTempWatchFolder() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "intake-cleanup-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }
}

struct CleanupProcessorTests {
    @Test
    func fileAwayMovesAndDeleteRemovesThenPrunesEmptyManagedFolders() throws {
        let fileManager = FileManager.default
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "intake-process-\(UUID().uuidString)",
            isDirectory: true
        )
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: root) }

        let documents = root.appendingPathComponent("Documents", isDirectory: true)
        try fileManager.createDirectory(at: documents, withIntermediateDirectories: true)
        let stale = documents.appendingPathComponent("Old.pdf")
        try Data("pdf".utf8).write(to: stale)
        try Data().write(to: documents.appendingPathComponent(".DS_Store"))

        let processor = CleanupProcessor(watchFolder: root)
        let filed = try processor.fileAway(
            CleanupCandidate(url: stale, byteCount: 3, lastUsed: Date.distantPast),
            to: root.appendingPathComponent("Archive", isDirectory: true),
            fileManager: fileManager
        )
        #expect(filed.kind == .moved)
        #expect(fileManager.fileExists(atPath: stale.path) == false)
        #expect(filed.fileName == "Old.pdf")

        let leftover = documents.appendingPathComponent("Trashme.txt")
        try Data("x".utf8).write(to: leftover)
        let deleted = try processor.delete(
            CleanupCandidate(url: leftover, byteCount: 1, lastUsed: Date.distantPast),
            fileManager: fileManager
        )
        #expect(deleted.kind == .deleted)
        #expect(fileManager.fileExists(atPath: leftover.path) == false)

        let pruned = processor.removeEmptyManagedFolders(fileManager: fileManager)
        #expect(pruned.map(\.fileName) == ["Documents"])
        #expect(fileManager.fileExists(atPath: documents.path) == false)
        #expect(pruned.first?.kind == .folderRemoved)
    }
}
