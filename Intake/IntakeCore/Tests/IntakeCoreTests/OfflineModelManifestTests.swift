import Foundation
import Testing
@testable import IntakeCore

// MARK: Manifest (SPEC §4) — sizes, revisions and SHA-256 are pinned.

struct OfflineModelManifestTests {
    @Test
    func entriesArePinnedToTheSpecManifest() {
        let lite = OfflineModelManifest.entry(for: .lite)
        #expect(lite.repository == "unsloth/Qwen3.5-0.8B-GGUF")
        #expect(lite.revision.hasPrefix("6ab4614"))
        #expect(lite.fileName == "Qwen3.5-0.8B-Q4_K_M.gguf")
        #expect(lite.byteSize == 532_517_120)
        #expect(lite.sha256 == "bd258782e35f7f458f8aced1adc053e6e92e89bc735ba3be89d38a06121dc517")

        let standard = OfflineModelManifest.entry(for: .standard)
        #expect(standard.repository == "unsloth/Qwen3.5-2B-GGUF")
        #expect(standard.revision.hasPrefix("f6d5376"))
        #expect(standard.fileName == "Qwen3.5-2B-Q4_K_M.gguf")
        #expect(standard.byteSize == 1_280_835_840)
        #expect(standard.sha256 == "aaf42c8b7c3cab2bf3d69c355048d4a0ee9973d48f16c731c0520ee914699223")

        let best = OfflineModelManifest.entry(for: .best)
        #expect(best.repository == "unsloth/Qwen3-4B-Instruct-2507-GGUF")
        #expect(best.revision.hasPrefix("a06e946"))
        #expect(best.fileName == "Qwen3-4B-Instruct-2507-Q4_K_M.gguf")
        #expect(best.byteSize == 2_497_281_120)
        #expect(best.sha256 == "3605803b982cb64aead44f6c1b2ae36e3acdb41d8e46c8a94c6533bc4c67e597")
    }

    @Test
    func revisionsAreFullCommitsAndChecksumsAreLowercaseHex() {
        let hex = Set("0123456789abcdef")
        for entry in OfflineModelManifest.entries + [OfflineModelManifest.bestChallenger] {
            #expect(entry.revision.count == 40)
            #expect(entry.revision.allSatisfy { hex.contains($0) })
            #expect(entry.sha256.count == 64)
            #expect(entry.sha256.allSatisfy { hex.contains($0) })
            #expect(entry.license == "Apache 2.0")
            #expect(entry.fileName.hasSuffix("-Q4_K_M.gguf"))
        }
    }

    @Test
    func downloadURLIsThePinnedResolveURLWithNoToken() {
        let best = OfflineModelManifest.best
        #expect(best.downloadURL.absoluteString
            == "https://huggingface.co/unsloth/Qwen3-4B-Instruct-2507-GGUF/resolve/a06e946bb6b655725eafa393f4a9745d460374c9/Qwen3-4B-Instruct-2507-Q4_K_M.gguf")
        #expect(best.downloadURL.query == nil)
    }

    @Test
    func diskNeedIsDownloadPlusTwoGigabytes() {
        // ≈ 2.53 / 3.28 / 4.50 GB (SPEC §6).
        #expect(OfflineModelManifest.lite.requiredFreeBytes == 2_532_517_120)
        #expect(OfflineModelManifest.standard.requiredFreeBytes == 3_280_835_840)
        #expect(OfflineModelManifest.best.requiredFreeBytes == 4_497_281_120)
        #expect(OfflineModelManifest.bestChallenger.requiredFreeBytes == 5_106_738_272)
    }

    @Test
    func tierLinesAreVerbatimPMCopy() {
        #expect(OfflineModelManifest.line(for: .best).text == "Best — 2.5 GB download · most accurate")
        #expect(OfflineModelManifest.line(for: .standard).text == "Standard — 1.28 GB download · accurate for everyday files")
        #expect(OfflineModelManifest.line(for: .lite).text == "Lite — 533 MB · smallest, fine for simple documents")
        #expect(OfflineModelManifest.line(for: .lite, on: .intel).text == "Lite (CPU) — 533 MB · renames when plugged in")
        #expect(OfflineModelManifest.line(for: .best).name == "Best")
    }

    @Test
    func tierCopyNeverMentionsModelNamesOrSpeed() {
        let lines = OfflineModelTier.allCases.map { OfflineModelManifest.line(for: $0).text }
            + [OfflineModelManifest.line(for: .lite, on: .intel).text]
            + OfflineModelRunSetting.allCases.map(\.help)
        for line in lines {
            for word in ["Qwen", "Gemma", "fast", "quick", "second"] {
                #expect(!line.localizedCaseInsensitiveContains(word))
            }
        }
    }

    @Test
    func architecturesAndMemoryMatchTheTierTable() {
        #expect(OfflineModelManifest.lite.runs(on: .intel))
        #expect(OfflineModelManifest.lite.runs(on: .appleSilicon))
        #expect(!OfflineModelManifest.standard.runs(on: .intel))
        #expect(!OfflineModelManifest.best.runs(on: .intel))
        #expect(OfflineModelManifest.best.minimumMemoryGB == 16)
        #expect(OfflineModelManifest.best.promptFormat == .qwen3Instruct)
        #expect(OfflineModelManifest.standard.promptFormat == .qwen35NonThinking)
        #expect(OfflineModelManifest.lite.promptFormat == .qwen35NonThinking)
        #expect(OfflineModelManifest.bestChallenger.promptFormat == .gemma4)
    }

    @Test
    func tierOrderAndNextSmaller() {
        #expect(OfflineModelTier.lite < .standard)
        #expect(OfflineModelTier.standard < .best)
        #expect(OfflineModelTier.best.nextSmaller == .standard)
        #expect(OfflineModelTier.standard.nextSmaller == .lite)
        #expect(OfflineModelTier.lite.nextSmaller == nil)
    }
}

