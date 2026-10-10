import Foundation
import Testing
@testable import IntakeCore

// MARK: Migration (SPEC §3, AC1)

struct OfflineModelMigrationTests {
    private func defaults() throws -> UserDefaults {
        try #require(UserDefaults(suiteName: "intake-migration-\(UUID().uuidString)"))
    }

    @Test
    func migrationTable() {
        let off = ContentAwareRenameSettings(isEnabled: false, provider: .onDevice)
        #expect(OfflineModelMigration.migrated(off).provider == .localModel)
        #expect(OfflineModelMigration.migrated(off).isEnabled == false)
        let apple = ContentAwareRenameSettings(isEnabled: true, provider: .onDevice)
        #expect(OfflineModelMigration.migrated(apple) == apple)
        let cloud = ContentAwareRenameSettings(isEnabled: true, provider: .openRouter)
        #expect(OfflineModelMigration.migrated(cloud) == cloud)
    }

    @Test
    func freshInstallDefaultsToTheOfflineModel() throws {
        let defaults = try defaults()
        let settings = OfflineModelMigration.migrateIfNeeded(defaults: defaults)
        #expect(settings.provider == .localModel)
        #expect(!OfflineModelMigration.wasUpgrade(defaults: defaults))
        #expect(defaults.bool(forKey: OfflineModelMigration.migratedKey))
    }

    @Test
    func upgraderOnAppleIntelligenceKeepsItUntilVerified() throws {
        let defaults = try defaults()
        ContentAwareRenameSettings(isEnabled: true, provider: .onDevice).save(to: defaults)
        let settings = OfflineModelMigration.migrateIfNeeded(defaults: defaults)
        #expect(settings.provider == .onDevice)
        #expect(settings.isEnabled)
        #expect(OfflineModelMigration.wasUpgrade(defaults: defaults))
        #expect(OfflineModelMigration.switchCheckboxDefault(for: settings) == true)
        // O5 checkbox left checked → switch on verify.
        let after = OfflineModelMigration.applyingVerifiedModel(to: settings, switchToOffline: true)
        #expect(after.provider == .localModel)
        #expect(after.isEnabled)
        // Unchecked → stays on Apple Intelligence.
        #expect(OfflineModelMigration.applyingVerifiedModel(to: settings, switchToOffline: false).provider == .onDevice)
    }

    @Test
    func upgraderOnOpenRouterStaysWithAnUncheckedBox() throws {
        let defaults = try defaults()
        ContentAwareRenameSettings(isEnabled: true, provider: .openRouter).save(to: defaults)
        let settings = OfflineModelMigration.migrateIfNeeded(defaults: defaults)
        #expect(settings.provider == .openRouter)
        #expect(OfflineModelMigration.switchCheckboxDefault(for: settings) == false)
        #expect(OfflineModelMigration.applyingVerifiedModel(to: settings, switchToOffline: false).provider == .openRouter)
    }

    @Test
    func upgraderWithRenamingOffMovesToOfflineAndTurnsOnWhenVerified() throws {
        let defaults = try defaults()
        ContentAwareRenameSettings(isEnabled: false, provider: .onDevice).save(to: defaults)
        let settings = OfflineModelMigration.migrateIfNeeded(defaults: defaults)
        #expect(settings.provider == .localModel)
        #expect(ContentAwareRenameSettings.load(from: defaults).provider == .localModel)
        #expect(OfflineModelMigration.switchCheckboxDefault(for: settings) == nil)
        let after = OfflineModelMigration.applyingVerifiedModel(to: settings, switchToOffline: false)
        #expect(after.provider == .localModel)
        #expect(after.isEnabled)
    }

    @Test
    func upgradeIsDetectedFromOtherKeysAndMigrationRunsOnce() throws {
        let defaults = try defaults()
        defaults.set(true, forKey: "intake.didShowMenuBarTip")
        OfflineModelMigration.migrateIfNeeded(defaults: defaults)
        #expect(OfflineModelMigration.wasUpgrade(defaults: defaults))
        // Later changes are not migrated again.
        ContentAwareRenameSettings(isEnabled: false, provider: .openRouter).save(to: defaults)
        #expect(OfflineModelMigration.migrateIfNeeded(defaults: defaults).provider == .openRouter)
        #expect(OfflineModelMigration.wasUpgrade(defaults: defaults))
    }
}

// MARK: Reminder, visibility, persisted state (SPEC §8.5)

struct OfflineSetupReminderTests {
    private let skipped = Date(timeIntervalSince1970: 1_800_000_000)
    private let day: TimeInterval = 86_400

    private func fires(
        _ state: OfflineSetupState,
        _ trigger: OfflineSetupReminder.Trigger,
        after days: Double,
        installed: Bool = false,
        provider: ContentAwareRenameProvider = .localModel
    ) -> Bool {
        OfflineSetupReminder.shouldFire(
            state: state, trigger: trigger, now: skipped.addingTimeInterval(days * day),
            modelInstalled: installed, provider: provider
        )
    }

