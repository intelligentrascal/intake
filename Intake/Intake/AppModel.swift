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

    var renameWhenDownloadFinishes: Bool {
        didSet {
            RenameWhenDownloadFinishesPreference.persist(renameWhenDownloadFinishes, to: .standard)
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
            ageGateHeartbeatTask?.cancel()
            ageGateHeartbeatTask = nil
            WaitingForAgeStore.clear(in: .standard)
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
    var openRouterSpendTracker: OpenRouterSpendTracker {
        didSet { openRouterSpendTracker.save(to: .standard) }
    }

    var activity: [ActivityEntry] {
        didSet { persistActivity() }
    }

    var cleanupCandidates: [CleanupCandidate]
    /// Kept across scans so an unchanged file's duplicate hash isn't recomputed.
    private let cleanupHashCache = DuplicateHashCache()
    private let cleanupPackageReceiptResolver = PackageReceiptResolver()
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

    /// Master toggle for IN-10 Notification digests. Off by default — no
    /// permission prompt until this is switched on.
    var notificationsEnabled: Bool {
        didSet {
            NotificationPreferences.persistMaster(notificationsEnabled, to: .standard)
            notificationDigestService.setMasterEnabled(notificationsEnabled)
        }
    }
    var notifyOnFiled: Bool {
        didSet { NotificationPreferences.persistFiled(notifyOnFiled, to: .standard) }
    }
    var notifyOnErrors: Bool {
        didSet { NotificationPreferences.persistErrors(notifyOnErrors, to: .standard) }
    }
    var notifyOnCleanup: Bool {
        didSet { NotificationPreferences.persistCleanup(notifyOnCleanup, to: .standard) }
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
    /// LIFO undo stack (cap 20) for Intake rename/move.
    var undoService: UndoService
    /// Bottom Activity toast for last rename/move (~10s).
    var undoToast: UndoToastPresentation?
    @ObservationIgnored private var undoToastDismissTask: Task<Void, Never>?

    /// Bumped so MenuBarExtra `SettingsOpenBridge` calls SwiftUI `openSettings`.
    var settingsWindowRequestID: UInt64 = 0
    var organizePreviewPresented = false
    var organizeNothingPresented = false
    var organizeProgressPresented = false
    var organizeDonePresented = false
    var organizeEligibleTotal = 0
    var organizeProcessedCount = 0
    var organizeSummary: OrganizeExistingSummary?
    var isOrganizingExisting = false
    /// What Organize Existing will do, shown in the preview sheet before Apply.
    var organizePreview: OrganizeExistingPreview?
    /// Source URLs the user excluded in the preview (single files or whole groups).
    var organizeExcludedURLs: Set<URL> = []
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
    private var ageGateHeartbeatTask: Task<Void, Never>?
    @ObservationIgnored
    private var arrivedDuringOrganize: [URL] = []
    @ObservationIgnored
    private var organizeCancelRequested = false
    @ObservationIgnored
    private var organizeTask: Task<Void, Never>?
    @ObservationIgnored
    private let notificationDigestService = NotificationDigestService()

    init() {
        let defaults = UserDefaults.standard
        // Load into locals first — do not read `self` until every stored property is set
        // (Swift 6 / @Observable rejects self.automaticOrganizing before organizingWait init).
        let autoEnabled = AutomaticOrganizingPreference.isEnabled(in: defaults)
        let waitPreference = OrganizingWait.load(from: defaults)
        let renameOnFinish = RenameWhenDownloadFinishesPreference.isEnabled(in: defaults)
        organizingWait = waitPreference
        automaticOrganizing = autoEnabled
        renameWhenDownloadFinishes = renameOnFinish
        AutomaticOrganizingPreference.persist(autoEnabled, to: defaults)
        RenameWhenDownloadFinishesPreference.persist(renameOnFinish, to: defaults)
        cleanupThresholdDays = defaults.object(forKey: SettingsKey.cleanupDays) as? Int ?? 30
        includeWatchRootInCleanup = defaults.object(forKey: SettingsKey.includeRoot) as? Bool ?? true
        aiSuggestionsEnabled = defaults.bool(forKey: SettingsKey.aiSuggestions)
        notificationsEnabled = NotificationPreferences.isMasterEnabled(in: defaults)
        notifyOnFiled = NotificationPreferences.isFiledEnabled(in: defaults)
        notifyOnErrors = NotificationPreferences.isErrorsEnabled(in: defaults)
        notifyOnCleanup = NotificationPreferences.isCleanupEnabled(in: defaults)
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
        undoService = UndoService.load(from: .standard)
        openRouterSpendTracker = OpenRouterSpendTracker.load(from: .standard)
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
        // Clear bad Settings split frames before any Settings scene restores them.
        SettingsSplitViewAutosave.resetSettingsSplitFrames()

        applyActivationPolicy()
        notificationDigestService.attach(to: self)
        // Restores the heartbeat if the user already turned notifications on in
        // a previous session — never requests authorization at launch for a
        // freshly-off toggle.
        notificationDigestService.setMasterEnabled(notificationsEnabled)
        scanCleanupCandidates()
        let firstRun = !UserDefaults.standard.bool(forKey: SettingsKey.didShowMenuBarTip)
        if firstRun {
            showFirstRunTip = true
        }
        Task { @MainActor in
            // Defense in depth: `.defaultLaunchBehavior(.suppressed)` should already
            // keep Activity off-screen. Hide anything restoration still presented.
            if LaunchWindowPolicy.hidesActivityAtLaunch {
                self.resignAndHideActivityWindows()
            }
            if LaunchWindowPolicy.presentsSettings(
                showsInDock: self.showsInDock,
                isFirstRun: firstRun
            ) {
                self.bringPrimaryWindowForward()
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

    func setRenameWhenDownloadFinishes(_ enabled: Bool) {
        renameWhenDownloadFinishes = enabled
    }

    func setPaused(_ paused: Bool) {
        let wasPaused = isPaused
        automaticOrganizing = !paused
        if paused {
            ageGateTask?.cancel()
            ageGateHeartbeatTask?.cancel()
            ageGateHeartbeatTask = nil
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
        // Activity must never steal key when Settings opens (Dock reopen, menu, etc.).
        resignAndHideActivityWindows()
        // Prefer SwiftUI openSettings bridge (MenuBarExtra) — AppKit showSettingsWindow:
        // often no-ops when Settings scene was never opened / no key window.
        settingsWindowRequestID &+= 1
        NotificationCenter.default.post(name: .intakeOpenSettings, object: nil)
        DispatchQueue.main.async { [weak self] in
            self?.frontSettingsWindow()
        }
        // AppKit fallback: send to NSApp (not nil — nil responder chain no-ops with no key window).
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            guard let self else { return }
            if !self.isSettingsWindowVisible {
                NSApp.sendAction(Selector(("showSettingsWindow:")), to: NSApp, from: nil)
                self.frontSettingsWindow()
            }
        }
        for delay in [0.12, 0.28] as [TimeInterval] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                guard let self else { return }
                // Don't thrash makeKeyAndOrderFront if Settings is already key.
                if let key = NSApp.keyWindow, self.isUsableSettingsWindow(key) { return }
                self.frontSettingsWindow()
            }
        }
    }

    /// True when a Settings surface is already on-screen (id stamped or heuristic).
    /// Broad on purpose: SwiftUI often delays `com_apple_SwiftUI_Settings_window`, and
    /// a narrow check made `applicationDidBecomeActive` call `openSettings` again while
    /// Settings was already front — which stole focus and killed sidebar clicks.
    var isSettingsWindowVisible: Bool {
        NSApp.windows.contains { isUsableSettingsWindow($0) }
    }

    /// Settings-like window that is visible and not miniaturized.
    func isUsableSettingsWindow(_ window: NSWindow) -> Bool {
        guard window.isVisible, !window.isMiniaturized else { return false }
        if window.isIntakeActivityWindow { return false }
        if window.isSwiftUISettingsWindow { return true }
        let id = window.identifier?.rawValue ?? ""
        if id.contains("Settings") || id == "intake.settings" { return true }
        // Untitled / delayed-id Settings panels: titled, non-Activity, app-owned size.
        if window.styleMask.contains(.titled),
           !window.className.contains("StatusBar"),
           window.contentView != nil,
           window.frame.width >= 500,
           window.frame.height >= 360 {
            // Exclude the Activity window by title when id missing.
            if window.title == "Activity" { return false }
            return true
        }
        return false
    }

    /// Order the SwiftUI Settings window front by known id / heuristic.
    func frontSettingsWindow() {
        let candidates = NSApp.windows.filter { isUsableSettingsWindow($0) }
        let preferred = candidates.first(where: \.isSwiftUISettingsWindow) ?? candidates.first
        guard let window = preferred else { return }
        if window.isMiniaturized {
            window.deminiaturize(nil)
        }
        window.collectionBehavior.insert(.moveToActiveSpace)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Dock / reopen / become-active: Settings is the primary surface (not Activity).
    /// If Settings is already up, only front it — do not re-enter `openSettings`
    /// (avoids focus thrash that breaks sidebar navigation).
    func bringPrimaryWindowForward() {
        if isSettingsWindowVisible {
            frontSettingsWindow()
            return
        }
        openSettings(pane: selectedSettingsPane)
    }

    var organizeConfirmTitle: String {
        OrganizeExistingCopy.confirmTitle(folderName: watchFolder.lastPathComponent)
    }

    var organizePausedNote: String? {
        isPaused ? OrganizeExistingCopy.pausedOneShotNote : nil
    }

    /// Files still selected in the preview (not excluded), in group order.
    var organizeSelectedCount: Int {
        guard let preview = organizePreview else { return 0 }
        return preview.groups.reduce(0) { total, group in
            total + group.items.filter { !organizeExcludedURLs.contains($0.id) }.count
        }
    }

    func isGroupFullyExcluded(_ group: OrganizePreviewGroup) -> Bool {
        group.items.allSatisfy { organizeExcludedURLs.contains($0.id) }
    }

    func toggleExcluded(_ item: OrganizePreviewItem) {
        if organizeExcludedURLs.contains(item.id) {
            organizeExcludedURLs.remove(item.id)
        } else {
            organizeExcludedURLs.insert(item.id)
        }
    }

    func toggleGroupExcluded(_ group: OrganizePreviewGroup) {
        if isGroupFullyExcluded(group) {
            for item in group.items {
                organizeExcludedURLs.remove(item.id)
            }
        } else {
            for item in group.items {
                organizeExcludedURLs.insert(item.id)
            }
        }
    }

    func requestOrganizeExisting() {
        if isOrganizingExisting {
            organizeProgressPresented = true
            openActivity()
            return
        }
        let scan = OrganizeExistingScanner(watchFolder: watchFolder).scan()
        let pipeline = IngestPipeline(watchFolder: watchFolder, rules: rules)
        let preview = OrganizeExistingPreviewBuilder.build(scan: scan, pipeline: pipeline)
        organizePreview = preview
        organizeExcludedURLs = []
        openActivity()
        if preview.isEmpty {
            organizeNothingPresented = true
            return
        }
        organizePreviewPresented = true
    }

    func confirmOrganizePreview() {
        organizePreviewPresented = false
        guard let preview = organizePreview else { return }
        let selectedItems = preview.groups.flatMap(\.items).filter {
            !organizeExcludedURLs.contains($0.id)
        }
        startOrganizeExisting(selectedItems: selectedItems, preScanned: preview.skipped)
    }

    /// Cancel changes nothing: the preview never touched disk, so dismissing it
    /// is enough.
    func cancelOrganizePreview() {
        organizePreviewPresented = false
        organizePreview = nil
        organizeExcludedURLs = []
    }

    func cancelOrganizeExisting() {
        organizeCancelRequested = true
        organizeTask?.cancel()
    }

    private func startOrganizeExisting(
        selectedItems: [OrganizePreviewItem],
        preScanned: [OrganizeExistingSkip]
    ) {
        organizeCancelRequested = false
        isOrganizingExisting = true
        organizeEligibleTotal = selectedItems.count
        organizeProcessedCount = 0
        organizeProgressPresented = true
        let processor = OrganizeExistingProcessor(
            watchFolder: watchFolder,
            rules: rules,
            ignorePolicy: ignorePolicy
        )
        let eligibleSet = Set(selectedItems.map { $0.plan.sourceURL.standardizedFileURL })
        waitingForAge.removeAll { eligibleSet.contains($0.url) }
        persistWaitingForAge()

        organizeTask = Task { @MainActor in
            for skip in preScanned where !skip.url.lastPathComponent.hasPrefix(".") {
                self.record(
                    ActivityEntry(
                        kind: .skipped,
                        detail: "Skipped \(skip.url.lastPathComponent) — \(skip.reason.reasonText.lowercased())",
                        url: skip.url,
                        fileName: skip.url.lastPathComponent
                    )
                )
            }

            let result = processor.applyPreview(
                items: selectedItems,
                alreadySkipped: preScanned.count,
                isCancelled: { Task.isCancelled || self.organizeCancelRequested },
                onProgress: { processed, _ in
                    self.organizeProcessedCount = processed
                },
                onFileResult: { fileResult in
                    switch fileResult {
                    case .organized(let entries):
                        self.recordOrganized(entries)
                    case .skipped(let entry), .error(let entry):
                        self.record(entry)
                    case .notInWatchRoot:
                        break
                    }
                }
            )

            self.organizeSummary = result.summary
            self.isOrganizingExisting = false
            self.organizeProgressPresented = false
            self.organizeDonePresented = true
            self.organizePreview = nil
            self.organizeExcludedURLs = []
            self.scanCleanupCandidates()
            self.flushArrivedDuringOrganize()
        }
    }

    private func resignAndHideActivityWindows() {
        for window in NSApp.windows where window.isIntakeActivityWindow {
            if window.isKeyWindow {
                window.resignKey()
            }
            window.orderOut(nil)
        }
    }

    private func existingSettingsWindow() -> NSWindow? {
        NSApp.windows.first { window in
            guard window.isVisible || window.isMiniaturized else { return false }
            if window.isIntakeActivityWindow { return false }
            // Settings scene windows use the standard Settings chrome; exclude
            // status-item / zero-size bridges.
            let frame = window.frame
            guard frame.width >= 400, frame.height >= 300 else { return false }
            return window.styleMask.contains(.titled)
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

    func saveRule(
        id: String?,
        folderName: String,
        extensions: Set<String>,
        conditions: [RuleCondition] = [],
        isEnabled: Bool
    ) {
        if let id {
            rules = RuleMutation.updating(
                rules,
                id: id,
                folderName: folderName,
                extensions: extensions,
                conditions: conditions,
                isEnabled: isEnabled
            )
        } else {
            rules = RuleMutation.addingCustom(
                rules,
                folderName: folderName,
                extensions: extensions,
                conditions: conditions,
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

    var unreachableRules: [RuleConflict.UnreachableRule] {
        RuleConflict.unreachableRules(in: rules)
    }

    /// Recently seen source domains, for the rule editor's hints — most recent first.
    var recentSourceDomains: [String] {
        var seen: Set<String> = []
        var result: [String] = []
        for entry in activity {
            guard let domain = entry.sourceDomain, !seen.contains(domain) else { continue }
            seen.insert(domain)
            result.append(domain)
            if result.count >= 5 { break }
        }
        return result
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

    func handleStableFile(_ reportedURL: URL, stableAt: Date = Date()) {
        if isOrganizingExisting {
            arrivedDuringOrganize.append(reportedURL)
            return
        }
        // A repeated or late stable event can name a file that was already renamed
        // or moved. Skip it instead of logging a second row for the same file, and
        // use the spelling on disk so one file never queues under two names.
        guard FileManager.default.fileExists(atPath: reportedURL.path) else { return }
        let url = FileIdentity.onDiskURL(for: reportedURL)
        let current = applyRenameOnStableIfNeeded(url)
        rememberStable(current, stableAt: stableAt)
        if isPaused {
            arrivedWhilePaused.removeAll { $0.standardizedFileURL == current.standardizedFileURL }
            arrivedWhilePaused.append(current)
            return
        }
        reevaluateWaitingForAge()
    }

    private var liveIngestPolicy: LiveIngestPolicy {
        LiveIngestPolicy(
            renameWhenDownloadFinishes: renameWhenDownloadFinishes,
            automaticOrganizing: automaticOrganizing
        )
    }

    private func applyRenameOnStableIfNeeded(_ url: URL) -> URL {
        guard liveIngestPolicy.shouldRenameOnStable else { return url }
        let processor = OrganizeExistingProcessor(
            watchFolder: watchFolder,
            rules: rules,
            ignorePolicy: ignorePolicy
        )
        switch processor.processOne(url, mode: .renameInPlace) {
        case .organized(let entries):
            recordOrganized(entries)
            let current = entries.last?.url ?? url
            // Prevent the watcher from treating the renamed root name as a new download.
            watcher.acknowledgeRootFile(named: current.lastPathComponent)
            if current.standardizedFileURL != url.standardizedFileURL {
                watcher.acknowledgeRootFile(named: url.lastPathComponent)
            }
            return current
        case .skipped(let entry):
            record(entry)
            return url
        case .error(let entry):
            record(entry)
            return url
        case .notInWatchRoot:
            return url
        }
    }

    private func rememberStable(_ url: URL, stableAt: Date) {
        let standardized = url.standardizedFileURL
        if waitingForAge.contains(where: { $0.url == standardized }) {
            return
        }
        waitingForAge.append(PendingStableFile(url: standardized, stableAt: stableAt))
        persistWaitingForAge()
    }

    private func reevaluateWaitingForAge() {
        ageGateTask?.cancel()
        ageGateTask = nil
        guard automaticOrganizing else {
            ensureAgeGateHeartbeat()
            return
        }

        let partitioned = FileAgeGate.partition(
            pending: waitingForAge,
            wait: organizingWait
        )
        waitingForAge = partitioned.waiting
        var deferred: [PendingStableFile] = []
        for item in partitioned.ready {
            // Belt-and-suspenders: never route before Wait even if partition misfires.
            guard liveIngestPolicy.shouldRoute(
                stableAt: item.stableAt,
                wait: organizingWait
            ) else {
                deferred.append(item)
                continue
            }
            if !applyIngest(item.url) {
                // Empty / still-writing — keep waiting with original stableAt.
                deferred.append(item)
            }
        }
        waitingForAge.append(contentsOf: deferred)
        persistWaitingForAge()
        ensureAgeGateHeartbeat()

        guard let next = waitingForAge.min(by: { $0.stableAt < $1.stableAt }) else { return }
        let delay = FileAgeGate.delayUntilEligible(stableAt: next.stableAt, wait: organizingWait)
        ageGateTask = Task { @MainActor in
            let nanoseconds = UInt64(max(delay, 0.05) * 1_000_000_000)
            try? await Task.sleep(nanoseconds: nanoseconds)
            guard !Task.isCancelled else { return }
            self.reevaluateWaitingForAge()
        }
    }

    /// Defensive 30s heartbeat so eligibility is not missed if the sleep Task is cancelled/lost.
    private func ensureAgeGateHeartbeat() {
        guard automaticOrganizing, !waitingForAge.isEmpty else {
            ageGateHeartbeatTask?.cancel()
            ageGateHeartbeatTask = nil
            return
        }
        guard ageGateHeartbeatTask == nil else { return }
        ageGateHeartbeatTask = Task { @MainActor in
            defer { self.ageGateHeartbeatTask = nil }
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 30_000_000_000)
                guard !Task.isCancelled else { return }
                guard self.automaticOrganizing, !self.waitingForAge.isEmpty else { return }
                self.reevaluateWaitingForAge()
            }
        }
    }

    private func persistWaitingForAge() {
        WaitingForAgeStore.save(waitingForAge, to: .standard)
    }

    /// Restore persisted Wait-queue entries after the watcher seeds `knownNames`.
    /// Acknowledge those root names so rename/watch does not double-ingest, but keep them in `waitingForAge`.
    private func restoreWaitingForAgeFromDisk() {
        let restored = WaitingForAgeStore.restoreExisting(
            from: .standard,
            watchRoot: watchFolder
        )
        guard !restored.isEmpty else {
            // Drop stale paths that no longer exist under this root.
            if WaitingForAgeStore.load(from: .standard).isEmpty == false {
                WaitingForAgeStore.save(waitingForAge, to: .standard)
            }
            return
        }
        for item in restored {
            if !waitingForAge.contains(where: { $0.url == item.url }) {
                waitingForAge.append(item)
            }
            watcher.acknowledgeRootFile(named: item.url.lastPathComponent)
        }
        persistWaitingForAge()
        reevaluateWaitingForAge()
    }

    /// Returns `false` when the file should stay queued (missing, empty, or not routed yet).
    @discardableResult
    private func applyIngest(_ url: URL) -> Bool {
        guard FileManager.default.fileExists(atPath: url.path) else { return true }
        if !DownloadWriteGate.allowsOrganizeOrRename(at: url) {
            return false
        }
        let processor = OrganizeExistingProcessor(
            watchFolder: watchFolder,
            rules: rules,
            ignorePolicy: ignorePolicy
        )
        switch processor.processOne(url, mode: liveIngestPolicy.applyModeAfterWait) {
        case .organized(let entries):
            if entries.isEmpty {
                // routeOnly refused (e.g. empty) — keep queued.
                return false
            }
            recordOrganized(entries)
            requestOpenRouterIfNeeded(entries: entries)
            return true
        case .skipped(let entry):
            record(entry)
            return true
        case .error(let entry):
            record(entry)
            return true
        case .notInWatchRoot:
            return true
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
            case .success(let suggestionWithCost):
                self.openRouterStatusMessage = nil
                self.pendingAISuggestions.insert(
                    PendingAISuggestion(
                        fileName: fileName,
                        url: destination,
                        fileExtension: ext,
                        proposedFolder: suggestionWithCost.suggestion.folderName,
                        reason: suggestionWithCost.suggestion.reason
                    ),
                    at: 0
                )
                if let cost = suggestionWithCost.cost, cost > 0 {
                    self.openRouterSpendTracker.addCost(cost)
                }
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
                    destinationFolder: folderName,
                    beforePath: url.path,
                    afterPath: destination.path
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
            managedFolderNames: managedFolderNames,
            hashCache: cleanupHashCache,
            mountedVolumeURLs: mountedVolumeURLs(),
            packageReceiptResolver: cleanupPackageReceiptResolver
        ).candidates()
        if notificationsEnabled && notifyOnCleanup {
            notificationDigestService.noteCleanupScan(cleanupCandidates)
        }
    }

    /// Currently mounted volumes, for skipping installers whose disk image
    /// is already mounted. Never mounts anything itself — read-only.
    private func mountedVolumeURLs() -> [URL] {
        FileManager.default.mountedVolumeURLs(
            includingResourceValuesForKeys: nil,
            options: [.skipHiddenVolumes]
        ) ?? []
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
        next[CleanupScanner.snoozeKey(for: candidate.url)] = CleanupScanner(
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
        recordOrganized(entries)
    }

    private func restartWatcher() {
        watcher.stop()
        watcher.start(folder: watchFolder, ignorePolicy: ignorePolicy) { [weak self] url in
            Task { @MainActor in
                self?.handleStableFile(url)
            }
        }
        // Watcher start seeds knownNames with existing root files — restore Wait queue
        // so pending files remain eligible without mass-organizing the whole Downloads folder.
        restoreWaitingForAgeFromDisk()
    }

    private func record(_ entry: ActivityEntry) {
        activity = ActivityLog.inserting(entry, into: activity)
        if let action = UndoService.makeAction(from: entry) {
            undoService.push(action)
            persistUndoStack()
            presentUndoToast(for: [action], filed: false)
        }
        notifyDigest(of: [entry])
    }

    /// Record organized ingest entries. Preserves Activity newest-first order while
    /// pushing undo chronologically so LIFO undoes move before rename.
    private func recordOrganized(_ entries: [ActivityEntry]) {
        guard !entries.isEmpty else { return }
        for entry in entries.reversed() {
            activity = ActivityLog.inserting(entry, into: activity)
        }
        var pushed: [UndoAction] = []
        for entry in entries {
            if let action = UndoService.makeAction(from: entry) {
                undoService.push(action)
                pushed.append(action)
            }
        }
        if !pushed.isEmpty {
            persistUndoStack()
            let filed = pushed.contains { $0.kind == .rename } && pushed.contains { $0.kind == .move }
            presentUndoToast(for: pushed, filed: filed)
        }
        notifyDigest(of: entries)
    }

    /// Feeds newly-recorded Activity entries to the notification batcher.
    /// Only Filed (moved) and Error entries are digest-worthy; everything else
    /// (skipped, deleted, folder-removed, plain renames) is left out here —
    /// rename-only entries stay out of the Filed digest by default.
    private func notifyDigest(of entries: [ActivityEntry]) {
        guard notificationsEnabled else { return }
        for entry in entries {
            switch entry.kind {
            case .moved:
                guard notifyOnFiled else { continue }
                notificationDigestService.noteFiled(entry)
            case .error:
                guard notifyOnErrors else { continue }
                notificationDigestService.noteError(entry)
            case .renamed, .skipped, .deleted, .folderRemoved:
                continue
            }
        }
    }

    private func persistUndoStack() {
        undoService.save(to: .standard)
    }

    private func presentUndoToast(for actions: [UndoAction], filed: Bool) {
        guard let last = actions.last else { return }
        let message: String
        if filed,
           let rename = actions.last(where: { $0.kind == .rename }),
           let move = actions.last(where: { $0.kind == .move }),
           let folder = move.destinationFolder {
            message = UndoCopy.toastFiled(name: rename.displayName, folder: folder)
        } else {
            message = UndoService.toastMessage(for: last)
        }
        undoToastDismissTask?.cancel()
        undoToast = UndoToastPresentation(actionID: last.id, message: message)
        undoToastDismissTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(UndoService.toastDuration * 1_000_000_000))
            guard !Task.isCancelled else { return }
            if undoToast?.actionID == last.id {
                undoToast = nil
            }
        }
    }

    func dismissUndoToast() {
        undoToastDismissTask?.cancel()
        undoToast = nil
    }

    func undoEligibility(for entry: ActivityEntry) -> UndoEligibility {
        undoService.eligibility(for: entry)
    }

    func undo(activityID: UUID) {
        guard let action = undoService.action(forActivityID: activityID) else {
            showUndoFailure(.tooOld)
            return
        }
        performUndo(action)
    }

    func undoLastFromToast() {
        guard let toast = undoToast,
              let action = undoService.actions.first(where: { $0.id == toast.actionID })
                ?? undoService.last
        else {
            dismissUndoToast()
            return
        }
        performUndo(action)
    }

    private func performUndo(_ action: UndoAction) {
        let result = undoService.perform(action)
        persistUndoStack()
        dismissUndoToast()
        switch result {
        case .success(let restored):
            watcher.acknowledgeRootFile(named: restored.lastPathComponent)
            if action.afterURL.lastPathComponent != restored.lastPathComponent {
                watcher.acknowledgeRootFile(named: action.afterURL.lastPathComponent)
            }
            // Refresh Activity URL for this row when still listed.
            if let idx = activity.firstIndex(where: { $0.id == action.activityID }) {
                var updated = activity[idx]
                updated.url = restored
                updated.fileName = restored.lastPathComponent
                updated.detail = "Undid — restored \(restored.lastPathComponent)"
                updated.beforePath = nil
                updated.afterPath = nil
                activity[idx] = updated
            }
            scanCleanupCandidates()
            refreshSuggestions()
        case .failure(let eligibility):
            showUndoFailure(eligibility)
        }
    }

    private func showUndoFailure(_ eligibility: UndoEligibility) {
        let message = eligibility.reason ?? UndoCopy.notUndoable
        undoToast = UndoToastPresentation(actionID: UUID(), message: message, showsUndoButton: false)
        undoToastDismissTask?.cancel()
        undoToastDismissTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(UndoService.toastDuration * 1_000_000_000))
            guard !Task.isCancelled else { return }
            if undoToast?.showsUndoButton == false {
                undoToast = nil
            }
        }
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
    static let renameWhenDownloadFinishes = RenameWhenDownloadFinishesPreference.currentKey
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


struct UndoToastPresentation: Identifiable, Equatable {
    var id: UUID { actionID }
    var actionID: UUID
    var message: String
    var showsUndoButton: Bool = true
}
