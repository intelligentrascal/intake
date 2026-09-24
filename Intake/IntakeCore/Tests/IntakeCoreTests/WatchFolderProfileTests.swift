import Foundation
import Testing
@testable import IntakeCore

private func makeDefaults(_ label: String) -> (UserDefaults, String) {
    let suite = "intake.tests.\(label)-\(UUID().uuidString)"
    return (UserDefaults(suiteName: suite)!, suite)
}

private func makeTempDirectory(_ label: String) throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("intake-\(label)-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

// MARK: - Profiles and migration

struct WatchFolderProfileMigrationTests {
    @Test
    func migratesThe12SingleFolderSettingsIntoProfileOne() throws {
        let (defaults, suite) = makeDefaults("profile-migrate")
        defer { defaults.removePersistentDomain(forName: suite) }
        let bookmark = Data("bookmark".utf8)
        defaults.set(bookmark, forKey: WatchFolderProfileStore.legacyBookmarkKey)
        AutomaticOrganizingPreference.persist(false, to: defaults)
        RenameWhenDownloadFinishesPreference.persist(false, to: defaults)
        OrganizingWait.persist(.oneHour, to: defaults)

        let folder = URL(fileURLWithPath: "/Users/demo/Downloads", isDirectory: true)
        var resolverCalls = 0
        let profiles = WatchFolderProfileStore.load(from: defaults) {
            resolverCalls += 1
            return folder
        }

        #expect(resolverCalls == 1)
        #expect(profiles.count == 1)
        let primary = try #require(profiles.first)
        #expect(primary.id == WatchFolderProfile.primaryID)
        #expect(primary.path == "/Users/demo/Downloads")
        #expect(primary.displayName == "Downloads")
        #expect(primary.bookmark == bookmark)
        #expect(primary.automaticOrganizing == false)
        #expect(primary.renameWhenDownloadFinishes == false)
        #expect(primary.organizingWait == .oneHour)
        #expect(primary.isPaused == false)
        // Saved, so the next launch reads it back instead of migrating again.
        #expect(defaults.data(forKey: WatchFolderProfileStore.defaultsKey) != nil)
        let reloaded = WatchFolderProfileStore.load(from: defaults) {
            resolverCalls += 1
            return URL(fileURLWithPath: "/elsewhere")
        }
        #expect(resolverCalls == 1)
        #expect(reloaded == profiles)
    }

    @Test
    func freshInstallGetsDownloadsWithProductDefaults() throws {
        let (defaults, suite) = makeDefaults("profile-fresh")
        defer { defaults.removePersistentDomain(forName: suite) }
        let profiles = WatchFolderProfileStore.load(from: defaults) {
            URL(fileURLWithPath: "/Users/demo/Downloads", isDirectory: true)
        }
        let primary = try #require(profiles.first)
        #expect(primary.bookmark == nil)
        #expect(primary.automaticOrganizing)
        #expect(primary.renameWhenDownloadFinishes)
        #expect(primary.organizingWait == .twoHours)
        #expect(primary.isOrganizing)
    }

    @Test
    func legacyPausedKeyMigratesAsAutomaticOrganizingOff() throws {
        let (defaults, suite) = makeDefaults("profile-paused")
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(true, forKey: AutomaticOrganizingPreference.legacyPausedKey)
        let profiles = WatchFolderProfileStore.load(from: defaults) {
            URL(fileURLWithPath: "/tmp/Downloads")
        }
        #expect(profiles.first?.automaticOrganizing == false)
        #expect(profiles.first?.isOrganizing == false)
    }

    @Test
    func migrationMovesTheWaitQueueToProfileOne() throws {
        let (defaults, suite) = makeDefaults("profile-queue")
        defer { defaults.removePersistentDomain(forName: suite) }
        let pending = PendingStableFile(
            url: URL(fileURLWithPath: "/Users/demo/Downloads/report.pdf"),
            stableAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        WaitingForAgeStore.save([pending], to: defaults)

        _ = WatchFolderProfileStore.load(from: defaults) {
            URL(fileURLWithPath: "/Users/demo/Downloads")
        }

        #expect(defaults.data(forKey: WaitingForAgeStore.defaultsKey) == nil)
        let migrated = WaitingForAgeStore.load(from: defaults, profileID: WatchFolderProfile.primaryID)
        #expect(migrated == [pending])
    }

    @Test
    func roundTripsAnOrderedProfileList() throws {
        let profiles = [
            WatchFolderProfile(id: WatchFolderProfile.primaryID, path: "/Users/demo/Downloads"),
            WatchFolderProfile(
                id: "folder-desktop",
                displayName: "My Desktop",
                path: "/Users/demo/Desktop",
                bookmark: Data([1, 2, 3]),
                renameWhenDownloadFinishes: false,
                organizingWait: .immediately,
                automaticOrganizing: true,
                isPaused: true
            ),
        ]
        let decoded = try WatchFolderProfileStore.decode(WatchFolderProfileStore.encode(profiles))
        #expect(decoded == profiles)
        #expect(decoded.map(\.id) == [WatchFolderProfile.primaryID, "folder-desktop"])
        #expect(decoded[1].isOrganizing == false)
    }

    @Test
    func decodesAProfileMissingSettingsWithDefaults() throws {
        let json = """
        [{"id": "folder-x", "path": "/Users/demo/Screenshots", "organizingWait": 12345}]
        """
        let decoded = try WatchFolderProfileStore.decode(Data(json.utf8))
        let profile = try #require(decoded.first)
        #expect(profile.displayName == "Screenshots")
        #expect(profile.renameWhenDownloadFinishes)
        #expect(profile.automaticOrganizing)
        #expect(profile.isPaused == false)
        // An unknown wait falls back to the default rather than failing.
        #expect(profile.organizingWait == .twoHours)
    }

    @Test
    func pausedProfileStillRenamesButDoesNotRoute() {
        let profile = WatchFolderProfile(path: "/tmp/Desktop", isPaused: true)
        #expect(profile.liveIngestPolicy.shouldRenameOnStable)
        #expect(profile.liveIngestPolicy.shouldRoute(stableAt: .distantPast, wait: .immediately) == false)
    }
}

// MARK: - Per-profile Wait queue

struct PerProfileWaitingQueueTests {
    @Test
    func queuesAreKeptPerProfile() {
        let (defaults, suite) = makeDefaults("queue-per-profile")
        defer { defaults.removePersistentDomain(forName: suite) }
        let downloads = PendingStableFile(url: URL(fileURLWithPath: "/tmp/Downloads/a.pdf"), stableAt: Date(timeIntervalSince1970: 1))
        let desktop = PendingStableFile(url: URL(fileURLWithPath: "/tmp/Desktop/b.png"), stableAt: Date(timeIntervalSince1970: 2))
        WaitingForAgeStore.save([downloads], to: defaults, profileID: "primary")
        WaitingForAgeStore.save([desktop], to: defaults, profileID: "desktop")

        #expect(WaitingForAgeStore.load(from: defaults, profileID: "primary") == [downloads])
        #expect(WaitingForAgeStore.load(from: defaults, profileID: "desktop") == [desktop])

        WaitingForAgeStore.clear(in: defaults, profileID: "desktop")
        #expect(WaitingForAgeStore.load(from: defaults, profileID: "desktop").isEmpty)
        #expect(WaitingForAgeStore.load(from: defaults, profileID: "primary") == [downloads])
        #expect(WaitingForAgeStore.defaultsKey(forProfileID: "desktop") == "intake.waitingForAge.desktop")
    }

    @Test
    func legacyMigrationNeverOverwritesAnExistingProfileQueue() {
        let (defaults, suite) = makeDefaults("queue-no-overwrite")
        defer { defaults.removePersistentDomain(forName: suite) }
        let legacy = PendingStableFile(url: URL(fileURLWithPath: "/tmp/old.pdf"), stableAt: Date(timeIntervalSince1970: 1))
        let current = PendingStableFile(url: URL(fileURLWithPath: "/tmp/new.pdf"), stableAt: Date(timeIntervalSince1970: 2))
        WaitingForAgeStore.save([legacy], to: defaults)
        WaitingForAgeStore.save([current], to: defaults, profileID: "primary")

        WaitingForAgeStore.migrateLegacyQueue(to: "primary", in: defaults)

        #expect(WaitingForAgeStore.load(from: defaults, profileID: "primary") == [current])
        #expect(defaults.data(forKey: WaitingForAgeStore.defaultsKey) == nil)
    }

    @Test
    func restoreExistingReadsOnlyThatProfilesQueue() throws {
        let (defaults, suite) = makeDefaults("queue-restore")
        defer { defaults.removePersistentDomain(forName: suite) }
        let root = URL(fileURLWithPath: "/tmp/watch-desktop")
        let item = PendingStableFile(url: root.appendingPathComponent("shot.png"), stableAt: Date(timeIntervalSince1970: 5))
        WaitingForAgeStore.save([item], to: defaults, profileID: "desktop")
        let restored = WaitingForAgeStore.restoreExisting(
            from: defaults,
            profileID: "desktop",
            watchRoot: root
        ) { _ in true }
        #expect(restored.map(\.url.lastPathComponent) == ["shot.png"])
        #expect(WaitingForAgeStore.restoreExisting(from: defaults, profileID: "primary", watchRoot: root) { _ in true }.isEmpty)
    }
}

// MARK: - Rule scope

struct RuleScopeTests {
    @Test
    func a13RuleWithNoScopeKeyDecodesAsAllWatchFolders() throws {
        let legacyJSON = """
        {
            "id": "custom-1",
            "folderName": "Receipts",
            "systemImage": "folder.badge.plus",
            "extensions": ["pdf"],
            "conditions": [],
            "isEnabled": true,
            "isBuiltIn": false,
            "subfolderPattern": "year"
        }
        """
        let decoded = try JSONDecoder().decode(RoutingRule.self, from: Data(legacyJSON.utf8))
        #expect(decoded.scope == .allWatchFolders)
        #expect(decoded.subfolderPattern == .year)
    }

    @Test
    func scopedRulesRoundTripThroughPersistence() throws {
        let rules = RuleMutation.addingCustom(
            DefaultTaxonomy.rules,
            folderName: "Screenshots",
            extensions: ["png"],
            scope: .watchFolders(["desktop", "screens"])
        )
        let decoded = try RulePersistence.decode(RulePersistence.encode(rules))
        #expect(decoded == rules)
        #expect(decoded.last?.scope == .watchFolders(["desktop", "screens"]))
        #expect(decoded.first?.scope == .allWatchFolders)
    }

    @Test
    func scopedFilteringKeepsOrderAndDropsOtherFolders() {
        let screenshots = RoutingRule.custom(
            folderName: "Screenshots",
            extensions: ["png"],
            id: "shots",
            scope: .watchFolders(["desktop"])
        )
        let rules = [screenshots] + DefaultTaxonomy.rules
        let forDesktop = RoutingRule.scoped(rules, toWatchFolder: "desktop")
        let forDownloads = RoutingRule.scoped(rules, toWatchFolder: WatchFolderProfile.primaryID)
        #expect(forDesktop.first?.id == "shots")
        #expect(forDesktop.count == rules.count)
        #expect(forDownloads.contains { $0.id == "shots" } == false)
        #expect(forDownloads.map(\.id) == DefaultTaxonomy.rules.map(\.id))
    }

    @Test
    func removingAWatchFolderNarrowsOrDisablesScopedRules() {
        let shared = RoutingRule.custom(folderName: "Shared", extensions: ["key"], id: "shared", scope: .watchFolders(["desktop", "screens"]))
        let only = RoutingRule.custom(folderName: "Only", extensions: ["heic"], id: "only", scope: .watchFolders(["desktop"]))
        let all = RoutingRule.custom(folderName: "All", extensions: ["zip"], id: "all")
        let result = RuleMutation.removingWatchFolder("desktop", from: [shared, only, all])
        #expect(result[0].scope == .watchFolders(["screens"]))
        #expect(result[0].isEnabled)
        // Never silently widened to every folder while enabled.
        #expect(result[1].scope == .allWatchFolders)
        #expect(result[1].isEnabled == false)
        #expect(result[2] == all)
    }

    @Test
    func rulesInDisjointScopesNeitherShadowNorConflict() {
        let downloadsPDF = RoutingRule.custom(folderName: "Bank", extensions: ["pdf"], id: "bank", scope: .watchFolders(["primary"]))
        let desktopPDF = RoutingRule.custom(folderName: "Notes", extensions: ["pdf"], id: "notes", scope: .watchFolders(["desktop"]))
        #expect(RuleConflict.unreachableRules(in: [downloadsPDF, desktopPDF]).isEmpty)
        #expect(RuleConflict.inRules([downloadsPDF, desktopPDF]).isEmpty)

        // An all-folders rule still shadows a later scoped one.
        let everywhere = RoutingRule.custom(folderName: "Docs", extensions: ["pdf"], id: "docs")
        let unreachable = RuleConflict.unreachableRules(in: [everywhere, desktopPDF])
        #expect(unreachable.map(\.ruleID) == ["notes"])
    }

    @Test
    func updatingARuleKeepsItsScopeUnlessGivenOne() {
        let rule = RoutingRule.custom(folderName: "Shots", extensions: ["png"], id: "shots", scope: .watchFolders(["desktop"]))
        let kept = RuleMutation.updating([rule], id: "shots", folderName: "Shots", extensions: ["png"], isEnabled: true)
        #expect(kept[0].scope == .watchFolders(["desktop"]))
        let widened = RuleMutation.updating([rule], id: "shots", folderName: "Shots", extensions: ["png"], isEnabled: true, scope: .allWatchFolders)
        #expect(widened[0].scope == .allWatchFolders)
    }
}

// MARK: - Per-profile pipelines

struct PerProfileIngestPipelineTests {
    @Test
    func eachProfileFilesIntoItsOwnCategoryFoldersWithScopedRules() throws {
        let fileManager = FileManager.default
        let base = try makeTempDirectory("profiles")
        defer { try? fileManager.removeItem(at: base) }
        let downloads = base.appendingPathComponent("Downloads", isDirectory: true)
        let desktop = base.appendingPathComponent("Desktop", isDirectory: true)
        try fileManager.createDirectory(at: downloads, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: desktop, withIntermediateDirectories: true)

        let rules = RuleMutation.addingCustom(
            DefaultTaxonomy.rules,
            folderName: "Screenshots",
            extensions: ["png"],
            scope: .watchFolders(["desktop"])
        )
        // Scoped rule is listed last, but only competes in Desktop — move it first there.
        let ordered = [rules.last!] + rules.dropLast()
        let downloadsPipeline = IngestPipeline(
            watchFolder: downloads,
            rules: RoutingRule.scoped(ordered, toWatchFolder: WatchFolderProfile.primaryID)
        )
        let desktopPipeline = IngestPipeline(
            watchFolder: desktop,
            rules: RoutingRule.scoped(ordered, toWatchFolder: "desktop")
        )

        let downloadsShot = downloads.appendingPathComponent("chart.png")
        let desktopShot = desktop.appendingPathComponent("Screen Shot.png")
        let desktopPDF = desktop.appendingPathComponent("notes.pdf")
        for url in [downloadsShot, desktopShot, desktopPDF] {
            try Data("content".utf8).write(to: url)
        }

        let downloadsEntries = try downloadsPipeline.apply(try #require(downloadsPipeline.plan(for: downloadsShot)))
        let shotEntries = try desktopPipeline.apply(try #require(desktopPipeline.plan(for: desktopShot)))
        let pdfEntries = try desktopPipeline.apply(try #require(desktopPipeline.plan(for: desktopPDF)))

        // Rules scoped to Desktop don't touch Downloads.
        #expect(downloadsEntries.last?.destinationFolder == "Images")
        #expect(fileManager.fileExists(atPath: downloads.appendingPathComponent("Images/Chart.png").path))
        #expect(fileManager.fileExists(atPath: downloads.appendingPathComponent("Screenshots").path) == false)
        // Desktop files land in Desktop category folders.
        #expect(shotEntries.last?.destinationFolder == "Screenshots")
        #expect(fileManager.fileExists(atPath: desktop.appendingPathComponent("Screenshots/Screen Shot.png").path))
        #expect(pdfEntries.last?.destinationFolder == "Documents")
        #expect(fileManager.fileExists(atPath: desktop.appendingPathComponent("Documents/Notes.pdf").path))
        #expect(fileManager.fileExists(atPath: downloads.appendingPathComponent("Documents").path) == false)
    }

    @Test
    func aPipelineIgnoresFilesFromAnotherWatchFolder() throws {
        let fileManager = FileManager.default
        let base = try makeTempDirectory("profiles-foreign")
        defer { try? fileManager.removeItem(at: base) }
        let downloads = base.appendingPathComponent("Downloads", isDirectory: true)
        let desktop = base.appendingPathComponent("Desktop", isDirectory: true)
        try fileManager.createDirectory(at: downloads, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: desktop, withIntermediateDirectories: true)
        let desktopFile = desktop.appendingPathComponent("a.pdf")
        try Data("x".utf8).write(to: desktopFile)

        let downloadsPipeline = IngestPipeline(watchFolder: downloads)
        #expect(downloadsPipeline.plan(for: desktopFile) == nil)
        #expect(try downloadsPipeline.applyRoute(at: desktopFile).isEmpty)
        #expect(fileManager.fileExists(atPath: desktopFile.path))
    }
}

// MARK: - Validation

struct WatchFolderValidationTests {
    let downloads = WatchFolderValidation.ExistingFolder(
        id: "primary",
        displayName: "Downloads",
        url: URL(fileURLWithPath: "/Users/demo/Downloads", isDirectory: true),
        managedFolderNames: DefaultTaxonomy.managedFolderNames
    )

    @Test
    func acceptsASeparateFolder() {
        let desktop = URL(fileURLWithPath: "/Users/demo/Desktop", isDirectory: true)
        #expect(WatchFolderValidation.validate(desktop, existing: [downloads]) == nil)
        // A sibling whose name merely starts the same isn't "inside".
        let lookalike = URL(fileURLWithPath: "/Users/demo/Downloads Old", isDirectory: true)
        #expect(WatchFolderValidation.validate(lookalike, existing: [downloads]) == nil)
    }

    @Test
    func rejectsTheSameFolderIgnoringCase() {
        let same = URL(fileURLWithPath: "/Users/demo/downloads/", isDirectory: true)
        #expect(WatchFolderValidation.validate(same, existing: [downloads]) == .sameAsExisting("Downloads"))
    }

    @Test
    func rejectsAFolderInsideAnotherWatchFolder() {
        let inside = URL(fileURLWithPath: "/Users/demo/Downloads/Projects", isDirectory: true)
        #expect(WatchFolderValidation.validate(inside, existing: [downloads]) == .insideExisting("Downloads"))
    }

    @Test
    func rejectsAFolderContainingAnotherWatchFolder() {
        let parent = URL(fileURLWithPath: "/Users/demo", isDirectory: true)
        #expect(WatchFolderValidation.validate(parent, existing: [downloads]) == .containsExisting("Downloads"))
    }

    @Test
    func rejectsManagedCategoryFoldersIncludingDateSubfolders() {
        let images = URL(fileURLWithPath: "/Users/demo/Downloads/Images", isDirectory: true)
        let yearly = URL(fileURLWithPath: "/Users/demo/Downloads/images/2026", isDirectory: true)
        #expect(WatchFolderValidation.validate(images, existing: [downloads])
            == .managedFolder(folderName: "Images", watchFolderName: "Downloads"))
        #expect(WatchFolderValidation.validate(yearly, existing: [downloads])
            == .managedFolder(folderName: "Images", watchFolderName: "Downloads"))
    }

    @Test
    func replacingAFolderSkipsItselfButNotItsCategoryFolders() {
        let sameAgain = URL(fileURLWithPath: "/Users/demo/Downloads", isDirectory: true)
        let subfolder = URL(fileURLWithPath: "/Users/demo/Downloads/Projects", isDirectory: true)
        let ownCategory = URL(fileURLWithPath: "/Users/demo/Downloads/Documents", isDirectory: true)
        #expect(WatchFolderValidation.validate(sameAgain, existing: [downloads], replacing: "primary") == nil)
        #expect(WatchFolderValidation.validate(subfolder, existing: [downloads], replacing: "primary") == nil)
        #expect(WatchFolderValidation.validate(ownCategory, existing: [downloads], replacing: "primary")
            == .managedFolder(folderName: "Documents", watchFolderName: "Downloads"))
    }

    @Test
    func customRuleFoldersCountAsManaged() {
        let custom = WatchFolderValidation.ExistingFolder(
            id: "desktop",
            displayName: "Desktop",
            url: URL(fileURLWithPath: "/Users/demo/Desktop", isDirectory: true),
            managedFolderNames: DefaultTaxonomy.managedFolderNames.union(["Screenshots"])
        )
        let shots = URL(fileURLWithPath: "/Users/demo/Desktop/Screenshots", isDirectory: true)
        #expect(WatchFolderValidation.validate(shots, existing: [downloads, custom])
            == .managedFolder(folderName: "Screenshots", watchFolderName: "Desktop"))
    }

    @Test
    func softCapStopsASixthFolderButNotAChange() {
        let existing = (0..<WatchFolderProfile.softCap).map { index in
            WatchFolderValidation.ExistingFolder(
                id: "f\(index)",
                displayName: "F\(index)",
                url: URL(fileURLWithPath: "/Users/demo/F\(index)", isDirectory: true),
                managedFolderNames: []
            )
        }
        let another = URL(fileURLWithPath: "/Users/demo/Other", isDirectory: true)
        #expect(WatchFolderProfile.softCap == 5)
        #expect(WatchFolderValidation.validate(another, existing: existing) == .limitReached(5))
        #expect(WatchFolderValidation.validate(another, existing: existing, replacing: "f0") == nil)
        #expect(WatchFolderValidation.validate(another, existing: Array(existing.prefix(4))) == nil)
    }

    @Test
    func resolvesSymlinksBeforeComparing() throws {
        let fileManager = FileManager.default
        let base = try makeTempDirectory("validate-symlink")
        defer { try? fileManager.removeItem(at: base) }
        let real = base.appendingPathComponent("Real", isDirectory: true)
        try fileManager.createDirectory(at: real, withIntermediateDirectories: true)
        let link = base.appendingPathComponent("Link")
        try fileManager.createSymbolicLink(at: link, withDestinationURL: real)
        let existing = WatchFolderValidation.ExistingFolder(id: "a", displayName: "Real", url: real, managedFolderNames: [])
        #expect(WatchFolderValidation.validate(link, existing: [existing]) == .sameAsExisting("Real"))
    }

    @Test
    func problemsHavePlainLanguageMessages() {
        #expect(WatchFolderValidation.Problem.limitReached(5).message.contains("up to 5"))
        #expect(WatchFolderValidation.Problem.insideExisting("Downloads").message.contains("inside “Downloads”"))
    }
}

// MARK: - Screenshot location and status

struct ScreenshotLocationTests {
    let home = URL(fileURLWithPath: "/Users/demo", isDirectory: true)

    @Test
    func fallsBackToDesktop() {
        #expect(ScreenshotLocation.resolve(storedLocation: nil, homeDirectory: home).path == "/Users/demo/Desktop")
        #expect(ScreenshotLocation.resolve(storedLocation: "  ", homeDirectory: home).path == "/Users/demo/Desktop")
        #expect(ScreenshotLocation.resolve(storedLocation: "relative", homeDirectory: home).path == "/Users/demo/Desktop")
    }

    @Test
    func usesTheSystemLocationExpandingTilde() {
        #expect(ScreenshotLocation.resolve(storedLocation: "~/Pictures/Screenshots", homeDirectory: home).path
            == "/Users/demo/Pictures/Screenshots")
        #expect(ScreenshotLocation.resolve(storedLocation: "/Volumes/Shots/", homeDirectory: home).path
            == "/Volumes/Shots")
    }
}

