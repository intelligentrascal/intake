import Foundation
import Testing
@testable import IntakeCore

struct DownloadIdentityTests {
    @Test
    func collisionSuffixSharesIdentityWithOriginalStem() {
        #expect(
            DownloadIdentity.key(forFileName: "Resurf 2.9.2-121.dmg")
                == DownloadIdentity.key(forFileName: "Resurf 2.9.2-121 2.dmg")
        )
        #expect(DownloadIdentity.key(forFileName: "Resurf 2.9.2-121.dmg") == "resurf 2.9.2-121.dmg")
        #expect(DownloadIdentity.key(forFileName: "Resurf 2.9.2-121 2.dmg") == "resurf 2.9.2-121.dmg")
        #expect(DownloadIdentity.key(forFileName: "Quarterly Report 3.pdf") == "quarterly report.pdf")
        #expect(
            DownloadIdentity.key(forFileName: "Budget 2024.pdf")
                == DownloadIdentity.key(forFileName: "Budget 2024 2.pdf")
        )
        #expect(DownloadIdentity.key(forFileName: "Budget 2024.pdf") == "budget 2024.pdf")
        #expect(
            DownloadIdentity.key(forFileName: "Report 2024.pdf")
                != DownloadIdentity.key(forFileName: "Report.pdf")
        )
        #expect(
            DownloadIdentity.key(forFileName: "Photo 1.jpg")
                != DownloadIdentity.key(forFileName: "Photo.jpg")
        )
    }

    @Test
    func identityIsCaseInsensitiveAndKeepsExtension() {
        #expect(
            DownloadIdentity.key(forFileName: "Foo.DMG")
                == DownloadIdentity.key(forFileName: "foo 2.dmg")
        )
        #expect(DownloadIdentity.key(forFileName: "Notes.md") != DownloadIdentity.key(forFileName: "Notes.txt"))
        #expect(DownloadIdentity.key(forFileName: "Makefile") == DownloadIdentity.key(forFileName: "Makefile 2"))
    }

    @Test
    func versionTokensAreNotTreatedAsCollisionSuffixes() {
        #expect(DownloadIdentity.key(forFileName: "App 2.9.2.dmg") == "app 2.9.2.dmg")
        #expect(
            DownloadIdentity.key(forFileName: "App 2.9.2.dmg")
                != DownloadIdentity.key(forFileName: "App.dmg")
        )
    }
}

struct DownloadWriteGateLogicTests {
    @Test
    func refusesZeroAndNegativeSizes() {
        #expect(DownloadWriteGate.allowsOrganizeOrRename(size: 0) == false)
        #expect(DownloadWriteGate.allowsOrganizeOrRename(size: -1) == false)
        #expect(DownloadWriteGate.allowsOrganizeOrRename(size: 1))
    }

    @Test
    func readsSizeFromDisk() throws {
        let fileManager = FileManager.default
        let root = try makeTempWatchFolder(prefix: "intake-write-gate")
        defer { try? fileManager.removeItem(at: root) }

        let empty = root.appendingPathComponent("empty.bin")
        let full = root.appendingPathComponent("full.bin")
        try Data().write(to: empty)
        try Data("bytes".utf8).write(to: full)

        #expect(DownloadWriteGate.allowsOrganizeOrRename(at: empty, fileManager: fileManager) == false)
        #expect(DownloadWriteGate.allowsOrganizeOrRename(at: full, fileManager: fileManager))
        #expect(DownloadWriteGate.fileSize(at: empty, fileManager: fileManager) == 0)
        #expect(DownloadWriteGate.fileSize(at: full, fileManager: fileManager) == 5)
    }
}

struct EmptyFullSiblingDedupeTests {
    @Test
    func listsEmptySiblingsWhenAFullCopyExists() {
        let root = URL(fileURLWithPath: "/tmp/Downloads", isDirectory: true)
        let empty = DownloadFileSnapshot(url: root.appendingPathComponent("Resurf 2.9.2-121.dmg"), size: 0)
        let full = DownloadFileSnapshot(url: root.appendingPathComponent("Resurf 2.9.2-121 2.dmg"), size: 4_096)
        let otherEmpty = DownloadFileSnapshot(url: root.appendingPathComponent("alone.dmg"), size: 0)
        let otherFull = DownloadFileSnapshot(url: root.appendingPathComponent("ready.dmg"), size: 12)

        let empties = EmptyFullSiblingDedupe.emptyURLsSharingIdentityWithFull([
            empty, full, otherEmpty, otherFull,
        ])
        #expect(empties.map(\.lastPathComponent) == ["Resurf 2.9.2-121.dmg"])
    }

