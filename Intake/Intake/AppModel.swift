import AppKit
import Foundation
import Observation
import ServiceManagement
import SwiftUI
import IntakeCore

@Observable
@MainActor
final class AppModel {
    var isPaused: Bool {
        didSet { UserDefaults.standard.set(isPaused, forKey: SettingsKey.paused) }
    }

    var watchFolder: URL {
        didSet {
            arrivedWhilePaused.removeAll()
            persistWatchFolderBookmark()
        }
    }

    var watchFolderBookmarkLost: Bool
    var rules: [RoutingRule] {
        didSet { persistRules() }
    }

    var activity: [ActivityEntry] {
        didSet { persistActivity() }
    }

    var cleanupCandidates: [CleanupCandidate]
    var cleanupThresholdDays: Int {
        didSet {
            UserDefaults.standard.set(cleanupThresholdDays, forKey: SettingsKey.cleanupDays)
            scanCleanupCandidates()
        }
    }

    var includeWatchRootInCleanup: Bool {
        didSet {
            UserDefaults.standard.set(includeWatchRootInCleanup, forKey: SettingsKey.includeRoot)
            scanCleanupCandidates()
        }
    }

    var aiSuggestionsEnabled: Bool {
        didSet { UserDefaults.standard.set(aiSuggestionsEnabled, forKey: SettingsKey.aiSuggestions) }
    }

    var launchAtLoginEnabled: Bool
    var showsInDock: Bool
    var showsInMenuBar: Bool
    var selectedSettingsPane: SettingsPane {
        didSet { UserDefaults.standard.set(selectedSettingsPane.rawValue, forKey: SettingsKey.settingsPane) }
    }

    var showFirstRunTip = false
    var keepOneSurfaceAlert = false
    var snoozedUntil: [String: Date] {
        didSet { persistSnooze() }
    }

    var recentActivity: [ActivityEntry] {
        Array(activity.prefix(5))
    }

    var statusTitle: String {
        if watchFolderBookmarkLost {
            return "Attention"
        }
        return isPaused ? "Paused" : "Watching"
    }

    var statusSubtitle: String {
        if watchFolderBookmarkLost {
            return "Needs folder access"
        }
        let folder = watchFolder.lastPathComponent
        if isPaused {
            return "Organizing is paused · \(folder)"
        }
        return "New files in \(folder)"
    }

    var menuBarAccessibilityLabel: String {
        if watchFolderBookmarkLost {
            return "Intake needs folder access"
        }
        return isPaused ? "Intake paused" : "Intake watching"
    }

    @ObservationIgnored
    private var watcher = DownloadsFolderWatcher()
    @ObservationIgnored
    private var accessingWatchFolder = false
    @ObservationIgnored
    private var arrivedWhilePaused: [URL] = []

    init() {
        let defaults = UserDefaults.standard
        isPaused = defaults.object(forKey: SettingsKey.paused) as? Bool ?? false
        cleanupThresholdDays = defaults.object(forKey: SettingsKey.cleanupDays) as? Int ?? 30
        includeWatchRootInCleanup = defaults.object(forKey: SettingsKey.includeRoot) as? Bool ?? true
        aiSuggestionsEnabled = defaults.bool(forKey: SettingsKey.aiSuggestions)
        showsInDock = defaults.object(forKey: SettingsKey.showDock) as? Bool ?? true
        showsInMenuBar = defaults.object(forKey: SettingsKey.showMenuBar) as? Bool ?? true
        selectedSettingsPane = SettingsPane(
            rawValue: defaults.string(forKey: SettingsKey.settingsPane) ?? ""
        ) ?? .general
        rules = Self.loadRules()
        activity = Self.loadActivity()
        snoozedUntil = Self.loadSnooze()
        cleanupCandidates = []
        launchAtLoginEnabled = SMAppService.mainApp.status == .enabled
        let resolved = Self.resolveWatchFolder()
        watchFolder = resolved.url
        watchFolderBookmarkLost = resolved.lost
        startAccessingWatchFolder()
        restartWatcher()
    }

    func applicationDidFinishLaunching() {
        applyActivationPolicy()
        scanCleanupCandidates()
        if !UserDefaults.standard.bool(forKey: SettingsKey.didShowMenuBarTip) {
            showFirstRunTip = true
            Task { @MainActor in
                self.bringPrimaryWindowForward()
            }
        }
    }

    func togglePaused() {
        setPaused(!isPaused)
    }

    func setPaused(_ paused: Bool) {
        let wasPaused = isPaused
        isPaused = paused
        if wasPaused && !paused {
            let pending = arrivedWhilePaused
            arrivedWhilePaused.removeAll()
            pending.forEach(handleStableFile)
        }
    }

