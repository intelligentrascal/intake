import Foundation
import Testing
@testable import IntakeCore

/// GH-21: one incoming file gives at most one renamed file. A collision suffix
/// is used only when a *different* file holds the target name.
struct RenameDuplicatesTests {
    // MARK: Repeated stable events

    @Test
    func repeatedStableEventsForOneFileRenameItOnce() throws {
        let fileManager = FileManager.default
        let root = try makeTempWatchFolder(prefix: "intake-gh21-repeat")
        defer { try? fileManager.removeItem(at: root) }

        let source = root.appendingPathComponent("quarterly_report.pdf")
        try Data("pdf".utf8).write(to: source)
        let processor = OrganizeExistingProcessor(watchFolder: root)

        var renamed: [ActivityEntry] = []
        // Watcher fires for the original name, again for the stale original name,
        // and once more for the renamed file (e.g. before its name was acknowledged).
        let events = [source, source, root.appendingPathComponent("Quarterly Report.pdf")]
        for url in events {
            if case .organized(let entries) = processor.processOne(
                url,
                mode: .renameInPlace,
                fileManager: fileManager
            ) {
                renamed.append(contentsOf: entries.filter { $0.kind == .renamed })
            }
        }

        #expect(renamed.count == 1)
        #expect(renamed.first?.fileName == "Quarterly Report.pdf")
        #expect(try rootFileNames(root) == ["Quarterly Report.pdf"])
    }

    @Test
    func repeatedStableEventAfterCaseOnlyRenameDoesNotSuffixTheFileAgainstItself() throws {
        let fileManager = FileManager.default
        let root = try makeTempWatchFolder(prefix: "intake-gh21-repeat-case")
        defer { try? fileManager.removeItem(at: root) }

        // APFS resolves the stale lowercase URL to the renamed file, so the second
        // event still "finds" it — and must not rename it to `Quarterly Report 2.pdf`.
        let source = root.appendingPathComponent("quarterly report.pdf")
        try Data("pdf".utf8).write(to: source)
        let processor = OrganizeExistingProcessor(watchFolder: root)

        var renamed: [ActivityEntry] = []
        for _ in 0..<2 {
            if case .organized(let entries) = processor.processOne(
                source,
                mode: .renameInPlace,
                fileManager: fileManager
            ) {
                renamed.append(contentsOf: entries.filter { $0.kind == .renamed })
            }
        }

        #expect(renamed.count == 1)
        #expect(try rootFileNames(root) == ["Quarterly Report.pdf"])
    }