struct WatchFolderStatusTests {
    @Test
    func aSingleFolderReadsExactlyLike12() {
        let watching = WatchFolderStatus.summarize([.init(displayName: "Downloads", isOrganizing: true, accessLost: false)])
        #expect(watching.title == "Watching")
        #expect(watching.subtitle == "New files in Downloads")
        #expect(watching.accessibilityLabel == "Intake watching")
        #expect(watching.isPaused == false)

        let paused = WatchFolderStatus.summarize([.init(displayName: "Downloads", isOrganizing: false, accessLost: false)])
        #expect(paused.title == "Paused")
        #expect(paused.subtitle == "Organizing is paused · Downloads")
        #expect(paused.accessibilityLabel == "Intake paused")
        #expect(paused.isPaused)

        let lost = WatchFolderStatus.summarize([.init(displayName: "Downloads", isOrganizing: true, accessLost: true)])
        #expect(lost.title == "Attention")
        #expect(lost.subtitle == "Needs folder access")
    }

    @Test
    func severalFoldersAreSummarized() {
        let status = WatchFolderStatus.summarize([
            .init(displayName: "Downloads", isOrganizing: true, accessLost: false),
            .init(displayName: "Desktop", isOrganizing: true, accessLost: false),
            .init(displayName: "Screenshots", isOrganizing: false, accessLost: false),
        ])
        #expect(status.title == "Watching 2")
        #expect(status.subtitle == "New files in Downloads, Desktop · 1 paused")
        #expect(status.watchingCount == 2)
        #expect(status.isPaused == false)

        let allPaused = WatchFolderStatus.summarize([
            .init(displayName: "Downloads", isOrganizing: false, accessLost: false),
            .init(displayName: "Desktop", isOrganizing: false, accessLost: false),
        ])
        #expect(allPaused.title == "Paused")
        #expect(allPaused.isPaused)

        let oneLost = WatchFolderStatus.summarize([
            .init(displayName: "Downloads", isOrganizing: true, accessLost: false),
            .init(displayName: "Desktop", isOrganizing: true, accessLost: true),
        ])
        #expect(oneLost.title == "Attention")
        #expect(oneLost.subtitle == "Desktop needs folder access")
        // The healthy folder keeps running.
        #expect(oneLost.watchingCount == 1)
        #expect(oneLost.isPaused == false)
    }
}