// MARK: Recommendation (SPEC §6, §8.1, §13 AC3)

struct OfflineModelRecommendationTests {
    private let gib: UInt64 = 1_073_741_824
    private func profile(_ arch: MacArchitecture, memoryGB: UInt64, freeGB: Double, chip: String? = nil) -> MacHardwareProfile {
        MacHardwareProfile(
            architecture: arch,
            memoryBytes: memoryGB * gib,
            chipName: chip,
            freeDiskBytes: Int64(freeGB * 1_000_000_000)
        )
    }

    @Test
    func appleSilicon16GBGetsBest() {
        let rec = OfflineModelRecommender.recommend(for: profile(.appleSilicon, memoryGB: 16, freeGB: 214, chip: "M2"))
        #expect(rec.status == .recommended(.best))
        #expect(rec.options.map(\.tier) == [.lite, .standard, .best])
        #expect(rec.options.allSatisfy { $0.isEnabled })
        #expect(rec.options.first { $0.isRecommended }?.tier == .best)
        #expect(rec.noSpaceMessage == nil)
    }

    @Test
    func appleSilicon8GBGetsStandardWithBestDisabled() {
        let rec = OfflineModelRecommender.recommend(for: profile(.appleSilicon, memoryGB: 8, freeGB: 96))
        #expect(rec.status == .recommended(.standard))
        let best = rec.options.first { $0.tier == .best }
        #expect(best?.disabledReason == .needsMemory(gigabytes: 16))
        #expect(best?.disabledReason?.text == "Needs 16 GB memory")
        #expect(rec.options.first { $0.tier == .lite }?.isEnabled == true)
    }

    @Test
    func intelListsLiteCPUOnly() {
        let rec = OfflineModelRecommender.recommend(for: profile(.intel, memoryGB: 8, freeGB: 120, chip: "Intel Core i5"))
        #expect(rec.status == .recommended(.lite))
        #expect(rec.options.map(\.tier) == [.lite])
        #expect(rec.options.first?.line.text == "Lite (CPU) — 533 MB · renames when plugged in")
    }

