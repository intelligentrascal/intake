import Foundation
import Observation
import IntakeCore

/// Live ingest for one watch folder profile: its security-scoped access, its
/// own `DownloadsFolderWatcher`, its Wait-before-organizing queue, and its
/// lost-access state. `AppModel` owns one per profile and keeps the settings
/// (`WatchFolderProfile`) and the shared Activity / Undo / notification plumbing.
@Observable
@MainActor
final class WatchFolderController {
    let profileID: String
    /// The resolved folder (bookmark, else the profile's last known path).
    private(set) var folder: URL
    /// True when the stored bookmark could not be resolved. Shown per folder
    /// with a Grant Access action.
    private(set) var accessLost: Bool

    @ObservationIgnored private unowned let model: AppModel
    @ObservationIgnored private let watcher = DownloadsFolderWatcher()
    @ObservationIgnored private var accessing = false
    @ObservationIgnored private var arrivedWhilePaused: [URL] = []
    @ObservationIgnored private var waitingForAge: [PendingStableFile] = []
    @ObservationIgnored private var ageGateTask: Task<Void, Never>?
    @ObservationIgnored private var ageGateHeartbeatTask: Task<Void, Never>?
    @ObservationIgnored private var arrivedDuringOrganize: [URL] = []

    init(profile: WatchFolderProfile, model: AppModel) {
        profileID = profile.id
        self.model = model
        let resolved = Self.resolve(profile)
        folder = resolved.url
        accessLost = resolved.lost
    }

    var profile: WatchFolderProfile {
        model.watchFolderProfile(id: profileID)
            ?? WatchFolderProfile(id: profileID, path: folder.path)
    }

    var displayName: String {
        profile.displayName
    }

    /// The global rule list narrowed to this folder's scope.
    var rules: [RoutingRule] {
        model.rules(forWatchFolder: profileID)
    }

    var managedFolderNames: Set<String> {
        DefaultTaxonomy.managedFolderNames(from: rules)
    }

    var ignorePolicy: DownloadIgnorePolicy {
        DownloadIgnorePolicy(managedFolderNames: managedFolderNames)
    }

    var pipeline: IngestPipeline {
        IngestPipeline(watchFolder: folder, rules: rules)
    }

    var processor: OrganizeExistingProcessor {
        OrganizeExistingProcessor(watchFolder: folder, rules: rules, ignorePolicy: ignorePolicy)
    }

    /// True when `url` is this folder or anything below it.
    func contains(_ url: URL) -> Bool {
        let root = folder.standardizedFileURL.path
        let path = url.standardizedFileURL.path
        return path == root || path.hasPrefix(root.hasSuffix("/") ? root : root + "/")
    }

    // MARK: Lifecycle

    func start() {
        accessing = folder.startAccessingSecurityScopedResource()
        restartWatcher()
    }

    func stop() {
        watcher.stop()
        cancelAgeGate()
        if accessing {
            folder.stopAccessingSecurityScopedResource()
            accessing = false
        }
    }

    /// The profile is being removed: stop and forget its Wait queue.
    func discard() {
        stop()
        waitingForAge.removeAll()
        arrivedWhilePaused.removeAll()
        WaitingForAgeStore.clear(in: .standard, profileID: profileID)
    }

    /// A folder was picked for this profile (Change… or Grant Access…).
    /// A different folder starts with an empty Wait queue, like 1.2 did.
    func replaceFolder(with url: URL) {
        let isSameFolder = url.standardizedFileURL.path == folder.standardizedFileURL.path
        stop()
        if !isSameFolder {
            arrivedWhilePaused.removeAll()
            waitingForAge.removeAll()
            WaitingForAgeStore.clear(in: .standard, profileID: profileID)
        }
        folder = url
        accessLost = false
        start()
    }

    /// Reacts to a settings change on this profile.
    func profileDidChange(from old: WatchFolderProfile) {
        let new = profile
        if old.isOrganizing && !new.isOrganizing {
            cancelAgeGate()
            return
        }
        if !old.isOrganizing && new.isOrganizing {
            let pending = arrivedWhilePaused
            arrivedWhilePaused.removeAll()
            let now = Date()
            pending.forEach { rememberStable($0, stableAt: now) }
            reevaluateWaitingForAge()
            return
        }
        if old.organizingWait != new.organizingWait {
            reevaluateWaitingForAge()
        }
    }

