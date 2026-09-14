import Foundation
import Testing
@testable import IntakeCore

struct RenameWhenDownloadFinishesPreferenceTests {
    @Test
    func defaultsToOnWhenNothingIsStored() {
        #expect(RenameWhenDownloadFinishesPreference.isEnabled(nil))
        #expect(RenameWhenDownloadFinishesPreference.currentKey == "intake.renameWhenDownloadFinishes")
    }

    @Test
    func honorsAnExplicitOffValue() {
        #expect(RenameWhenDownloadFinishesPreference.isEnabled(false) == false)
        #expect(RenameWhenDownloadFinishesPreference.isEnabled(true))
    }

    @Test
    func roundTripsThroughUserDefaultsAndDefaultsMissingKeyToOn() {
        let suite = "intake.tests.rename-on-stable.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        #expect(RenameWhenDownloadFinishesPreference.isEnabled(in: defaults))

        RenameWhenDownloadFinishesPreference.persist(false, to: defaults)
        #expect(RenameWhenDownloadFinishesPreference.isEnabled(in: defaults) == false)

        RenameWhenDownloadFinishesPreference.persist(true, to: defaults)
        #expect(RenameWhenDownloadFinishesPreference.isEnabled(in: defaults))
    }
}

struct RenameOnStableCopyTests {
    @Test
    func settingsCopyMatchesLockedUX() {
        #expect(RenameOnStableCopy.toggleTitle == "Rename when download finishes")
        #expect(
            RenameOnStableCopy.footer
                == "Renames the file as soon as the download is stable — on this Mac only. Wait before organizing still delays filing into folders."
        )
        #expect(
            RenameOnStableCopy.compactFooter
                == "Local rename when the file is ready. Wait only delays filing."
        )
    }
}

struct LiveIngestPolicyTests {
    @Test
    func renameOnRunsBeforeWaitElapsesAndWaitOnlyGatesRouting() {
        let policy = LiveIngestPolicy(
            renameWhenDownloadFinishes: true,
            automaticOrganizing: true
        )
        let stableAt = Date()
        #expect(policy.shouldRenameOnStable)
        #expect(
            FileAgeGate.isEligible(stableAt: stableAt, wait: .twoHours, now: stableAt) == false
        )
        #expect(
            policy.shouldRoute(stableAt: stableAt, wait: .twoHours, now: stableAt) == false
        )
        #expect(
            policy.shouldRoute(
                stableAt: stableAt,
                wait: .twoHours,
                now: stableAt.addingTimeInterval(OrganizingWait.twoHours.seconds)
            )
        )
    }

    @Test
    func waitImmediatelyRenamesThenRoutesBackToBack() {
        let policy = LiveIngestPolicy(
            renameWhenDownloadFinishes: true,
            automaticOrganizing: true
        )
        let stableAt = Date()
        #expect(policy.shouldRenameOnStable)
        #expect(policy.shouldRoute(stableAt: stableAt, wait: .immediately, now: stableAt))
    }

    @Test
    func renameOffSkipsEarlyRenameAndStillRoutesAfterWait() {
        let policy = LiveIngestPolicy(
            renameWhenDownloadFinishes: false,
            automaticOrganizing: true
        )
        let stableAt = Date()
        #expect(policy.shouldRenameOnStable == false)
        #expect(policy.shouldRoute(stableAt: stableAt, wait: .twoHours, now: stableAt) == false)
        #expect(
            policy.shouldRoute(
                stableAt: stableAt,
                wait: .twoHours,
                now: stableAt.addingTimeInterval(OrganizingWait.twoHours.seconds)
            )
        )
        #expect(policy.legacyRenameWhenFiling)
    }

    @Test
    func automaticOrganizingOffStillRenamesInRootAndNeverAutoMoves() {
        let policy = LiveIngestPolicy(
            renameWhenDownloadFinishes: true,
            automaticOrganizing: false
        )
        let stableAt = Date()
        #expect(policy.shouldRenameOnStable)
        #expect(policy.shouldRoute(stableAt: stableAt, wait: .immediately, now: stableAt) == false)
        #expect(
            policy.shouldRoute(
                stableAt: stableAt,
                wait: .twoHours,
                now: stableAt.addingTimeInterval(OrganizingWait.twoHours.seconds)
            ) == false
        )
    }

    @Test
    func bothTogglesOffDoesNothingOnStable() {
        let policy = LiveIngestPolicy(
            renameWhenDownloadFinishes: false,
            automaticOrganizing: false
        )
        #expect(policy.shouldRenameOnStable == false)
        #expect(policy.shouldRoute(stableAt: Date(), wait: .immediately) == false)
        #expect(policy.legacyRenameWhenFiling == false)
    }
}