    @Test
    func doesNotFlagTwoFullOrTwoEmptyFiles() {
        let root = URL(fileURLWithPath: "/tmp/Downloads", isDirectory: true)
        let firstFull = DownloadFileSnapshot(url: root.appendingPathComponent("Report.pdf"), size: 10)
        let secondFull = DownloadFileSnapshot(url: root.appendingPathComponent("Report 2.pdf"), size: 12)
        let firstEmpty = DownloadFileSnapshot(url: root.appendingPathComponent("Wait.dmg"), size: 0)
        let secondEmpty = DownloadFileSnapshot(url: root.appendingPathComponent("Wait 2.dmg"), size: 0)

        #expect(EmptyFullSiblingDedupe.emptyURLsSharingIdentityWithFull([firstFull, secondFull]).isEmpty)
        #expect(EmptyFullSiblingDedupe.emptyURLsSharingIdentityWithFull([firstEmpty, secondEmpty]).isEmpty)
        #expect(EmptyFullSiblingDedupe.emptyURLsSharingIdentityWithFull([firstEmpty]).isEmpty)
    }

    @Test
    func removeDeletesOnlyTheEmptyTwinAndRechecksSize() throws {
        let fileManager = FileManager.default
        let root = try makeTempWatchFolder(prefix: "intake-empty-twin")
        defer { try? fileManager.removeItem(at: root) }

        let empty = root.appendingPathComponent("Resurf 2.9.2-121.dmg")
        let full = root.appendingPathComponent("Resurf 2.9.2-121 2.dmg")
        let leftoverEmpty = root.appendingPathComponent("still-writing.dmg")
        try Data().write(to: empty)
        try Data("installer".utf8).write(to: full)
        try Data().write(to: leftoverEmpty)

        let removed = EmptyFullSiblingDedupe.removeEmptySiblings(
            of: full,
            in: root,
            fileManager: fileManager
        )
        #expect(removed.map(\.lastPathComponent) == ["Resurf 2.9.2-121.dmg"])
        #expect(fileManager.fileExists(atPath: empty.path) == false)
        #expect(fileManager.fileExists(atPath: full.path))
        #expect(fileManager.fileExists(atPath: leftoverEmpty.path))
        let remaining = try Data(contentsOf: full)
        #expect(remaining == Data("installer".utf8))
    }

    @Test
    func doesNotRemoveAnEmptyNewDownloadJustBecauseAnOlderFullFileExists() throws {
        let fileManager = FileManager.default
        let root = try makeTempWatchFolder(prefix: "intake-old-full-new-empty")
        defer { try? fileManager.removeItem(at: root) }

        let oldFull = root.appendingPathComponent("Report.pdf")
        let newEmpty = root.appendingPathComponent("Report 2.pdf")
        try Data("old".utf8).write(to: oldFull)
        try Data().write(to: newEmpty)

        #expect(
            EmptyFullSiblingDedupe.removeEmptySiblings(
                of: newEmpty,
                in: root,
                fileManager: fileManager
            ).isEmpty
        )
        #expect(
            EmptyFullSiblingDedupe.removeEmptySiblings(
                of: oldFull,
                in: root,
                fileManager: fileManager
            ).isEmpty
        )
        #expect(fileManager.fileExists(atPath: newEmpty.path))
        #expect(fileManager.fileExists(atPath: oldFull.path))
    }
}

struct IngestPipelineEmptyRenameTests {
    @Test
    func renameInPlaceRefusesEmptyPlaceholder() throws {
        let fileManager = FileManager.default
        let root = try makeTempWatchFolder(prefix: "intake-empty-rename")
        defer { try? fileManager.removeItem(at: root) }

        let empty = root.appendingPathComponent("Resurf_Installers.dmg")
        try Data().write(to: empty)
        let pipeline = IngestPipeline(watchFolder: root)
        let renamed = try pipeline.applyRenameInPlace(at: empty, fileManager: fileManager)

        #expect(renamed.entries.isEmpty)
        #expect(renamed.url == empty.standardizedFileURL)
        #expect(fileManager.fileExists(atPath: empty.path))
        #expect(empty.lastPathComponent == "Resurf_Installers.dmg")
        #expect(
            fileManager.fileExists(
                atPath: root.appendingPathComponent("Resurf Installers.dmg").path
            ) == false
        )
    }

    @Test
    func combinedApplyRefusesEmptyAndDoesNotCreateCategoryFolders() throws {
        let fileManager = FileManager.default
        let root = try makeTempWatchFolder(prefix: "intake-empty-apply")
        defer { try? fileManager.removeItem(at: root) }

        let empty = root.appendingPathComponent("Resurf_Installers.dmg")
        try Data().write(to: empty)
        let pipeline = IngestPipeline(watchFolder: root)
        guard let plan = pipeline.plan(for: empty) else {
            Issue.record("expected an ingest plan")
            return
        }
        let entries = try pipeline.apply(plan, fileManager: fileManager)
        #expect(entries.isEmpty)
        #expect(fileManager.fileExists(atPath: empty.path))
        #expect(
            fileManager.fileExists(
                atPath: root.appendingPathComponent("Installers", isDirectory: true).path
            ) == false
        )
    }
}