    func updateIgnorePolicy() {
        watcher.updateIgnorePolicy(ignorePolicy)
    }

    /// Mark a root name known so the watcher doesn't treat it as a new download.
    func acknowledgeRootFile(named name: String) {
        watcher.acknowledgeRootFile(named: name)
    }

    /// Organize Existing is about to handle these files — drop them from Wait.
    func removeFromWaitingQueue(_ urls: Set<URL>) {
        waitingForAge.removeAll { urls.contains($0.url) }
        persistWaitingForAge()
    }

    func flushArrivedDuringOrganize() {
        let pending = arrivedDuringOrganize
        arrivedDuringOrganize.removeAll()
        for url in pending {
            handleStableFile(url)
        }
    }

    func pruneEmptyManagedFolders() {
        let entries = CleanupProcessor(
            watchFolder: folder,
            managedFolderNames: managedFolderNames
        ).removeEmptyManagedFolders()
        model.recordOrganized(entries, watchFolderID: profileID)
    }

    // MARK: Live ingest

    func handleStableFile(_ reportedURL: URL, stableAt: Date = Date()) {
        if model.isOrganizingExisting {
            arrivedDuringOrganize.append(reportedURL)
            return
        }
        // A repeated or late stable event can name a file that was already renamed
        // or moved. Skip it instead of logging a second row for the same file, and
        // use the spelling on disk so one file never queues under two names.
        guard FileManager.default.fileExists(atPath: reportedURL.path) else { return }
        let url = FileIdentity.onDiskURL(for: reportedURL)
        let current = applyRenameOnStableIfNeeded(url)
        rememberStable(current, stableAt: stableAt)
        if !profile.isOrganizing {
            arrivedWhilePaused.removeAll { $0.standardizedFileURL == current.standardizedFileURL }
            arrivedWhilePaused.append(current)
            return
        }
        reevaluateWaitingForAge()
    }

    private func applyRenameOnStableIfNeeded(_ url: URL) -> URL {
        guard profile.liveIngestPolicy.shouldRenameOnStable else { return url }
        switch processor.processOne(url, mode: .renameInPlace) {
        case .organized(let entries):
            model.recordOrganized(entries, watchFolderID: profileID)
            let current = entries.last?.url ?? url
            // Prevent the watcher from treating the renamed root name as a new download.
            watcher.acknowledgeRootFile(named: current.lastPathComponent)
            if current.standardizedFileURL != url.standardizedFileURL {
                watcher.acknowledgeRootFile(named: url.lastPathComponent)
            }
            return current
        case .skipped(let entry), .error(let entry):
            model.record(entry, watchFolderID: profileID)
            return url
        case .notInWatchRoot:
            return url
        }
    }

    private func rememberStable(_ url: URL, stableAt: Date) {
        let standardized = url.standardizedFileURL
        if waitingForAge.contains(where: { $0.url == standardized }) {
            return
        }
        waitingForAge.append(PendingStableFile(url: standardized, stableAt: stableAt))
        persistWaitingForAge()
    }

    private func reevaluateWaitingForAge() {
        ageGateTask?.cancel()
        ageGateTask = nil
        let profile = profile
        guard profile.isOrganizing else {
            ensureAgeGateHeartbeat()
            return
        }

        let partitioned = FileAgeGate.partition(
            pending: waitingForAge,
            wait: profile.organizingWait
        )
        waitingForAge = partitioned.waiting
        var deferred: [PendingStableFile] = []
        for item in partitioned.ready {
            // Belt-and-suspenders: never route before Wait even if partition misfires.
            guard profile.liveIngestPolicy.shouldRoute(
                stableAt: item.stableAt,
                wait: profile.organizingWait
            ) else {
                deferred.append(item)
                continue
            }
            if !applyIngest(item.url, stableAt: item.stableAt, policy: profile.liveIngestPolicy) {
                // Empty / still-writing — keep waiting with original stableAt.
                deferred.append(item)
            }
        }
        waitingForAge.append(contentsOf: deferred)
        persistWaitingForAge()
        ensureAgeGateHeartbeat()

        guard let next = waitingForAge.min(by: { $0.stableAt < $1.stableAt }) else { return }
        let delay = FileAgeGate.delayUntilEligible(stableAt: next.stableAt, wait: profile.organizingWait)
        ageGateTask = Task { @MainActor in
            let nanoseconds = UInt64(max(delay, 0.05) * 1_000_000_000)
            try? await Task.sleep(nanoseconds: nanoseconds)
            guard !Task.isCancelled else { return }
            self.reevaluateWaitingForAge()
        }
    }