    @Test
    func routeFromAStaleCaseSpellingKeepsTheRenamedName() throws {
        let fileManager = FileManager.default
        let root = try makeTempWatchFolder(prefix: "intake-gh21-route-stale")
        defer { try? fileManager.removeItem(at: root) }

        try Data("pdf".utf8).write(to: root.appendingPathComponent("Quarterly Report.pdf"))
        let stale = root.appendingPathComponent("quarterly report.pdf")

        let routed = try IngestPipeline(watchFolder: root)
            .applyRoute(at: stale, fileManager: fileManager)

        #expect(routed.first?.fileName == "Quarterly Report.pdf")
        #expect(
            try fileManager.contentsOfDirectory(
                atPath: root.appendingPathComponent("Documents").path
            ) == ["Quarterly Report.pdf"]
        )
    }

    @Test
    func renameInPlaceIsIdempotentForAnAlreadyNormalizedName() throws {
        let fileManager = FileManager.default
        let root = try makeTempWatchFolder(prefix: "intake-gh21-idempotent")
        defer { try? fileManager.removeItem(at: root) }

        let source = root.appendingPathComponent("Team_Notes (1).md")
        try Data("notes".utf8).write(to: source)
        let pipeline = IngestPipeline(watchFolder: root)

        let first = try pipeline.applyRenameInPlace(at: source, fileManager: fileManager)
        let second = try pipeline.applyRenameInPlace(at: first.url, fileManager: fileManager)

        #expect(first.entries.map(\.kind) == [.renamed])
        #expect(second.entries.isEmpty)
        #expect(second.url == first.url)
        #expect(try rootFileNames(root) == ["Team Notes.md"])
    }

    // MARK: Browser temporary file + final file

    @Test
    func browserTemporaryFileIsNeverRenamedAlongsideTheFinalFile() throws {
        let fileManager = FileManager.default
        let root = try makeTempWatchFolder(prefix: "intake-gh21-temp-twin")
        defer { try? fileManager.removeItem(at: root) }

        let processor = OrganizeExistingProcessor(watchFolder: root)
        // In-flight: an empty placeholder at the final name + the browser's partial.
        // Partial suffixes cover Chromium, Firefox, Safari, DuckDuckGo, Opera,
        // Chrome File System Access, torrent clients and aria2 / yt-dlp.
        let partialExtensions = [
            "crdownload", "part", "download", "duckload", "opdownload",
            "crswap", "!ut", "!qB", "bc!", "aria2", "ytdl",
        ]
        for ext in partialExtensions {
            let placeholder = root.appendingPathComponent("setup_tool.dmg")
            let partial = root.appendingPathComponent("setup_tool.dmg.\(ext)")
            try Data().write(to: placeholder)
            try Data("half".utf8).write(to: partial)

            for url in [placeholder, partial] {
                if case .organized(let entries) = processor.processOne(
                    url,
                    mode: .renameInPlace,
                    fileManager: fileManager
                ) {
                    Issue.record("\(url.lastPathComponent) must not be renamed: \(entries)")
                }
            }
            #expect(try rootFileNames(root) == ["setup_tool.dmg", "setup_tool.dmg.\(ext)"])

            // Browser finishes: the partial replaces the placeholder.
            try fileManager.removeItem(at: placeholder)
            try fileManager.moveItem(at: partial, to: placeholder)
            guard case .organized(let entries) = processor.processOne(
                placeholder,
                mode: .renameInPlace,
                fileManager: fileManager
            ) else {
                Issue.record("finished download should be renamed")
                return
            }
            #expect(entries.map(\.kind) == [.renamed])
            #expect(try rootFileNames(root) == ["Setup Tool.dmg"])
            try fileManager.removeItem(at: root.appendingPathComponent("Setup Tool.dmg"))
        }
    }

    // MARK: Target name held by the file itself

    @Test
    func caseOnlyRenameDoesNotCollideWithItself() throws {
        let fileManager = FileManager.default
        let root = try makeTempWatchFolder(prefix: "intake-gh21-self")
        defer { try? fileManager.removeItem(at: root) }

        let source = root.appendingPathComponent("quarterly report.pdf")
        try Data("pdf".utf8).write(to: source)

        let renamed = try IngestPipeline(watchFolder: root)
            .applyRenameInPlace(at: source, fileManager: fileManager)

        #expect(renamed.entries.map(\.kind) == [.renamed])
        #expect(renamed.url.lastPathComponent == "Quarterly Report.pdf")
        #expect(try rootFileNames(root) == ["Quarterly Report.pdf"])
    }

    @Test
    func sourceSpelledDifferentlyFromDiskDoesNotCollideWithItself() throws {
        let fileManager = FileManager.default
        let root = try makeTempWatchFolder(prefix: "intake-gh21-self-spelling")
        defer { try? fileManager.removeItem(at: root) }

        // On disk the file is `Quarterly Report.pdf`; a stale event names it in
        // lowercase. The only entry holding the target is the file itself.
        let onDisk = root.appendingPathComponent("Quarterly Report.pdf")
        try Data("pdf".utf8).write(to: onDisk)
        let staleSpelling = root.appendingPathComponent("quarterly report.pdf")

        let renamed = try IngestPipeline(watchFolder: root)
            .applyRenameInPlace(at: staleSpelling, fileManager: fileManager)

        #expect(renamed.url.lastPathComponent == "Quarterly Report.pdf")
        #expect(try rootFileNames(root) == ["Quarterly Report.pdf"])
    }

    @Test
    func caseOnlyRenameCanBeUndone() throws {
        let fileManager = FileManager.default
        let root = try makeTempWatchFolder(prefix: "intake-gh21-self-undo")
        defer { try? fileManager.removeItem(at: root) }

        let source = root.appendingPathComponent("quarterly report.pdf")
        try Data("pdf".utf8).write(to: source)
        let renamed = try IngestPipeline(watchFolder: root)
            .applyRenameInPlace(at: source, fileManager: fileManager)
        let entry = try #require(renamed.entries.first)
        let action = try #require(UndoService.makeAction(from: entry))

        var undo = UndoService()
        undo.push(action)
        #expect(undo.eligibility(for: action, fileManager: fileManager) == .eligible)
        guard case .success(let restored) = undo.perform(action, fileManager: fileManager) else {
            Issue.record("case-only rename should undo")
            return
        }
        #expect(restored.lastPathComponent == "quarterly report.pdf")
        #expect(try rootFileNames(root) == ["quarterly report.pdf"])
    }

    // MARK: Target name held by another file

    @Test
    func identicalContentAtTargetKeepsSuffixedNameAndDeletesNothing() throws {
        let fileManager = FileManager.default
        let root = try makeTempWatchFolder(prefix: "intake-gh21-identical")
        defer { try? fileManager.removeItem(at: root) }

        let occupant = root.appendingPathComponent("Invoice.pdf")
        let redownload = root.appendingPathComponent("invoice (1).pdf")
        try Data("same bytes".utf8).write(to: occupant)
        try Data("same bytes".utf8).write(to: redownload)

        let renamed = try IngestPipeline(watchFolder: root)
            .applyRenameInPlace(at: redownload, fileManager: fileManager)

        #expect(renamed.entries.map(\.kind) == [.renamed])
        #expect(renamed.url.lastPathComponent == "Invoice 2.pdf")
        #expect(try rootFileNames(root) == ["Invoice 2.pdf", "Invoice.pdf"])
        #expect(try Data(contentsOf: occupant) == Data("same bytes".utf8))
        #expect(try Data(contentsOf: renamed.url) == Data("same bytes".utf8))

        // Undo still restores the browser name from the suffixed one.
        let action = try #require(renamed.entries.first.flatMap(UndoService.makeAction(from:)))
        var undo = UndoService()
        undo.push(action)
        guard case .success(let restored) = undo.perform(action, fileManager: fileManager) else {
            Issue.record("suffixed rename should undo")
            return
        }
        #expect(restored.lastPathComponent == "invoice (1).pdf")
        #expect(try rootFileNames(root) == ["Invoice.pdf", "invoice (1).pdf"])
    }

    @Test
    func differentFileWithOnlyCaseDifferenceGetsCollisionSuffix() throws {
        let fileManager = FileManager.default
        let root = try makeTempWatchFolder(prefix: "intake-gh21-case-occupant")
        defer { try? fileManager.removeItem(at: root) }

        let occupant = root.appendingPathComponent("invoice.pdf")
        let incoming = root.appendingPathComponent("invoice (1).pdf")
        try Data("older".utf8).write(to: occupant)
        try Data("newer".utf8).write(to: incoming)

        let renamed = try IngestPipeline(watchFolder: root)
            .applyRenameInPlace(at: incoming, fileManager: fileManager)

        #expect(renamed.url.lastPathComponent == "Invoice 2.pdf")
        #expect(try rootFileNames(root) == ["Invoice 2.pdf", "invoice.pdf"])
        #expect(try Data(contentsOf: occupant) == Data("older".utf8))
    }

    @Test
    func routeSuffixesWhenDestinationHoldsACaseVariant() throws {
        let fileManager = FileManager.default
        let root = try makeTempWatchFolder(prefix: "intake-gh21-route-case")
        defer { try? fileManager.removeItem(at: root) }

        let documents = root.appendingPathComponent("Documents", isDirectory: true)
        try fileManager.createDirectory(at: documents, withIntermediateDirectories: true)
        try Data("filed".utf8).write(to: documents.appendingPathComponent("report.pdf"))
        let source = root.appendingPathComponent("Report.pdf")
        try Data("new".utf8).write(to: source)

        let routed = try IngestPipeline(watchFolder: root)
            .applyRoute(at: source, fileManager: fileManager)

        #expect(routed.map(\.kind) == [.moved])
        #expect(routed.first?.fileName == "Report 2.pdf")
        #expect(try fileManager.contentsOfDirectory(atPath: documents.path).sorted()
            == ["Report 2.pdf", "report.pdf"])
    }

    @Test
    func uniquedComparesNamesCaseInsensitively() {
        #expect(IngestPipeline.uniqued(fileName: "Report.pdf", among: ["report.pdf"]) == "Report 2.pdf")
        #expect(
            IngestPipeline.uniqued(fileName: "Report.pdf", among: ["REPORT.PDF", "report 2.pdf"])
                == "Report 3.pdf"
        )
        #expect(IngestPipeline.uniqued(fileName: "Report.pdf", among: ["Report.pdf.zip"]) == "Report.pdf")
    }
}

private func rootFileNames(_ root: URL) throws -> [String] {
    try FileManager.default.contentsOfDirectory(atPath: root.path)
        .filter { !$0.hasPrefix(".") }
        .sorted()
}

private func makeTempWatchFolder(prefix: String) throws -> URL {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(
        "\(prefix)-\(UUID().uuidString)",
        isDirectory: true
    )
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    return root
}
