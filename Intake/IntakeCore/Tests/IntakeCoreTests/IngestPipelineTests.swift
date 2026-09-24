import Foundation
import Testing
@testable import IntakeCore

struct IngestPipelineTests {
    let watch = URL(fileURLWithPath: "/tmp/Downloads", isDirectory: true)

    @Test
    func plansRenameThenRouteIntoLazyCategoryFolder() {
        let pipeline = IngestPipeline(watchFolder: watch)
        let source = watch.appendingPathComponent("Quarterly_Report.pdf")
        let plan = pipeline.plan(for: source)
        #expect(plan?.needsRename == true)
        #expect(plan?.renamedFileName == "Quarterly Report.pdf")
        #expect(plan?.category == .documents)
        #expect(plan?.destinationFolderName == "Documents")
        #expect(plan?.destinationDirectory.lastPathComponent == "Documents")
        #expect(plan?.destinationURL.lastPathComponent == "Quarterly Report.pdf")
    }

    @Test
    func unmatchedTypesGoToOther() {
        let pipeline = IngestPipeline(watchFolder: watch)
        let source = watch.appendingPathComponent("notes.xyz")
        let plan = pipeline.plan(for: source)
        #expect(plan?.category == .other)
        #expect(plan?.destinationFolderName == "Other")
        #expect(plan?.destinationDirectory.lastPathComponent == "Other")
    }

