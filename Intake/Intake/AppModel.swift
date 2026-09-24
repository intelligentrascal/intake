import AppKit
import Foundation
import Observation
import ServiceManagement
import SwiftUI
import IntakeCore

@Observable
@MainActor
final class AppModel {
    /// Ordered watch folders with their per-folder settings. Profile #1 is the
    /// migrated 1.2 watch folder.
    var watchFolderProfiles: [WatchFolderProfile] {
        didSet { WatchFolderProfileStore.save(watchFolderProfiles, to: .standard) }
    }

    /// One live-ingest controller per profile, in profile order.
    private(set) var watchFolderControllers: [WatchFolderController] = []
    /// Why the last add / change of a watch folder was refused.
    var watchFolderAlertMessage: String?
    /// Activity folder filter; `nil` shows every folder.
    var activityFolderFilter: String?
    /// Cleanup folder scope; `nil` scans every folder.
    var cleanupFolderScope: String? {
        didSet { scanCleanupCandidates() }
    }

    var watchFolderStatus: WatchFolderStatus {
        WatchFolderStatus.summarize(
            watchFolderControllers.map { controller in
                let profile = controller.profile
                return WatchFolderStatus.Folder(
                    displayName: profile.displayName,
                    isOrganizing: profile.isOrganizing,
                    accessLost: controller.accessLost
                )
            }
        )
    }

    var isPaused: Bool {
        watchFolderStatus.isPaused
    }

    var hasMultipleWatchFolders: Bool {
        watchFolderProfiles.count > 1
    }

    var canAddWatchFolder: Bool {
        watchFolderProfiles.count < WatchFolderProfile.softCap
    }

    /// Organize Existing needs at least one folder Intake can still see.
    var isOrganizeExistingDisabled: Bool {
        isOrganizingExisting || watchFolderControllers.allSatisfy(\.accessLost)
    }

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
    /// The watch folder the current Organize Existing run targets; `nil` = all.
    var organizeTargetProfileID: String?
    /// True while the preview is reading eligible files for content-aware names.
    var organizeReadingContents = false
    /// On-device content-aware rename (GH-32). Off by default.
    var contentAwareRename: ContentAwareRenameSettings {
        didSet { contentAwareRename.save(to: .standard) }
    }
    /// Refreshed when the AI pane appears and before each use.
    var contentAwareAvailability: OnDeviceModelAvailability = .current
    var snoozedUntil: [String: Date] {
        didSet { persistSnooze() }
    }

    var recentActivity: [ActivityEntry] {
        Array(activity.prefix(5))
    }

    /// Activity narrowed by the folder filter (older rows count as profile #1).
    var filteredActivity: [ActivityEntry] {
        ActivityLog.filtered(activity, watchFolderID: activityFolderFilter)
    }

    var statusTitle: String {
        watchFolderStatus.title
    }

    var statusSubtitle: String {
        watchFolderStatus.subtitle
    }

    var menuBarAccessibilityLabel: String {
        watchFolderStatus.accessibilityLabel
    }

    /// Cleanup candidate → the watch folder it was found in.
    @ObservationIgnored
    private var cleanupProfileByURL: [URL: String] = [:]
    @ObservationIgnored
    private var organizeCancelRequested = false
    @ObservationIgnored
    private var organizeTask: Task<Void, Never>?
    @ObservationIgnored
    private var organizeContentTask: Task<Void, Never>?
    @ObservationIgnored
    private let notificationDigestService = NotificationDigestService()