struct OrganizeExistingEmptyWriteGateTests {
    @Test
    func scannerSkipsZeroBytePlaceholdersWithoutRemovingThem() throws {
        let fileManager = FileManager.default
        let root = try makeTempWatchFolder(prefix: "intake-scan-empty")
        defer { try? fileManager.removeItem(at: root) }

        let empty = root.appendingPathComponent("writing.dmg")
        let ready = root.appendingPathComponent("ready.pdf")
        try Data().write(to: empty)
        try Data("pdf".utf8).write(to: ready)

        let scan = OrganizeExistingScanner(watchFolder: root).scan(fileManager: fileManager)
        #expect(Set(scan.eligible.map(\.lastPathComponent)) == ["ready.pdf"])
        #expect(scan.skipped.map(\.url.lastPathComponent) == ["writing.dmg"])
        #expect(scan.skipped.map(\.reason) == [.emptyPlaceholder])
        #expect(fileManager.fileExists(atPath: empty.path))
    }

    @Test
    func scannerSkipsEmptyTwinWithoutDeletingUntilTheFullFileIsFiled() throws {
        let fileManager = FileManager.default
        let root = try makeTempWatchFolder(prefix: "intake-scan-twin")
        defer { try? fileManager.removeItem(at: root) }

        let empty = root.appendingPathComponent("Resurf 2.9.2-121.dmg")
        let full = root.appendingPathComponent("Resurf 2.9.2-121 2.dmg")
        try Data().write(to: empty)
        try Data("payload".utf8).write(to: full)

        let scan = OrganizeExistingScanner(watchFolder: root).scan(fileManager: fileManager)
        #expect(scan.eligible.map(\.lastPathComponent) == ["Resurf 2.9.2-121 2.dmg"])
        #expect(scan.skipped.map(\.url.lastPathComponent) == ["Resurf 2.9.2-121.dmg"])
        #expect(fileManager.fileExists(atPath: empty.path))
        #expect(fileManager.fileExists(atPath: full.path))
    }

    @Test
    func filingTheFullTwinRemovesTheEmptyPlaceholder() throws {
        let fileManager = FileManager.default
        let root = try makeTempWatchFolder(prefix: "intake-file-twin")
        defer { try? fileManager.removeItem(at: root) }

        let empty = root.appendingPathComponent("Resurf 2.9.2-121.dmg")
        let full = root.appendingPathComponent("Resurf 2.9.2-121 2.dmg")
        try Data().write(to: empty)
        try Data("payload".utf8).write(to: full)

        let processor = OrganizeExistingProcessor(watchFolder: root)
        switch processor.processOne(full, mode: .renameAndRoute, fileManager: fileManager) {
        case .organized:
            #expect(fileManager.fileExists(atPath: empty.path) == false)
            #expect(
                fileManager.fileExists(
                    atPath: root
                        .appendingPathComponent("Installers", isDirectory: true)
                        .appendingPathComponent("Resurf 2.9.2-121 2.dmg").path
                )
            )
        default:
            Issue.record("full twin should be filed")
        }
    }

    @Test
    func processorSkipsEmptyPlaceholders() throws {
        let fileManager = FileManager.default
        let root = try makeTempWatchFolder(prefix: "intake-process-empty")
        defer { try? fileManager.removeItem(at: root) }

        let empty = root.appendingPathComponent("placeholder.dmg")
        try Data().write(to: empty)
        let processor = OrganizeExistingProcessor(watchFolder: root)

        switch processor.processOne(empty, mode: .renameInPlace, fileManager: fileManager) {
        case .skipped:
            #expect(fileManager.fileExists(atPath: empty.path))
            #expect(empty.lastPathComponent == "placeholder.dmg")
        default:
            Issue.record("empty placeholders must be skipped, not renamed")
        }

        switch processor.processOne(empty, mode: .renameAndRoute, fileManager: fileManager) {
        case .skipped:
            #expect(
                fileManager.fileExists(
                    atPath: root.appendingPathComponent("Installers", isDirectory: true).path
                ) == false
            )
        default:
            Issue.record("empty placeholders must not be filed")
        }
    }
}

private func makeTempWatchFolder(prefix: String) throws -> URL {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(
        "\(prefix)-\(UUID().uuidString)",
        isDirectory: true
    )
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    return root
}