    @Test
    func customRulesRouteIntoNamedFoldersWithoutPrecreatingThem() throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory.appendingPathComponent(
            "intake-custom-rule-\(UUID().uuidString)",
            isDirectory: true
        )
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: root) }

        let rules = RuleMutation.addingCustom(
            DefaultTaxonomy.rules,
            folderName: "Design",
            extensions: ["psd"]
        )
        let source = root.appendingPathComponent("hero.psd")
        try Data("psd".utf8).write(to: source)
        let pipeline = IngestPipeline(watchFolder: root, rules: rules)
        guard let plan = pipeline.plan(for: source) else {
            Issue.record("expected a plan for .psd")
            return
        }
        #expect(plan.destinationFolderName == "Design")
        #expect(fileManager.fileExists(atPath: plan.destinationDirectory.path) == false)
        _ = try pipeline.apply(plan, fileManager: fileManager)
        #expect(fileManager.fileExists(atPath: plan.destinationURL.path))
    }

    @Test
    func firstMatchingEnabledRuleWinsByOrder() {
        let pipeline = IngestPipeline(
            watchFolder: watch,
            rules: [
                RoutingRule.custom(folderName: "Design", extensions: ["psd"], isEnabled: true),
                RoutingRule(category: .images, extensions: ["png", "psd"], isEnabled: true),
            ]
        )
        let plan = pipeline.plan(for: watch.appendingPathComponent("hero.psd"))
        #expect(plan?.destinationFolderName == "Design")
        #expect(plan?.category == .other)
    }

    @Test
    func ignoresFilesAlreadyOutsideTheWatchRoot() {
        let pipeline = IngestPipeline(watchFolder: watch)
        let nested = watch.appendingPathComponent("Documents").appendingPathComponent("done.pdf")
        #expect(pipeline.plan(for: nested) == nil)
    }

    @Test
    func uniquedNamesSkipExistingDestinations() {
        #expect(IngestPipeline.uniqued(fileName: "Report.pdf", among: []) == "Report.pdf")
        #expect(
            IngestPipeline.uniqued(fileName: "Report.pdf", among: ["Report.pdf"]) == "Report 2.pdf"
        )
        #expect(
            IngestPipeline.uniqued(
                fileName: "Report.pdf",
                among: ["Report.pdf", "Report 2.pdf"]
            ) == "Report 3.pdf"
        )
    }

    private func makeTempRoot(_ label: String) throws -> URL {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory.appendingPathComponent(
            "intake-\(label)-\(UUID().uuidString)",
            isDirectory: true
        )
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    @Test
    func ruleWithSourceDomainConditionMatchesSubdomainsAndFallsThroughOtherwise() throws {
        let fileManager = FileManager.default
        let root = try makeTempRoot("domain-condition")
        defer { try? fileManager.removeItem(at: root) }

        let rules = [
            RoutingRule.custom(
                folderName: "Finance",
                extensions: ["pdf"],
                conditions: [.sourceDomain("bank.com")]
            ),
            RoutingRule(category: .documents, extensions: ["pdf"]),
        ]
        let pipeline = IngestPipeline(watchFolder: root, rules: rules)

        // From a subdomain of bank.com: routes to Finance.
        let bankFile = root.appendingPathComponent("Statement.pdf")
        try Data("statement".utf8).write(to: bankFile)
        try WhereFromMetadata.write(
            urls: ["https://secure.bank.com/statement.pdf"],
            atPath: bankFile.path
        )
        let bankPlan = try #require(pipeline.plan(for: bankFile))
        #expect(bankPlan.destinationFolderName == "Finance")
        #expect(bankPlan.sourceDomain == "secure.bank.com")

        // Same extension, unrelated source: falls through to Documents.
        let otherFile = root.appendingPathComponent("Other.pdf")
        try Data("other".utf8).write(to: otherFile)
        try WhereFromMetadata.write(urls: ["https://example.com/other.pdf"], atPath: otherFile.path)
        let otherPlan = try #require(pipeline.plan(for: otherFile))
        #expect(otherPlan.destinationFolderName == "Documents")

        // No where-from metadata at all: fails the domain condition, falls through.
        let unknownFile = root.appendingPathComponent("Unknown.pdf")
        try Data("unknown".utf8).write(to: unknownFile)
        let unknownPlan = try #require(pipeline.plan(for: unknownFile))
        #expect(unknownPlan.destinationFolderName == "Documents")
        #expect(unknownPlan.sourceDomain == nil)
    }

    @Test
    func extensionlessRuleMatchesAnyTypeFromASourceDomain() throws {
        let fileManager = FileManager.default
        let root = try makeTempRoot("extensionless-domain")
        defer { try? fileManager.removeItem(at: root) }

        let rules = [
            RoutingRule.custom(
                folderName: "GitHub",
                extensions: [],
                conditions: [.sourceDomain("github.com")]
            ),
        ]
        let pipeline = IngestPipeline(watchFolder: root, rules: rules)

        let release = root.appendingPathComponent("tool-1.2.0.zip")
        try Data("zip".utf8).write(to: release)
        try WhereFromMetadata.write(urls: ["https://github.com/org/tool/releases"], atPath: release.path)

        let plan = try #require(pipeline.plan(for: release))
        #expect(plan.destinationFolderName == "GitHub")
    }

    @Test
    func nameAndSizeConditionsCombineWithAND() throws {
        let fileManager = FileManager.default
        let root = try makeTempRoot("name-size-condition")
        defer { try? fileManager.removeItem(at: root) }

        let rules = [
            RoutingRule.custom(
                folderName: "Big Invoices",
                extensions: ["pdf"],
                conditions: [.nameContains("invoice"), .sizeAtLeast(10)]
            ),
            RoutingRule(category: .documents, extensions: ["pdf"]),
        ]
        let pipeline = IngestPipeline(watchFolder: root, rules: rules)

        let bigInvoice = root.appendingPathComponent("Invoice_Acme.pdf")
        try Data(repeating: 0, count: 20).write(to: bigInvoice)
        let bigPlan = try #require(pipeline.plan(for: bigInvoice))
        #expect(bigPlan.destinationFolderName == "Big Invoices")

        // Matches the name but not the size: falls through.
        let smallInvoice = root.appendingPathComponent("Invoice_Small.pdf")
        try Data(repeating: 0, count: 2).write(to: smallInvoice)
        let smallPlan = try #require(pipeline.plan(for: smallInvoice))
        #expect(smallPlan.destinationFolderName == "Documents")

        // Matches the size but not the name: falls through.
        let bigReport = root.appendingPathComponent("Report.pdf")
        try Data(repeating: 0, count: 20).write(to: bigReport)
        let reportPlan = try #require(pipeline.plan(for: bigReport))
        #expect(reportPlan.destinationFolderName == "Documents")
    }

    @Test
    func wildcardNameConditionMatchesCaseInsensitively() throws {
        let fileManager = FileManager.default
        let root = try makeTempRoot("wildcard-condition")
        defer { try? fileManager.removeItem(at: root) }

        let rules = [
            RoutingRule.custom(
                folderName: "Screenshots",
                extensions: [],
                conditions: [.nameMatchesWildcard("img_*")]
            ),
        ]
        let pipeline = IngestPipeline(watchFolder: root, rules: rules)
        let file = root.appendingPathComponent("IMG_0099.heic")
        try Data("heic".utf8).write(to: file)
        let plan = try #require(pipeline.plan(for: file))
        #expect(plan.destinationFolderName == "Screenshots")
    }

    @Test
    func applyRouteRecordsSourceDomainOnTheActivityEntry() throws {
        let fileManager = FileManager.default
        let root = try makeTempRoot("apply-domain")
        defer { try? fileManager.removeItem(at: root) }

        let source = root.appendingPathComponent("Statement.pdf")
        try Data("statement".utf8).write(to: source)
        try WhereFromMetadata.write(urls: ["https://secure.bank.com/statement.pdf"], atPath: source.path)

        let pipeline = IngestPipeline(watchFolder: root)
        let entries = try pipeline.applyRoute(at: source, fileManager: fileManager)
        #expect(entries.first?.sourceDomain == "secure.bank.com")
    }

    @Test
    func applyRenamesThenCreatesFolderThenMoves() throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory.appendingPathComponent(
            "intake-ingest-\(UUID().uuidString)",
            isDirectory: true
        )
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: root) }

        let source = root.appendingPathComponent("Team_Notes.md")
        try "hello".write(to: source, atomically: true, encoding: .utf8)

        let pipeline = IngestPipeline(watchFolder: root)
        guard let plan = pipeline.plan(for: source) else {
            Issue.record("expected an ingest plan")
            return
        }

        #expect(fileManager.fileExists(atPath: plan.destinationDirectory.path) == false)
        #expect(plan.isNewFolder)

        let entries = try pipeline.apply(plan, fileManager: fileManager)
        #expect(fileManager.fileExists(atPath: source.path) == false)
        #expect(fileManager.fileExists(atPath: plan.destinationURL.path))
        #expect(entries.map(\.kind) == [.renamed, .moved])
        #expect(plan.category == .documents)

        // A second file routed to the now-existing folder is not "new".
        let secondSource = root.appendingPathComponent("Second_Notes.md")
        try "hi".write(to: secondSource, atomically: true, encoding: .utf8)
        let secondPlan = try #require(pipeline.plan(for: secondSource, fileManager: fileManager))
        #expect(secondPlan.isNewFolder == false)
    }

    @Test
    func dateSubfolderPatternNoneDoesNotAddSubfolder() throws {
        let fileManager = FileManager.default
        let root = try makeTempRoot("subfolder-none")
        defer { try? fileManager.removeItem(at: root) }

        let rules = [
            RoutingRule.custom(
                folderName: "Images",
                extensions: ["jpg"],
                subfolderPattern: .none
            ),
        ]
        let pipeline = IngestPipeline(watchFolder: root, rules: rules)

        let source = root.appendingPathComponent("photo.jpg")
        try Data("jpg".utf8).write(to: source)

        let date = Calendar.current.date(from: DateComponents(year: 2026, month: 9, day: 24))!
        let plan = try #require(pipeline.plan(for: source, stableAt: date, fileManager: fileManager))

        #expect(plan.destinationDirectory.lastPathComponent == "Images")
        #expect(plan.destinationFolderName == "Images")
    }

    @Test
    func dateSubfolderPatternYearCreatesYearSubfolder() throws {
        let fileManager = FileManager.default
        let root = try makeTempRoot("subfolder-year")
        defer { try? fileManager.removeItem(at: root) }

        let rules = [
            RoutingRule.custom(
                folderName: "Images",
                extensions: ["jpg"],
                subfolderPattern: .year
            ),
        ]
        let pipeline = IngestPipeline(watchFolder: root, rules: rules)

        let source = root.appendingPathComponent("photo.jpg")
        try Data("jpg".utf8).write(to: source)

        let date = Calendar.current.date(from: DateComponents(year: 2026, month: 9, day: 24))!
        let plan = try #require(pipeline.plan(for: source, stableAt: date, fileManager: fileManager))

        #expect(plan.destinationDirectory.lastPathComponent == "2026")
        let parentDirectory = plan.destinationDirectory.deletingLastPathComponent()
        #expect(parentDirectory.lastPathComponent == "Images")
        #expect(plan.destinationFolderName == "Images")
    }

    @Test
    func dateSubfolderPatternYearMonthCreatesYearMonthSubfolder() throws {
        let fileManager = FileManager.default
        let root = try makeTempRoot("subfolder-yearmonth")
        defer { try? fileManager.removeItem(at: root) }

        let rules = [
            RoutingRule.custom(
                folderName: "Images",
                extensions: ["jpg"],
                subfolderPattern: .yearMonth
            ),
        ]
        let pipeline = IngestPipeline(watchFolder: root, rules: rules)

        let source = root.appendingPathComponent("photo.jpg")
        try Data("jpg".utf8).write(to: source)

        let date = Calendar.current.date(from: DateComponents(year: 2026, month: 9, day: 24))!
        let plan = try #require(pipeline.plan(for: source, stableAt: date, fileManager: fileManager))

        #expect(plan.destinationDirectory.lastPathComponent == "2026-09")
        let parentDirectory = plan.destinationDirectory.deletingLastPathComponent()
        #expect(parentDirectory.lastPathComponent == "Images")
        #expect(plan.destinationFolderName == "Images")
    }

    @Test
    func dateSubfolderCreatedLazilyOnlyAtMoveTime() throws {
        let fileManager = FileManager.default
        let root = try makeTempRoot("subfolder-lazy")
        defer { try? fileManager.removeItem(at: root) }

        let rules = [
            RoutingRule.custom(
                folderName: "Images",
                extensions: ["jpg"],
                subfolderPattern: .yearMonth
            ),
        ]
        let pipeline = IngestPipeline(watchFolder: root, rules: rules)

        let source = root.appendingPathComponent("photo.jpg")
        try Data("jpg".utf8).write(to: source)

        let date = Calendar.current.date(from: DateComponents(year: 2026, month: 9, day: 24))!
        let plan = try #require(pipeline.plan(for: source, stableAt: date, fileManager: fileManager))

        // After plan, the destination folder (including subfolder) should not exist yet
        #expect(fileManager.fileExists(atPath: plan.destinationDirectory.path) == false)
        #expect(plan.isNewFolder == true)

        // After apply, it should exist
        _ = try pipeline.apply(plan, stableAt: date, fileManager: fileManager)
        #expect(fileManager.fileExists(atPath: plan.destinationURL.path))
        #expect(fileManager.fileExists(atPath: plan.destinationDirectory.path))
    }

    @Test
    func oldRulesWithoutSubfolderPatternDecodeToNone() throws {
        let json = """
        {
            "id": "test-rule",
            "folderName": "Documents",
            "systemImage": "folder",
            "extensions": ["pdf"],
            "conditions": [],
            "isEnabled": true,
            "isBuiltIn": false,
            "builtInCategory": null
        }
        """
        let data = json.data(using: .utf8)!
        let decoder = JSONDecoder()
        let rule = try decoder.decode(RoutingRule.self, from: data)

        #expect(rule.subfolderPattern == .none)
    }

    @Test
    func undoRestoresFileAndEmptySubfolderIsRemovedByCleanup() throws {
        let fileManager = FileManager.default
        let root = try makeTempRoot("undo-subfolder")
        defer { try? fileManager.removeItem(at: root) }

        let rules = [
            RoutingRule.custom(
                folderName: "Documents",
                extensions: ["pdf"],
                subfolderPattern: .yearMonth
            ),
        ]
        let pipeline = IngestPipeline(watchFolder: root, rules: rules)

        let source = root.appendingPathComponent("file.pdf")
        try Data("pdf".utf8).write(to: source)

        let date = Calendar.current.date(from: DateComponents(year: 2026, month: 9, day: 24))!
        let plan = try #require(pipeline.plan(for: source, stableAt: date, fileManager: fileManager))

        let entries = try pipeline.apply(plan, stableAt: date, fileManager: fileManager)
        #expect(fileManager.fileExists(atPath: plan.destinationURL.path))

        // Verify paths: beforePath should be in root, afterPath should be in dated subfolder
        let movedEntry = entries.first(where: { $0.kind == .moved })
        #expect((movedEntry?.beforePath ?? "").contains(root.path) == true)
        #expect((movedEntry?.afterPath ?? "").contains("2026-09") == true)

        // Undo by moving back (simulating the before path)
        let beforeURL = URL(fileURLWithPath: movedEntry?.beforePath ?? source.path)
        try fileManager.moveItem(at: plan.destinationURL, to: beforeURL)
        #expect(fileManager.fileExists(atPath: beforeURL.path))

        // Cleanup should remove empty date subfolder
        let processor = CleanupProcessor(watchFolder: root)
        let cleanupEntries = processor.removeEmptyManagedFolders(fileManager: fileManager)

        // Verify the empty date subfolder was removed
        #expect(fileManager.fileExists(atPath: plan.destinationDirectory.path) == false)
        #expect(cleanupEntries.contains { $0.kind == .folderRemoved } == true)
    }

    @Test
    func liveIngestRouteWithStableAtInDifferentMonthThanCreationDate() throws {
        let fileManager = FileManager.default
        let root = try makeTempRoot("live-ingest-stableat")
        defer { try? fileManager.removeItem(at: root) }

        let rules = [
            RoutingRule.custom(
                folderName: "Downloads",
                extensions: ["pdf"],
                subfolderPattern: .yearMonth
            ),
        ]
        let pipeline = IngestPipeline(watchFolder: root, rules: rules)

        let source = root.appendingPathComponent("document.pdf")
        try Data("pdf".utf8).write(to: source)

        // Set file creation date to January 2026
        let creationDate = Calendar.current.date(from: DateComponents(year: 2026, month: 1, day: 15))!
        try fileManager.setAttributes([.creationDate: creationDate], ofItemAtPath: source.path)

        // But pass a different stableAt date (September 2026) to simulate live ingest
        let stableAtDate = Calendar.current.date(from: DateComponents(year: 2026, month: 9, day: 24))!
        let plan = try #require(pipeline.plan(for: source, stableAt: stableAtDate, fileManager: fileManager))

        // Should use stableAt month, not creation date month
        #expect(plan.destinationDirectory.lastPathComponent == "2026-09")

        // Apply and verify it lands in the correct folder
        _ = try pipeline.apply(plan, stableAt: stableAtDate, fileManager: fileManager)
        #expect(fileManager.fileExists(atPath: plan.destinationURL.path))
        #expect(plan.destinationURL.path.contains("2026-09"))
    }

    @Test
    func organizeExistingPreviewShowsDestinationWithSubfolderAndCorrectIsNewFolder() throws {
        let fileManager = FileManager.default
        let root = try makeTempRoot("preview-subfolder")
        defer { try? fileManager.removeItem(at: root) }

        let rules = [
            RoutingRule.custom(
                folderName: "Documents",
                extensions: ["pdf"],
                subfolderPattern: .yearMonth
            ),
        ]
        let pipeline = IngestPipeline(watchFolder: root, rules: rules)

        // Create two files
        let file1 = root.appendingPathComponent("doc1.pdf")
        try Data("pdf1".utf8).write(to: file1)

        let file2 = root.appendingPathComponent("doc2.pdf")
        try Data("pdf2".utf8).write(to: file2)

        let scan = OrganizeExistingScan(
            eligible: [file1, file2],
            skipped: []
        )

        let preview = OrganizeExistingPreviewBuilder.build(scan: scan, pipeline: pipeline, fileManager: fileManager)

        // Should have one group for the dated subfolder destination
        #expect(preview.groups.count == 1)
        let group = try #require(preview.groups.first)

        // The destination should be the dated subfolder, not the parent category folder
        #expect(group.destinationDirectory.lastPathComponent.hasPrefix("202"))  // YYYY-MM format
        let parentFolder = group.destinationDirectory.deletingLastPathComponent()
        #expect(parentFolder.lastPathComponent == "Documents")

        // isNewFolder should be true since we haven't created the subfolder yet
        #expect(group.isNewFolder == true)

        // Both files should be in this group
        #expect(group.items.count == 2)
    }
}
