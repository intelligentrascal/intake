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

struct InstallerCleanupTests {
    @Test
    func installerWithNewerAppIsFlaggedAsInstalled() throws {
        let fileManager = FileManager.default
        let root = try makeTempWatchFolder()
        defer { try? fileManager.removeItem(at: root) }
        let apps = try makeTempApplicationsFolder()
        defer { try? fileManager.removeItem(at: apps) }

        let installer = root.appendingPathComponent("Foo-2.3-arm64.dmg")
        try Data("dmg".utf8).write(to: installer)
        let now = Date()
        let app = try makeApp(named: "Foo.app", in: apps)

        let found = CleanupScanner(
            watchFolder: root,
            thresholdDays: 365,
            includeWatchRoot: true,
            applicationsFolders: [apps],
            installDateProvider: dateProvider([
                installer: now.addingTimeInterval(-10 * 24 * 3600),
                app: now.addingTimeInterval(-1 * 24 * 3600),
            ])
        ).candidates(now: now, fileManager: fileManager)

        #expect(found.map(\.url.lastPathComponent) == ["Foo-2.3-arm64.dmg"])
        guard case .installed(let appName, let appURL) = found.first?.reason else {
            Issue.record("Expected an .installed reason")
            return
        }
        #expect(appName == "Foo")
        #expect(appURL.standardizedFileURL.resolvingSymlinksInPath() == app.standardizedFileURL.resolvingSymlinksInPath())
    }

    @Test
    func noCandidateWhenTheMatchingAppIsMissing() throws {
        let fileManager = FileManager.default
        let root = try makeTempWatchFolder()
        defer { try? fileManager.removeItem(at: root) }
        let apps = try makeTempApplicationsFolder()
        defer { try? fileManager.removeItem(at: apps) }

        let installer = root.appendingPathComponent("Foo-2.3-arm64.dmg")
        try Data("dmg".utf8).write(to: installer)
        let now = Date()

        // Recent enough that it wouldn't be stale on its own, and no app in
        // the fake Applications folder to match against.
        let found = CleanupScanner(
            watchFolder: root,
            thresholdDays: 365,
            includeWatchRoot: true,
            applicationsFolders: [apps],
            installDateProvider: dateProvider([installer: now.addingTimeInterval(-10 * 24 * 3600)])
        ).candidates(now: now, fileManager: fileManager)

        #expect(found.isEmpty)
    }

    @Test
    func noCandidateWhenTheAppIsOlderThanTheInstaller() throws {
        let fileManager = FileManager.default
        let root = try makeTempWatchFolder()
        defer { try? fileManager.removeItem(at: root) }
        let apps = try makeTempApplicationsFolder()
        defer { try? fileManager.removeItem(at: apps) }

        let installer = root.appendingPathComponent("Foo-2.3-arm64.dmg")
        try Data("dmg".utf8).write(to: installer)
        let now = Date()
        let app = try makeApp(named: "Foo.app", in: apps)

        let found = CleanupScanner(
            watchFolder: root,
            thresholdDays: 365,
            includeWatchRoot: true,
            applicationsFolders: [apps],
            installDateProvider: dateProvider([
                installer: now.addingTimeInterval(-1 * 24 * 3600),
                app: now.addingTimeInterval(-10 * 24 * 3600),
            ])
        ).candidates(now: now, fileManager: fileManager)

        #expect(found.isEmpty)
    }

    @Test
    func appWithAnOldBuildDateButRecentAddedDateStillMatches() throws {
        // Regression test: Finder preserves a dragged app's original
        // (vendor build) mtime, which is almost always before the download.
        // The "added" date — when the bundle actually landed in
        // Applications — is what should decide the match. Real mtime is set
        // to an implausibly old date here to prove the match doesn't
        // silently fall through to it once the injected provider is in play.
        let fileManager = FileManager.default
        let root = try makeTempWatchFolder()
        defer { try? fileManager.removeItem(at: root) }
        let apps = try makeTempApplicationsFolder()
        defer { try? fileManager.removeItem(at: apps) }

        let installer = root.appendingPathComponent("Foo-2.3-arm64.dmg")
        try Data("dmg".utf8).write(to: installer)
        let now = Date()
        let app = try makeApp(named: "Foo.app", in: apps)
        try fileManager.setAttributes(
            [.modificationDate: now.addingTimeInterval(-400 * 24 * 3600)],
            ofItemAtPath: app.path
        )

        let found = CleanupScanner(
            watchFolder: root,
            thresholdDays: 365,
            includeWatchRoot: true,
            applicationsFolders: [apps],
            installDateProvider: dateProvider([
                installer: now.addingTimeInterval(-10 * 24 * 3600),
                app: now.addingTimeInterval(-1 * 24 * 3600),
            ])
        ).candidates(now: now, fileManager: fileManager)

        #expect(found.map(\.url.lastPathComponent) == ["Foo-2.3-arm64.dmg"])
        guard case .installed(let appName, _) = found.first?.reason else {
            Issue.record("Expected an .installed reason")
            return
        }
        #expect(appName == "Foo")
    }

