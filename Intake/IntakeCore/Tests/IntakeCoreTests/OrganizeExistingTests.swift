import Foundation
import Testing
@testable import IntakeCore

struct OrganizeExistingCopyTests {
    @Test
    func confirmTitleUsesWatchFolderName() {
        #expect(
            OrganizeExistingCopy.confirmTitle(folderName: "Downloads")
                == "Organize files already in Downloads?"
        )
        #expect(
            OrganizeExistingCopy.confirmTitle(folderName: "Inbox")
                == "Organize files already in Inbox?"
        )
    }

    @Test
    func confirmBodyMatchesProductCopy() {
        #expect(
            OrganizeExistingCopy.confirmBody
                == "Intake will rename and file items sitting in the watch folder root using your current rules. Files already in category folders are left alone. You can follow every change in Activity."
        )
    }

    @Test
    func doneSummaryUsesCompactCounts() {
        #expect(
            OrganizeExistingSummary(organized: 4, skipped: 2, errors: 1).doneMessage
                == "Organized 4. 2 skipped. 1 errors."
        )
    }

}

struct OrganizeExistingScannerTests {
    @Test
    func scansLooseRootFilesAndLeavesManagedFolderContentsAlone() throws {
        let fileManager = FileManager.default
        let root = try makeTempWatchFolder()
        defer { try? fileManager.removeItem(at: root) }

        let loosePDF = root.appendingPathComponent("Quarterly_Report.pdf")
        let looseImage = root.appendingPathComponent("holiday.heic")
        let partial = root.appendingPathComponent("movie.mp4.crdownload")
        try Data("pdf".utf8).write(to: loosePDF)
        try Data("img".utf8).write(to: looseImage)
        try Data("part".utf8).write(to: partial)

        let documents = root.appendingPathComponent("Documents", isDirectory: true)
        let images = root.appendingPathComponent("Images", isDirectory: true)
        try fileManager.createDirectory(at: documents, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: images, withIntermediateDirectories: true)
        let alreadyFiled = documents.appendingPathComponent("already.pdf")
        let nestedImage = images.appendingPathComponent("nested.png")
        try Data("filed".utf8).write(to: alreadyFiled)
        try Data("nested".utf8).write(to: nestedImage)

        let customFolder = root.appendingPathComponent("My Project", isDirectory: true)
        try fileManager.createDirectory(at: customFolder, withIntermediateDirectories: true)
        try Data("nope".utf8).write(to: customFolder.appendingPathComponent("inside.txt"))

        let scan = OrganizeExistingScanner(watchFolder: root).scan(fileManager: fileManager)
        let eligibleNames = Set(scan.eligible.map(\.lastPathComponent))
        let skippedNames = Set(scan.skipped.map(\.url.lastPathComponent))

        #expect(eligibleNames == ["Quarterly_Report.pdf", "holiday.heic"])
        #expect(skippedNames == ["movie.mp4.crdownload"])
        #expect(scan.eligible.allSatisfy { $0.deletingLastPathComponent() == root })
        #expect(fileManager.fileExists(atPath: alreadyFiled.path))
        #expect(fileManager.fileExists(atPath: nestedImage.path))
    }

    @Test
    func ignorePolicyMatchesLiveIngestForRootPartialsAndDotfiles() throws {
        let fileManager = FileManager.default
        let root = try makeTempWatchFolder()
        defer { try? fileManager.removeItem(at: root) }

        try Data("ok".utf8).write(to: root.appendingPathComponent("Invoice.pdf"))
        try Data("partial".utf8).write(to: root.appendingPathComponent("Invoice.pdf.download"))
        try Data("chrome".utf8).write(to: root.appendingPathComponent("photo.jpg.crdownload"))
        try Data("store".utf8).write(to: root.appendingPathComponent(".DS_Store"))
        try Data("unconfirmed".utf8).write(to: root.appendingPathComponent("Unconfirmed 999.crdownload"))

        let scan = OrganizeExistingScanner(watchFolder: root).scan(fileManager: fileManager)
        #expect(scan.eligible.map(\.lastPathComponent) == ["Invoice.pdf"])
        #expect(
            Set(scan.skipped.map(\.url.lastPathComponent))
                == [
                    "Invoice.pdf.download",
                    "photo.jpg.crdownload",
                    ".DS_Store",
                    "Unconfirmed 999.crdownload",
                ]
        )
    }

    @Test
    func doesNotRecurseIntoEveryManagedCategoryFolder() throws {
        let fileManager = FileManager.default
        let root = try makeTempWatchFolder()
        defer { try? fileManager.removeItem(at: root) }

        for name in DefaultTaxonomy.managedFolderNames {
            let folder = root.appendingPathComponent(name, isDirectory: true)
            try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
            try Data("nested".utf8).write(to: folder.appendingPathComponent("nested.bin"))
        }
        try Data("loose".utf8).write(to: root.appendingPathComponent("notes.md"))

        let scan = OrganizeExistingScanner(watchFolder: root).scan(fileManager: fileManager)
        #expect(scan.eligible.map(\.lastPathComponent) == ["notes.md"])
        #expect(scan.skipped.isEmpty)
    }

    private func makeTempWatchFolder() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "intake-organize-scan-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }
}

