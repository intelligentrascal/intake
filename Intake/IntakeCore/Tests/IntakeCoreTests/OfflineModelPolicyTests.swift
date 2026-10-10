import Foundation
import Testing
@testable import IntakeCore

// MARK: Run policy (SPEC §9.2, AC6)

struct OfflineModelPolicyTests {
    private func decide(
        _ work: OfflineWorkKind = .singleNewFile,
        _ setting: OfflineModelRunSetting = .smart,
        thermal: ThermalLevel = .nominal,
        memory: MemoryPressureLevel = .normal,
        lpm: Bool = false,
        power: PowerSource = .ac,
        arch: MacArchitecture = .appleSilicon,
        loaded: Bool = false,
        tier: OfflineModelTier = .best,
        backup: OfflineModelTier? = nil
    ) -> OfflinePolicyDecision {
        OfflineModelPolicy.decide(
            work: work,
            setting: setting,
            signals: ResourceSignals(thermal: thermal, memory: memory, lowPowerMode: lpm, power: power, architecture: arch),
            isModelLoaded: loaded,
            activeTier: tier,
            installedBackup: backup
        )
    }

    private let run = OfflinePolicyDecision.run(priority: .utility, tier: nil)

    @Test
    func row1CriticalStopsEverythingIncludingRenameNow() {
        for setting in OfflineModelRunSetting.allCases {
            for work in [OfflineWorkKind.singleNewFile, .batch, .renameNow] {
                #expect(decide(work, setting, thermal: .critical) == .wait(.macIsHot, unload: .now))
                #expect(decide(work, setting, memory: .critical) == .wait(.lowMemory, unload: .now))
            }
        }
    }

    @Test
    func renameNowBypassesRowsTwoThroughNine() {
        let now = OfflinePolicyDecision.run(priority: .userInitiated, tier: nil)
        #expect(decide(.renameNow, thermal: .serious) == now)
        #expect(decide(.renameNow, memory: .warning) == now)
        #expect(decide(.renameNow, lpm: true) == now)
        #expect(decide(.renameNow, power: .battery(percent: 5)) == now)
        #expect(decide(.renameNow, .pluggedIn, power: .battery(percent: 80)) == now)
        #expect(decide(.renameNow, power: .battery(percent: 80), arch: .intel) == now)
    }

    @Test
    func row2SeriousThermalWaitsAndUnloadsAfterAMinuteOnEverySetting() {
        for setting in OfflineModelRunSetting.allCases {
            #expect(decide(.singleNewFile, setting, thermal: .serious) == .wait(.macIsHot, unload: .after(60)))
        }
        #expect(decide(thermal: .fair) == run)
    }

    @Test
    func row3MemoryWarningStepsDownOnlyToAnInstalledSmallerTier() {
        #expect(decide(memory: .warning) == .wait(.lowMemory, unload: .now))
        #expect(decide(memory: .warning, tier: .best, backup: .standard) == .run(priority: .utility, tier: .standard))
        #expect(decide(memory: .warning, tier: .standard, backup: .best) == .wait(.lowMemory, unload: .now))
        #expect(decide(memory: .warning, tier: .lite, backup: .lite) == .wait(.lowMemory, unload: .now))
        #expect(decide(.singleNewFile, .pluggedIn, memory: .warning) == .wait(.lowMemory, unload: .now))
        // Always ignores load (rows 3–9).
        #expect(decide(.singleNewFile, .always, memory: .warning) == run)
    }

    @Test
    func smartOnPowerRunsEverything() {
        #expect(decide(.singleNewFile) == run)
        #expect(decide(.batch) == run)
        #expect(decide(.batch, arch: .intel) == run)
    }

    @Test
    func smartLowPowerModeWaits() {
        #expect(decide(lpm: true) == .wait(.lowPowerMode, unload: .keep))
        #expect(decide(lpm: true, power: .battery(percent: 90)) == .wait(.lowPowerMode, unload: .keep))
        #expect(decide(.singleNewFile, .always, lpm: true) == run)
    }

    @Test
    func smartBatteryBands() {
        let wait = OfflinePolicyDecision.wait(.waitingForPower, unload: .keep)
        // ≤ 20%
        #expect(decide(power: .battery(percent: 20), loaded: true) == wait)
        // 21–40%: only when already loaded.
        #expect(decide(power: .battery(percent: 21), loaded: false) == wait)
        #expect(decide(power: .battery(percent: 40), loaded: true) == run)
        // > 40%: single new files.
        #expect(decide(power: .battery(percent: 41)) == run)
        #expect(decide(power: .battery(percent: nil)) == run)
        // No batches on battery.
        #expect(decide(.batch, power: .battery(percent: 100), loaded: true) == wait)
    }

