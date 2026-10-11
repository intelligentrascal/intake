import Foundation

/// Provider migration for 1.4.0 (SPEC §3, locked).
///
/// | Before upgrade              | After upgrade                                       |
/// |-----------------------------|-----------------------------------------------------|
/// | `isEnabled == false`        | `localModel`                                        |
/// | Enabled on Apple Intelligence | stays until the download is verified, then switches (O5 checkbox pre-checked) |
/// | Enabled on OpenRouter       | stays; O5 checkbox unchecked                         |
public enum OfflineModelMigration {
    public static let migratedKey = "intake.offlineModel.migrated"

    /// Keys only an earlier Intake writes; any of them means this is an upgrade.
    public static let priorInstallKeys = [
        ContentAwareRenameSettings.defaultsKey,
        "intake.didShowMenuBarTip",
        "intake.activity",
        "intake.rules",
        "intake.settingsPane",
    ]

    public static func isUpgrade(defaults: UserDefaults) -> Bool {
        priorInstallKeys.contains { defaults.object(forKey: $0) != nil }
    }

    public static func migrated(_ settings: ContentAwareRenameSettings) -> ContentAwareRenameSettings {
        var settings = settings
        if !settings.isEnabled {
            settings.provider = .localModel
        }
        return settings
    }

    /// Set on the first 1.4 launch: true when an earlier Intake ran here.
    public static let upgradedKey = "intake.offlineModel.upgradedInstall"

    /// Runs once per install, before anything else writes defaults. Returns
    /// the settings to use; `wasUpgrade(defaults:)` remembers the answer.
    @discardableResult
    public static func migrateIfNeeded(defaults: UserDefaults) -> ContentAwareRenameSettings {
        let loaded = ContentAwareRenameSettings.load(from: defaults)
        guard !defaults.bool(forKey: migratedKey) else { return loaded }
        defaults.set(isUpgrade(defaults: defaults), forKey: upgradedKey)
        let settings = migrated(loaded)
        if defaults.data(forKey: ContentAwareRenameSettings.defaultsKey) != nil || settings != loaded {
            settings.save(to: defaults)
        }
        defaults.set(true, forKey: migratedKey)
        return settings
    }

    public static func wasUpgrade(defaults: UserDefaults) -> Bool {
        defaults.bool(forKey: upgradedKey)
    }

    /// O5 upgrade variant: whether "Use the offline model for renaming"
    /// shows, and its default. `nil` = no checkbox (already on the offline model).
    public static func switchCheckboxDefault(for settings: ContentAwareRenameSettings) -> Bool? {
        guard settings.isEnabled else { return nil }
        switch settings.provider {
        case .localModel: return nil
        case .onDevice: return true
        case .openRouter: return false
        }
    }

    /// The model passed its checksum and self-test. Clicking Download was the
    /// opt-in: the Offline model provider turns on. Other providers switch
    /// only when the O5 checkbox says so.
    public static func applyingVerifiedModel(
        to settings: ContentAwareRenameSettings,
        switchToOffline: Bool
    ) -> ContentAwareRenameSettings {
        var settings = settings
        if settings.provider == .localModel || !settings.isEnabled {
            settings.provider = .localModel
            settings.isEnabled = true
        } else if switchToOffline {
            settings.provider = .localModel
            settings.isEnabled = true
        }
        return settings
    }
}

/// O1–O5 (SPEC §8.2). One window, one step at a time.
public enum OfflineOnboardingStep: String, Equatable, Codable, Sendable {
    case welcome
    case recommendation
    case downloading
    case verifying
    case ready
}

/// Persisted onboarding / reminder facts (SPEC §8.5).
public struct OfflineSetupState: Equatable, Codable, Sendable {
    public static let defaultsKey = "intake.offlineModel.setup"

    /// When the user chose Skip for Now (or Not Now on the upgrade sheet).
    public var skippedAt: Date?
    /// `intake.offlineModel.reminderShown`: fires once ever.
    public var reminderShown: Bool
    /// Notifications were off: the menu bar shows a template dot instead.
    public var reminderDotPending: Bool
    public var upgradeSheetShown: Bool
    public var onboardingCompleted: Bool
    /// Tiers that failed their self-test on this Mac.
    public var unsupportedTiers: Set<OfflineModelTier>
    /// O5 upgrade checkbox, captured when the download starts.
    public var switchToOfflineOnVerify: Bool?
    /// Installed and verified tier.
    public var installedTier: OfflineModelTier?
    public var retainedPartial: RetainedPartialDownload?
    /// A download was running or paused at quit.
    public var activeDownloadTier: OfflineModelTier?
    public var activeDownloadPaused: Bool

