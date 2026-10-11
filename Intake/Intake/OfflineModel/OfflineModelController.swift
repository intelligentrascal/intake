import AppKit
import Foundation
import IntakeCore
import IntakeLlama
import Observation
import UserNotifications

/// Owns the Offline model provider on this Mac: setup and download state,
/// the installed model, the run policy, the rename queue and the loaded
/// session (SPEC §6–§9). Pure decisions live in IntakeCore; this class feeds
/// them real signals and performs their effects.
@Observable
@MainActor
final class OfflineModelController {
    enum ModelProblem: Equatable {
        /// The verified file is gone or unreadable.
        case damaged
        /// The model couldn't start on this Mac.
        case loadFailed
    }

    static let setupWindowID = "offline-setup"
    static let blockedTitle = "Can't rename right now"
    static let blockedMessage = "Your Mac is too hot or low on memory. Intake will rename this file when it recovers."

    // MARK: Persisted state

    var setup: OfflineSetupState {
        didSet { setup.save(to: defaults) }
    }
    private(set) var queue: OfflineRenameQueue {
        didSet { queue.save(to: defaults) }
    }
    var runSetting: OfflineModelRunSetting {
        didSet {
            defaults.set(runSetting.rawValue, forKey: OfflineModelRunSetting.defaultsKey)
            reevaluate()
        }
    }

    // MARK: Live state

    private(set) var machine = OfflineModelDownloadMachine()
    private(set) var hardware: MacHardwareProfile?
    private(set) var recommendation: OfflineModelRecommendation?
    /// O2 / Settings choice; `nil` = the recommendation.
    var selectedTier: OfflineModelTier?
    var onboardingStep: OfflineOnboardingStep = .welcome
    /// Bumped to open the setup window (menu, sheet, notification).
    private(set) var setupWindowRequestID: UInt64 = 0
    /// O3's cancel confirmation (also raised from the menu bar).
    var cancelConfirmationPresented = false
    var upgradeSheetPresented = false
    /// Activity's Rename Now hit row 1 (thermal / memory critical).
    var renameNowBlockedPresented = false
    private(set) var networkStatus: OfflineNetworkStatus = .unmetered
    private(set) var signals: ResourceSignals = ResourceSignals()
    private(set) var secondsRemaining: TimeInterval?
    /// Whole percent, updated at most once a second (menu bar ring).
    private(set) var ringPercent: Int = 0
    private(set) var isModelLoaded = false
    private(set) var modelProblem: ModelProblem?
    private(set) var isRenamingQueue = false
    /// "Too many files waiting. N kept their tidy names."
    var overflowNote: String?

    // MARK: Plumbing