    @Test
    func smartIntelOnBatteryQueuesEvenWhenCharged() {
        #expect(decide(power: .battery(percent: 100), arch: .intel, loaded: true)
            == .wait(.waitingForPower, unload: .keep))
    }

    @Test
    func alwaysRunsOnBattery() {
        #expect(decide(.batch, .always, power: .battery(percent: 3), arch: .intel) == run)
    }

    @Test
    func pluggedInWaitsOnBatteryOnly() {
        #expect(decide(.singleNewFile, .pluggedIn, power: .battery(percent: 99))
            == .wait(.waitingForPower, unload: .keep))
        #expect(decide(.batch, .pluggedIn) == run)
        #expect(decide(.singleNewFile, .pluggedIn, lpm: true) == run)
    }

    @Test
    func decisionHelpers() {
        #expect(run.shouldRun)
        #expect(run.waitReason == nil)
        #expect(OfflinePolicyDecision.wait(.macIsHot, unload: .now).waitReason == .macIsHot)
        #expect(OfflineModelPolicy.drainChunkSize == 20)
    }

    @Test
    func runSettingCopyAndKey() {
        #expect(OfflineModelRunSetting.allCases.map { $0.title } == ["Smart (recommended)", "Always", "Only when plugged in"])
        #expect(OfflineModelRunSetting.defaultsKey == "intake.offlineModel.runSetting")
        #expect(OfflineModelRunSetting.allCases.allSatisfy { !$0.help.isEmpty })
        #expect(OfflineWaitReason.waitingForPower.text == "Waiting for power")
        #expect(OfflineWaitReason.macIsHot.text == "Mac is hot")
        #expect(OfflineWaitReason.lowMemory.text == "Low memory")
        #expect(OfflineWaitReason.lowPowerMode.text == "Low Power Mode")
    }
}

struct ResourceSignalHysteresisTests {
    @Test
    func heldForTwoMinutesAfterClearing() {
        let start = Date(timeIntervalSince1970: 0)
        var hysteresis = ResourceSignalHysteresis()
        #expect(hysteresis.effective(ResourceSignals(), now: start).thermal == .nominal)
        #expect(hysteresis.nextRelease(now: start) == nil)
        #expect(hysteresis.effective(ResourceSignals(thermal: .critical, memory: .critical), now: start).thermal == .critical)
        let cleared = ResourceSignals()
        let soon = hysteresis.effective(cleared, now: start.addingTimeInterval(119))
        #expect(soon.thermal == .critical)
        #expect(soon.memory == .critical)
        #expect(hysteresis.nextRelease(now: start.addingTimeInterval(100)) == 20)
        let later = hysteresis.effective(cleared, now: start.addingTimeInterval(120))
        #expect(later.thermal == .nominal)
        #expect(later.memory == .normal)
    }

    @Test
    func seriousIsHeldAsSerious() {
        let start = Date(timeIntervalSince1970: 0)
        var hysteresis = ResourceSignalHysteresis()
        _ = hysteresis.effective(ResourceSignals(thermal: .serious), now: start)
        #expect(hysteresis.effective(ResourceSignals(thermal: .fair), now: start.addingTimeInterval(60)).thermal == .serious)
        #expect(hysteresis.effective(ResourceSignals(thermal: .fair), now: start.addingTimeInterval(200)).thermal == .fair)
    }
}

// MARK: Queue (SPEC §9.3)

struct OfflineRenameQueueTests {
    private let base = Date(timeIntervalSince1970: 1_800_000_000)

    private func item(_ name: String, at offset: TimeInterval, id: UInt64? = 1) -> QueuedOfflineRename {
        QueuedOfflineRename(
            url: URL(fileURLWithPath: "/Users/r/Downloads/\(name)"),
            fileIdentifier: id,
            watchFolderID: "downloads",
            enqueuedAt: base.addingTimeInterval(offset),
            reason: .waitingForPower
        )
    }

    @Test
    func keepsNewestFirstAndRefreshesDuplicates() {
        var queue = OfflineRenameQueue()
        queue.enqueue(item("A.pdf", at: 0))
        queue.enqueue(item("C.pdf", at: 20))
        queue.enqueue(item("B.pdf", at: 10))
        #expect(queue.items.map { $0.fileName } == ["C.pdf", "B.pdf", "A.pdf"])
        queue.enqueue(item("A.pdf", at: 30))
        #expect(queue.items.map { $0.fileName } == ["A.pdf", "C.pdf", "B.pdf"])
        #expect(queue.count == 3)
        #expect(queue.nextChunk(size: 2).map { $0.fileName } == ["A.pdf", "C.pdf"])
        #expect(queue.nextChunk().count == 3)
    }