struct IngestPipelineSplitTests {
    @Test
    func renameStageNormalizesWatchRootBeforeWaitAndDoesNotCreateFolders() throws {
        let fileManager = FileManager.default
        let root = try makeTempWatchFolder()
        defer { try? fileManager.removeItem(at: root) }

        let source = root.appendingPathComponent("Quarterly_Report.pdf")
        try Data("pdf".utf8).write(to: source)

        let pipeline = IngestPipeline(watchFolder: root)
        let renamed = try pipeline.applyRenameInPlace(at: source, fileManager: fileManager)

        #expect(renamed.url.lastPathComponent == "Quarterly Report.pdf")
        #expect(renamed.entries.map(\.kind) == [.renamed])
        #expect(renamed.entries.first?.url == renamed.url)
        #expect(fileManager.fileExists(atPath: source.path) == false)
        #expect(fileManager.fileExists(atPath: renamed.url.path))
        #expect(renamed.url.deletingLastPathComponent().standardizedFileURL == root.standardizedFileURL)
        #expect(
            fileManager.fileExists(
                atPath: root.appendingPathComponent("Documents", isDirectory: true).path
            ) == false
        )
    }

    @Test
    func routeStageAfterWaitPreservesNormalizedNameUnlessCollision() throws {
        let fileManager = FileManager.default
        let root = try makeTempWatchFolder()
        defer { try? fileManager.removeItem(at: root) }

        let source = root.appendingPathComponent("Quarterly_Report.pdf")
        try Data("pdf".utf8).write(to: source)
        let pipeline = IngestPipeline(watchFolder: root)
        let renamed = try pipeline.applyRenameInPlace(at: source, fileManager: fileManager)

        let documents = root.appendingPathComponent("Documents", isDirectory: true)
        try fileManager.createDirectory(at: documents, withIntermediateDirectories: true)
        let occupant = documents.appendingPathComponent("Quarterly Report.pdf")
        try Data("existing".utf8).write(to: occupant)

        let routed = try pipeline.applyRoute(at: renamed.url, fileManager: fileManager)
        let collision = documents.appendingPathComponent("Quarterly Report 2.pdf")
        #expect(routed.map(\.kind) == [.moved])
        #expect(routed.first?.destinationFolder == "Documents")
        #expect(routed.first?.fileName == "Quarterly Report 2.pdf")
        #expect(fileManager.fileExists(atPath: occupant.path))
        #expect(fileManager.fileExists(atPath: collision.path))
        #expect(fileManager.fileExists(atPath: renamed.url.path) == false)
    }

    @Test
    func immediatelyRenameThenRouteLeavesNoMultiHourGap() throws {
        let fileManager = FileManager.default
        let root = try makeTempWatchFolder()
        defer { try? fileManager.removeItem(at: root) }

        let source = root.appendingPathComponent("Team_Notes.md")
        try Data("notes".utf8).write(to: source)
        let pipeline = IngestPipeline(watchFolder: root)

        let renamed = try pipeline.applyRenameInPlace(at: source, fileManager: fileManager)
        let routed = try pipeline.applyRoute(at: renamed.url, fileManager: fileManager)
        let destination = root
            .appendingPathComponent("Documents", isDirectory: true)
            .appendingPathComponent("Team Notes.md")

        #expect(renamed.entries.map(\.kind) == [.renamed])
        #expect(routed.map(\.kind) == [.moved])
        #expect(fileManager.fileExists(atPath: destination.path))
        #expect(fileManager.fileExists(atPath: renamed.url.path) == false)
    }

    @Test
    func routeOnlyWithoutEarlyRenameKeepsNoisyName() throws {
        let fileManager = FileManager.default
        let root = try makeTempWatchFolder()
        defer { try? fileManager.removeItem(at: root) }

        let source = root.appendingPathComponent("Team_Notes.md")
        try Data("notes".utf8).write(to: source)
        let pipeline = IngestPipeline(watchFolder: root)
        let routed = try pipeline.applyRoute(at: source, fileManager: fileManager)

        #expect(routed.map(\.kind) == [.moved])
        #expect(
            fileManager.fileExists(
                atPath: root
                    .appendingPathComponent("Documents", isDirectory: true)
                    .appendingPathComponent("Team_Notes.md").path
            )
        )
        #expect(fileManager.fileExists(atPath: source.path) == false)
    }

    @Test
    func combinedApplyStillRenamesWhenFilingIfEarlyRenameWasOff() throws {
        let fileManager = FileManager.default
        let root = try makeTempWatchFolder()
        defer { try? fileManager.removeItem(at: root) }

        let source = root.appendingPathComponent("Team_Notes.md")
        try Data("notes".utf8).write(to: source)
        let pipeline = IngestPipeline(watchFolder: root)
        guard let plan = pipeline.plan(for: source) else {
            Issue.record("expected an ingest plan")
            return
        }
        let entries = try pipeline.apply(plan, fileManager: fileManager)
        #expect(entries.map(\.kind) == [.renamed, .moved])
        #expect(
            fileManager.fileExists(
                atPath: root
                    .appendingPathComponent("Documents", isDirectory: true)
                    .appendingPathComponent("Team Notes.md").path
            )
        )
    }

    @Test
    func renameInPlaceUniquesAgainstWatchRootAndSkipsCategoryFolders() throws {
        let fileManager = FileManager.default
        let root = try makeTempWatchFolder()
        defer { try? fileManager.removeItem(at: root) }

        let existing = root.appendingPathComponent("Quarterly Report.pdf")
        let source = root.appendingPathComponent("Quarterly_Report.pdf")
        try Data("keep".utf8).write(to: existing)
        try Data("new".utf8).write(to: source)

        let documents = root.appendingPathComponent("Documents", isDirectory: true)
        try fileManager.createDirectory(at: documents, withIntermediateDirectories: true)
        let nested = documents.appendingPathComponent("already_filed.pdf")
        try Data("nested".utf8).write(to: nested)

        let pipeline = IngestPipeline(watchFolder: root)
        let renamed = try pipeline.applyRenameInPlace(at: source, fileManager: fileManager)
        #expect(renamed.url.lastPathComponent == "Quarterly Report 2.pdf")
        #expect(renamed.url.deletingLastPathComponent().standardizedFileURL == root.standardizedFileURL)
        #expect(fileManager.fileExists(atPath: existing.path))

        let ignored = try pipeline.applyRenameInPlace(at: nested, fileManager: fileManager)
        #expect(ignored.entries.isEmpty)
        #expect(ignored.url == nested)
        #expect(fileManager.fileExists(atPath: nested.path))
        #expect(nested.lastPathComponent == "already_filed.pdf")
    }

    private func makeTempWatchFolder() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "intake-rename-on-stable-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }
}

