import Foundation
import Testing
@testable import IntakeCore

// MARK: Download state machine (SPEC §7, §8.4, §14, §13 AC4)

struct OfflineModelDownloadMachineTests {
    private let plenty: Int64 = 200_000_000_000

    @Test
    func happyPathDownloadsVerifiesSelfTestsAndInstalls() {
        var machine = OfflineModelDownloadMachine()
        #expect(machine.handle(.requestDownload(.best, network: .unmetered, freeBytes: plenty, partialBytes: 0))
            == [.startTransfer(.best, fromByte: 0)])
        #expect(machine.phase == .downloading(.best, receivedBytes: 0))
        machine.handle(.progress(receivedBytes: 1_200_000_000))
        #expect(machine.receivedBytes == 1_200_000_000)
        #expect(machine.handle(.transferFinished(totalBytes: OfflineModelManifest.best.byteSize)) == [.verifyChecksum(.best)])
        #expect(machine.phase == .verifyingChecksum(.best))
        #expect(machine.handle(.checksumResult(matches: true)) == [.runSelfTest(.best)])
        #expect(machine.phase == .selfTesting(.best))
        #expect(machine.handle(.selfTestResult(passed: true)) == [.install(.best)])
        #expect(machine.phase == .ready(.best))
    }

    @Test
    func offlineAtStartWaitsAndStartsWhenBackOnline() {
        var machine = OfflineModelDownloadMachine()
        #expect(machine.handle(.requestDownload(.standard, network: .offline, freeBytes: plenty, partialBytes: 0)).isEmpty)
        #expect(machine.phase == .waitingForNetwork(.standard, receivedBytes: 0))
        #expect(machine.handle(.networkChanged(.offline)).isEmpty)
        #expect(machine.handle(.networkChanged(.unmetered)) == [.startTransfer(.standard, fromByte: 0)])
    }

    @Test
    func meteredNetworkAsksFirst() {
        var machine = OfflineModelDownloadMachine()
        #expect(machine.handle(.requestDownload(.best, network: .metered, freeBytes: plenty, partialBytes: 0)).isEmpty)
        #expect(machine.phase == .confirmingMetered(.best))
        #expect(machine.handle(.meteredChoice(downloadAnyway: true)) == [.startTransfer(.best, fromByte: 0)])
        // Approved: staying on the hotspot doesn't ask again.
        #expect(machine.handle(.networkChanged(.metered)).isEmpty)
        #expect(machine.phase == .downloading(.best, receivedBytes: 0))
    }

    @Test
    func waitForWifiStartsOnlyOnAnUnmeteredPath() {
        var machine = OfflineModelDownloadMachine()
        machine.handle(.requestDownload(.best, network: .metered, freeBytes: plenty, partialBytes: 500))
        #expect(machine.handle(.meteredChoice(downloadAnyway: false)).isEmpty)
        #expect(machine.phase == .waitingForUnmetered(.best))
        #expect(machine.handle(.networkChanged(.metered)).isEmpty)
        #expect(machine.handle(.networkChanged(.offline)).isEmpty)
        #expect(machine.handle(.networkChanged(.unmetered)) == [.startTransfer(.best, fromByte: 500)])
    }

    @Test
    func movingOntoAHotspotMidDownloadStopsAndAsks() {
        var machine = OfflineModelDownloadMachine()
        machine.handle(.requestDownload(.best, network: .unmetered, freeBytes: plenty, partialBytes: 0))
        machine.handle(.progress(receivedBytes: 700))
        #expect(machine.handle(.networkChanged(.metered)) == [.stopTransfer])
        #expect(machine.phase == .confirmingMetered(.best))
        #expect(machine.handle(.meteredChoice(downloadAnyway: true)) == [.startTransfer(.best, fromByte: 700)])
    }

    @Test
    func pauseAndResumeContinueFromTheReceivedByte() {
        var machine = OfflineModelDownloadMachine()
        machine.handle(.requestDownload(.best, network: .unmetered, freeBytes: plenty, partialBytes: 0))
        machine.handle(.progress(receivedBytes: 1_200_000_000))
        #expect(machine.handle(.pause) == [.stopTransfer])
        #expect(machine.phase == .paused(.best, receivedBytes: 1_200_000_000))
        #expect(machine.handle(.resume(network: .unmetered)) == [.startTransfer(.best, fromByte: 1_200_000_000)])
    }

    @Test
    func networkLossWaitsThenResumesWithARange() {
        var machine = OfflineModelDownloadMachine()
        machine.handle(.requestDownload(.best, network: .unmetered, freeBytes: plenty, partialBytes: 0))
        machine.handle(.progress(receivedBytes: 900))
        #expect(machine.handle(.networkChanged(.offline)) == [.stopTransfer])
        #expect(machine.phase == .waitingForNetwork(.best, receivedBytes: 900))
        #expect(machine.handle(.networkChanged(.unmetered)) == [.startTransfer(.best, fromByte: 900)])

        machine.handle(.progress(receivedBytes: 1_500))
        #expect(machine.handle(.transferFailedNetwork(receivedBytes: 1_500)).isEmpty)
        #expect(machine.handle(.networkChanged(.unmetered)) == [.startTransfer(.best, fromByte: 1_500)])
    }

    @Test
    func resumesAfterQuitOrSleep() {
        var running = OfflineModelDownloadMachine()
        #expect(running.handle(.restore(.standard, partialBytes: 4_000, wasPaused: false, network: .unmetered))
            == [.startTransfer(.standard, fromByte: 4_000)])
        var paused = OfflineModelDownloadMachine()
        #expect(paused.handle(.restore(.standard, partialBytes: 4_000, wasPaused: true, network: .unmetered)).isEmpty)
        #expect(paused.phase == .paused(.standard, receivedBytes: 4_000))
        var hotspot = OfflineModelDownloadMachine()
        #expect(hotspot.handle(.restore(.standard, partialBytes: 4_000, wasPaused: false, network: .metered)).isEmpty)
        #expect(hotspot.phase == .confirmingMetered(.standard))
        var offline = OfflineModelDownloadMachine()
        offline.handle(.restore(.standard, partialBytes: 4_000, wasPaused: false, network: .offline))
        #expect(offline.phase == .waitingForNetwork(.standard, receivedBytes: 4_000))
    }

    @Test
    func pinnedRevisionGoneIsUnavailable() {
        for status in [401, 403, 404] {
            var machine = OfflineModelDownloadMachine()
            machine.handle(.requestDownload(.best, network: .unmetered, freeBytes: plenty, partialBytes: 0))
            #expect(machine.handle(.transferFailedHTTP(status: status)) == [.deletePartial(.best)])
            #expect(machine.phase == .failed(.best, .unavailable))
        }
        var transient = OfflineModelDownloadMachine()
        transient.handle(.requestDownload(.best, network: .unmetered, freeBytes: plenty, partialBytes: 0))
        transient.handle(.transferFailedHTTP(status: 503))
        #expect(transient.phase == .waitingForNetwork(.best, receivedBytes: 0))
    }

    @Test
    func notEnoughSpaceToStartCountsThePartialAlreadyOnDisk() {
        let need = OfflineModelManifest.best.requiredFreeBytes
        var machine = OfflineModelDownloadMachine()
        #expect(machine.handle(.requestDownload(.best, network: .unmetered, freeBytes: need - 10, partialBytes: 0)).isEmpty)
        #expect(machine.phase == .failed(.best, .lowDisk(shortBytes: 10)))
        var resumed = OfflineModelDownloadMachine()
        #expect(resumed.handle(.requestDownload(.best, network: .unmetered, freeBytes: need - 10, partialBytes: 10))
            == [.startTransfer(.best, fromByte: 10)])
    }

    @Test
    func diskFullAtTheFinalMoveKeepsThePartial() {
        var machine = OfflineModelDownloadMachine()
        machine.handle(.requestDownload(.best, network: .unmetered, freeBytes: plenty, partialBytes: 0))
        let effects = machine.handle(.transferFailedDiskFull(shortBytes: 420_000_000))
        #expect(effects == [.stopTransfer])
        #expect(!effects.contains(.deletePartial(.best)))
        #expect(machine.phase == .failed(.best, .lowDisk(shortBytes: 420_000_000)))
    }

    @Test
    func badChecksumIsDeletedNeverLoadedAndCounted() {
        var machine = OfflineModelDownloadMachine()
        machine.handle(.requestDownload(.best, network: .unmetered, freeBytes: plenty, partialBytes: 0))
        machine.handle(.transferFinished(totalBytes: OfflineModelManifest.best.byteSize))
        let first = machine.handle(.checksumResult(matches: false))
        #expect(first == [.deletePartial(.best)])
        #expect(!first.contains(.runSelfTest(.best)))
        #expect(!first.contains(.install(.best)))
        #expect(machine.phase == .failed(.best, .checksumMismatch(attempt: 1)))

        // Try Again (same tier) → second failure links to Send Feedback.
        machine.handle(.requestDownload(.best, network: .unmetered, freeBytes: plenty, partialBytes: 0))
        machine.handle(.transferFinished(totalBytes: OfflineModelManifest.best.byteSize))
        machine.handle(.checksumResult(matches: false))
        #expect(machine.phase == .failed(.best, .checksumMismatch(attempt: 2)))
    }

    @Test
    func wrongByteCountNeverReachesVerifyOrLoad() {
        var machine = OfflineModelDownloadMachine()
        machine.handle(.requestDownload(.lite, network: .unmetered, freeBytes: plenty, partialBytes: 0))
        #expect(machine.handle(.transferFinished(totalBytes: 12)) == [.deletePartial(.lite)])
        #expect(machine.phase == .failed(.lite, .checksumMismatch(attempt: 1)))
    }

    @Test
    func selfTestGatesReady() {
        var machine = OfflineModelDownloadMachine()
        machine.handle(.requestDownload(.best, network: .unmetered, freeBytes: plenty, partialBytes: 0))
        machine.handle(.transferFinished(totalBytes: OfflineModelManifest.best.byteSize))
        machine.handle(.checksumResult(matches: true))
        #expect(machine.handle(.selfTestResult(passed: false)) == [.deleteModel(.best)])
        #expect(machine.phase == .failed(.best, .selfTestFailed))

        var loadFail = OfflineModelDownloadMachine()
        loadFail.handle(.requestDownload(.best, network: .unmetered, freeBytes: plenty, partialBytes: 0))
        loadFail.handle(.transferFinished(totalBytes: OfflineModelManifest.best.byteSize))
        loadFail.handle(.checksumResult(matches: true))
        #expect(loadFail.handle(.loadFailed) == [.deleteModel(.best)])
        #expect(loadFail.phase == .failed(.best, .loadFailed))
    }

    @Test
    func cancelKeepsThePartialForResume() {
        var machine = OfflineModelDownloadMachine()
        machine.handle(.requestDownload(.best, network: .unmetered, freeBytes: plenty, partialBytes: 0))
        machine.handle(.progress(receivedBytes: 300))
        #expect(machine.handle(.cancel) == [.stopTransfer, .retainPartial(.best)])
        #expect(machine.phase == .idle)
        #expect(machine.handle(.cancel).isEmpty)
    }

    @Test
    func eventsInTheWrongPhaseAreIgnored() {
        var machine = OfflineModelDownloadMachine()
        #expect(machine.handle(.checksumResult(matches: true)).isEmpty)
        #expect(machine.handle(.selfTestResult(passed: true)).isEmpty)
        #expect(machine.handle(.progress(receivedBytes: 5)).isEmpty)
        #expect(machine.phase == .idle)
        #expect(!machine.isActive)
    }
}