    init() {
        let defaults = UserDefaults.standard
        // Do not read `self` until every stored property is set (Swift 6 / @Observable).
        // First launch after 1.2 migrates the single watch folder, its Rename / Wait /
        // Automatic organizing settings and its Wait queue into profile #1.
        watchFolderProfiles = WatchFolderProfileStore.load(
            from: defaults,
            legacyFolder: Self.resolveLegacyWatchFolder
        )
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
        contentAwareRename = ContentAwareRenameSettings.load(from: .standard)
        snoozedUntil = Self.loadSnooze()
        cleanupCandidates = []
        launchAtLoginEnabled = SMAppService.mainApp.status == .enabled
        watchFolderControllers = watchFolderProfiles.map {
            WatchFolderController(profile: $0, model: self)
        }
        watchFolderControllers.forEach { $0.start() }
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

    /// Menu bar / Activity Pause and Resume act on every watch folder. Resume
    /// also turns Automatic organizing back on when nothing would be organizing
    /// otherwise — with one folder this is exactly 1.2's Pause / Resume.
    func setPaused(_ paused: Bool) {
        if paused {
            for id in watchFolderProfiles.map(\.id) {
                updateProfile(id) { $0.isPaused = true }
            }
            return
        }
        for id in watchFolderProfiles.map(\.id) {
            updateProfile(id) { $0.isPaused = false }
        }
        if !watchFolderProfiles.contains(where: \.isOrganizing) {
            for id in watchFolderProfiles.map(\.id) {
                updateProfile(id) { $0.automaticOrganizing = true }
            }
        }
    }

    // MARK: Watch folders

    func watchFolderProfile(id: String) -> WatchFolderProfile? {
        watchFolderProfiles.first { $0.id == id }
    }

    func watchFolderController(id: String) -> WatchFolderController? {
        watchFolderControllers.first { $0.profileID == id }
    }

    /// The controller whose folder holds `url` (deepest match wins).
    func watchFolderController(containing url: URL) -> WatchFolderController? {
        watchFolderControllers
            .filter { $0.contains(url) }
            .max { $0.folder.path.count < $1.folder.path.count }
    }

    func watchFolderName(id: String) -> String? {
        watchFolderProfile(id: id)?.displayName
    }

    /// The global rule list narrowed to one watch folder's scope.
    func rules(forWatchFolder id: String) -> [RoutingRule] {
        RoutingRule.scoped(rules, toWatchFolder: id)
    }

    /// Settings toggle: shows whether the folder is organizing, so Pause from
    /// the menu bar reads as off here too. Turning it on also clears Pause.
    func setAutomaticOrganizing(_ enabled: Bool, for id: String) {
        updateProfile(id) { profile in
            profile.automaticOrganizing = enabled
            if enabled {
                profile.isPaused = false
            }
        }
    }

    func setOrganizingWait(_ wait: OrganizingWait, for id: String) {
        updateProfile(id) { $0.organizingWait = wait }
    }

    func setRenameWhenDownloadFinishes(_ enabled: Bool, for id: String) {
        updateProfile(id) { $0.renameWhenDownloadFinishes = enabled }
    }

    func setWatchFolderPaused(_ paused: Bool, for id: String) {
        updateProfile(id) { $0.isPaused = paused }
    }

    func renameWatchFolder(id: String, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        updateProfile(id) { $0.displayName = trimmed }
    }

    /// Where macOS saves screenshots (or the Desktop), offered as a one-click
    /// watch folder. `nil` when it's already watched or can't be added.
    var screenshotFolderSuggestion: URL? {
        let stored = CFPreferencesCopyAppValue(
            ScreenshotLocation.locationKey as CFString,
            ScreenshotLocation.defaultsDomain as CFString
        ) as? String
        let url = ScreenshotLocation.resolve(storedLocation: stored, homeDirectory: Self.userHomeDirectory)
        guard canAddWatchFolder,
              WatchFolderValidation.validate(url, existing: validationFolders()) == nil
        else {
            return nil
        }
        return url
    }

    /// Adds a watch folder. The folder picker opens at `suggestion` (e.g. the
    /// screenshot location) — sandbox access is still granted by the picker.
    func addWatchFolder(startingAt suggestion: URL? = nil) {
        guard canAddWatchFolder else {
            watchFolderAlertMessage = WatchFolderValidation.Problem
                .limitReached(WatchFolderProfile.softCap).message
            return
        }
        let start = suggestion ?? Self.userHomeDirectory
        guard let url = WatchFolderPicker.present(startingAt: start) else { return }
        if let problem = WatchFolderValidation.validate(url, existing: validationFolders()) {
            watchFolderAlertMessage = problem.message
            return
        }
        let profile = WatchFolderProfile(
            displayName: FileManager.default.displayName(atPath: url.path),
            path: url.path,
            bookmark: WatchFolderController.bookmark(for: url)
        )
        watchFolderProfiles.append(profile)
        let controller = WatchFolderController(profile: profile, model: self)
        watchFolderControllers.append(controller)
        controller.start()
        refreshSuggestions()
        scanCleanupCandidates()
    }

    /// Change… or Grant Access… for one folder. Re-granting the same folder
    /// keeps its Wait queue; a different folder starts fresh.
    func changeWatchFolder(id: String) {
        guard let controller = watchFolderController(id: id) else { return }
        guard let url = WatchFolderPicker.present(startingAt: controller.folder) else { return }
        if let problem = WatchFolderValidation.validate(
            url,
            existing: validationFolders(),
            replacing: id
        ) {
            watchFolderAlertMessage = problem.message
            return
        }
        let oldName = controller.folder.lastPathComponent
        updateProfile(id) { profile in
            if profile.displayName == oldName {
                profile.displayName = FileManager.default.displayName(atPath: url.path)
            }
            profile.path = url.standardizedFileURL.path
            profile.bookmark = WatchFolderController.bookmark(for: url)
        }
        controller.replaceFolder(with: url)
        refreshSuggestions()
        scanCleanupCandidates()
    }

    /// Removes one watch folder; the others keep running. The last folder
    /// can't be removed. Rules scoped only to it are disabled, not widened.
    func removeWatchFolder(id: String) {
        guard hasMultipleWatchFolders,
              let index = watchFolderControllers.firstIndex(where: { $0.profileID == id })
        else {
            return
        }
        watchFolderControllers[index].discard()
        watchFolderControllers.remove(at: index)
        watchFolderProfiles.removeAll { $0.id == id }
        rules = RuleMutation.removingWatchFolder(id, from: rules)
        if activityFolderFilter == id {
            activityFolderFilter = nil
        }
        if cleanupFolderScope == id {
            cleanupFolderScope = nil
        } else {
            scanCleanupCandidates()
        }
        refreshSuggestions()
    }

    func revealWatchFolder(id: String) {
        guard let controller = watchFolderController(id: id) else { return }
        NSWorkspace.shared.open(controller.folder)
    }

    private func updateProfile(_ id: String, _ mutate: (inout WatchFolderProfile) -> Void) {
        guard let index = watchFolderProfiles.firstIndex(where: { $0.id == id }) else { return }
        let old = watchFolderProfiles[index]
        var updated = old
        mutate(&updated)
        guard updated != old else { return }
        watchFolderProfiles[index] = updated
        watchFolderController(id: id)?.profileDidChange(from: old)
    }

    private func validationFolders() -> [WatchFolderValidation.ExistingFolder] {
        watchFolderControllers.map { controller in
            WatchFolderValidation.ExistingFolder(
                id: controller.profileID,
                displayName: controller.displayName,
                url: controller.folder,
                managedFolderNames: controller.managedFolderNames
            )
        }
    }

    /// The real home folder, not the sandbox container.
    private static var userHomeDirectory: URL {
        if let entry = getpwuid(getuid()), let dir = entry.pointee.pw_dir {
            return URL(fileURLWithPath: String(cString: dir), isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser
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
        if let name = organizeTargetName {
            return OrganizeExistingCopy.confirmTitle(folderName: name)
        }
        return OrganizeExistingCopy.confirmTitleAllFolders
    }

    /// The single folder Organize Existing targets, or `nil` for several.
    var organizeTargetName: String? {
        if let id = organizeTargetProfileID {
            return watchFolderName(id: id)
        }
        return hasMultipleWatchFolders ? nil : watchFolderProfiles.first?.displayName
    }

    var organizePausedNote: String? {
        let targets = organizeTargets(for: organizeTargetProfileID)
        return targets.contains(where: { !$0.profile.isOrganizing })
            ? OrganizeExistingCopy.pausedOneShotNote
            : nil
    }

    /// Group header in the preview; names the watch folder when the preview
    /// spans more than one.
    func organizeGroupTitle(_ group: OrganizePreviewGroup) -> String {
        guard organizeTargetProfileID == nil, hasMultipleWatchFolders,
              let controller = watchFolderController(containing: group.destinationDirectory)
        else {
            return group.destinationFolderName
        }
        return "\(controller.displayName) › \(group.destinationFolderName)"
    }

    private func organizeTargets(for profileID: String?) -> [WatchFolderController] {
        let candidates = profileID.flatMap { id in watchFolderController(id: id).map { [$0] } }
            ?? watchFolderControllers
        return candidates.filter { !$0.accessLost }
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

    /// Organize Existing for one watch folder, or every folder when `profileID`
    /// is `nil`. Each folder is scanned and previewed with its own scoped rules.
    func requestOrganizeExisting(profileID: String? = nil) {
        if isOrganizingExisting {
            organizeProgressPresented = true
            openActivity()
            return
        }
        organizeTargetProfileID = profileID
        organizeContentTask?.cancel()
        organizeReadingContents = false
        let scans = organizeTargets(for: profileID).map { controller in
            (controller: controller, scan: OrganizeExistingScanner(watchFolder: controller.folder).scan())
        }
        let preview = Self.combinedPreview(scans, contentAwareNames: [:])
        organizePreview = preview
        organizeExcludedURLs = []
        openActivity()
        if preview.isEmpty {
            organizeNothingPresented = true
            return
        }
        organizePreviewPresented = true
        readContentAwareNames(for: scans)
    }

    private static func combinedPreview(
        _ scans: [(controller: WatchFolderController, scan: OrganizeExistingScan)],
        contentAwareNames: [URL: String]
    ) -> OrganizeExistingPreview {
        var groups: [OrganizePreviewGroup] = []
        var skipped: [OrganizeExistingSkip] = []
        for (controller, scan) in scans {
            let preview = OrganizeExistingPreviewBuilder.build(
                scan: scan,
                pipeline: controller.pipeline,
                contentAwareNames: contentAwareNames
            )
            groups.append(contentsOf: preview.groups)
            skipped.append(contentsOf: preview.skipped)
        }
        return OrganizeExistingPreview(groups: groups, skipped: skipped)
    }

    /// With content-aware rename on, reads eligible files on this Mac and
    /// rebuilds the preview so it shows (and Apply uses) their content names.
    private func readContentAwareNames(
        for scans: [(controller: WatchFolderController, scan: OrganizeExistingScan)]
    ) {
        guard let renamer = contentAwareRenamer() else { return }
        let normalizer = FileNameNormalizer()
        let candidates = scans.flatMap(\.scan.eligible)
            .filter { renamer.isEligible($0) }
            .prefix(Self.organizeContentAwareLimit)
        guard !candidates.isEmpty else { return }
        organizeReadingContents = true
        organizeContentTask = Task { @MainActor in
            var names: [URL: String] = [:]
            for url in candidates {
                guard !Task.isCancelled else { return }
                let titleCase = normalizer.proposedFileName(for: url)
                if let name = await renamer.proposal(for: url, currentFileName: titleCase).fileName {
                    names[url.standardizedFileURL] = name
                }
            }
            guard !Task.isCancelled else { return }
            self.organizeReadingContents = false
            guard self.organizePreviewPresented else { return }
            self.organizePreview = Self.combinedPreview(scans, contentAwareNames: names)
        }
    }

    /// Cap on files read for one Organize Existing preview; the rest keep
    /// Title Case names.
    static let organizeContentAwareLimit = 40

    /// The content-aware renamer when the feature is on and the on-device
    /// model can run on this Mac; `nil` otherwise (files keep Title Case).
    func contentAwareRenamer() -> ContentAwareRenamer? {
        guard contentAwareRename.isEnabled else { return nil }
        contentAwareAvailability = .current
        guard contentAwareAvailability.isAvailable else { return nil }
        return ContentAwareRenamer(
            settings: contentAwareRename,
            extractor: OnDeviceTextExtractor(),
            namer: FoundationModelsContentNamer()
        )
    }

    /// "Try on a file…": what content-aware rename would call `url`, without
    /// renaming anything. Runs even while the master toggle is off.
    func tryContentAwareName(for url: URL) async -> String {
        contentAwareAvailability = .current
        if let message = contentAwareAvailability.message {
            return message
        }
        var settings = contentAwareRename
        settings.isEnabled = true
        let renamer = ContentAwareRenamer(
            settings: settings,
            extractor: OnDeviceTextExtractor(),
            namer: FoundationModelsContentNamer()
        )
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        let titleCase = FileNameNormalizer().proposedFileName(for: url)
        switch await renamer.proposal(for: url, currentFileName: titleCase) {
        case .proposed(let name):
            return "Would rename to “\(name)”."
        case .fallback(let reason):
            return "Keeps “\(titleCase)”. \(reason.reasonText)"
        }
    }

    func confirmOrganizePreview() {
        organizeContentTask?.cancel()
        organizeReadingContents = false
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
        organizeContentTask?.cancel()
        organizeReadingContents = false
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
        // Each item is applied by the folder it sits in, with that folder's rules.
        let batches: [(controller: WatchFolderController, items: [OrganizePreviewItem])] =
            watchFolderControllers.compactMap { controller in
                let items = selectedItems.filter {
                    $0.plan.sourceURL.deletingLastPathComponent().standardizedFileURL.path
                        == controller.folder.standardizedFileURL.path
                }
                return items.isEmpty ? nil : (controller, items)
            }
        for batch in batches {
            batch.controller.removeFromWaitingQueue(
                Set(batch.items.map { $0.plan.sourceURL.standardizedFileURL })
            )
        }

        organizeTask = Task { @MainActor in
            for skip in preScanned where !skip.url.lastPathComponent.hasPrefix(".") {
                self.record(
                    ActivityEntry(
                        kind: .skipped,
                        detail: "Skipped \(skip.url.lastPathComponent) — \(skip.reason.reasonText.lowercased())",
                        url: skip.url,
                        fileName: skip.url.lastPathComponent
                    ),
                    watchFolderID: self.watchFolderController(containing: skip.url)?.profileID
                )
            }

            var summary = OrganizeExistingSummary(organized: 0, skipped: preScanned.count, errors: 0)
            var processedBefore = 0
            for batch in batches {
                let id = batch.controller.profileID
                let result = batch.controller.processor.applyPreview(
                    items: batch.items,
                    isCancelled: { Task.isCancelled || self.organizeCancelRequested },
                    onProgress: { processed, _ in
                        self.organizeProcessedCount = processedBefore + processed
                    },
                    onFileResult: { fileResult in
                        switch fileResult {
                        case .organized(let entries):
                            self.recordOrganized(entries, watchFolderID: id)
                        case .skipped(let entry), .error(let entry):
                            self.record(entry, watchFolderID: id)
                        case .notInWatchRoot:
                            break
                        }
                    }
                )
                processedBefore += batch.items.count
                summary.organized += result.summary.organized
                summary.skipped += result.summary.skipped
                summary.errors += result.summary.errors
                if result.summary.cancelled {
                    summary.cancelled = true
                    break
                }
            }

            self.organizeSummary = summary
            self.isOrganizingExisting = false
            self.organizeProgressPresented = false
            self.organizeDonePresented = true
            self.organizePreview = nil
            self.organizeExcludedURLs = []
            self.scanCleanupCandidates()
            self.watchFolderControllers.forEach { $0.flushArrivedDuringOrganize() }
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
        isEnabled: Bool,
        subfolderPattern: SubfolderPattern = .none,
        scope: RuleScope = .allWatchFolders
    ) {
        if let id {
            rules = RuleMutation.updating(
                rules,
                id: id,
                folderName: folderName,
                extensions: extensions,
                conditions: conditions,
                isEnabled: isEnabled,
                subfolderPattern: subfolderPattern,
                scope: scope
            )
        } else {
            rules = RuleMutation.addingCustom(
                rules,
                folderName: folderName,
                extensions: extensions,
                conditions: conditions,
                isEnabled: isEnabled,
                subfolderPattern: subfolderPattern,
                scope: scope
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
        var histogram: [String: Int] = [:]
        for controller in watchFolderControllers {
            let counts = WatchRootHistogram.counts(
                watchFolder: controller.folder,
                ignorePolicy: controller.ignorePolicy
            )
            histogram.merge(counts, uniquingKeysWith: +)
        }
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

    func requestOpenRouterIfNeeded(entries: [ActivityEntry]) {
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
        guard fileManager.fileExists(atPath: url.path),
              let controller = watchFolderController(containing: url)
        else {
            return
        }
        let destDir = controller.folder.appendingPathComponent(folderName, isDirectory: true)
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
                ),
                watchFolderID: controller.profileID
            )
            controller.pruneEmptyManagedFolders()
        } catch {
            record(
                ActivityEntry(
                    kind: .error,
                    detail: "Could not file \(url.lastPathComponent): \(error.localizedDescription)",
                    url: url,
                    fileName: url.lastPathComponent
                ),
                watchFolderID: controller.profileID
            )
        }
    }

    /// Scans the Cleanup scope (one watch folder or all), each folder with its
    /// own category folders.
    func scanCleanupCandidates() {
        let targets = cleanupFolderScope.flatMap { id in watchFolderController(id: id).map { [$0] } }
            ?? watchFolderControllers
        let mounted = mountedVolumeURLs()
        var found: [CleanupCandidate] = []
        var owners: [URL: String] = [:]
        for controller in targets where !controller.accessLost {
            let candidates = CleanupScanner(
                watchFolder: controller.folder,
                thresholdDays: cleanupThresholdDays,
                includeWatchRoot: includeWatchRootInCleanup,
                snoozedUntil: snoozedUntil,
                ignorePolicy: controller.ignorePolicy,
                managedFolderNames: controller.managedFolderNames,
                hashCache: cleanupHashCache,
                mountedVolumeURLs: mounted,
                packageReceiptResolver: cleanupPackageReceiptResolver
            ).candidates()
            for candidate in candidates {
                owners[candidate.url] = controller.profileID
            }
            found.append(contentsOf: candidates)
        }
        cleanupProfileByURL = owners
        cleanupCandidates = found.sorted { $0.lastUsed < $1.lastUsed }
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

    /// The watch folder a Cleanup candidate was found in.
    private func cleanupController(for candidate: CleanupCandidate) -> WatchFolderController? {
        cleanupProfileByURL[candidate.url].flatMap(watchFolderController(id:))
            ?? watchFolderController(containing: candidate.url)
            ?? watchFolderControllers.first
    }

    func fileAway(_ candidate: CleanupCandidate) {
        guard let controller = cleanupController(for: candidate),
              let directory = DestinationFolderPicker.present(startingAt: controller.folder)
        else {
            return
        }
        do {
            let entry = try CleanupProcessor(
                watchFolder: controller.folder,
                managedFolderNames: controller.managedFolderNames
            ).fileAway(candidate, to: directory)
            record(entry, watchFolderID: controller.profileID)
            controller.pruneEmptyManagedFolders()
            scanCleanupCandidates()
        } catch {
            record(
                ActivityEntry(
                    kind: .error,
                    detail: "Could not file away \(candidate.url.lastPathComponent): \(error.localizedDescription)",
                    url: candidate.url,
                    fileName: candidate.url.lastPathComponent
                ),
                watchFolderID: controller.profileID
            )
        }
    }

    func keep(_ candidate: CleanupCandidate) {
        var next = snoozedUntil
        next[CleanupScanner.snoozeKey(for: candidate.url)] = CleanupScanner(
            watchFolder: cleanupController(for: candidate)?.folder ?? candidate.url.deletingLastPathComponent(),
            thresholdDays: cleanupThresholdDays,
            includeWatchRoot: includeWatchRootInCleanup,
            snoozedUntil: snoozedUntil
        ).snoozeDate()
        snoozedUntil = next
        scanCleanupCandidates()
    }

    func delete(_ candidate: CleanupCandidate) {
        let controller = cleanupController(for: candidate)
        let profileID = controller?.profileID
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
                        ),
                        watchFolderID: profileID
                    )
                    return
                }
                self.record(
                    ActivityEntry(
                        kind: .deleted,
                        detail: "Deleted \(candidate.url.lastPathComponent)",
                        fileName: candidate.url.lastPathComponent
                    ),
                    watchFolderID: profileID
                )
                controller?.pruneEmptyManagedFolders()
                self.scanCleanupCandidates()
            }
        }
    }

    /// Records one Activity entry, stamped with the watch folder it came from.
    func record(_ entry: ActivityEntry, watchFolderID: String? = nil) {
        let entry = Self.stamped(entry, watchFolderID: watchFolderID)
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
    func recordOrganized(_ entries: [ActivityEntry], watchFolderID: String? = nil) {
        let entries = entries.map { Self.stamped($0, watchFolderID: watchFolderID) }
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
            watchFolderController(containing: restored)?
                .acknowledgeRootFile(named: restored.lastPathComponent)
            if action.afterURL.lastPathComponent != restored.lastPathComponent {
                watchFolderController(containing: action.afterURL)?
                    .acknowledgeRootFile(named: action.afterURL.lastPathComponent)
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
        watchFolderControllers.forEach { $0.updateIgnorePolicy() }
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

    private static func stamped(_ entry: ActivityEntry, watchFolderID: String?) -> ActivityEntry {
        guard let watchFolderID, entry.watchFolderID == nil else { return entry }
        var copy = entry
        copy.watchFolderID = watchFolderID
        return copy
    }

    /// The 1.2 single watch folder: its bookmark when it resolves, else
    /// Downloads. Only used to migrate it into profile #1.
    private static func resolveLegacyWatchFolder() -> URL {
        let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Downloads")
        guard let data = UserDefaults.standard.data(forKey: WatchFolderProfileStore.legacyBookmarkKey) else {
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
    static let cleanupDays = "intake.cleanupDays"
    static let includeRoot = "intake.includeWatchRoot"
    static let aiSuggestions = "intake.aiSuggestions"
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