struct OrganizeExistingSplitProcessorTests {
    @Test
    func renameInPlaceModeStaysInRootAndRouteOnlyMovesAfter() throws {
        let fileManager = FileManager.default
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "intake-organize-split-\(UUID().uuidString)",
            isDirectory: true
        )
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: root) }

        let source = root.appendingPathComponent("Invoice_Q1.pdf")
        try Data("pdf".utf8).write(to: source)
        let processor = OrganizeExistingProcessor(watchFolder: root)

        switch processor.processOne(source, mode: .renameInPlace, fileManager: fileManager) {
        case .organized(let entries):
            #expect(entries.map(\.kind) == [.renamed])
            #expect(entries.first?.fileName == "Invoice Q1.pdf")
            #expect(
                fileManager.fileExists(atPath: root.appendingPathComponent("Invoice Q1.pdf").path)
            )
            #expect(
                fileManager.fileExists(
                    atPath: root.appendingPathComponent("Documents", isDirectory: true).path
                ) == false
            )
        default:
            Issue.record("expected rename-in-place to organize with a renamed entry")
            return
        }

        let renamedURL = root.appendingPathComponent("Invoice Q1.pdf")
        switch processor.processOne(renamedURL, mode: .routeOnly, fileManager: fileManager) {
        case .organized(let entries):
            #expect(entries.map(\.kind) == [.moved])
            #expect(entries.first?.destinationFolder == "Documents")
            #expect(entries.first?.fileName == "Invoice Q1.pdf")
        default:
            Issue.record("expected route-only to move the already-renamed file")
        }
    }

    @Test
    func ignoredPartialsAreNotRenamedOnStable() throws {
        let fileManager = FileManager.default
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "intake-rename-ignore-\(UUID().uuidString)",
            isDirectory: true
        )
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: root) }

        let partial = root.appendingPathComponent("movie.mp4.crdownload")
        try Data("partial".utf8).write(to: partial)
        let processor = OrganizeExistingProcessor(watchFolder: root)
        switch processor.processOne(partial, mode: .renameInPlace, fileManager: fileManager) {
        case .skipped:
            #expect(fileManager.fileExists(atPath: partial.path))
            #expect(partial.lastPathComponent == "movie.mp4.crdownload")
        default:
            Issue.record("partial downloads must stay ignored during rename-on-stable")
        }
    }
}

struct OpenRouterFolderOnlyTests {
    @Test
    func openRouterPromptAsksForAFolderNotARename() throws {
        let data = try OpenRouterRequestBuilder.body(
            model: OpenRouterConfiguration.defaultModel,
            fileName: "Quarterly_Report.pdf",
            folders: ["Documents", "Other"]
        )
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let messages = object?["messages"] as? [[String: Any]]
        let system = messages?.first?["content"] as? String ?? ""
        #expect(system.contains("destination folder"))
        #expect(system.contains("File name") == false)
        #expect(system.localizedCaseInsensitiveContains("rename") == false)
        let user = messages?.last?["content"] as? String ?? ""
        #expect(user == "File name: Quarterly_Report.pdf")
    }
}