    @Test
    func installerWithAnOldServerMtimeButRecentAddedDateStillMatches() throws {
        // Regression test: browsers can set a downloaded file's mtime from
        // the server's Last-Modified header, which can be months old (or
        // just wrong). The "added" date — when Intake's watch folder
        // actually received the file — is what should decide the match.
        let fileManager = FileManager.default
        let root = try makeTempWatchFolder()
        defer { try? fileManager.removeItem(at: root) }
        let apps = try makeTempApplicationsFolder()
        defer { try? fileManager.removeItem(at: apps) }

        let installer = root.appendingPathComponent("Foo-2.3-arm64.dmg")
        try Data("dmg".utf8).write(to: installer)
        let now = Date()
        try fileManager.setAttributes(
            [.modificationDate: now.addingTimeInterval(-400 * 24 * 3600)],
            ofItemAtPath: installer.path
        )
        let app = try makeApp(named: "Foo.app", in: apps)

        let found = CleanupScanner(
            watchFolder: root,
            thresholdDays: 365,
            includeWatchRoot: true,
            applicationsFolders: [apps],
            installDateProvider: dateProvider([
                installer: now.addingTimeInterval(-10 * 24 * 3600),
                app: now.addingTimeInterval(-1 * 24 * 3600),
            ])
        ).candidates(now: now, fileManager: fileManager)

        #expect(found.map(\.url.lastPathComponent) == ["Foo-2.3-arm64.dmg"])
    }

    @Test
    func defaultDatePrefersCreationDateOverModificationDate() throws {
        let fileManager = FileManager.default
        let root = try makeTempWatchFolder()
        defer { try? fileManager.removeItem(at: root) }
        let file = root.appendingPathComponent("Foo.dmg")
        try Data("dmg".utf8).write(to: file)
        let now = Date()
        try fileManager.setAttributes(
            [
                .creationDate: now.addingTimeInterval(-1 * 24 * 3600),
                .modificationDate: now.addingTimeInterval(-400 * 24 * 3600),
            ],
            ofItemAtPath: file.path
        )

        let date = InstalledAppMatcher.defaultDate(for: file, fileManager: fileManager)
        #expect(date > now.addingTimeInterval(-2 * 24 * 3600))
    }

    @Test
    func mountedImageIsSkippedEvenWhenStale() throws {
        let fileManager = FileManager.default
        let root = try makeTempWatchFolder()
        defer { try? fileManager.removeItem(at: root) }

        let installer = root.appendingPathComponent("Foo-2.3-arm64.dmg")
        try Data("dmg".utf8).write(to: installer)
        let now = Date()
        try fileManager.setAttributes(
            [.modificationDate: now.addingTimeInterval(-90 * 24 * 3600)],
            ofItemAtPath: installer.path
        )

        // A fake mounted volume named "Foo" — same URLs the real
        // FileManager.mountedVolumeURLs API would hand back.
        let mountedVolume = URL(fileURLWithPath: "/Volumes/Foo", isDirectory: true)

        let found = CleanupScanner(
            watchFolder: root,
            thresholdDays: 30,
            includeWatchRoot: true,
            applicationsFolders: [],
            mountedVolumeURLs: [mountedVolume]
        ).candidates(now: now, fileManager: fileManager)

        #expect(found.isEmpty)
    }

    @Test
    func installerInInstallersFolderIsMatched() throws {
        let fileManager = FileManager.default
        let root = try makeTempWatchFolder()
        defer { try? fileManager.removeItem(at: root) }
        let apps = try makeTempApplicationsFolder()
        defer { try? fileManager.removeItem(at: apps) }

        let installersFolder = root.appendingPathComponent("Installers", isDirectory: true)
        try fileManager.createDirectory(at: installersFolder, withIntermediateDirectories: true)
        let installer = installersFolder.appendingPathComponent("Foo-2.3-arm64.dmg")
        try Data("dmg".utf8).write(to: installer)
        let now = Date()
        let app = try makeApp(named: "Foo.app", in: apps)

        let found = CleanupScanner(
            watchFolder: root,
            thresholdDays: 365,
            includeWatchRoot: false,
            applicationsFolders: [apps],
            installDateProvider: dateProvider([
                installer: now.addingTimeInterval(-10 * 24 * 3600),
                app: now.addingTimeInterval(-1 * 24 * 3600),
            ])
        ).candidates(now: now, fileManager: fileManager)

        #expect(found.map(\.url.lastPathComponent) == ["Foo-2.3-arm64.dmg"])
        #expect(found.first?.reason.label == "Installer")
    }