    @Test
    func firesSevenDaysAfterSkipOnAFileOrFourteenAtLaunch() {
        let state = OfflineSetupState(skippedAt: skipped)
        let file = OfflineSetupReminder.Trigger.titleCaseRename(fileName: "Scan 0042.pdf")
        #expect(!fires(state, file, after: 6.9))
        #expect(fires(state, file, after: 7))
        #expect(!fires(state, .launch, after: 13))
        #expect(fires(state, .launch, after: 14))
    }

    @Test
    func onlyOnceOnlyAfterSkipOnlyWithoutAModelOnlyOnOfflineProvider() {
        let file = OfflineSetupReminder.Trigger.titleCaseRename(fileName: "a.pdf")
        #expect(!fires(OfflineSetupState(), file, after: 30))
        #expect(!fires(OfflineSetupState(skippedAt: skipped, reminderShown: true), file, after: 30))
        #expect(!fires(OfflineSetupState(skippedAt: skipped), file, after: 30, installed: true))
        #expect(!fires(OfflineSetupState(skippedAt: skipped), file, after: 30, provider: .onDevice))
        #expect(!fires(OfflineSetupState(skippedAt: skipped), file, after: 30, provider: .openRouter))
    }

    @Test
    func deliveryUsesANotificationOrTheMenuDot() {
        let delivery = OfflineSetupReminder.delivery(
            trigger: .titleCaseRename(fileName: "Scan 0042.pdf"),
            notificationsAuthorized: true,
            recommendedSizeLabel: "2.5 GB"
        )
        #expect(delivery == .notification(
            title: "Want clearer names for files like this?",
            body: "Intake just named “Scan 0042.pdf”. Set up offline renaming to name files from their contents, like “2026-03-14 Invoice Acme”. Runs on this Mac. 2.5 GB."
        ))
        #expect(OfflineSetupReminder.delivery(trigger: .launch, notificationsAuthorized: false, recommendedSizeLabel: "2.5 GB") == .menuDot)

        var state = OfflineSetupState(skippedAt: skipped)
        OfflineSetupReminder.markFired(&state, delivery: .menuDot)
        #expect(state.reminderShown)
        #expect(state.reminderDotPending)
        var notified = OfflineSetupState(skippedAt: skipped)
        OfflineSetupReminder.markFired(&notified, delivery: delivery)
        #expect(notified.reminderShown)
        #expect(!notified.reminderDotPending)
    }

    @Test
    func menuItemSheetAndLaunchVisibility() {
        #expect(OfflineSetupVisibility.showsMenuSetUpItem(modelInstalled: false, provider: .localModel, downloadActive: false, unsupported: false))
        #expect(!OfflineSetupVisibility.showsMenuSetUpItem(modelInstalled: true, provider: .localModel, downloadActive: false, unsupported: false))
        #expect(!OfflineSetupVisibility.showsMenuSetUpItem(modelInstalled: false, provider: .onDevice, downloadActive: false, unsupported: false))
        #expect(!OfflineSetupVisibility.showsMenuSetUpItem(modelInstalled: false, provider: .localModel, downloadActive: true, unsupported: false))
        #expect(!OfflineSetupVisibility.showsMenuSetUpItem(modelInstalled: false, provider: .localModel, downloadActive: false, unsupported: true))

        #expect(OfflineSetupVisibility.showsUpgradeSheet(state: OfflineSetupState(), isUpgrade: true, modelInstalled: false))
        #expect(!OfflineSetupVisibility.showsUpgradeSheet(state: OfflineSetupState(upgradeSheetShown: true), isUpgrade: true, modelInstalled: false))
        #expect(!OfflineSetupVisibility.showsUpgradeSheet(state: OfflineSetupState(), isUpgrade: false, modelInstalled: false))

        #expect(OfflineSetupVisibility.opensOnboardingAtLaunch(state: OfflineSetupState(), isFirstRun: true, modelInstalled: false))
        #expect(!OfflineSetupVisibility.opensOnboardingAtLaunch(state: OfflineSetupState(), isFirstRun: false, modelInstalled: false))
        #expect(!OfflineSetupVisibility.opensOnboardingAtLaunch(state: OfflineSetupState(skippedAt: skipped), isFirstRun: true, modelInstalled: false))
    }

    @Test
    func setupStateRoundTrips() throws {
        let defaults = try #require(UserDefaults(suiteName: "intake-setup-\(UUID().uuidString)"))
        #expect(OfflineSetupState.load(from: defaults) == OfflineSetupState())
        let state = OfflineSetupState(
            skippedAt: skipped,
            reminderShown: true,
            unsupportedTiers: [.best],
            switchToOfflineOnVerify: true,
            installedTier: .standard,
            retainedPartial: RetainedPartialDownload(tier: .best, cancelledAt: skipped),
            activeDownloadTier: .standard,
            activeDownloadPaused: true
        )
        state.save(to: defaults)
        #expect(OfflineSetupState.load(from: defaults) == state)
    }
}

