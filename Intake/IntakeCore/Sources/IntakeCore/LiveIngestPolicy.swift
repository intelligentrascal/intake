import Foundation

/// Live-watcher stages: local rename on stable vs route after Wait.
/// OpenRouter is unchanged and is not part of this policy.
public struct LiveIngestPolicy: Equatable, Sendable {
    public var renameWhenDownloadFinishes: Bool
    public var automaticOrganizing: Bool

    public init(renameWhenDownloadFinishes: Bool, automaticOrganizing: Bool) {
        self.renameWhenDownloadFinishes = renameWhenDownloadFinishes
        self.automaticOrganizing = automaticOrganizing
    }

    public var shouldRenameOnStable: Bool {
        renameWhenDownloadFinishes
    }

    /// When Rename is off, filing still runs the combined rename → route path.
    public var legacyRenameWhenFiling: Bool {
        !renameWhenDownloadFinishes && automaticOrganizing
    }

    public var applyModeAfterWait: IngestApplyMode {
        renameWhenDownloadFinishes ? .routeOnly : .renameAndRoute
    }

    public func shouldRoute(
        stableAt: Date,
        wait: OrganizingWait,
        now: Date = Date()
    ) -> Bool {
        automaticOrganizing && FileAgeGate.isEligible(stableAt: stableAt, wait: wait, now: now)
    }
}

public enum IngestApplyMode: String, Sendable, Equatable {
    case renameInPlace
    case routeOnly
    case renameAndRoute
}