    @Test
    func pkgFallsBackToNameMatchingWhenReceiptsArentReadable() throws {
        let fileManager = FileManager.default
        let root = try makeTempWatchFolder()
        defer { try? fileManager.removeItem(at: root) }
        let apps = try makeTempApplicationsFolder()
        defer { try? fileManager.removeItem(at: apps) }

        // Not a real xar/flat package, so the receipt resolver can't find an
        // identifier in it and returns nil — matching falls back to names.
        let installer = root.appendingPathComponent("Foo Setup 1.0.pkg")
        try Data("not a real pkg".utf8).write(to: installer)
        let now = Date()
        let app = try makeApp(named: "Foo.app", in: apps)

        let found = CleanupScanner(
            watchFolder: root,
            thresholdDays: 365,
            includeWatchRoot: true,
            applicationsFolders: [apps],
            installDateProvider: dateProvider([
                installer: now.addingTimeInterval(-10 * 24 * 3600),
                app: now.addingTimeInterval(-1 * 24 * 3600),
            ])
        ).candidates(now: now, fileManager: fileManager)

        #expect(found.map(\.url.lastPathComponent) == ["Foo Setup 1.0.pkg"])
        guard case .installed(let appName, _) = found.first?.reason else {
            Issue.record("Expected an .installed reason via name-match fallback")
            return
        }
        #expect(appName == "Foo")
    }

    @Test
    func mpkgIsMatchedLikeADmgOrPkg() throws {
        let fileManager = FileManager.default
        let root = try makeTempWatchFolder()
        defer { try? fileManager.removeItem(at: root) }
        let apps = try makeTempApplicationsFolder()
        defer { try? fileManager.removeItem(at: apps) }

        let installer = root.appendingPathComponent("Foo-2.3.mpkg")
        try Data("mpkg".utf8).write(to: installer)
        let now = Date()
        let app = try makeApp(named: "Foo.app", in: apps)

        let found = CleanupScanner(
            watchFolder: root,
            thresholdDays: 365,
            includeWatchRoot: true,
            applicationsFolders: [apps],
            installDateProvider: dateProvider([
                installer: now.addingTimeInterval(-10 * 24 * 3600),
                app: now.addingTimeInterval(-1 * 24 * 3600),
            ])
        ).candidates(now: now, fileManager: fileManager)

        #expect(found.map(\.url.lastPathComponent) == ["Foo-2.3.mpkg"])
        #expect(found.first?.reason.label == "Installer")
    }

    @Test
    func normalizeStripsVersionsArchTokensAndInstallerWords() {
        #expect(InstalledAppMatcher.normalize("Foo-2.3-arm64.dmg") == "foo")
        #expect(InstalledAppMatcher.normalize("Foo Setup 1.0.pkg") == "foo")
        #expect(InstalledAppMatcher.normalize("Foo_Installer_x86_64.dmg") == "foo")
        #expect(InstalledAppMatcher.normalize("Foo.app") == "foo")
        #expect(InstalledAppMatcher.normalize("Foo") == "foo")
    }

    /// Builds an `installDateProvider` from a fixed `[URL: Date]` map,
    /// standing in for a real added-to-directory date that a test can't
    /// reliably set on disk. URLs not in `overrides` fall back to `.distantPast`.
    private func dateProvider(_ overrides: [URL: Date]) -> @Sendable (URL, FileManager) -> Date {
        let normalized = Dictionary(
            uniqueKeysWithValues: overrides.map { ($0.key.standardizedFileURL.path, $0.value) }
        )
        return { url, _ in normalized[url.standardizedFileURL.path] ?? .distantPast }
    }

    private func makeTempWatchFolder() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "intake-cleanup-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func makeTempApplicationsFolder() throws -> URL {
        let apps = FileManager.default.temporaryDirectory.appendingPathComponent(
            "intake-fake-applications-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: apps, withIntermediateDirectories: true)
        return apps
    }

