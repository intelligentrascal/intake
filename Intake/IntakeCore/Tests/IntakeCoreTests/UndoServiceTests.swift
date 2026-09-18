import Foundation
import XCTest
@testable import IntakeCore

final class UndoServiceTests: XCTestCase {
    private var tempRoot: URL!
    private var fm: FileManager!

    override func setUp() {
        super.setUp()
        fm = .default
        tempRoot = fm.temporaryDirectory.appendingPathComponent("intake-undo-\(UUID().uuidString)", isDirectory: true)
        try! fm.createDirectory(at: tempRoot, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? fm.removeItem(at: tempRoot)
        super.tearDown()
    }

    func testCapAt20LIFO() {
        var service = UndoService()
        for i in 0..<25 {
            service.push(sampleAction(id: i))
        }
        XCTAssertEqual(service.actions.count, 20)
        XCTAssertEqual(service.last?.displayName, "file-24.txt")
        XCTAssertNil(service.actions.first { $0.displayName == "file-0.txt" })
    }

    func testEligibilityMissingAndCollision() throws {
        let before = tempRoot.appendingPathComponent("old.txt")
        let after = tempRoot.appendingPathComponent("new.txt")
        try "hi".write(to: after, atomically: true, encoding: .utf8)
        var service = UndoService()
        let action = UndoAction(
            activityID: UUID(),
            kind: .rename,
            beforePath: before.path,
            afterPath: after.path,
            displayName: "new.txt"
        )
        service.push(action)
        XCTAssertEqual(service.eligibility(for: action, fileManager: fm), .eligible)

        try "other".write(to: before, atomically: true, encoding: .utf8)
        XCTAssertEqual(service.eligibility(for: action, fileManager: fm), .collision)

        try fm.removeItem(at: after)
        XCTAssertEqual(service.eligibility(for: action, fileManager: fm), .missingFile)
    }

    func testPerformRenameRestore() throws {
        let before = tempRoot.appendingPathComponent("old-invoice.pdf")
        let after = tempRoot.appendingPathComponent("New Invoice.pdf")
        try "pdf".write(to: after, atomically: true, encoding: .utf8)
        var service = UndoService()
        let action = UndoAction(
            activityID: UUID(),
            kind: .rename,
            beforePath: before.path,
            afterPath: after.path,
            displayName: "New Invoice.pdf"
        )
        service.push(action)
        let result = service.perform(action, fileManager: fm)
        guard case .success(let url) = result else {
            return XCTFail("expected success \(result)")
        }
        XCTAssertEqual(url.standardizedFileURL, before.standardizedFileURL)
        XCTAssertTrue(fm.fileExists(atPath: before.path))
        XCTAssertFalse(fm.fileExists(atPath: after.path))
        XCTAssertNil(service.last)
    }

    func testPerformMoveRestore() throws {
        let docs = tempRoot.appendingPathComponent("Documents", isDirectory: true)
        try fm.createDirectory(at: docs, withIntermediateDirectories: true)
        let before = tempRoot.appendingPathComponent("note.txt")
        let after = docs.appendingPathComponent("note.txt")
        try "x".write(to: after, atomically: true, encoding: .utf8)
        var service = UndoService()
        let action = UndoAction(
            activityID: UUID(),
            kind: .move,
            beforePath: before.path,
            afterPath: after.path,
            displayName: "note.txt",
            destinationFolder: "Documents"
        )
        service.push(action)
        let result = service.perform(action, fileManager: fm)
        guard case .success = result else {
            return XCTFail("expected success \(result)")
        }
        XCTAssertTrue(fm.fileExists(atPath: before.path))
        XCTAssertFalse(fm.fileExists(atPath: after.path))
    }

    func testTooOldWhenPathsButNotOnStack() {
        let entry = ActivityEntry(
            kind: .renamed,
            detail: "Renamed a to b",
            fileName: "b.txt",
            beforePath: "/tmp/a.txt",
            afterPath: "/tmp/b.txt"
        )
        let service = UndoService()
        XCTAssertEqual(service.eligibility(for: entry), .tooOld)
    }

    func testDeletedNotUndoable() {
        let entry = ActivityEntry(kind: .deleted, detail: "Deleted x", fileName: "x")
        XCTAssertEqual(UndoService().eligibility(for: entry), .notUndoable)
    }

    func testPersistenceRoundTrip() {
        let suite = "intake.undo.test.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        var service = UndoService()
        let action = sampleAction(id: 1)
        service.push(action)
        service.save(to: defaults)
        let loaded = UndoService.load(from: defaults)
        XCTAssertEqual(loaded.actions.count, 1)
        XCTAssertEqual(loaded.last?.displayName, action.displayName)
        XCTAssertEqual(loaded.last?.beforePath, action.beforePath)
    }

    func testToastCopy() {
        XCTAssertEqual(UndoCopy.toastRenamed(name: "A.pdf"), "Renamed to A.pdf")
        XCTAssertEqual(UndoCopy.toastMoved(folder: "Documents"), "Moved to Documents")
        XCTAssertEqual(UndoCopy.toastFiled(name: "A.pdf", folder: "Documents"), "Filed as A.pdf in Documents")
        XCTAssertEqual(UndoCopy.undo, "Undo")
        XCTAssertEqual(UndoCopy.tooOld, "Too old to undo")
    }

    func testPipelineWritesUndoPaths() throws {
        let watch = tempRoot.appendingPathComponent("Downloads", isDirectory: true)
        let docs = watch.appendingPathComponent("Documents", isDirectory: true)
        try fm.createDirectory(at: watch, withIntermediateDirectories: true)
        let source = watch.appendingPathComponent("my_invoice.pdf")
        try "data".write(to: source, atomically: true, encoding: .utf8)
        let pipeline = IngestPipeline(watchFolder: watch)
        let entries = try pipeline.apply(
            pipeline.plan(for: source)!,
            fileManager: fm
        )
        XCTAssertFalse(entries.isEmpty)
        for entry in entries where entry.kind == .renamed || entry.kind == .moved {
            XCTAssertNotNil(entry.beforePath)
            XCTAssertNotNil(entry.afterPath)
        }
        _ = docs
    }

    private func sampleAction(id: Int) -> UndoAction {
        UndoAction(
            activityID: UUID(),
            kind: .rename,
            beforePath: "/tmp/before-\(id).txt",
            afterPath: "/tmp/after-\(id).txt",
            displayName: "file-\(id).txt"
        )
    }
}