// MARK: Onboarding screen resolution (SPEC §8.2–8.4)

struct OfflineOnboardingScreenTests {
    private let gib: UInt64 = 1_073_741_824

    private func recommendation(memoryGB: UInt64 = 16, free: Int64 = 200_000_000_000, arch: MacArchitecture = .appleSilicon, unsupported: Set<OfflineModelTier> = []) -> OfflineModelRecommendation {
        OfflineModelRecommender.recommend(
            for: MacHardwareProfile(architecture: arch, memoryBytes: memoryGB * gib, freeDiskBytes: free),
            unsupportedTiers: unsupported
        )
    }

    private func screen(
        _ step: OfflineOnboardingStep,
        _ rec: OfflineModelRecommendation?,
        network: OfflineNetworkStatus = .unmetered,
        _ phase: OfflineModelDownloadMachine.Phase = .idle,
        checkbox: Bool? = nil
    ) -> OfflineOnboardingScreen {
        OfflineOnboardingScreen.resolve(step: step, recommendation: rec, network: network, download: phase, upgradeCheckboxDefault: checkbox)
    }

    @Test
    func recommendationStates() {
        #expect(screen(.welcome, nil) == .welcome)
        #expect(screen(.recommendation, nil) == .detecting)
        #expect(screen(.recommendation, recommendation()) == .recommendation(.normal))
        #expect(screen(.recommendation, recommendation(), network: .offline) == .recommendation(.offline))
        #expect(screen(.recommendation, recommendation(free: 3_900_000_000)) == .recommendation(.smallerTierForSpace))
        #expect(screen(.recommendation, recommendation(free: 1_000_000_000)) == .recommendation(.noSpace))
        #expect(screen(.recommendation, recommendation(memoryGB: 4, arch: .intel)) == .unsupported)
        #expect(screen(.recommendation, recommendation(), .confirmingMetered(.best)) == .recommendation(.confirmingMetered))
        #expect(screen(.recommendation, recommendation(), .waitingForUnmetered(.best)) == .recommendation(.waitingForWifi))
        // Download When Online: still on O2.
        #expect(screen(.recommendation, recommendation(), network: .offline, .waitingForNetwork(.best, receivedBytes: 0)) == .recommendation(.offline))
    }

    @Test
    func lowDiskExampleMatchesTheRuling() {
        let rec = recommendation(free: 3_900_000_000)
        #expect(rec.recommendedTier == .standard)
        #expect(rec.noSpaceMessage == "Best needs 2.5 GB plus 2 GB free. This Mac has 3.9 GB free.")
        #expect(rec.smallerTierMessage == "Standard fits: 1.28 GB.")
    }

    @Test
    func downloadAndVerifyStates() {
        let rec = recommendation()
        #expect(screen(.downloading, rec, .downloading(.best, receivedBytes: 1)) == .downloading(.inProgress))
        #expect(screen(.downloading, rec, .paused(.best, receivedBytes: 1)) == .downloading(.paused))
        #expect(screen(.downloading, rec, network: .offline, .waitingForNetwork(.best, receivedBytes: 0)) == .downloading(.waitingForNetwork))
        #expect(screen(.downloading, rec, .failed(.best, .lowDisk(shortBytes: 420_000_000))) == .lowDisk(shortBytes: 420_000_000))
        #expect(screen(.downloading, rec, .failed(.best, .unavailable)) == .unavailable)
        #expect(screen(.verifying, rec, .verifyingChecksum(.best)) == .verifyingChecksum)
        #expect(screen(.verifying, rec, .selfTesting(.best)) == .selfTesting)
        #expect(screen(.verifying, rec, .failed(.best, .checksumMismatch(attempt: 1))) == .checksumFailed(again: false))
        #expect(screen(.verifying, rec, .failed(.best, .checksumMismatch(attempt: 2))) == .checksumFailed(again: true))
        #expect(screen(.verifying, rec, .failed(.best, .selfTestFailed)) == .selfTestFailed(smallerTier: .standard))
        #expect(screen(.verifying, rec, .failed(.lite, .selfTestFailed)) == .selfTestFailed(smallerTier: nil))
        #expect(screen(.verifying, rec, .failed(.standard, .loadFailed)) == .loadFailed(smallerTier: .lite))
        #expect(screen(.ready, rec, .ready(.best), checkbox: true) == .ready(upgradeCheckboxDefault: true))
        #expect(screen(.ready, rec, .ready(.best)) == .ready(upgradeCheckboxDefault: nil))
    }

    @Test
    func selfTestFailureStepsTheRecommendationDown() {
        #expect(recommendation(unsupported: [.best]).recommendedTier == .standard)
        #expect(recommendation(unsupported: [.best, .standard]).recommendedTier == .lite)
        #expect(recommendation(unsupported: [.best, .standard, .lite]).status == .unsupported)
    }
}
