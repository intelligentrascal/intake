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

    var rules: [RoutingRule]
    var activity: [ActivityEntry]
    var cleanupCandidates: [CleanupCandidate]
    var cleanupThresholdDays: Int {
        didSet { UserDefaults.standard.set(cleanupThresholdDays, forKey: SettingsKey.cleanupDays) }
    }

    var includeWatchRootInCleanup: Bool {
        didSet { UserDefaults.standard.set(includeWatchRootInCleanup, forKey: SettingsKey.includeRoot) }
    }

    var aiSuggestionsEnabled: Bool {
        didSet { UserDefaults.standard.set(aiSuggestionsEnabled, forKey: SettingsKey.aiSuggestions) }
    }

    var launchAtLoginEnabled: Bool

    var recentActivity: [ActivityEntry] {
        Array(activity.prefix(5))
    }

    var statusTitle: String {
        isPaused ? "Paused" : "Watching"
    }

    var statusSubtitle: String {
        let folder = watchFolder.lastPathComponent
        if isPaused {
            return "Organizing is paused · \(folder)"
        }
        return "New files in \(folder)"
    }

    var menuBarSymbol: String {
        isPaused ? "pause.circle.fill" : "tray.and.arrow.down.fill"
    }

    var menuBarAccessibilityLabel: String {
        isPaused ? "Intake paused" : "Intake watching"
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
        rules = DefaultTaxonomy.rules
        activity = []
        cleanupCandidates = []
        launchAtLoginEnabled = SMAppService.mainApp.status == .enabled
        watchFolder = Self.resolvedWatchFolder()
        startAccessingWatchFolder()
        restartWatcher()
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

    func chooseWatchFolder() {
        guard let url = WatchFolderPicker.present(startingAt: watchFolder) else { return }
        stopAccessingWatchFolder()
        watchFolder = url
        startAccessingWatchFolder()
        restartWatcher()
    }

    func revealWatchFolder() {
        NSWorkspace.shared.open(watchFolder)
    }

    func reveal(_ url: URL?) {
        guard let url else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
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
                    detail: "Could not update Open at Login: \(error.localizedDescription)"
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
                    url: url
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
                    url: url
                )
            )
        }
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
        activity.insert(entry, at: 0)
        if activity.count > 50 {
            activity = Array(activity.prefix(50))
        }
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

    private static func resolvedWatchFolder() -> URL {
        let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Downloads")
        guard let data = UserDefaults.standard.data(forKey: SettingsKey.watchFolderBookmark) else {
            return downloads
        }
        var stale = false
        guard let url = try? URL(
            resolvingBookmarkData: data,
            options: [.withSecurityScope],
            relativeTo: nil,
            bookmarkDataIsStale: &stale
        ) else {
            return downloads
        }
        return url
    }
}

private enum SettingsKey {
    static let paused = "intake.paused"
    static let cleanupDays = "intake.cleanupDays"
    static let includeRoot = "intake.includeWatchRoot"
    static let aiSuggestions = "intake.aiSuggestions"
    static let watchFolderBookmark = "intake.watchFolderBookmark"
}