// MARK: - Activity watch folder id

struct ActivityWatchFolderTests {
    @Test
    func olderRowsWithoutAnIDCountAsProfileOne() throws {
        let legacyJSON = """
        [{
            "id": "6F9619FF-8B86-D011-B42D-00C04FC964FF",
            "date": "2026-09-01T10:00:00Z",
            "kind": "moved",
            "detail": "Moved a.pdf to Documents",
            "fileName": "a.pdf",
            "destinationFolder": "Documents"
        }]
        """
        let decoded = try ActivityLog.decode(Data(legacyJSON.utf8))
        let entry = try #require(decoded.first)
        #expect(entry.watchFolderID == nil)
        #expect(entry.effectiveWatchFolderID == WatchFolderProfile.primaryID)
    }

    @Test
    func watchFolderIDRoundTripsAndFilters() throws {
        let downloads = ActivityEntry(kind: .moved, detail: "Moved a", fileName: "a.pdf")
        let desktop = ActivityEntry(kind: .renamed, detail: "Renamed b", fileName: "b.png", watchFolderID: "desktop")
        let decoded = try ActivityLog.decode(ActivityLog.encode([desktop, downloads]))
        #expect(decoded[0].watchFolderID == "desktop")

        #expect(ActivityLog.filtered(decoded, watchFolderID: nil).count == 2)
        #expect(ActivityLog.filtered(decoded, watchFolderID: "desktop").map(\.fileName) == ["b.png"])
        #expect(ActivityLog.filtered(decoded, watchFolderID: WatchFolderProfile.primaryID).map(\.fileName) == ["a.pdf"])
    }
}