    public init(
        skippedAt: Date? = nil,
        reminderShown: Bool = false,
        reminderDotPending: Bool = false,
        upgradeSheetShown: Bool = false,
        onboardingCompleted: Bool = false,
        unsupportedTiers: Set<OfflineModelTier> = [],
        switchToOfflineOnVerify: Bool? = nil,
        installedTier: OfflineModelTier? = nil,
        retainedPartial: RetainedPartialDownload? = nil,
        activeDownloadTier: OfflineModelTier? = nil,
        activeDownloadPaused: Bool = false
    ) {
        self.skippedAt = skippedAt
        self.reminderShown = reminderShown
        self.reminderDotPending = reminderDotPending
        self.upgradeSheetShown = upgradeSheetShown
        self.onboardingCompleted = onboardingCompleted
        self.unsupportedTiers = unsupportedTiers
        self.switchToOfflineOnVerify = switchToOfflineOnVerify
        self.installedTier = installedTier
        self.retainedPartial = retainedPartial
        self.activeDownloadTier = activeDownloadTier
        self.activeDownloadPaused = activeDownloadPaused
    }

    public static func load(from defaults: UserDefaults) -> OfflineSetupState {
        guard let data = defaults.data(forKey: defaultsKey),
              let state = try? JSONDecoder().decode(OfflineSetupState.self, from: data)
        else { return OfflineSetupState() }
        return state
    }

    public func save(to defaults: UserDefaults) {
        if let data = try? JSONEncoder().encode(self) {
            defaults.set(data, forKey: Self.defaultsKey)
        }
    }
}

/// The single 7-day reminder (SPEC §8.5, locked).
public enum OfflineSetupReminder {
    public static let delay: TimeInterval = 7 * 24 * 60 * 60

    public enum Trigger: Equatable, Sendable {
        /// A PDF or image just got a Title Case rename.
        case titleCaseRename(fileName: String)
        case launch
    }

    public enum Delivery: Equatable, Sendable {
        case notification(title: String, body: String)
        /// Notifications are off: monochrome dot on the menu bar icon and item.
        case menuDot
    }

    /// Whether the reminder fires now. Once ever, only after Skip / Not Now,
    /// only with no model and the Offline model provider. A file trigger
    /// fires after 7 days; launch fires only if no file arrived in the next 7.
    public static func shouldFire(
        state: OfflineSetupState,
        trigger: Trigger,
        now: Date,
        modelInstalled: Bool,
        provider: ContentAwareRenameProvider
    ) -> Bool {
        guard !state.reminderShown,
              let skippedAt = state.skippedAt,
              !modelInstalled,
              provider == .localModel
        else { return false }
        let elapsed = now.timeIntervalSince(skippedAt)
        switch trigger {
        case .titleCaseRename:
            return elapsed >= delay
        case .launch:
            return elapsed >= 2 * delay
        }
    }

    public static let title = "Want clearer names for files like this?"

    public static func body(fileName: String?, sizeLabel: String) -> String {
        let named = fileName.map { "Intake just named “\($0)”. " } ?? ""
        return "\(named)Set up offline renaming to name files from their contents, like “2026-03-14 Invoice Acme”. Runs on this Mac. \(sizeLabel)."
    }

    public static func delivery(
        trigger: Trigger,
        notificationsAuthorized: Bool,
        recommendedSizeLabel: String
    ) -> Delivery {
        guard notificationsAuthorized else { return .menuDot }
        var fileName: String?
        if case .titleCaseRename(let name) = trigger { fileName = name }
        return .notification(title: title, body: body(fileName: fileName, sizeLabel: recommendedSizeLabel))
    }

    /// Marks the reminder as used. Fire once ever.
    public static func markFired(_ state: inout OfflineSetupState, delivery: Delivery) {
        state.reminderShown = true
        if delivery == .menuDot {
            state.reminderDotPending = true
        }
    }
}

/// Visibility rules for the menu bar setup item and the upgrade sheet.
public enum OfflineSetupVisibility {
    /// "Set Up Offline Renaming…" (top-level, PM ruling 2): shows until a
    /// model is installed, for the Offline model provider, and is replaced by
    /// the download row while a download runs.
    public static func showsMenuSetUpItem(
        modelInstalled: Bool,
        provider: ContentAwareRenameProvider,
        downloadActive: Bool,
        unsupported: Bool
    ) -> Bool {
        !modelInstalled && provider == .localModel && !downloadActive && !unsupported
    }

