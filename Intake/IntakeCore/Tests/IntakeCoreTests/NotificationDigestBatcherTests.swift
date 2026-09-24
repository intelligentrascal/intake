import Foundation
import Testing
@testable import IntakeCore

struct NotificationDigestBatcherTests {
    private func filed(_ i: Int, folder: String = "Documents") -> ActivityEntry {
        ActivityEntry(
            kind: .moved,
            detail: "Moved file\(i)",
            fileName: "file\(i).pdf",
            destinationFolder: folder,
            beforePath: "/before/file\(i)",
            afterPath: "/after/file\(i)"
        )
    }

    private func error(_ i: Int) -> ActivityEntry {
        ActivityEntry(kind: .error, detail: "Error \(i)", fileName: "e\(i)")
    }

    // MARK: Filing — quiet-period flush

    @Test
    func flushesAfterFiveQuietMinutes() {
        var batcher = NotificationDigestBatcher()
        let start = Date(timeIntervalSince1970: 0)
        for i in 0..<12 {
            #expect(batcher.addFiling(filed(i), now: start) == nil)
        }
        // Not yet 5 minutes since the last filing.
        #expect(batcher.checkFilingQuietPeriod(now: start.addingTimeInterval(60)) == nil)
        #expect(batcher.pendingFilingCount == 12)

        let digest = batcher.checkFilingQuietPeriod(now: start.addingTimeInterval(5 * 60 + 1))
        #expect(digest?.title == "Filed 12 items")
        #expect(batcher.pendingFilingCount == 0)
    }

    @Test
    func quietPeriodResetsOnEachNewFiling() {
        var batcher = NotificationDigestBatcher()
        let start = Date(timeIntervalSince1970: 0)
        batcher.addFiling(filed(0), now: start)
        // A new filing 4 minutes later should push the quiet deadline out.
        batcher.addFiling(filed(1), now: start.addingTimeInterval(4 * 60))
        #expect(batcher.checkFilingQuietPeriod(now: start.addingTimeInterval(5 * 60 + 1)) == nil)
        let digest = batcher.checkFilingQuietPeriod(now: start.addingTimeInterval(4 * 60 + 5 * 60 + 1))
        #expect(digest?.title == "Filed 2 items")
    }

    // MARK: Filing — 50-entry flush

    @Test
    func flushesAtFiftyEntriesWithoutWaiting() {
        var batcher = NotificationDigestBatcher()
        let start = Date(timeIntervalSince1970: 0)
        var lastDigest: NotificationDigest?
        for i in 0..<50 {
            lastDigest = batcher.addFiling(filed(i), now: start.addingTimeInterval(Double(i)))
        }
        #expect(lastDigest?.title == "Filed 50 items")
        #expect(batcher.pendingFilingCount == 0)
    }

    @Test
    func singleFilingFlushOffersUndo() {
        var batcher = NotificationDigestBatcher()
        let start = Date(timeIntervalSince1970: 0)
        let entry = filed(0)
        batcher.addFiling(entry, now: start)
        let digest = batcher.checkFilingQuietPeriod(now: start.addingTimeInterval(5 * 60 + 1))
        #expect(digest?.showsUndo == true)
        #expect(digest?.undoActivityID == entry.id)
    }

    @Test
    func emptyBatcherQuietCheckReturnsNil() {
        var batcher = NotificationDigestBatcher()
        #expect(batcher.checkFilingQuietPeriod(now: Date()) == nil)
    }

    // MARK: Errors — immediate but throttled

    @Test
    func firstErrorSendsImmediately() {
        var batcher = NotificationDigestBatcher()
        let digest = batcher.addError(error(0), now: Date(timeIntervalSince1970: 0))
        #expect(digest?.title == "Intake error")
    }

    @Test
    func secondErrorWithinAMinuteIsThrottled() {
        var batcher = NotificationDigestBatcher()
        let start = Date(timeIntervalSince1970: 0)
        #expect(batcher.addError(error(0), now: start) != nil)
        #expect(batcher.addError(error(1), now: start.addingTimeInterval(10)) == nil)
        #expect(batcher.pendingErrorCount == 1)
    }

    @Test
    func throttledErrorsFlushAfterAMinuteAndBatchTogether() {
        var batcher = NotificationDigestBatcher()
        let start = Date(timeIntervalSince1970: 0)
        #expect(batcher.addError(error(0), now: start) != nil)
        #expect(batcher.addError(error(1), now: start.addingTimeInterval(5)) == nil)
        #expect(batcher.addError(error(2), now: start.addingTimeInterval(30)) == nil)
        let digest = batcher.checkErrorThrottle(now: start.addingTimeInterval(61))
        #expect(digest?.title == "2 errors")
        #expect(batcher.pendingErrorCount == 0)
    }

    @Test
    func errorThrottleAllowsOnePerMinuteSustained() {
        var batcher = NotificationDigestBatcher()
        let start = Date(timeIntervalSince1970: 0)
        #expect(batcher.addError(error(0), now: start) != nil)
        #expect(batcher.addError(error(1), now: start.addingTimeInterval(61)) != nil)
    }

    // MARK: Cleanup — de-dup across scans

    @Test
    func cleanupDigestOnlyIncludesNewItemsAcrossScans() {
        var batcher = NotificationDigestBatcher()
        let a = CleanupCandidate(url: URL(fileURLWithPath: "/a"), byteCount: 1, lastUsed: .distantPast)
        let b = CleanupCandidate(url: URL(fileURLWithPath: "/b"), byteCount: 1, lastUsed: .distantPast)

        let first = batcher.cleanupDigest(for: [a])
        #expect(first?.title == "1 item ready for cleanup")

        // Same scan repeated (e.g. re-scan with no new candidates) yields nothing.
        #expect(batcher.cleanupDigest(for: [a]) == nil)

        // A second scan with one more candidate reports only the new one.
        let second = batcher.cleanupDigest(for: [a, b])
        #expect(second?.title == "1 item ready for cleanup")
    }

    @Test
    func cleanupDigestReturnsNilWhenNothingNew() {
        var batcher = NotificationDigestBatcher()
        #expect(batcher.cleanupDigest(for: []) == nil)
    }

    @Test
    func pruneNotifiedCleanupURLsForgetsResolvedItems() {
        var batcher = NotificationDigestBatcher()
        let a = CleanupCandidate(url: URL(fileURLWithPath: "/a"), byteCount: 1, lastUsed: .distantPast)
        _ = batcher.cleanupDigest(for: [a])
        batcher.pruneNotifiedCleanupURLs(stillPresent: [])
        // `a` was cleaned up and no longer appears; if it reappears later it's news again.
        #expect(batcher.cleanupDigest(for: [a])?.title == "1 item ready for cleanup")
    }
}