struct OrganizeExistingProcessorTests {
    @Test
    func organizesRootFilesWithSameRenameRouteActivityPipelineAndLazyFolders() throws {
        let fileManager = FileManager.default
        let root = try makeTempWatchFolder()
        defer { try? fileManager.removeItem(at: root) }

        let loosePDF = root.appendingPathComponent("Team_Notes.md")
        let looseSheet = root.appendingPathComponent("budget.csv")
        try Data("notes".utf8).write(to: loosePDF)
        try Data("1,2".utf8).write(to: looseSheet)

        let documents = root.appendingPathComponent("Documents", isDirectory: true)
        try fileManager.createDirectory(at: documents, withIntermediateDirectories: true)
        let alreadyFiled = documents.appendingPathComponent("already.md")
        try Data("keep".utf8).write(to: alreadyFiled)

        let processor = OrganizeExistingProcessor(watchFolder: root)
        let scan = OrganizeExistingScanner(watchFolder: root).scan(fileManager: fileManager)
        let result = processor.process(
            urls: scan.eligible,
            alreadySkipped: scan.skipped.count,
            fileManager: fileManager
        )

        #expect(result.summary.organized == 2)
        #expect(result.summary.skipped == 0)
        #expect(result.summary.errors == 0)
        #expect(fileManager.fileExists(atPath: loosePDF.path) == false)
        #expect(fileManager.fileExists(atPath: alreadyFiled.path))
        #expect(
            fileManager.fileExists(
                atPath: documents.appendingPathComponent("Team Notes.md").path
            )
        )
        #expect(
            fileManager.fileExists(
                atPath: root.appendingPathComponent("Spreadsheets", isDirectory: true)
                    .appendingPathComponent("Budget.csv").path
            )
        )
        #expect(
            fileManager.fileExists(
                atPath: root.appendingPathComponent("Images", isDirectory: true).path
            ) == false
        )
        #expect(result.entries.contains { $0.kind == .renamed && $0.fileName == "Team Notes.md" })
        #expect(result.entries.contains { $0.kind == .moved && $0.destinationFolder == "Documents" })
        #expect(result.entries.contains { $0.kind == .moved && $0.destinationFolder == "Spreadsheets" })
    }

    @Test
    func skippedIgnoredRootFilesStayPutAndAreCounted() throws {
        let fileManager = FileManager.default
        let root = try makeTempWatchFolder()
        defer { try? fileManager.removeItem(at: root) }

        let partial = root.appendingPathComponent("setup.dmg.part")
        let ready = root.appendingPathComponent("setup.dmg")
        try Data("partial".utf8).write(to: partial)
        try Data("ready".utf8).write(to: ready)

        let scan = OrganizeExistingScanner(watchFolder: root).scan(fileManager: fileManager)
        let processor = OrganizeExistingProcessor(watchFolder: root)
        let result = processor.process(
            urls: scan.eligible,
            alreadySkipped: scan.skipped.count,
            fileManager: fileManager
        )

        #expect(scan.skipped.map(\.url.lastPathComponent) == ["setup.dmg.part"])
        #expect(result.summary.organized == 1)
        #expect(result.summary.skipped == 1)
        #expect(fileManager.fileExists(atPath: partial.path))
        #expect(
            fileManager.fileExists(
                atPath: root.appendingPathComponent("Installers", isDirectory: true)
                    .appendingPathComponent("Setup.dmg").path
            )
        )
    }

    @Test
    func cancelStopsSchedulingNewFilesWithoutHalfMoves() throws {
        let fileManager = FileManager.default
        let root = try makeTempWatchFolder()
        defer { try? fileManager.removeItem(at: root) }

        let first = root.appendingPathComponent("alpha.pdf")
        let second = root.appendingPathComponent("beta.pdf")
        let third = root.appendingPathComponent("gamma.pdf")
        try Data("a".utf8).write(to: first)
        try Data("b".utf8).write(to: second)
        try Data("c".utf8).write(to: third)

        var allowed = 1
        let processor = OrganizeExistingProcessor(watchFolder: root)
        let result = processor.process(
            urls: [first, second, third],
            isCancelled: {
                if allowed == 0 {
                    return true
                }
                allowed -= 1
                return false
            },
            fileManager: fileManager
        )

        #expect(result.summary.organized == 1)
        #expect(result.summary.cancelled)
        #expect(fileManager.fileExists(atPath: first.path) == false)
        #expect(
            fileManager.fileExists(
                atPath: root.appendingPathComponent("Documents", isDirectory: true)
                    .appendingPathComponent("Alpha.pdf").path
            )
        )
        #expect(fileManager.fileExists(atPath: second.path))
        #expect(fileManager.fileExists(atPath: third.path))
        let leftover = (try fileManager.contentsOfDirectory(atPath: root.path)).sorted()
        #expect(leftover.contains("beta.pdf"))
        #expect(leftover.contains("gamma.pdf"))
        #expect(leftover.contains("alpha.pdf") == false)
        #expect(leftover.contains("alpha.pdf.tmp") == false)
    }

    private func makeTempWatchFolder() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "intake-organize-run-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }
}