    func setShowsInDock(_ show: Bool) {
        if !show && !showsInMenuBar {
            keepOneSurfaceAlert = true
            return
        }
        showsInDock = show
        UserDefaults.standard.set(show, forKey: SettingsKey.showDock)
        applyActivationPolicy()
    }

    func setShowsInMenuBar(_ show: Bool) {
        if !show && !showsInDock {
            keepOneSurfaceAlert = true
            return
        }
        showsInMenuBar = show
        UserDefaults.standard.set(show, forKey: SettingsKey.showMenuBar)
    }

    func applyActivationPolicy() {
        NSApp.setActivationPolicy(showsInDock ? .regular : .accessory)
    }

    func bringPrimaryWindowForward() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
    }

    func openSettings(pane: SettingsPane) {
        selectedSettingsPane = pane
        bringPrimaryWindowForward()
    }

    func acknowledgeFirstRunTip() {
        showFirstRunTip = false
        UserDefaults.standard.set(true, forKey: SettingsKey.didShowMenuBarTip)
    }

    func chooseWatchFolder() {
        guard let url = WatchFolderPicker.present(startingAt: watchFolder) else { return }
        stopAccessingWatchFolder()
        watchFolderBookmarkLost = false
        watchFolder = url
        startAccessingWatchFolder()
        restartWatcher()
        scanCleanupCandidates()
    }

    func revealWatchFolder() {
        NSWorkspace.shared.open(watchFolder)
    }

    func reveal(_ url: URL?) {
        guard let url else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    func copyPath(_ url: URL?) {
        guard let url else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(url.path, forType: .string)
    }

    func binding(for rule: RoutingRule) -> Binding<Bool> {
        Binding(
            get: {
                self.rules.first(where: { $0.id == rule.id })?.isEnabled ?? false
            },
            set: { enabled in
                if let index = self.rules.firstIndex(where: { $0.id == rule.id }) {
                    self.rules[index].isEnabled = enabled
                }
            }
        )
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            launchAtLoginEnabled = SMAppService.mainApp.status == .enabled
        } catch {
            record(
                ActivityEntry(
                    kind: .error,
                    detail: "Could not update Open at Login: \(error.localizedDescription)",
                    fileName: "Open at Login"
                )
            )
            launchAtLoginEnabled = SMAppService.mainApp.status == .enabled
        }
    }

    func handleStableFile(_ url: URL) {
        if isPaused {
            arrivedWhilePaused.append(url)
            return
        }
        let policy = DownloadIgnorePolicy()
        let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
        if policy.shouldIgnore(url: url, kind: .appeared, isDirectory: isDirectory) {
            record(
                ActivityEntry(
                    kind: .skipped,
                    detail: "Skipped \(url.lastPathComponent)",
                    url: url,
                    fileName: url.lastPathComponent
                )
            )
            return
        }

        let pipeline = IngestPipeline(watchFolder: watchFolder, rules: rules)
        let existing = existingNames(in: pipeline.plan(for: url)?.destinationDirectory)
        guard let plan = pipeline.plan(for: url, existingNamesInDestination: existing) else {
            return
        }
        do {
            let entries = try pipeline.apply(plan)
            entries.reversed().forEach(record)
        } catch {
            record(
                ActivityEntry(
                    kind: .error,
                    detail: "Could not file \(url.lastPathComponent): \(error.localizedDescription)",
                    url: url,
                    fileName: url.lastPathComponent
                )
            )
        }
    }

    func scanCleanupCandidates() {
        cleanupCandidates = CleanupScanner(
            watchFolder: watchFolder,
            thresholdDays: cleanupThresholdDays,
            includeWatchRoot: includeWatchRootInCleanup,
            snoozedUntil: snoozedUntil
        ).candidates()
    }

    func fileAway(_ candidate: CleanupCandidate) {
        guard let directory = DestinationFolderPicker.present(startingAt: watchFolder) else { return }
        do {
            let entry = try CleanupProcessor(watchFolder: watchFolder).fileAway(candidate, to: directory)
            record(entry)
            pruneEmptyManagedFolders()
            scanCleanupCandidates()
        } catch {
            record(
                ActivityEntry(
                    kind: .error,
                    detail: "Could not file away \(candidate.url.lastPathComponent): \(error.localizedDescription)",
                    url: candidate.url,
                    fileName: candidate.url.lastPathComponent
                )
            )
        }
    }

    func keep(_ candidate: CleanupCandidate) {
        var next = snoozedUntil
        next[candidate.url.path] = CleanupScanner(
            watchFolder: watchFolder,
            thresholdDays: cleanupThresholdDays,
            includeWatchRoot: includeWatchRootInCleanup,
            snoozedUntil: snoozedUntil
        ).snoozeDate()
        snoozedUntil = next
        scanCleanupCandidates()
    }

    func delete(_ candidate: CleanupCandidate) {
        NSWorkspace.shared.recycle([candidate.url]) { [weak self] _, error in
            Task { @MainActor in
                guard let self else { return }
                if let error {
                    self.record(
                        ActivityEntry(
                            kind: .error,
                            detail: "Could not delete \(candidate.url.lastPathComponent): \(error.localizedDescription)",
                            url: candidate.url,
                            fileName: candidate.url.lastPathComponent
                        )
                    )
                    return
                }
                self.record(
                    ActivityEntry(
                        kind: .deleted,
                        detail: "Deleted \(candidate.url.lastPathComponent)",
                        fileName: candidate.url.lastPathComponent
                    )
                )
                self.pruneEmptyManagedFolders()
                self.scanCleanupCandidates()
            }
        }
    }

    private func pruneEmptyManagedFolders() {
        let entries = CleanupProcessor(watchFolder: watchFolder).removeEmptyManagedFolders()
        entries.reversed().forEach(record)
    }

    private func restartWatcher() {
        watcher.stop()
        watcher.start(folder: watchFolder) { [weak self] url in
            Task { @MainActor in
                self?.handleStableFile(url)
            }
        }
    }

    private func record(_ entry: ActivityEntry) {
        activity = ActivityLog.inserting(entry, into: activity)
    }

    private func persistActivity() {
        if let data = try? ActivityLog.encode(activity) {
            UserDefaults.standard.set(data, forKey: SettingsKey.activity)
        }
    }

    private func persistRules() {
        UserDefaults.standard.set(
            RulePersistence.enabledByCategory(from: rules),
            forKey: SettingsKey.ruleEnabled
        )
    }

    private func persistSnooze() {
        let raw = snoozedUntil.mapValues(\.timeIntervalSince1970)
        UserDefaults.standard.set(raw, forKey: SettingsKey.cleanupSnooze)
    }

    private func existingNames(in directory: URL?) -> Set<String> {
        guard let directory else { return [] }
        let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        return Set(names)
    }

    private func persistWatchFolderBookmark() {
        let data = try? watchFolder.bookmarkData(
            options: .withSecurityScope,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        UserDefaults.standard.set(data, forKey: SettingsKey.watchFolderBookmark)
    }

    private func startAccessingWatchFolder() {
        accessingWatchFolder = watchFolder.startAccessingSecurityScopedResource()
    }

    private func stopAccessingWatchFolder() {
        if accessingWatchFolder {
            watchFolder.stopAccessingSecurityScopedResource()
            accessingWatchFolder = false
        }
    }

    private static func resolveWatchFolder() -> (url: URL, lost: Bool) {
        let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Downloads")
        guard let data = UserDefaults.standard.data(forKey: SettingsKey.watchFolderBookmark) else {
            return (downloads, false)
        }
        var stale = false
        guard let url = try? URL(
            resolvingBookmarkData: data,
            options: [.withSecurityScope],
            relativeTo: nil,
            bookmarkDataIsStale: &stale
        ) else {
            return (downloads, true)
        }
        return (url, false)
    }

    private static func loadRules() -> [RoutingRule] {
        let flags = UserDefaults.standard.dictionary(forKey: SettingsKey.ruleEnabled) as? [String: Bool] ?? [:]
        return RulePersistence.applying(flags, to: DefaultTaxonomy.rules)
    }

    private static func loadActivity() -> [ActivityEntry] {
        guard let data = UserDefaults.standard.data(forKey: SettingsKey.activity) else {
            return []
        }
        return (try? ActivityLog.decode(data)) ?? []
    }

    private static func loadSnooze() -> [String: Date] {
        let raw = UserDefaults.standard.dictionary(forKey: SettingsKey.cleanupSnooze) as? [String: Double] ?? [:]
        return raw.mapValues(Date.init(timeIntervalSince1970:))
    }
}

private enum SettingsKey {
    static let paused = "intake.paused"
    static let cleanupDays = "intake.cleanupDays"
    static let includeRoot = "intake.includeWatchRoot"
    static let aiSuggestions = "intake.aiSuggestions"
    static let watchFolderBookmark = "intake.watchFolderBookmark"
    static let showDock = "intake.showInDock"
    static let showMenuBar = "intake.showInMenuBar"
    static let settingsPane = "intake.settingsPane"
    static let activity = "intake.activity"
    static let ruleEnabled = "intake.ruleEnabled"
    static let cleanupSnooze = "intake.cleanupSnooze"
    static let didShowMenuBarTip = "intake.didShowMenuBarTip"
}
