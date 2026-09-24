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

        let entries = try pipeline.apply(plan, fileManager: fileManager)
        #expect(fileManager.fileExists(atPath: source.path) == false)
        #expect(fileManager.fileExists(atPath: plan.destinationURL.path))
        #expect(entries.map(\.kind) == [.renamed, .moved])
        #expect(plan.category == .documents)
    }
}
