import AppKit
import Foundation
import Observation
import ServiceManagement
import SwiftUI
import IntakeCore

@Observable
@MainActor
final class AppModel {
    var automaticOrganizing: Bool {
        didSet { AutomaticOrganizingPreference.persist(automaticOrganizing, to: .standard) }
    }

    var organizingWait: OrganizingWait {
        didSet {
            OrganizingWait.persist(organizingWait, to: .standard)
            reevaluateWaitingForAge()
        }
    }

    var isPaused: Bool {
        !automaticOrganizing
    }

    var watchFolder: URL {
        didSet {
            arrivedWhilePaused.removeAll()
            waitingForAge.removeAll()
            ageGateTask?.cancel()
            persistWatchFolderBookmark()
        }
    }

    var watchFolderBookmarkLost: Bool
    var rules: [RoutingRule] {
        didSet { persistRules() }
    }

    var ruleSuggestions: [RuleSuggestion] = []
    var suggestionMemory: SuggestionMemory {
        didSet { persistSuggestionMemory() }
    }

    var pendingAISuggestions: [PendingAISuggestion] = []
    var openRouterEnabled: Bool {
        didSet { UserDefaults.standard.set(openRouterEnabled, forKey: SettingsKey.openRouterEnabled) }
    }
    var openRouterBaseURL: String {
        didSet { UserDefaults.standard.set(openRouterBaseURL, forKey: SettingsKey.openRouterBaseURL) }
    }
    var openRouterModel: String {
        didSet { UserDefaults.standard.set(openRouterModel, forKey: SettingsKey.openRouterModel) }
    }
    var openRouterStatusMessage: String?
    var openRouterRequestCount = 0

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
    private var waitingForAge: [PendingStableFile] = []
    @ObservationIgnored
    private var ageGateTask: Task<Void, Never>?
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
        automaticOrganizing = AutomaticOrganizingPreference.isEnabled(in: defaults)
        AutomaticOrganizingPreference.persist(automaticOrganizing, to: defaults)
        organizingWait = OrganizingWait.load(from: defaults)
        cleanupThresholdDays = defaults.object(forKey: SettingsKey.cleanupDays) as? Int ?? 30
        includeWatchRootInCleanup = defaults.object(forKey: SettingsKey.includeRoot) as? Bool ?? true
        aiSuggestionsEnabled = defaults.bool(forKey: SettingsKey.aiSuggestions)
        openRouterEnabled = defaults.bool(forKey: SettingsKey.openRouterEnabled)
        openRouterBaseURL = defaults.string(forKey: SettingsKey.openRouterBaseURL)
            ?? OpenRouterConfiguration.defaultBaseURL
        openRouterModel = defaults.string(forKey: SettingsKey.openRouterModel)
            ?? OpenRouterConfiguration.defaultModel
        showsInDock = defaults.object(forKey: SettingsKey.showDock) as? Bool ?? true
        showsInMenuBar = defaults.object(forKey: SettingsKey.showMenuBar) as? Bool ?? true
        selectedSettingsPane = SettingsPane(
            rawValue: defaults.string(forKey: SettingsKey.settingsPane) ?? ""
        ) ?? .general
        rules = Self.loadRules()
        suggestionMemory = Self.loadSuggestionMemory()
        activity = Self.loadActivity()
        snoozedUntil = Self.loadSnooze()
        cleanupCandidates = []
        launchAtLoginEnabled = SMAppService.mainApp.status == .enabled
        let resolved = Self.resolveWatchFolder()
        watchFolder = resolved.url
        watchFolderBookmarkLost = resolved.lost
        startAccessingWatchFolder()
        restartWatcher()
        refreshSuggestions()
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

    func setAutomaticOrganizing(_ enabled: Bool) {
        setPaused(!enabled)
    }

    func setOrganizingWait(_ wait: OrganizingWait) {
        organizingWait = wait
    }

