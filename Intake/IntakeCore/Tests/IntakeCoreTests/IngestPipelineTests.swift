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
