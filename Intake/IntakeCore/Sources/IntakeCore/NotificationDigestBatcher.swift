import Foundation

/// Batches Activity/Cleanup events into `NotificationDigest`s for IN-10.
/// Time is always passed in (`now:`) so tests never depend on the wall clock.
///
/// - Filing entries flush after 5 minutes with no new filings, or at 50
///   entries, whichever comes first.
/// - Errors are sent immediately but throttled to at most one digest a minute.
/// - New Cleanup items are summarized once per scan — only items not already
///   notified about are included.
public struct NotificationDigestBatcher: Sendable {
    public static let filingQuietWindow: TimeInterval = 5 * 60
    public static let filingMaxBatchSize = 50
    public static let errorThrottleWindow: TimeInterval = 60

    private var pendingFilings: [ActivityEntry] = []
    private var lastFilingAt: Date?
    private var pendingErrors: [ActivityEntry] = []
    private var lastErrorSentAt: Date?
    private var notifiedCleanupURLs: Set<URL> = []

    public init() {}

    // MARK: Filed

    /// Buffers a filed entry. Returns a digest immediately once the batch
    /// reaches `filingMaxBatchSize`; otherwise `nil` — call
    /// `checkFilingQuietPeriod` on a heartbeat to flush after 5 idle minutes.
    @discardableResult
    public mutating func addFiling(
        _ entry: ActivityEntry,
        now: Date = Date(),
        includeRenameOnly: Bool = false
    ) -> NotificationDigest? {
        pendingFilings.append(entry)
        lastFilingAt = now
        guard pendingFilings.count >= Self.filingMaxBatchSize else { return nil }
        return flushFilings(includeRenameOnly: includeRenameOnly)
    }

    /// Call periodically; flushes buffered filings once 5 minutes have passed
    /// since the last one arrived.
    @discardableResult
    public mutating func checkFilingQuietPeriod(
        now: Date = Date(),
        includeRenameOnly: Bool = false
    ) -> NotificationDigest? {
        guard !pendingFilings.isEmpty, let lastFilingAt else { return nil }
        guard now.timeIntervalSince(lastFilingAt) >= Self.filingQuietWindow else { return nil }
        return flushFilings(includeRenameOnly: includeRenameOnly)
    }

    public var pendingFilingCount: Int { pendingFilings.count }

    private mutating func flushFilings(includeRenameOnly: Bool) -> NotificationDigest? {
        let digest = NotificationDigestComposer.filedDigest(
            entries: pendingFilings,
            includeRenameOnly: includeRenameOnly
        )
        pendingFilings.removeAll()
        lastFilingAt = nil
        return digest
    }

    // MARK: Errors

    /// Buffers an error and sends immediately unless a digest already went
    /// out within the last minute, in which case it stays queued for the
    /// next `addError` or `checkErrorThrottle` call once the window elapses.
    @discardableResult
    public mutating func addError(_ entry: ActivityEntry, now: Date = Date()) -> NotificationDigest? {
        pendingErrors.append(entry)
        return flushErrorsIfAllowed(now: now)
    }

    /// Call periodically; flushes any throttled errors once the minute is up.
    @discardableResult
    public mutating func checkErrorThrottle(now: Date = Date()) -> NotificationDigest? {
        flushErrorsIfAllowed(now: now)
    }

    public var pendingErrorCount: Int { pendingErrors.count }

    private mutating func flushErrorsIfAllowed(now: Date) -> NotificationDigest? {
        guard !pendingErrors.isEmpty else { return nil }
        if let lastErrorSentAt, now.timeIntervalSince(lastErrorSentAt) < Self.errorThrottleWindow {
            return nil
        }
        let digest = NotificationDigestComposer.errorDigest(entries: pendingErrors)
        pendingErrors.removeAll()
        lastErrorSentAt = now
        return digest
    }

    // MARK: Cleanup

    /// Summarizes a finished Cleanup scan, excluding items already notified
    /// about in a previous scan (by URL).
    @discardableResult
    public mutating func cleanupDigest(for candidates: [CleanupCandidate]) -> NotificationDigest? {
        let newCandidates = candidates.filter { !notifiedCleanupURLs.contains($0.url) }
        guard !newCandidates.isEmpty else { return nil }
        notifiedCleanupURLs.formUnion(newCandidates.map(\.url))
        return NotificationDigestComposer.cleanupDigest(candidates: newCandidates)
    }

    /// Drops URLs that no longer appear in a scan (deleted / filed away) so the
    /// notified set doesn't grow without bound. Call after each scan with the
    /// full current candidate list.
    public mutating func pruneNotifiedCleanupURLs(stillPresent candidates: [CleanupCandidate]) {
        let present = Set(candidates.map(\.url))
        notifiedCleanupURLs.formIntersection(present)
    }
}