    /// The one-time "New: rename files offline" sheet for upgraders.
    public static func showsUpgradeSheet(state: OfflineSetupState, isUpgrade: Bool, modelInstalled: Bool) -> Bool {
        isUpgrade && !state.upgradeSheetShown && !modelInstalled
    }

    /// Onboarding opens by itself only on a fresh install's first run.
    public static func opensOnboardingAtLaunch(state: OfflineSetupState, isFirstRun: Bool, modelInstalled: Bool) -> Bool {
        isFirstRun && !state.onboardingCompleted && state.skippedAt == nil && !modelInstalled
    }
}

/// Which O1–O5 screen (and state) the onboarding window shows. Pure, so every
/// §8.2–8.4 state is reachable in tests with mocked detection, network and disk.
public enum OfflineOnboardingScreen: Equatable, Sendable {
    case welcome
    case detecting
    case recommendation(RecommendationState)
    case unsupported
    case downloading(DownloadState)
    case lowDisk(shortBytes: Int64)
    case unavailable
    case verifyingChecksum
    case selfTesting
    case checksumFailed(again: Bool)
    case selfTestFailed(smallerTier: OfflineModelTier?)
    case loadFailed(smallerTier: OfflineModelTier?)
    case ready(upgradeCheckboxDefault: Bool?)

    public enum RecommendationState: Equatable, Sendable {
        case normal
        /// "You're offline…", button "Download When Online".
        case offline
        /// Recommended tier didn't fit; a smaller one did.
        case smallerTierForSpace
        /// Nothing fits: "Free up space and try again."
        case noSpace
        /// Metered alert is up.
        case confirmingMetered
        /// "Wait for Wi-Fi" chosen.
        case waitingForWifi
    }

    public enum DownloadState: Equatable, Sendable {
        case inProgress
        case paused
        case waitingForNetwork
    }

    public static func resolve(
        step: OfflineOnboardingStep,
        recommendation: OfflineModelRecommendation?,
        network: OfflineNetworkStatus,
        download: OfflineModelDownloadMachine.Phase,
        upgradeCheckboxDefault: Bool?
    ) -> OfflineOnboardingScreen {
        switch download {
        case .downloading:
            return .downloading(.inProgress)
        case .paused:
            return .downloading(.paused)
        case .waitingForNetwork(_, let bytes) where bytes > 0 || step == .downloading:
            return .downloading(.waitingForNetwork)
        case .verifyingChecksum:
            return .verifyingChecksum
        case .selfTesting:
            return .selfTesting
        case .ready:
            return .ready(upgradeCheckboxDefault: upgradeCheckboxDefault)
        case .failed(_, .lowDisk(let short)) where step == .downloading:
            return .lowDisk(shortBytes: short)
        case .failed(_, .unavailable):
            return .unavailable
        case .failed(_, .checksumMismatch(let attempt)):
            return .checksumFailed(again: attempt >= 2)
        case .failed(let tier, .selfTestFailed):
            return .selfTestFailed(smallerTier: tier.nextSmaller)
        case .failed(let tier, .loadFailed):
            return .loadFailed(smallerTier: tier.nextSmaller)
        case .confirmingMetered:
            return .recommendation(.confirmingMetered)
        case .waitingForUnmetered:
            return .recommendation(.waitingForWifi)
        case .idle, .waitingForNetwork, .failed:
            break
        }
        switch step {
        case .welcome:
            return .welcome
        case .downloading, .verifying, .ready, .recommendation:
            guard let recommendation else { return .detecting }
            switch recommendation.status {
            case .unsupported:
                return .unsupported
            case .noTierFits:
                return .recommendation(.noSpace)
            case .recommended:
                if network == .offline { return .recommendation(.offline) }
                if recommendation.noSpaceMessage != nil { return .recommendation(.smallerTierForSpace) }
                return .recommendation(.normal)
            }
        }
    }
}

extension OfflineOnboardingScreen {
    /// O4 self-test / load failure copy when a smaller tier exists. Neutral
    /// wording with no speed claim (Firstmate ruling, overrides SPEC §8 "too
    /// slow"; HANDOFF: "The copy must not mention speed").
    public static func selfTestFailedMessage(smallerTierName: String) -> String {
        "This model couldn't finish its setup check on this Mac. Try \(smallerTierName) instead."
    }
}
