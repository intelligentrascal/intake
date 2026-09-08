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
    var activityWindowRequestID: UInt64 = 0
    var organizeConfirmPresented = false
    var organizeNothingPresented = false
    var organizeProgressPresented = false
    var organizeDonePresented = false
    var organizeEligibleTotal = 0
    var organizeProcessedCount = 0
    var organizeSummary: OrganizeExistingSummary?
    var isOrganizingExisting = false
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
    @ObservationIgnored
    private var arrivedDuringOrganize: [URL] = []
    @ObservationIgnored
    private var pendingOrganizeScan: OrganizeExistingScan?
    @ObservationIgnored
    private var organizeCancelRequested = false
    @ObservationIgnored
    private var organizeTask: Task<Void, Never>?

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
        let firstRun = !UserDefaults.standard.bool(forKey: SettingsKey.didShowMenuBarTip)
        if firstRun {
            showFirstRunTip = true
        }
        Task { @MainActor in
            if self.showsInDock || firstRun {
                self.bringPrimaryWindowForward()
            } else {
                NSApp.windows.filter(\.isIntakeActivityWindow).forEach { $0.orderOut(nil) }
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
        openActivity()
    }

    func openActivity() {
        NSApp.activate(ignoringOtherApps: true)
        if let window = existingActivityWindow() {
            closeDuplicateActivityWindows(keeping: window)
            front(window)
            return
        }
        activityWindowRequestID += 1
        NotificationCenter.default.post(name: .intakeOpenActivity, object: nil)
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(80))
            if let window = self.existingActivityWindow() {
                self.closeDuplicateActivityWindows(keeping: window)
                self.front(window)
                return
            }
            ActivityWindowFallback.shared.present(model: self)
        }
    }

    func openSettings(pane: SettingsPane) {
        selectedSettingsPane = pane
        NSApp.activate(ignoringOtherApps: true)
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
    }

    var organizeConfirmTitle: String {
        OrganizeExistingCopy.confirmTitle(folderName: watchFolder.lastPathComponent)
    }

    var organizeConfirmMessage: String {
        if isPaused {
            return OrganizeExistingCopy.confirmBody + "\n\n" + OrganizeExistingCopy.pausedOneShotNote
        }
        return OrganizeExistingCopy.confirmBody
    }

    func requestOrganizeExisting() {
        if isOrganizingExisting {
            organizeProgressPresented = true
            openActivity()
            return
        }
        let scan = OrganizeExistingScanner(watchFolder: watchFolder).scan()
        pendingOrganizeScan = scan
        openActivity()
        if scan.eligible.isEmpty {
            organizeNothingPresented = true
            return
        }
        organizeConfirmPresented = true
    }

    func confirmOrganizeExisting() {
        organizeConfirmPresented = false
        guard let scan = pendingOrganizeScan else { return }
        startOrganizeExisting(scan)
    }

    func cancelOrganizeExisting() {
        organizeCancelRequested = true
        organizeTask?.cancel()
    }

    private func startOrganizeExisting(_ scan: OrganizeExistingScan) {
        organizeCancelRequested = false
        isOrganizingExisting = true
        organizeEligibleTotal = scan.eligible.count
        organizeProcessedCount = 0
        organizeProgressPresented = true
        let processor = OrganizeExistingProcessor(watchFolder: watchFolder, rules: rules)
        let skippedURLs = scan.skipped
        let files = scan.eligible

        organizeTask = Task { @MainActor in
            for url in skippedURLs where !url.lastPathComponent.hasPrefix(".") {
                self.record(
                    ActivityEntry(
                        kind: .skipped,
                        detail: "Skipped \(url.lastPathComponent)",
                        url: url,
                        fileName: url.lastPathComponent
                    )
                )
            }

            var organized = 0
            var skipped = skippedURLs.count
            var errors = 0

            for (index, url) in files.enumerated() {
                if Task.isCancelled || self.organizeCancelRequested {
                    break
                }
                self.arrivedWhilePaused.removeAll {
                    $0.standardizedFileURL == url.standardizedFileURL
                }
                switch processor.processOne(url) {
                case .organized(let entries):
                    organized += 1
                    entries.reversed().forEach(self.record)
                case .skipped(let entry):
                    skipped += 1
                    self.record(entry)
                case .error(let entry):
                    errors += 1
                    self.record(entry)
                case .notInWatchRoot:
                    skipped += 1
                }
                self.organizeProcessedCount = index + 1
            }

            self.organizeSummary = OrganizeExistingSummary(
                organized: organized,
                skipped: skipped,
                errors: errors,
                cancelled: Task.isCancelled || self.organizeCancelRequested
            )
            self.isOrganizingExisting = false
            self.organizeProgressPresented = false
            self.organizeDonePresented = true
            self.scanCleanupCandidates()
            self.flushArrivedDuringOrganize()
        }
    }

    private func existingActivityWindow() -> NSWindow? {
        NSApp.windows.first(where: \.isIntakeActivityWindow)
    }

    private func closeDuplicateActivityWindows(keeping keeper: NSWindow) {
        for window in NSApp.windows where window.isIntakeActivityWindow && window !== keeper {
            window.close()
        }
    }

    private func front(_ window: NSWindow) {
        if window.isMiniaturized {
            window.deminiaturize(nil)
        }
        window.makeKeyAndOrderFront(nil)
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
        if isOrganizingExisting {
            arrivedDuringOrganize.append(url)
            return
        }
        if isPaused {
            arrivedWhilePaused.append(url)
            return
        }
        applyIngest(url)
    }

    private func applyIngest(_ url: URL) {
        let processor = OrganizeExistingProcessor(watchFolder: watchFolder, rules: rules)
        switch processor.processOne(url) {
        case .organized(let entries):
            entries.reversed().forEach(record)
        case .skipped(let entry):
            record(entry)
        case .error(let entry):
            record(entry)
        case .notInWatchRoot:
            break
        }
    }

    private func flushArrivedDuringOrganize() {
        let pending = arrivedDuringOrganize
        arrivedDuringOrganize.removeAll()
        for url in pending {
            handleStableFile(url)
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