struct OrganizeExistingPreviewTests {
    private func makeTempWatchFolder() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "intake-organize-preview-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    @Test
    func previewGroupsEligibleFilesByDestinationWithCountsAndMarksNewFolders() throws {
        let fileManager = FileManager.default
        let root = try makeTempWatchFolder()
        defer { try? fileManager.removeItem(at: root) }

        try Data("notes".utf8).write(to: root.appendingPathComponent("Team_Notes.md"))
        try Data("more".utf8).write(to: root.appendingPathComponent("More_Notes.md"))
        try Data("1,2".utf8).write(to: root.appendingPathComponent("budget.csv"))

        let scan = OrganizeExistingScanner(watchFolder: root).scan(fileManager: fileManager)
        let pipeline = IngestPipeline(watchFolder: root)
        let preview = OrganizeExistingPreviewBuilder.build(
            scan: scan,
            pipeline: pipeline,
            fileManager: fileManager
        )

        #expect(preview.eligibleCount == 3)
        let documents = try #require(preview.groups.first { $0.destinationFolderName == "Documents" })
        #expect(documents.items.count == 2)
        #expect(documents.isNewFolder)
        let spreadsheets = try #require(
            preview.groups.first { $0.destinationFolderName == "Spreadsheets" }
        )
        #expect(spreadsheets.items.count == 1)
        #expect(spreadsheets.isNewFolder)
        #expect(
            Set(documents.items.map(\.plan.renamedFileName)) == ["Team Notes.md", "More Notes.md"]
        )
    }

    @Test
    func previewCarriesASkipReasonForEachIneligibleFile() throws {
        let fileManager = FileManager.default
        let root = try makeTempWatchFolder()
        defer { try? fileManager.removeItem(at: root) }

        try Data("ready".utf8).write(to: root.appendingPathComponent("ready.pdf"))
        try Data().write(to: root.appendingPathComponent("writing.dmg"))
        try Data("partial".utf8).write(to: root.appendingPathComponent("movie.mp4.crdownload"))
        try Data("hidden".utf8).write(to: root.appendingPathComponent(".DS_Store"))

        let scan = OrganizeExistingScanner(watchFolder: root).scan(fileManager: fileManager)
        let preview = OrganizeExistingPreviewBuilder.build(
            scan: scan,
            pipeline: IngestPipeline(watchFolder: root),
            fileManager: fileManager
        )

        let reasons = Dictionary(
            uniqueKeysWithValues: preview.skipped.map { ($0.url.lastPathComponent, $0.reason) }
        )
        #expect(reasons["writing.dmg"] == .emptyPlaceholder)
        #expect(reasons["movie.mp4.crdownload"] == .stillDownloading)
        #expect(reasons[".DS_Store"] == .ignored)
    }

    @Test
    func previewComputesDistinctCollisionSuffixesForTwoFilesThatWouldCollide() throws {
        let fileManager = FileManager.default
        let root = try makeTempWatchFolder()
        defer { try? fileManager.removeItem(at: root) }

        // Both normalize to "Invoice.pdf" and both route to Documents.
        try Data("a".utf8).write(to: root.appendingPathComponent("invoice.pdf"))
        try Data("b".utf8).write(to: root.appendingPathComponent("Invoice_.pdf"))

        let scan = OrganizeExistingScanner(watchFolder: root).scan(fileManager: fileManager)
        let pipeline = IngestPipeline(watchFolder: root)
        let preview = OrganizeExistingPreviewBuilder.build(
            scan: scan,
            pipeline: pipeline,
            fileManager: fileManager
        )

        let documents = try #require(preview.groups.first { $0.destinationFolderName == "Documents" })
        #expect(documents.items.count == 2)
        let names = Set(documents.items.map(\.plan.renamedFileName))
        #expect(names == ["Invoice.pdf", "Invoice 2.pdf"])

        // Applying every previewed item reproduces exactly what the preview promised.
        let processor = OrganizeExistingProcessor(watchFolder: root)
        let result = processor.applyPreview(items: documents.items, fileManager: fileManager)
        #expect(result.summary.organized == 2)
        #expect(result.summary.skipped == 0)
        #expect(result.summary.errors == 0)
        let documentsFolder = root.appendingPathComponent("Documents", isDirectory: true)
        #expect(fileManager.fileExists(atPath: documentsFolder.appendingPathComponent("Invoice.pdf").path))
        #expect(
            fileManager.fileExists(atPath: documentsFolder.appendingPathComponent("Invoice 2.pdf").path)
        )
    }

    @Test
    func excludedItemsAreNeverPassedToApplyAndStayUntouched() throws {
        let fileManager = FileManager.default
        let root = try makeTempWatchFolder()
        defer { try? fileManager.removeItem(at: root) }

        try Data("a".utf8).write(to: root.appendingPathComponent("keep.pdf"))
        try Data("b".utf8).write(to: root.appendingPathComponent("skip.pdf"))

        let scan = OrganizeExistingScanner(watchFolder: root).scan(fileManager: fileManager)
        let preview = OrganizeExistingPreviewBuilder.build(
            scan: scan,
            pipeline: IngestPipeline(watchFolder: root),
            fileManager: fileManager
        )
        let documents = try #require(preview.groups.first { $0.destinationFolderName == "Documents" })
        let excluded = try #require(documents.items.first { $0.plan.sourceURL.lastPathComponent == "skip.pdf" })
        let selected = documents.items.filter { $0.id != excluded.id }

        let processor = OrganizeExistingProcessor(watchFolder: root)
        let result = processor.applyPreview(items: selected, fileManager: fileManager)

        #expect(result.summary.organized == 1)
        #expect(fileManager.fileExists(atPath: root.appendingPathComponent("skip.pdf").path))
        #expect(
            fileManager.fileExists(
                atPath: root.appendingPathComponent("Documents", isDirectory: true)
                    .appendingPathComponent("Keep.pdf").path
            )
        )
    }

    @Test
    func applyLogsAFileThatDisappearedOrChangedAsSkippedNotAnError() throws {
        let fileManager = FileManager.default
        let root = try makeTempWatchFolder()
        defer { try? fileManager.removeItem(at: root) }

        let goneFile = root.appendingPathComponent("gone.pdf")
        let changedFile = root.appendingPathComponent("changed.pdf")
        let stableFile = root.appendingPathComponent("stable.pdf")
        try Data("gone".utf8).write(to: goneFile)
        try Data("changed".utf8).write(to: changedFile)
        try Data("stable".utf8).write(to: stableFile)

        let scan = OrganizeExistingScanner(watchFolder: root).scan(fileManager: fileManager)
        let preview = OrganizeExistingPreviewBuilder.build(
            scan: scan,
            pipeline: IngestPipeline(watchFolder: root),
            fileManager: fileManager
        )
        let documents = try #require(preview.groups.first { $0.destinationFolderName == "Documents" })

        // Mutate disk after the preview was built, before Apply runs.
        try fileManager.removeItem(at: goneFile)
        try Data("changed a lot more than before".utf8).write(to: changedFile)

        let processor = OrganizeExistingProcessor(watchFolder: root)
        let result = processor.applyPreview(items: documents.items, fileManager: fileManager)

        #expect(result.summary.organized == 1)
        #expect(result.summary.skipped == 2)
        #expect(result.summary.errors == 0)
        #expect(result.entries.allSatisfy { $0.kind != ActivityEntry.Kind.error })
        #expect(
            result.entries.filter { $0.kind == ActivityEntry.Kind.skipped }.count == 2
        )
        #expect(fileManager.fileExists(atPath: changedFile.path))
        #expect(
            fileManager.fileExists(
                atPath: root.appendingPathComponent("Documents", isDirectory: true)
                    .appendingPathComponent("Stable.pdf").path
            )
        )
    }
}