    @ObservationIgnored private weak var model: AppModel?
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored let storage: OfflineModelStorage
    @ObservationIgnored let session: OfflineModelSession
    @ObservationIgnored private var systemSignals: OfflineSystemSignals?
    @ObservationIgnored private var hysteresis = ResourceSignalHysteresis()
    @ObservationIgnored private var rate = DownloadRateEstimator()
    @ObservationIgnored private var transfer: OfflineModelTransfer?
    @ObservationIgnored private var transferID = UUID()
    @ObservationIgnored private var lastRingUpdate = Date.distantPast
    @ObservationIgnored private var idleTask: Task<Void, Never>?
    @ObservationIgnored private var drainTask: Task<Void, Never>?
    @ObservationIgnored private var thermalUnloadTask: Task<Void, Never>?
    @ObservationIgnored private var holdReleaseTask: Task<Void, Never>?
    @ObservationIgnored private var verifyTask: Task<Void, Never>?
    @ObservationIgnored private var networkRetryTask: Task<Void, Never>?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        storage = OfflineModelStorage(root: OfflineModelStorage.defaultRoot())
        session = OfflineModelSession(runtime: LlamaRuntime())
        setup = OfflineSetupState.load(from: defaults)
        queue = OfflineRenameQueue.load(from: defaults)
        runSetting = defaults.string(forKey: OfflineModelRunSetting.defaultsKey)
            .flatMap(OfflineModelRunSetting.init(rawValue:)) ?? .smart
    }

    func attach(to model: AppModel) {
        self.model = model
    }

    // MARK: Launch

    func start(isFirstRun: Bool) {
        refreshHardware()
        let monitor = OfflineSystemSignals(architecture: hardware?.architecture ?? .appleSilicon)
        monitor.onChange = { [weak self] in self?.systemSignalsChanged() }
        monitor.start()
        systemSignals = monitor
        networkStatus = monitor.network
        signals = monitor.resources

        cleanUpPartials()
        checkInstalledModel()
        restoreDownload()

        queue.pruneExpired(now: Date())

        idleTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                guard let self else { return }
                await self.idleTick()
            }
        }

        presentLaunchSurfaces(isFirstRun: isFirstRun)
        reevaluate()
    }

    private func presentLaunchSurfaces(isFirstRun: Bool) {
        guard let model else { return }
        let installed = isModelInstalled
        if OfflineSetupVisibility.opensOnboardingAtLaunch(state: setup, isFirstRun: isFirstRun, modelInstalled: installed),
           !isUnsupported {
            // Give the menu bar / Settings bridges a moment to exist.
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(600))
                self?.openSetup(step: .welcome)
            }
            return
        }
        if OfflineSetupVisibility.showsUpgradeSheet(
            state: setup,
            isUpgrade: OfflineModelMigration.wasUpgrade(defaults: defaults),
            modelInstalled: installed
        ), !isUnsupported {
            upgradeSheetPresented = true
            model.openSettings(pane: .ai)
            return
        }
        considerReminder(.launch)
    }

    // MARK: Derived

    var installedTier: OfflineModelTier? {
        guard let tier = setup.installedTier, modelProblem != .damaged else { return nil }
        return tier
    }

    var installedEntry: OfflineModelManifestEntry? {
        installedTier.map(OfflineModelManifest.entry(for:))
    }

    var isModelInstalled: Bool { installedTier != nil }

    var isUnsupported: Bool { recommendation?.status == .unsupported }

    var architecture: MacArchitecture { hardware?.architecture ?? .appleSilicon }

    /// The tier Download acts on: the user's pick, else the recommendation.
    var chosenTier: OfflineModelTier? {
        if let selectedTier,
           recommendation?.options.contains(where: { $0.tier == selectedTier && $0.isEnabled }) ?? false {
            return selectedTier
        }
        return recommendation?.recommendedTier
    }

    func tierName(_ tier: OfflineModelTier) -> String {
        OfflineModelManifest.displayName(for: tier, on: architecture)
    }

    func line(_ tier: OfflineModelTier) -> OfflineTierLine {
        OfflineModelManifest.line(for: tier, on: architecture)
    }

    var loadConfiguration: LocalModelLoadConfiguration {
        LocalModelLoadConfiguration(useGPU: architecture == .appleSilicon)
    }

    var downloadingEntry: OfflineModelManifestEntry? {
        machine.tier.map(OfflineModelManifest.entry(for:))
    }

    var downloadFraction: Double {
        guard let entry = downloadingEntry, entry.byteSize > 0 else { return 0 }
        return min(max(Double(machine.receivedBytes) / Double(entry.byteSize), 0), 1)
    }

    /// "1.2 GB of 2.5 GB · about 3 minutes left"
    var progressText: String {
        guard let entry = downloadingEntry else { return "" }
        return OfflineModelFormat.progress(received: machine.receivedBytes, entry: entry, secondsRemaining: secondsRemaining)
    }

    var isVerifying: Bool {
        switch machine.phase {
        case .verifyingChecksum, .selfTesting: true
        default: false
        }
    }

    var isDownloadPaused: Bool {
        if case .paused = machine.phase { return true }
        return false
    }

    var isWaitingForNetwork: Bool {
        switch machine.phase {
        case .waitingForNetwork, .waitingForUnmetered: true
        default: false
        }
    }

    /// Menu bar's disabled status row while a download is active.
    var menuDownloadTitle: String? {
        guard machine.isActive else { return nil }
        if isVerifying { return "Checking the download…" }
        if isDownloadPaused {
            return "Downloading model · Paused at \(OfflineModelFormat.bytes(machine.receivedBytes))"
        }
        if isWaitingForNetwork { return "Downloading model · Paused — waiting for network" }
        let total = downloadingEntry?.byteSize ?? 0
        return "Downloading model · \(OfflineModelFormat.percent(received: machine.receivedBytes, total: total))"
    }

    var showsMenuSetUpItem: Bool {
        OfflineSetupVisibility.showsMenuSetUpItem(
            modelInstalled: isModelInstalled,
            provider: model?.contentAwareRename.provider ?? .localModel,
            downloadActive: machine.isActive,
            unsupported: isUnsupported
        )
    }

    /// The reason queued files show everywhere (menu, Settings, Activity).
    var queueReason: OfflineWaitReason {
        queue.items.first?.reason ?? .waitingForPower
    }

    var queuedPaths: Set<String> {
        Set(queue.items.map(\.path))
    }

    var queueItems: [QueuedOfflineRename] { queue.items }

    // MARK: Hardware / recommendation

    func refreshHardware() {
        let profile = MacHardwareProbe.profile(storageRoot: storage.root)
        hardware = profile
        recommendation = OfflineModelRecommender.recommend(for: profile, unsupportedTiers: setup.unsupportedTiers)
    }

    // MARK: Setup window

    func openSetup(step: OfflineOnboardingStep) {
        if machine.isActive || isVerifying {
            onboardingStep = isVerifying ? .verifying : .downloading
        } else {
            onboardingStep = step
            if step == .recommendation { refreshHardware() }
        }
        setup.reminderDotPending = false
        setupWindowRequestID &+= 1
    }

    func skipForNow() {
        if setup.skippedAt == nil { setup.skippedAt = Date() }
        setup.onboardingCompleted = true
    }

    func upgradeSheetChoseSetUp() {
        setup.upgradeSheetShown = true
        upgradeSheetPresented = false
        openSetup(step: .recommendation)
    }

    func upgradeSheetChoseNotNow() {
        setup.upgradeSheetShown = true
        upgradeSheetPresented = false
        // The reminder only fires for the Offline model provider (§8.5).
        if setup.skippedAt == nil { setup.skippedAt = Date() }
    }

    /// The window closed: anything short of a finished setup counts as Skip.
    func setupWindowClosed() {
        if !isModelInstalled, !machine.isActive {
            skipForNow()
        } else {
            setup.onboardingCompleted = true
        }
    }

    // MARK: Reminder (§8.5)

    func noteTitleCaseRename(fileName: String) {
        considerReminder(.titleCaseRename(fileName: fileName))
    }

    private func considerReminder(_ trigger: OfflineSetupReminder.Trigger) {
        guard let model else { return }
        guard OfflineSetupReminder.shouldFire(
            state: setup,
            trigger: trigger,
            now: Date(),
            modelInstalled: isModelInstalled,
            provider: model.contentAwareRename.provider
        ), !isUnsupported else { return }
        // Mark first so a burst of files can't fire twice while we ask.
        setup.reminderShown = true
        let sizeLabel = recommendation?.recommendedTier.map { OfflineModelManifest.entry(for: $0).sizeLabel }
            ?? OfflineModelManifest.standard.sizeLabel
        Task { @MainActor [weak self] in
            // Never asks for permission: Intake only asks when the user turns
            // notifications on. Not allowed → the monochrome menu bar dot.
            let settings = await UNUserNotificationCenter.current().notificationSettings()
            let authorized = settings.authorizationStatus == .authorized && settings.alertSetting == .enabled
            guard let self else { return }
            let delivery = OfflineSetupReminder.delivery(
                trigger: trigger,
                notificationsAuthorized: authorized,
                recommendedSizeLabel: sizeLabel
            )
            OfflineSetupReminder.markFired(&self.setup, delivery: delivery)
            if case .notification(let title, let body) = delivery {
                self.model?.deliverOfflineSetupReminder(title: title, body: body)
            }
        }
    }

    // MARK: Download

    func startDownload(_ tier: OfflineModelTier? = nil, switchToOffline: Bool? = nil) {
        guard let tier = tier ?? chosenTier else { return }
        refreshHardware()
        if let switchToOffline {
            setup.switchToOfflineOnVerify = switchToOffline
        } else if setup.switchToOfflineOnVerify == nil, let model {
            setup.switchToOfflineOnVerify = OfflineModelMigration.switchCheckboxDefault(for: model.contentAwareRename)
        }
        let entry = OfflineModelManifest.entry(for: tier)
        // A partial for another tier is dropped; one for this tier resumes.
        for other in OfflineModelManifest.entries where other.tier != tier {
            storage.deletePartial(for: other)
        }
        if setup.retainedPartial?.tier != tier { setup.retainedPartial = nil }
        handle(.requestDownload(
            tier,
            network: networkStatus,
            freeBytes: hardware?.freeDiskBytes ?? MacHardwareProbe.freeBytes(near: storage.root),
            partialBytes: storage.partialBytes(for: entry)
        ))
        if case .failed(_, .lowDisk) = machine.phase {
            // Not enough space to start: O2 explains it with the free space.
            handle(.reset)
            onboardingStep = .recommendation
            return
        }
        onboardingStep = .downloading
    }

    func meteredChoice(downloadAnyway: Bool) {
        handle(.meteredChoice(downloadAnyway: downloadAnyway))
    }

    func pauseDownload() { handle(.pause) }

    func resumeDownload() { handle(.resume(network: networkStatus)) }

    func cancelDownload() {
        handle(.cancel)
        onboardingStep = .recommendation
    }

    /// Settings: "Resume" for a partial kept after Cancel.
    var resumablePartial: RetainedPartialDownload? {
        guard let retained = setup.retainedPartial, !retained.isExpired(now: Date()) else { return nil }
        let entry = OfflineModelManifest.entry(for: retained.tier)
        return storage.partialBytes(for: entry) > 0 ? retained : nil
    }

    func deleteModel() {
        guard let tier = setup.installedTier else { return }
        Task { await session.unload() }
        isModelLoaded = false
        storage.deleteModel(for: OfflineModelManifest.entry(for: tier))
        setup.installedTier = nil
        modelProblem = nil
        if !machine.isActive { handle(.reset) }
        queue.removeAll()
    }

    private func handle(_ event: OfflineModelDownloadMachine.Event) {
        let effects = machine.handle(event)
        for effect in effects {
            perform(effect)
        }
        if case .downloading = machine.phase {} else {
            secondsRemaining = nil
        }
        persistDownloadPhase()
        updateRing(force: true)
        scheduleNetworkRetryIfNeeded()
    }

    /// Waiting for the network while the path looks fine (server error,
    /// timeout): try again every 30 s instead of waiting for a path change.
    private func scheduleNetworkRetryIfNeeded() {
        guard case .waitingForNetwork = machine.phase, networkStatus != .offline else {
            networkRetryTask?.cancel()
            networkRetryTask = nil
            return
        }
        guard networkRetryTask == nil else { return }
        networkRetryTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(30))
            guard let self, !Task.isCancelled else { return }
            self.networkRetryTask = nil
            self.handle(.networkChanged(self.networkStatus))
        }
    }

    private func perform(_ effect: OfflineModelDownloadMachine.Effect) {
        switch effect {
        case .startTransfer(let tier, let fromByte):
            startTransfer(tier, fromByte: fromByte)
        case .stopTransfer:
            transfer?.cancel()
            transfer = nil
            transferID = UUID()
        case .retainPartial(let tier):
            setup.retainedPartial = RetainedPartialDownload(tier: tier, cancelledAt: Date())
        case .deletePartial(let tier):
            storage.deletePartial(for: OfflineModelManifest.entry(for: tier))
            if setup.retainedPartial?.tier == tier { setup.retainedPartial = nil }
        case .verifyChecksum(let tier):
            verify(tier)
        case .runSelfTest(let tier):
            runSelfTest(tier)
        case .install(let tier):
            install(tier)
        case .deleteModel(let tier):
            let entry = OfflineModelManifest.entry(for: tier)
            storage.deletePartial(for: entry)
            if setup.installedTier != tier { storage.deleteModel(for: entry) }
            setup.unsupportedTiers.insert(tier)
            recommendation = hardware.map {
                OfflineModelRecommender.recommend(for: $0, unsupportedTiers: setup.unsupportedTiers)
            }
        }
    }

    private func startTransfer(_ tier: OfflineModelTier, fromByte: Int64) {
        let entry = OfflineModelManifest.entry(for: tier)
        do {
            try storage.prepareDirectories()
            excludeFromBackup(storage.root)
        } catch {
            handle(.transferFailedDiskFull(shortBytes: entry.byteSize - fromByte))
            return
        }
        transfer?.cancel()
        rate.reset()
        let id = UUID()
        transferID = id
        let transfer = OfflineModelTransfer(
            sourceURL: entry.downloadURL,
            destination: storage.partialURL(for: entry),
            startByte: fromByte,
            expectedTotal: entry.byteSize,
            onProgress: { [weak self] bytes in
                Task { @MainActor in self?.transferProgress(bytes, id: id) }
            },
            onComplete: { [weak self] outcome in
                Task { @MainActor in self?.transferCompleted(outcome, id: id) }
            }
        )
        self.transfer = transfer
        transfer.start()
    }

    private func transferProgress(_ bytes: Int64, id: UUID) {
        guard id == transferID, case .downloading = machine.phase else { return }
        machine.handle(.progress(receivedBytes: bytes))
        let now = Date()
        rate.record(bytes: bytes, at: now)
        if let total = downloadingEntry?.byteSize {
            secondsRemaining = rate.secondsRemaining(received: bytes, total: total)
        }
        updateRing(force: false)
    }

    private func transferCompleted(_ outcome: OfflineModelTransfer.Outcome, id: UUID) {
        guard id == transferID else { return }
        transfer = nil
        switch outcome {
        case .finished(let total):
            handle(.transferFinished(totalBytes: total))
        case .httpStatus(let status):
            handle(.transferFailedHTTP(status: status))
        case .networkLost(let received):
            handle(.transferFailedNetwork(receivedBytes: received))
        case .diskFull(let short):
            handle(.transferFailedDiskFull(shortBytes: short))
        case .cancelled:
            break
        }
    }

    private func verify(_ tier: OfflineModelTier) {
        onboardingStep = .verifying
        let entry = OfflineModelManifest.entry(for: tier)
        let url = storage.partialURL(for: entry)
        verifyTask = Task { @MainActor [weak self] in
            let matches = await Task.detached(priority: .utility) {
                OfflineModelFileVerifier.verify(url, against: entry)
            }.value
            self?.handle(.checksumResult(matches: matches))
        }
    }

    /// Load the verified file and name a bundled sample within 30 s.
    private func runSelfTest(_ tier: OfflineModelTier) {
        let entry = OfflineModelManifest.entry(for: tier)
        let url = storage.partialURL(for: entry)
        let configuration = loadConfiguration
        let session = session
        verifyTask = Task { @MainActor [weak self] in
            let started = Date()
            do {
                try await session.load(model: url, configuration: configuration)
            } catch {
                await session.unload()
                self?.handle(.loadFailed)
                return
            }
            let namer = OfflineModelContentNamer(session: session, entry: entry, modelURL: url, configuration: configuration)
            let fields = await Self.withTimeout(OfflineModelSelfTest.timeLimit) {
                await namer.fields(for: OfflineModelSelfTest.sampleInput)
            }
            let passed = OfflineModelSelfTest.passed(fields ?? nil, elapsed: Date().timeIntervalSince(started))
            // Reload from the installed path on first real use.
            await session.unload()
            self?.handle(.selfTestResult(passed: passed))
        }
    }

    private func install(_ tier: OfflineModelTier) {
        let entry = OfflineModelManifest.entry(for: tier)
        do {
            if let previous = setup.installedTier, previous != tier {
                storage.deleteModel(for: OfflineModelManifest.entry(for: previous))
            }
            _ = try storage.installPartial(for: entry)
            excludeFromBackup(storage.root)
        } catch {
            modelProblem = .damaged
            handle(.reset)
            return
        }
        setup.installedTier = tier
        setup.retainedPartial = nil
        setup.onboardingCompleted = true
        setup.unsupportedTiers.remove(tier)
        modelProblem = nil
        if let model {
            model.contentAwareRename = OfflineModelMigration.applyingVerifiedModel(
                to: model.contentAwareRename,
                switchToOffline: setup.switchToOfflineOnVerify ?? true
            )
        }
        onboardingStep = .ready
        reevaluate()
    }

    /// O5's checkbox, shown to upgraders still on another provider.
    var readyCheckboxDefault: Bool? {
        guard let model else { return nil }
        guard OfflineModelMigration.wasUpgrade(defaults: defaults) else { return nil }
        return setup.switchToOfflineOnVerify.flatMap { value in
            model.contentAwareRename.provider == .localModel && value ? nil : value
        } ?? OfflineModelMigration.switchCheckboxDefault(for: model.contentAwareRename)
    }

    /// O5 checkbox changed after install: switch provider now.
    func setUseOfflineModel(_ on: Bool) {
        guard let model else { return }
        setup.switchToOfflineOnVerify = on
        if on {
            model.contentAwareRename.provider = .localModel
            model.contentAwareRename.isEnabled = true
        }
    }

    private func persistDownloadPhase() {
        switch machine.phase {
        case .downloading(let tier, _), .waitingForNetwork(let tier, _), .waitingForUnmetered(let tier),
             .confirmingMetered(let tier):
            setup.activeDownloadTier = tier
            setup.activeDownloadPaused = false
        case .paused(let tier, _):
            setup.activeDownloadTier = tier
            setup.activeDownloadPaused = true
        case .idle, .verifyingChecksum, .selfTesting, .ready, .failed:
            if setup.activeDownloadTier != nil {
                setup.activeDownloadTier = nil
                setup.activeDownloadPaused = false
            }
        }
    }

    private func restoreDownload() {
        guard let tier = setup.activeDownloadTier else { return }
        let entry = OfflineModelManifest.entry(for: tier)
        handle(.restore(
            tier,
            partialBytes: storage.partialBytes(for: entry),
            wasPaused: setup.activeDownloadPaused,
            network: networkStatus
        ))
    }

    private func cleanUpPartials() {
        let now = Date()
        if let retained = setup.retainedPartial, retained.isExpired(now: now) {
            storage.deletePartial(for: OfflineModelManifest.entry(for: retained.tier))
            setup.retainedPartial = nil
        }
        var keep: Set<String> = []
        for tier in [setup.retainedPartial?.tier, setup.activeDownloadTier].compactMap({ $0 }) {
            keep.insert(storage.partialURL(for: tier).lastPathComponent)
        }
        for stray in storage.strayPartials(keeping: keep) {
            try? FileManager.default.removeItem(at: stray)
        }
    }

    private func checkInstalledModel() {
        guard let tier = setup.installedTier else { return }
        let entry = OfflineModelManifest.entry(for: tier)
        // A size check at launch; the full SHA-256 ran before install.
        modelProblem = storage.isInstalled(entry) ? nil : .damaged
    }

    private func excludeFromBackup(_ url: URL) {
        var url = url
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? url.setResourceValues(values)
    }

    private func updateRing(force: Bool) {
        let percent = Int((downloadFraction * 100).rounded(.down))
        let now = Date()
        guard force || (percent != ringPercent && now.timeIntervalSince(lastRingUpdate) >= 1) else { return }
        lastRingUpdate = now
        if percent != ringPercent { ringPercent = percent }
    }

    // MARK: Naming

    /// The `ContentNamer` for the Offline model provider, or `nil` when no
    /// verified model is installed.
    func contentNamer() -> (any ContentNamer)? {
        guard let entry = installedEntry, modelProblem == nil else { return nil }
        let namer = OfflineModelContentNamer(
            session: session,
            entry: entry,
            modelURL: storage.modelURL(for: entry),
            configuration: loadConfiguration
        )
        return ObservedOfflineNamer(inner: namer) { [weak self] loaded in
            Task { @MainActor in self?.noteGeneration(loaded: loaded) }
        }
    }

    private func noteGeneration(loaded: Bool) {
        isModelLoaded = loaded
        if !loaded, modelProblem == nil, let entry = installedEntry, !storage.isInstalled(entry) {
            modelProblem = .damaged
        }
    }

    /// Run-policy answer for this kind of work right now.
    func decide(_ work: OfflineWorkKind) -> OfflinePolicyDecision {
        let raw = systemSignals?.sample() ?? signals
        let effective = hysteresis.effective(raw, now: Date())
        let decision = OfflineModelPolicy.decide(
            work: work,
            setting: runSetting,
            signals: effective,
            isModelLoaded: isModelLoaded,
            activeTier: installedTier ?? .lite,
            installedBackup: nil
        )
        if case .wait(_, let unload) = decision {
            applyUnload(unload)
        }
        scheduleHoldRelease()
        return decision
    }

    private func applyUnload(_ directive: OfflineUnloadDirective) {
        switch directive {
        case .keep:
            break
        case .now:
            thermalUnloadTask?.cancel()
            drainTask?.cancel()
            Task { [session] in await session.unload() }
            isModelLoaded = false
        case .after(let delay):
            guard thermalUnloadTask == nil else { return }
            thermalUnloadTask = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(delay))
                guard let self, !Task.isCancelled else { return }
                self.thermalUnloadTask = nil
                if self.decide(.singleNewFile).waitReason == .macIsHot {
                    await self.session.unload()
                    self.isModelLoaded = false
                }
            }
        }
    }

    // MARK: Queue (§9.3)

    /// Queue a file that keeps its Title Case name for now.
    func enqueue(_ url: URL, watchFolderID: String, reason: OfflineWaitReason) {
        let fileNumber = (try? FileManager.default.attributesOfItem(atPath: url.path)[.systemFileNumber] as? NSNumber)?
            .uint64Value
        let dropped = queue.enqueue(QueuedOfflineRename(
            url: url,
            fileIdentifier: fileNumber,
            watchFolderID: watchFolderID,
            enqueuedAt: Date(),
            reason: reason
        ))
        queue.setReason(reason)
        if dropped > 0, let note = queue.takeOverflowNote() {
            overflowNote = note
        }
    }

    /// Intake filed or renamed a queued file: follow it.
    func noteMoved(from old: URL, to new: URL) {
        guard queue.contains(path: old.standardizedFileURL.path) else { return }
        queue.noteMoved(from: old, to: new)
    }

    /// The provider changed away from the Offline model: queued files keep
    /// their Title Case names.
    func providerChanged(to provider: ContentAwareRenameProvider) {
        if provider != .localModel, !queue.isEmpty {
            drainTask?.cancel()
            queue.removeAll()
        }
    }

    /// Rename Now (one file) / Rename All Now.
    func renameNow(_ ids: [UUID]? = nil) {
        if case .wait = decide(.renameNow) {
            renameNowBlockedPresented = true
            return
        }
        if let ids {
            for id in ids.reversed() { queue.prioritize(id: id) }
        }
        drain(work: .renameNow, onlyIDs: ids.map(Set.init))
    }

    private func systemSignalsChanged() {
        guard let systemSignals else { return }
        signals = systemSignals.resources
        if networkStatus != systemSignals.network {
            networkStatus = systemSignals.network
            if machine.phase != .idle {
                handle(.networkChanged(networkStatus))
            }
        }
        reevaluate()
    }

    /// Re-run the policy after any change: unload, update reasons, drain.
    func reevaluate() {
        guard isModelInstalled else { return }
        guard !queue.isEmpty else {
            // Nothing waiting: still apply unload rules to a loaded model.
            if isModelLoaded { _ = decide(.singleNewFile) }
            return
        }
        let decision = decide(.batch)
        switch decision {
        case .run:
            drain(work: .batch, onlyIDs: nil)
        case .wait(let reason, _):
            if queue.items.contains(where: { $0.reason != reason }) {
                queue.setReason(reason)
            }
        }
    }

    private func scheduleHoldRelease() {
        guard let delay = hysteresis.nextRelease(now: Date()) else { return }
        holdReleaseTask?.cancel()
        holdReleaseTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(delay + 0.5))
            guard !Task.isCancelled else { return }
            self?.reevaluate()
        }
    }

    private func drain(work: OfflineWorkKind, onlyIDs: Set<UUID>?) {
        guard drainTask == nil, let model, isModelInstalled else { return }
        guard model.contentAwareRename.provider == .localModel || work == .renameNow else { return }
        isRenamingQueue = true
        drainTask = Task { @MainActor [weak self] in
            await self?.drainLoop(work: work, onlyIDs: onlyIDs)
            self?.drainTask = nil
            self?.isRenamingQueue = false
        }
    }

    private func drainLoop(work: OfflineWorkKind, onlyIDs: Set<UUID>?) async {
        while !Task.isCancelled {
            let chunk = queue.nextChunk().filter { onlyIDs?.contains($0.id) ?? true }
            guard !chunk.isEmpty else { return }
            for item in chunk {
                guard !Task.isCancelled else { return }
                if case .wait(let reason, _) = decide(work) {
                    queue.setReason(reason)
                    return
                }
                await renameQueued(item)
            }
            // Between chunks (20 files), let the Mac breathe and re-sample.
            try? await Task.sleep(for: .milliseconds(500))
        }
    }

    private func renameQueued(_ item: QueuedOfflineRename) async {
        guard let model else { return }
        queue.remove(id: item.id)
        let url = item.url
        let fileManager = FileManager.default
        let exists = fileManager.fileExists(atPath: url.path)
        let fileNumber = (try? fileManager.attributesOfItem(atPath: url.path)[.systemFileNumber] as? NSNumber)?.uint64Value
        let lastOpened = (try? url.resourceValues(forKeys: [.contentAccessDateKey]))?.contentAccessDate
        let snapshot = QueuedFileSnapshot(
            exists: exists,
            fileIdentifier: fileNumber,
            // Access dates move on any read (Quick Look, Spotlight indexing);
            // treat only a read well after queueing as "opened".
            lastOpened: lastOpened.flatMap { $0.timeIntervalSince(item.enqueuedAt) > 5 ? $0 : nil },
            isInsideManagedFolder: model.isInsideWatchFolder(url, profileID: item.watchFolderID)
        )
        guard QueuedRenameCheck.evaluate(item, snapshot: snapshot) == .proceed else { return }
        guard let renamer = model.offlineRenamer() else { return }
        let proposal = await renamer.proposal(for: url)
        guard let name = proposal.fileName else { return }
        model.applyDeferredContentRename(at: url, to: name, profileID: item.watchFolderID)
    }

    private func idleTick() async {
        if await session.unloadIfIdle() {
            isModelLoaded = false
        }
        if let retained = setup.retainedPartial, retained.isExpired(now: Date()) {
            storage.deletePartial(for: OfflineModelManifest.entry(for: retained.tier))
            setup.retainedPartial = nil
        }
        if queue.items.contains(where: { Date().timeIntervalSince($0.enqueuedAt) > OfflineRenameQueue.maximumAge }) {
            queue.pruneExpired(now: Date())
        }
    }

    // MARK: Helpers

    nonisolated private static func withTimeout<T: Sendable>(
        _ seconds: TimeInterval,
        _ work: @escaping @Sendable () async -> T
    ) async -> T? {
        await withTaskGroup(of: T?.self) { group in
            group.addTask { await work() }
            group.addTask {
                try? await Task.sleep(for: .seconds(seconds))
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
    }
}

/// Wraps the offline namer to report load state back to the controller.
nonisolated private struct ObservedOfflineNamer: ContentNamer {
    var inner: OfflineModelContentNamer
    var onFinish: @Sendable (Bool) -> Void

    func fields(for input: ContentNamingInput) async -> ContentNamingFields? {
        let fields = await inner.fields(for: input)
        onFinish(await inner.session.isLoaded)
        return fields
    }
}