    /// Defensive 30s heartbeat so eligibility is not missed if the sleep Task is cancelled/lost.
    private func ensureAgeGateHeartbeat() {
        guard profile.isOrganizing, !waitingForAge.isEmpty else {
            ageGateHeartbeatTask?.cancel()
            ageGateHeartbeatTask = nil
            return
        }
        guard ageGateHeartbeatTask == nil else { return }
        ageGateHeartbeatTask = Task { @MainActor in
            defer { self.ageGateHeartbeatTask = nil }
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 30_000_000_000)
                guard !Task.isCancelled else { return }
                guard self.profile.isOrganizing, !self.waitingForAge.isEmpty else { return }
                self.reevaluateWaitingForAge()
            }
        }
    }

    private func cancelAgeGate() {
        ageGateTask?.cancel()
        ageGateTask = nil
        ageGateHeartbeatTask?.cancel()
        ageGateHeartbeatTask = nil
    }

    private func persistWaitingForAge() {
        WaitingForAgeStore.save(waitingForAge, to: .standard, profileID: profileID)
    }

    /// Restore persisted Wait-queue entries after the watcher seeds `knownNames`.
    /// Acknowledge those root names so rename/watch does not double-ingest, but keep them in `waitingForAge`.
    private func restoreWaitingForAgeFromDisk() {
        let restored = WaitingForAgeStore.restoreExisting(
            from: .standard,
            profileID: profileID,
            watchRoot: folder
        )
        guard !restored.isEmpty else {
            // Drop stale paths that no longer exist under this root.
            if !WaitingForAgeStore.load(from: .standard, profileID: profileID).isEmpty {
                persistWaitingForAge()
            }
            return
        }
        for item in restored {
            if !waitingForAge.contains(where: { $0.url == item.url }) {
                waitingForAge.append(item)
            }
            watcher.acknowledgeRootFile(named: item.url.lastPathComponent)
        }
        persistWaitingForAge()
        reevaluateWaitingForAge()
    }

    /// Returns `false` when the file should stay queued (missing, empty, or not routed yet).
    @discardableResult
    private func applyIngest(_ url: URL, stableAt: Date?, policy: LiveIngestPolicy) -> Bool {
        guard FileManager.default.fileExists(atPath: url.path) else { return true }
        if !DownloadWriteGate.allowsOrganizeOrRename(at: url) {
            return false
        }
        switch processor.processOne(url, mode: policy.applyModeAfterWait, stableAt: stableAt) {
        case .organized(let entries):
            if entries.isEmpty {
                // routeOnly refused (e.g. empty) — keep queued.
                return false
            }
            model.recordOrganized(entries, watchFolderID: profileID)
            model.requestOpenRouterIfNeeded(entries: entries)
            return true
        case .skipped(let entry), .error(let entry):
            model.record(entry, watchFolderID: profileID)
            return true
        case .notInWatchRoot:
            return true
        }
    }

    private func restartWatcher() {
        watcher.stop()
        watcher.start(folder: folder, ignorePolicy: ignorePolicy) { [weak self] url in
            Task { @MainActor in
                self?.handleStableFile(url)
            }
        }
        // Watcher start seeds knownNames with existing root files — restore Wait queue
        // so pending files remain eligible without mass-organizing the whole folder.
        restoreWaitingForAgeFromDisk()
    }

    // MARK: Bookmarks

    /// Resolves the profile's security-scoped bookmark. No bookmark means the
    /// default folder the user never had to pick (Downloads). A bookmark that
    /// can't be resolved is "access lost": keep the last known path so the
    /// row can still name the folder.
    private static func resolve(_ profile: WatchFolderProfile) -> (url: URL, lost: Bool) {
        guard let data = profile.bookmark else {
            return (profile.url, false)
        }
        var stale = false
        guard let url = try? URL(
            resolvingBookmarkData: data,
            options: [.withSecurityScope],
            relativeTo: nil,
            bookmarkDataIsStale: &stale
        ) else {
            return (profile.url, true)
        }
        return (url, false)
    }

    static func bookmark(for url: URL) -> Data? {
        try? url.bookmarkData(
            options: .withSecurityScope,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
    }
}