    /// A minimal, real `.app` bundle: a directory with an Info.plist naming
    /// the app, so InstalledAppMatcher's Info.plist read exercises real code.
    private func makeApp(named name: String, in folder: URL) throws -> URL {
        let fileManager = FileManager.default
        let appURL = folder.appendingPathComponent(name, isDirectory: true)
        let contents = appURL.appendingPathComponent("Contents", isDirectory: true)
        try fileManager.createDirectory(at: contents, withIntermediateDirectories: true)
        let displayName = (name as NSString).deletingPathExtension
        let plist: [String: Any] = [
            "CFBundleDisplayName": displayName,
            "CFBundleName": displayName,
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try data.write(to: contents.appendingPathComponent("Info.plist"))
        return appURL
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

struct ActivityRevealTests {
    @Test
    func revealURLUsesEntryURLWhenFileStillExists() {
        let watch = "/tmp/intake-reveal/Downloads"
        let path = "\(watch)/Notes.pdf"
        let entry = ActivityEntry(
            kind: .renamed,
            detail: "Renamed a to Notes.pdf",
            url: URL(fileURLWithPath: path),
            fileName: "Notes.pdf",
            beforePath: "\(watch)/notes.pdf",
            afterPath: path
        )
        let exists: Set<String> = [path]
        let url = ActivityLog.revealURL(for: entry, in: [entry], fileExists: { exists.contains($0) })
        #expect(url?.path == path)
    }

    @Test
    func revealURLFollowsRenameThenMoveChainWhenRenamePathIsStale() {
        let watch = "/tmp/intake-reveal/Downloads"
        let renamedPath = "\(watch)/Notes.pdf"
        let filedPath = "\(watch)/Documents/Notes.pdf"
        let renamed = ActivityEntry(
            kind: .renamed,
            detail: "Renamed a to Notes.pdf",
            url: URL(fileURLWithPath: renamedPath),
            fileName: "Notes.pdf",
            beforePath: "\(watch)/notes.pdf",
            afterPath: renamedPath
        )
        let moved = ActivityEntry(
            kind: .moved,
            detail: "Moved Notes.pdf to Documents",
            url: URL(fileURLWithPath: filedPath),
            fileName: "Notes.pdf",
            destinationFolder: "Documents",
            beforePath: renamedPath,
            afterPath: filedPath
        )
        // Newest-first Activity order.
        let entries = [moved, renamed]
        let exists: Set<String> = [filedPath]
        let url = ActivityLog.revealURL(for: renamed, in: entries, fileExists: { exists.contains($0) })
        #expect(url?.path == filedPath)
    }

    @Test
    func revealURLFollowsTitleCaseThenContentAwareThenMove() {
        let watch = "/tmp/intake-reveal/Downloads"
        let titlePath = "\(watch)/Notes.pdf"
        let contentPath = "\(watch)/Q3 Notes.pdf"
        let filedPath = "\(watch)/Documents/Q3 Notes.pdf"
        let titleCase = ActivityEntry(
            kind: .renamed,
            detail: "Renamed a to Notes.pdf",
            url: URL(fileURLWithPath: titlePath),
            fileName: "Notes.pdf",
            beforePath: "\(watch)/notes.pdf",
            afterPath: titlePath,
            renameSource: .titleCase
        )
        let contentAware = ActivityEntry(
            kind: .renamed,
            detail: "Renamed Notes.pdf to Q3 Notes.pdf",
            url: URL(fileURLWithPath: contentPath),
            fileName: "Q3 Notes.pdf",
            beforePath: titlePath,
            afterPath: contentPath,
            renameSource: .contentAware
        )
        let moved = ActivityEntry(
            kind: .moved,
            detail: "Moved Q3 Notes.pdf to Documents",
            url: URL(fileURLWithPath: filedPath),
            fileName: "Q3 Notes.pdf",
            destinationFolder: "Documents",
            beforePath: contentPath,
            afterPath: filedPath
        )
        let entries = [moved, contentAware, titleCase]
        let exists: Set<String> = [filedPath]
        let url = ActivityLog.revealURL(for: titleCase, in: entries, fileExists: { exists.contains($0) })
        #expect(url?.path == filedPath)
    }

    @Test
    func revealFallbackDirectoryWhenFileGone() {
        let path = "/tmp/intake-reveal/Downloads/Documents/Gone.pdf"
        let entry = ActivityEntry(
            kind: .moved,
            detail: "Moved Gone.pdf to Documents",
            url: URL(fileURLWithPath: path),
            fileName: "Gone.pdf",
            afterPath: path
        )
        let parent = "/tmp/intake-reveal/Downloads/Documents"
        let exists: Set<String> = [parent]
        let dir = ActivityLog.revealFallbackDirectory(for: entry, fileExists: { exists.contains($0) })
        #expect(dir?.path == parent)
        #expect(ActivityLog.revealURL(for: entry, in: [entry], fileExists: { exists.contains($0) }) == nil)
    }

    @Test
    func hasRevealablePathRequiresSomePath() {
        #expect(ActivityEntry(kind: .skipped, detail: "x", fileName: "x").hasRevealablePath == false)
        #expect(
            ActivityEntry(
                kind: .moved,
                detail: "x",
                fileName: "x",
                afterPath: "/tmp/x"
            ).hasRevealablePath
        )
    }
}