    func setPaused(_ paused: Bool) {
        let wasPaused = isPaused
        automaticOrganizing = !paused
        if paused {
            ageGateTask?.cancel()
            return
        }
        if wasPaused {
            let pending = arrivedWhilePaused
            arrivedWhilePaused.removeAll()
            let now = Date()
            pending.forEach { rememberStable($0, stableAt: now) }
            reevaluateWaitingForAge()
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
        // IN-09-dock-crash: Dock / reopen opens Settings — not Activity.
        // Avoids ActivityWindowFallback SEGV on the reopen path.
        openSettings(pane: selectedSettingsPane)
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
            // Never construct ActivityWindowFallback — it SEGVs under Xcode 26.
            // openWindow bridge (menu bar / Settings) may still present Activity later.
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
        let processor = OrganizeExistingProcessor(
            watchFolder: watchFolder,
            rules: rules,
            ignorePolicy: ignorePolicy
        )
        let skippedURLs = scan.skipped
        let files = scan.eligible
        let eligibleSet = Set(files.map(\.standardizedFileURL))
        waitingForAge.removeAll { eligibleSet.contains($0.url) }

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
                self.rules = RuleMutation.settingEnabled(self.rules, id: rule.id, isEnabled: enabled)
            }
        )
    }

    func moveRules(from source: IndexSet, to destination: Int) {
        rules = RuleMutation.moving(rules, from: source, to: destination)
    }

    func saveRule(id: String?, folderName: String, extensions: Set<String>, isEnabled: Bool) {
        if let id {
            rules = RuleMutation.updating(
                rules,
                id: id,
                folderName: folderName,
                extensions: extensions,
                isEnabled: isEnabled
            )
        } else {
            rules = RuleMutation.addingCustom(
                rules,
                folderName: folderName,
                extensions: extensions,
                isEnabled: isEnabled
            )
        }
    }

    func deleteCustomRule(id: String) {
        rules = RuleMutation.deletingCustom(rules, id: id)
    }

    func resetBuiltInRule(id: String) {
        rules = RuleMutation.resettingBuiltIn(rules, id: id)
    }

    func acceptSuggestion(_ suggestion: RuleSuggestion) {
        rules = RuleMutation.accepting(suggestion, into: rules)
        var memory = suggestionMemory
        memory.dismissedUntil[suggestion.id] = nil
        suggestionMemory = memory
        refreshSuggestions()
    }

    func dismissSuggestion(_ suggestion: RuleSuggestion) {
        suggestionMemory = suggestionMemory.dismissing(suggestion)
        refreshSuggestions()
    }

    func neverSuggestion(_ suggestion: RuleSuggestion) {
        suggestionMemory = suggestionMemory.nevering(suggestion)
        refreshSuggestions()
    }

    func resetDismissedSuggestions() {
        suggestionMemory = SuggestionMemory()
        refreshSuggestions()
    }

    func refreshSuggestions() {
        let histogram = WatchRootHistogram.counts(
            watchFolder: watchFolder,
            ignorePolicy: ignorePolicy
        )
        ruleSuggestions = RuleSuggestionEngine.suggestions(
            activity: activity,
            watchRootHistogram: histogram,
            rules: rules,
            memory: suggestionMemory
        )
    }

    var ruleConflicts: [RuleConflict] {
        RuleConflict.inRules(rules)
    }

    var managedFolderNames: Set<String> {
        DefaultTaxonomy.managedFolderNames(from: rules)
    }

    var ignorePolicy: DownloadIgnorePolicy {
        DownloadIgnorePolicy(managedFolderNames: managedFolderNames)
    }

    var openRouterConfiguration: OpenRouterConfiguration {
        OpenRouterConfiguration(baseURL: openRouterBaseURL, model: openRouterModel)
    }

    var canCallOpenRouter: Bool {
        aiSuggestionsEnabled && openRouterEnabled && OpenRouterKeychain.hasKey
    }

    func acceptAISuggestion(_ suggestion: PendingAISuggestion) {
        pendingAISuggestions.removeAll { $0.id == suggestion.id }
        let synthetic = RuleSuggestion(
            id: "ai:\(suggestion.fileExtension)",
            title: suggestion.proposedFolder,
            subtitle: suggestion.reason,
            extensions: [suggestion.fileExtension],
            proposedFolderName: suggestion.proposedFolder,
            systemImage: "sparkles",
            targetRuleID: rules.first {
                $0.folderName.compare(suggestion.proposedFolder, options: .caseInsensitive) == .orderedSame
            }?.id,
            hitCount: 1
        )
        rules = RuleMutation.accepting(synthetic, into: rules)
        if let url = suggestion.url {
            refile(url, toFolder: suggestion.proposedFolder)
        }
    }

    func dismissAISuggestion(_ suggestion: PendingAISuggestion) {
        pendingAISuggestions.removeAll { $0.id == suggestion.id }
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

    func handleStableFile(_ url: URL, stableAt: Date = Date()) {
        if isOrganizingExisting {
            arrivedDuringOrganize.append(url)
            return
        }
        rememberStable(url, stableAt: stableAt)
        if isPaused {
            arrivedWhilePaused.removeAll { $0.standardizedFileURL == url.standardizedFileURL }
            arrivedWhilePaused.append(url)
            return
        }
        reevaluateWaitingForAge()
    }

    private func rememberStable(_ url: URL, stableAt: Date) {
        let standardized = url.standardizedFileURL
        if waitingForAge.contains(where: { $0.url == standardized }) {
            return
        }
        waitingForAge.append(PendingStableFile(url: standardized, stableAt: stableAt))
    }

    private func reevaluateWaitingForAge() {
        ageGateTask?.cancel()
        ageGateTask = nil
        guard automaticOrganizing else { return }

        let partitioned = FileAgeGate.partition(
            pending: waitingForAge,
            wait: organizingWait
        )
        waitingForAge = partitioned.waiting
        for item in partitioned.ready {
            applyIngest(item.url)
        }

        guard let next = waitingForAge.min(by: { $0.stableAt < $1.stableAt }) else { return }
        let delay = FileAgeGate.delayUntilEligible(stableAt: next.stableAt, wait: organizingWait)
        ageGateTask = Task { @MainActor in
            let nanoseconds = UInt64(max(delay, 0.05) * 1_000_000_000)
            try? await Task.sleep(nanoseconds: nanoseconds)
            guard !Task.isCancelled else { return }
            self.reevaluateWaitingForAge()
        }
    }

    private func applyIngest(_ url: URL) {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        let processor = OrganizeExistingProcessor(
            watchFolder: watchFolder,
            rules: rules,
            ignorePolicy: ignorePolicy
        )
        switch processor.processOne(url) {
        case .organized(let entries):
            entries.reversed().forEach(record)
            requestOpenRouterIfNeeded(entries: entries)
        case .skipped(let entry):
            record(entry)
        case .error(let entry):
            record(entry)
        case .notInWatchRoot:
            break
        }
    }

    private func requestOpenRouterIfNeeded(entries: [ActivityEntry]) {
        guard aiSuggestionsEnabled, openRouterEnabled else { return }
        guard let moved = entries.first(where: {
            $0.kind == .moved && $0.destinationFolder == FileCategory.other.folderName
        }) else {
            return
        }
        let fileName = moved.fileName
        let ext = URL(fileURLWithPath: fileName).pathExtension.lowercased()
        guard !ext.isEmpty else { return }
        let apiKey = OpenRouterKeychain.load() ?? ""
        guard !apiKey.isEmpty else {
            openRouterStatusMessage = OpenRouterFailure.missingKey.userMessage
            return
        }
        let folders = rules.map(\.folderName)
        let configuration = openRouterConfiguration
        let destination = moved.url
        openRouterRequestCount += 1
        Task { @MainActor in
            let result = await OpenRouterClient.suggestFolder(
                fileName: fileName,
                folders: folders,
                apiKey: apiKey,
                configuration: configuration
            )
            switch result {
            case .success(let suggestion):
                self.openRouterStatusMessage = nil
                self.pendingAISuggestions.insert(
                    PendingAISuggestion(
                        fileName: fileName,
                        url: destination,
                        fileExtension: ext,
                        proposedFolder: suggestion.folderName,
                        reason: suggestion.reason
                    ),
                    at: 0
                )
            case .failure(let failure):
                self.openRouterStatusMessage = failure.userMessage
            }
        }
    }

    private func refile(_ url: URL, toFolder folderName: String) {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: url.path) else { return }
        let destDir = watchFolder.appendingPathComponent(folderName, isDirectory: true)
        do {
            try fileManager.createDirectory(at: destDir, withIntermediateDirectories: true)
            let existing = Set((try? fileManager.contentsOfDirectory(atPath: destDir.path)) ?? [])
            let unique = IngestPipeline.uniqued(fileName: url.lastPathComponent, among: existing)
            let destination = destDir.appendingPathComponent(unique, isDirectory: false)
            try fileManager.moveItem(at: url, to: destination)
            record(
                ActivityEntry(
                    kind: .moved,
                    detail: "Moved \(destination.lastPathComponent) to \(folderName)",
                    url: destination,
                    fileName: destination.lastPathComponent,
                    destinationFolder: folderName
                )
            )
            pruneEmptyManagedFolders()
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
            snoozedUntil: snoozedUntil,
            ignorePolicy: ignorePolicy,
            managedFolderNames: managedFolderNames
        ).candidates()
    }

    func fileAway(_ candidate: CleanupCandidate) {
        guard let directory = DestinationFolderPicker.present(startingAt: watchFolder) else { return }
        do {
            let entry = try CleanupProcessor(
                watchFolder: watchFolder,
                managedFolderNames: managedFolderNames
            ).fileAway(candidate, to: directory)
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
        let entries = CleanupProcessor(
            watchFolder: watchFolder,
            managedFolderNames: managedFolderNames
        ).removeEmptyManagedFolders()
        entries.reversed().forEach(record)
    }

    private func restartWatcher() {
        watcher.stop()
        watcher.start(folder: watchFolder, ignorePolicy: ignorePolicy) { [weak self] url in
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
        if let data = try? RulePersistence.encode(rules) {
            UserDefaults.standard.set(data, forKey: SettingsKey.rules)
        }
        UserDefaults.standard.set(
            RulePersistence.enabledByCategory(from: rules),
            forKey: SettingsKey.ruleEnabled
        )
        watcher.updateIgnorePolicy(ignorePolicy)
        refreshSuggestions()
    }

    private func persistSuggestionMemory() {
        if let data = try? SuggestionMemoryPersistence.encode(suggestionMemory) {
            UserDefaults.standard.set(data, forKey: SettingsKey.suggestionMemory)
        }
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
        let defaults = UserDefaults.standard
        let flags = defaults.dictionary(forKey: SettingsKey.ruleEnabled) as? [String: Bool] ?? [:]
        return RulePersistence.load(
            storedRules: defaults.data(forKey: SettingsKey.rules),
            enabledByCategory: flags
        )
    }

    private static func loadSuggestionMemory() -> SuggestionMemory {
        guard let data = UserDefaults.standard.data(forKey: SettingsKey.suggestionMemory) else {
            return SuggestionMemory()
        }
        return (try? SuggestionMemoryPersistence.decode(data)) ?? SuggestionMemory()
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
    static let paused = AutomaticOrganizingPreference.legacyPausedKey
    static let automaticOrganizing = AutomaticOrganizingPreference.currentKey
    static let cleanupDays = "intake.cleanupDays"
    static let includeRoot = "intake.includeWatchRoot"
    static let aiSuggestions = "intake.aiSuggestions"
    static let watchFolderBookmark = "intake.watchFolderBookmark"
    static let showDock = "intake.showInDock"
    static let showMenuBar = "intake.showInMenuBar"
    static let settingsPane = "intake.settingsPane"
    static let activity = "intake.activity"
    static let ruleEnabled = "intake.ruleEnabled"
    static let rules = "intake.rules"
    static let suggestionMemory = "intake.suggestionMemory"
    static let cleanupSnooze = "intake.cleanupSnooze"
    static let didShowMenuBarTip = "intake.didShowMenuBarTip"
    static let openRouterEnabled = "intake.openRouterEnabled"
    static let openRouterBaseURL = "intake.openRouterBaseURL"
    static let openRouterModel = "intake.openRouterModel"
}