    @Test
    func capsAtFiveHundredDroppingTheOldest() {
        var queue = OfflineRenameQueue()
        for index in 0..<500 {
            #expect(queue.enqueue(item("f\(index).pdf", at: TimeInterval(index))) == 0)
        }
        #expect(queue.enqueue(item("new.pdf", at: 1_000)) == 1)
        #expect(queue.count == 500)
        #expect(!queue.contains(path: "/Users/r/Downloads/f0.pdf"))
        #expect(queue.items.first?.fileName == "new.pdf")
        queue.enqueue(item("new2.pdf", at: 1_001))
        #expect(queue.takeOverflowNote() == "Too many files waiting. 2 kept their tidy names.")
        #expect(queue.takeOverflowNote() == nil)
    }

    @Test
    func prunesItemsOlderThanSevenDays() {
        var queue = OfflineRenameQueue()
        queue.enqueue(item("old.pdf", at: 0))
        queue.enqueue(item("new.pdf", at: 6 * 86_400))
        let expired = queue.pruneExpired(now: base.addingTimeInterval(7 * 86_400 + 1))
        #expect(expired.map { $0.fileName } == ["old.pdf"])
        #expect(queue.items.map { $0.fileName } == ["new.pdf"])
    }

    @Test
    func prioritizeRemoveAndFollowMoves() {
        var queue = OfflineRenameQueue()
        let a = item("A.pdf", at: 0)
        queue.enqueue(a)
        queue.enqueue(item("B.pdf", at: 10))
        queue.prioritize(id: a.id)
        #expect(queue.items.first?.id == a.id)
        queue.noteMoved(from: a.url, to: URL(fileURLWithPath: "/Users/r/Documents/Invoices/A.pdf"))
        #expect(queue.items.first?.path == "/Users/r/Documents/Invoices/A.pdf")
        #expect(queue.items.first?.queuedFileName == "A.pdf")
        queue.setReason(.macIsHot)
        #expect(queue.items.allSatisfy { $0.reason == .macIsHot })
        #expect(queue.remove(id: a.id)?.fileName == "A.pdf")
        #expect(queue.remove(id: a.id) == nil)
        queue.removeAll()
        #expect(queue.isEmpty)
    }

    @Test
    func persistsPathsOnlyNeverText() throws {
        let defaults = try #require(UserDefaults(suiteName: "intake-queue-\(UUID().uuidString)"))
        #expect(OfflineRenameQueue.load(from: defaults).isEmpty)
        var queue = OfflineRenameQueue()
        queue.enqueue(item("Scan.pdf", at: 0, id: 42))
        queue.save(to: defaults)
        #expect(OfflineRenameQueue.load(from: defaults) == queue)
        let data = try #require(defaults.data(forKey: OfflineRenameQueue.defaultsKey))
        let json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let stored = try #require((json["items"] as? [[String: Any]])?.first)
        #expect(Set(stored.keys) == ["id", "path", "queuedFileName", "fileIdentifier", "watchFolderID", "enqueuedAt", "reason"])
    }

    @Test
    func checkSkipsAnythingTheUserTouched() {
        let queued = item("A.pdf", at: 0, id: 7)
        #expect(QueuedRenameCheck.evaluate(queued, snapshot: QueuedFileSnapshot(exists: true, fileIdentifier: 7)) == .proceed)
        #expect(QueuedRenameCheck.evaluate(queued, snapshot: QueuedFileSnapshot(exists: true)) == .proceed)
        #expect(QueuedRenameCheck.evaluate(queued, snapshot: QueuedFileSnapshot(exists: false)) == .skip(.missing))
        #expect(QueuedRenameCheck.evaluate(queued, snapshot: QueuedFileSnapshot(exists: true, fileIdentifier: 8)) == .skip(.replaced))
        #expect(QueuedRenameCheck.evaluate(queued, snapshot: QueuedFileSnapshot(exists: true, isInsideManagedFolder: false)) == .skip(.movedOut))
        #expect(QueuedRenameCheck.evaluate(queued, snapshot: QueuedFileSnapshot(exists: true, lastOpened: base.addingTimeInterval(5))) == .skip(.opened))
        #expect(QueuedRenameCheck.evaluate(queued, snapshot: QueuedFileSnapshot(exists: true, lastOpened: base.addingTimeInterval(-5))) == .proceed)
    }

    @Test
    func copy() {
        #expect(OfflineRenameQueue.menuLine(count: 1, reason: .waitingForPower) == "1 file waiting to rename · Waiting for power")
        #expect(OfflineRenameQueue.menuLine(count: 3, reason: .macIsHot) == "3 files waiting to rename · Mac is hot")
        #expect(OfflineRenameQueue.settingsLine(count: 2, reason: .lowMemory) == "2 files waiting · Low memory")
        #expect(OfflineRenameQueue.renameButtonTitle(count: 1) == "Rename Now")
        #expect(OfflineRenameQueue.renameButtonTitle(count: 4) == "Rename All Now")
    }
}
