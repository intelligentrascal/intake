import Foundation
import Testing
@testable import IntakeCore

struct FileAgeGateTests {
    @Test
    func immediatelyIsEligibleAtTheMomentOfStability() {
        let stableAt = Date()
        #expect(FileAgeGate.isEligible(stableAt: stableAt, wait: .immediately, now: stableAt))
        #expect(FileAgeGate.delayUntilEligible(stableAt: stableAt, wait: .immediately, now: stableAt) == 0)
        #expect(OrganizingWait.immediately.title == "Immediately")
    }

    @Test
    func defaultWaitIsTwoHoursAndTitlesMatchLockedUX() {
        #expect(OrganizingWait.default == .twoHours)
        #expect(OrganizingWait.allCases.map(\.title) == [
            "Immediately",
            "15 minutes",
            "1 hour",
            "2 hours",
            "1 day",
        ])
        #expect(OrganizingWait(storedSeconds: nil) == .twoHours)
        #expect(OrganizingWait(storedSeconds: 123) == .twoHours)
        #expect(OrganizingWait(storedSeconds: 0) == .immediately)
        #expect(OrganizingWait(storedSeconds: 86_400) == .oneDay)
    }

    @Test
    func tooYoungSinceStableAtIsNotEligible() {
        let stableAt = Date()
        let almost = stableAt.addingTimeInterval(2 * 3600 - 1)
        #expect(
            FileAgeGate.isEligible(stableAt: stableAt, wait: .twoHours, now: almost) == false
        )
        #expect(
            FileAgeGate.isEligible(
                stableAt: stableAt,
                wait: .twoHours,
                now: stableAt.addingTimeInterval(2 * 3600)
            )
        )
    }

    @Test
    func ageStartsAtStableAtNotFirstByte() {
        let firstByte = Date().addingTimeInterval(-5 * 3600)
        let stableAt = firstByte.addingTimeInterval(4 * 3600)
        let now = stableAt.addingTimeInterval(10 * 60)
        #expect(FileAgeGate.isEligible(stableAt: stableAt, wait: .twoHours, now: now) == false)
        #expect(now.timeIntervalSince(firstByte) > OrganizingWait.twoHours.seconds)
        #expect(
            FileAgeGate.isEligible(
                stableAt: stableAt,
                wait: .twoHours,
                now: stableAt.addingTimeInterval(2 * 3600)
            )
        )
    }

    @Test
    func changingThresholdMidWaitReevaluatesTheSameStableAt() {
        let stableAt = Date()
        let now = stableAt.addingTimeInterval(20 * 60)
        let pending = [PendingStableFile(url: URL(fileURLWithPath: "/tmp/report.pdf"), stableAt: stableAt)]
        let stillWaiting = FileAgeGate.partition(pending: pending, wait: .twoHours, now: now) { _ in true }
        #expect(stillWaiting.ready.isEmpty)
        #expect(stillWaiting.waiting.count == 1)
        #expect(stillWaiting.waiting.first?.stableAt == stableAt)

        let shortened = FileAgeGate.partition(pending: pending, wait: .fifteenMinutes, now: now) { _ in true }
        #expect(shortened.ready.count == 1)
        #expect(shortened.ready.first?.stableAt == stableAt)

        let lengthened = FileAgeGate.partition(pending: pending, wait: .oneDay, now: now) { _ in true }
        #expect(lengthened.ready.isEmpty)
        #expect(lengthened.waiting.first?.stableAt == stableAt)

        let immediate = FileAgeGate.partition(pending: pending, wait: .immediately, now: now) { _ in true }
        #expect(immediate.ready.count == 1)
    }

    @Test
    func missingFilesAreDroppedSilently() {
        let pending = [
            PendingStableFile(url: URL(fileURLWithPath: "/tmp/gone.pdf"), stableAt: Date().addingTimeInterval(-3 * 3600)),
        ]
        let result = FileAgeGate.partition(pending: pending, wait: .twoHours) { _ in false }
        #expect(result.ready.isEmpty)
        #expect(result.waiting.isEmpty)
    }

    @Test
    func organizeExistingBypassesTheAgeGateForABrandNewFile() throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory.appendingPathComponent(
            "intake-age-organize-\(UUID().uuidString)",
            isDirectory: true
        )
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: root) }

        let fresh = root.appendingPathComponent("just-downloaded.pdf")
        try Data("pdf".utf8).write(to: fresh)
        let justNow = Date()
        #expect(FileAgeGate.isEligible(stableAt: justNow, wait: .twoHours, now: justNow) == false)

        let result = OrganizeExistingProcessor(watchFolder: root).processOne(
            fresh,
            fileManager: fileManager
        )
        guard case .organized = result else {
            Issue.record("Organize Existing should file a new root file without waiting")
            return
        }
        #expect(
            fileManager.fileExists(
                atPath: root.appendingPathComponent("Documents", isDirectory: true)
                    .appendingPathComponent("Just Downloaded.pdf").path
            )
        )
    }
}