// MARK: 24 h partial retention (SPEC v1.3.1 ruling 6)

struct RetainedPartialDownloadTests {
    @Test
    func partialsExpireAfter24Hours() {
        let cancelled = Date(timeIntervalSince1970: 1_000_000)
        let record = RetainedPartialDownload(tier: .best, cancelledAt: cancelled)
        #expect(!record.isExpired(now: cancelled.addingTimeInterval(23 * 3_600)))
        #expect(record.isExpired(now: cancelled.addingTimeInterval(24 * 3_600)))
        let fresh = RetainedPartialDownload(tier: .lite, cancelledAt: cancelled.addingTimeInterval(20 * 3_600))
        let split = RetainedPartialDownload.partition([record, fresh], now: cancelled.addingTimeInterval(25 * 3_600))
        #expect(split.kept == [fresh])
        #expect(split.expired == [record])
    }
}

// MARK: Storage and SHA-256 verification

struct OfflineModelStorageTests {
    private func tempRoot() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("intake-offline-model-\(UUID().uuidString)", isDirectory: true)
    }

    @Test
    func layoutIsUnderAPartialFolder() {
        let storage = OfflineModelStorage(root: URL(fileURLWithPath: "/tmp/Models"))
        #expect(storage.modelURL(for: .best).path == "/tmp/Models/Qwen3-4B-Instruct-2507-Q4_K_M.gguf")
        #expect(storage.partialURL(for: .best).path == "/tmp/Models/.partial/Qwen3-4B-Instruct-2507-Q4_K_M.gguf.part")
        #expect(OfflineModelStorage.defaultRoot().path.hasSuffix("/Intake/Models"))
        #if os(macOS)
        #expect(OfflineModelStorage.defaultRoot().path.hasSuffix("Application Support/Intake/Models"))
        #endif
    }

    @Test
    func streamingSHA256MatchesKnownVectors() throws {
        let root = tempRoot()
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let abc = root.appendingPathComponent("abc")
        try Data("abc".utf8).write(to: abc)
        #expect(OfflineModelFileVerifier.sha256Hex(of: abc)
            == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
        // Chunk boundaries don't change the digest.
        let big = root.appendingPathComponent("big")
        try Data(repeating: 0x61, count: 1_000_000).write(to: big)
        let whole = OfflineModelFileVerifier.sha256Hex(of: big)
        #expect(OfflineModelFileVerifier.sha256Hex(of: big, chunkSize: 4_097) == whole)
        #expect(whole == "cdc76e5c9914fb9281a1c7e284d73e67f1809a48a497200e046d39ccc7112cd0")
        #expect(OfflineModelFileVerifier.sha256Hex(of: root.appendingPathComponent("missing")) == nil)
    }

    @Test
    func verifyRequiresBothSizeAndChecksum() throws {
        let root = tempRoot()
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("model.gguf")
        let content = Data("abc".utf8)
        try content.write(to: file)
        var entry = OfflineModelManifest.lite
        entry.byteSize = 3
        entry.sha256 = "BA7816BF8F01CFEA414140DE5DAE2223B00361A396177A9CB410FF61F20015AD"
        #expect(OfflineModelFileVerifier.verify(file, against: entry))
        entry.byteSize = 4
        #expect(!OfflineModelFileVerifier.verify(file, against: entry))
        entry.byteSize = 3
        entry.sha256 = String(repeating: "0", count: 64)
        #expect(!OfflineModelFileVerifier.verify(file, against: entry))
        // The real manifest never accepts a stand-in file.
        #expect(!OfflineModelFileVerifier.verify(file, against: OfflineModelManifest.lite))
    }

    @Test
    func installMovesThePartialAndDeleteLeavesNothingBehind() throws {
        let storage = OfflineModelStorage(root: tempRoot())
        defer { try? FileManager.default.removeItem(at: storage.root) }
        try storage.prepareDirectories()
        var entry = OfflineModelManifest.lite
        entry.byteSize = 5
        try Data("hello".utf8).write(to: storage.partialURL(for: entry))
        #expect(storage.partialBytes(for: entry) == 5)
        let installed = try storage.installPartial(for: entry)
        #expect(installed == storage.modelURL(for: entry))
        #expect(storage.isInstalled(entry))
        #expect(storage.partialBytes(for: entry) == 0)

        try Data("he".utf8).write(to: storage.partialURL(for: entry))
        storage.deleteModel(for: entry)
        #expect(!FileManager.default.fileExists(atPath: storage.modelURL(for: entry).path))
        #expect(!FileManager.default.fileExists(atPath: storage.partialURL(for: entry).path))
        #expect(storage.strayPartials(keeping: []).isEmpty)
    }

    @Test
    func strayPartialsAreFound() throws {
        let storage = OfflineModelStorage(root: tempRoot())
        defer { try? FileManager.default.removeItem(at: storage.root) }
        try storage.prepareDirectories()
        try Data("x".utf8).write(to: storage.partialURL(for: .best))
        try Data("x".utf8).write(to: storage.partialDirectory.appendingPathComponent("old-model.gguf.part"))
        let stray = storage.strayPartials(keeping: [storage.partialURL(for: .best).lastPathComponent])
        #expect(stray.map(\.lastPathComponent) == ["old-model.gguf.part"])
    }
}