    @Test
    func intelUnder8GBIsUnsupported() {
        let rec = OfflineModelRecommender.recommend(for: profile(.intel, memoryGB: 4, freeGB: 61))
        #expect(rec.status == .unsupported)
        #expect(rec.options.isEmpty)
        #expect(OfflineModelRecommendation.unsupportedMessage
            == "Offline renaming needs at least 8 GB of memory. Intake will keep giving files tidy names. You can use OpenRouter in Settings › AI.")
    }

    @Test
    func rosettaCountsAsAppleSilicon() {
        #expect(MacHardwareProfile.architecture(isARM64Build: false, isTranslated: true) == .appleSilicon)
        #expect(MacHardwareProfile.architecture(isARM64Build: true, isTranslated: false) == .appleSilicon)
        #expect(MacHardwareProfile.architecture(isARM64Build: false, isTranslated: false) == .intel)
    }

    @Test
    func lowDiskRecommendsTheLargestTierThatFitsAndSaysWhy() {
        // 16 GB Mac with 3.9 GB free (PM ruling 3): Best needs 4.50, Standard 3.28.
        let rec = OfflineModelRecommender.recommend(for: profile(.appleSilicon, memoryGB: 16, freeGB: 3.9, chip: "M2"))
        #expect(rec.status == .recommended(.standard))
        #expect(rec.hardwareTier == .best)
        #expect(rec.noSpaceMessage == "Best needs 2.5 GB plus 2 GB free. This Mac has 3.9 GB free.")
        #expect(rec.smallerTierMessage == "Standard fits: 1.28 GB.")
        #expect(rec.options.first { $0.tier == .best }?.disabledReason?.text == "Needs 4.5 GB free space")
    }

    @Test
    func nothingFitsAsksToFreeUpSpace() {
        let rec = OfflineModelRecommender.recommend(for: profile(.appleSilicon, memoryGB: 16, freeGB: 0.9))
        #expect(rec.status == .noTierFits)
        #expect(rec.recommendedTier == nil)
        #expect(rec.options.allSatisfy { !$0.isEnabled })
        #expect(OfflineModelRecommendation.noSpaceNoneMessage == "Free up space and try again.")
    }

    @Test
    func diskRuleBoundaries() {
        let exact = MacHardwareProfile(architecture: .appleSilicon, memoryBytes: 16 * gib, freeDiskBytes: OfflineModelManifest.best.requiredFreeBytes)
        #expect(OfflineModelRecommender.recommend(for: exact).status == .recommended(.best))
        let oneShort = MacHardwareProfile(architecture: .appleSilicon, memoryBytes: 16 * gib, freeDiskBytes: OfflineModelManifest.best.requiredFreeBytes - 1)
        #expect(OfflineModelRecommender.recommend(for: oneShort).status == .recommended(.standard))
        let liteOnly = MacHardwareProfile(architecture: .appleSilicon, memoryBytes: 8 * gib, freeDiskBytes: 3_000_000_000)
        #expect(OfflineModelRecommender.recommend(for: liteOnly).status == .recommended(.lite))
    }

    @Test
    func selfTestFailuresStepTheRecommendationDown() {
        let mac = profile(.appleSilicon, memoryGB: 16, freeGB: 214)
        #expect(OfflineModelRecommender.recommend(for: mac, unsupportedTiers: [.best]).status == .recommended(.standard))
        #expect(OfflineModelRecommender.recommend(for: mac, unsupportedTiers: [.best, .standard]).status == .recommended(.lite))
        #expect(OfflineModelRecommender.recommend(for: mac, unsupportedTiers: [.best, .standard, .lite]).status == .unsupported)
        let intel = profile(.intel, memoryGB: 16, freeGB: 100)
        #expect(OfflineModelRecommender.recommend(for: intel, unsupportedTiers: [.lite]).status == .unsupported)
    }

    @Test
    func macLineHandlesLongChipsAndFourDigitDisks() {
        #expect(profile(.appleSilicon, memoryGB: 16, freeGB: 214, chip: "M2").macLine == "M2 · 16 GB memory · 214 GB free")
        #expect(profile(.appleSilicon, memoryGB: 64, freeGB: 1_842.4, chip: "M4 Max").macLine == "M4 Max · 64 GB memory · 1,842 GB free")
        #expect(profile(.intel, memoryGB: 8, freeGB: 120).macLine == "Intel · 8 GB memory · 120 GB free")
        #expect(profile(.appleSilicon, memoryGB: 8, freeGB: 50, chip: "  ").chipDisplayName == "Apple silicon")
    }
}

// MARK: Formatting

struct OfflineModelFormatTests {
    @Test
    func bytesUseDecimalUnitsLikeFinder() {
        #expect(OfflineModelFormat.bytes(900_000_000) == "900 MB")
        #expect(OfflineModelFormat.bytes(190_400_000) == "190 MB")
        #expect(OfflineModelFormat.bytes(1_200_000_000) == "1.2 GB")
        #expect(OfflineModelFormat.bytes(3_900_000_000) == "3.9 GB")
        #expect(OfflineModelFormat.bytes(214_000_000_000) == "214 GB")
        #expect(OfflineModelFormat.bytes(1_842_000_000_000) == "1,842 GB")
    }

    @Test
    func timeRemainingCopy() {
        #expect(OfflineModelFormat.timeRemaining(nil) == nil)
        #expect(OfflineModelFormat.timeRemaining(20) == "less than a minute left")
        #expect(OfflineModelFormat.timeRemaining(65) == "about 1 minute left")
        #expect(OfflineModelFormat.timeRemaining(180) == "about 3 minutes left")
        #expect(OfflineModelFormat.timeRemaining(4_800) == "about 1 hour 20 minutes left")
        #expect(OfflineModelFormat.timeRemaining(7_200) == "about 2 hours left")
    }

    @Test
    func progressLineAndPercent() {
        let best = OfflineModelManifest.best
        #expect(OfflineModelFormat.progress(received: 1_200_000_000, entry: best, secondsRemaining: 180)
            == "1.2 GB of 2.5 GB · about 3 minutes left")
        #expect(OfflineModelFormat.progress(received: 1_200_000_000, entry: best, secondsRemaining: nil)
            == "1.2 GB of 2.5 GB")
        #expect(OfflineModelFormat.percent(received: 1_200_000_000, total: best.byteSize) == "48%")
        #expect(OfflineModelFormat.percent(received: 5, total: 0) == "0%")
    }

    @Test
    func rateEstimatorUsesAMovingWindow() {
        var estimator = DownloadRateEstimator(window: 10)
        let start = Date(timeIntervalSince1970: 0)
        #expect(estimator.bytesPerSecond == nil)
        estimator.record(bytes: 0, at: start)
        estimator.record(bytes: 10_000_000, at: start.addingTimeInterval(1))
        #expect(estimator.bytesPerSecond == 10_000_000)
        #expect(estimator.secondsRemaining(received: 10_000_000, total: 110_000_000) == 10)
        // Old samples fall out of the window.
        estimator.record(bytes: 20_000_000, at: start.addingTimeInterval(30))
        estimator.record(bytes: 25_000_000, at: start.addingTimeInterval(31))
        #expect(estimator.bytesPerSecond == 5_000_000)
    }
}
