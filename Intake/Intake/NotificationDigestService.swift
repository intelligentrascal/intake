import Foundation
import IntakeCore
import UserNotifications

/// Delivers IN-10 notification digests through `UNUserNotificationCenter`.
/// Owns the pure `NotificationDigestBatcher` (IntakeCore) and turns its
/// output into real notifications with Show Activity / Undo actions.
/// Authorization is requested only when the master toggle is switched on —
/// never at launch, and never merely because a digest is ready.
@MainActor
final class NotificationDigestService: NSObject {
    nonisolated static let filedCategoryID = "intake.digest.filed"
    nonisolated static let errorsCategoryID = "intake.digest.errors"
    nonisolated static let cleanupCategoryID = "intake.digest.cleanup"
    nonisolated static let showActivityActionID = "intake.action.showActivity"
    nonisolated static let undoActionID = "intake.action.undo"
    nonisolated static let undoActivityIDKey = "undoActivityID"

    /// Heartbeat cadence for quiet-period / throttle checks — matches the
    /// cadence AppModel already uses for its Wait-before-organizing heartbeat.
    private static let heartbeatInterval: TimeInterval = 30

    private var batcher = NotificationDigestBatcher()
    private var heartbeatTask: Task<Void, Never>?
    private weak var model: AppModel?

    func attach(to model: AppModel) {
        self.model = model
        UNUserNotificationCenter.current().delegate = self
        registerCategories()
    }

    /// Call once at launch with the persisted master-toggle value, and again
    /// whenever the user flips the toggle in Settings.
    func setMasterEnabled(_ enabled: Bool) {
        guard enabled else {
            stopHeartbeat()
            return
        }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
        startHeartbeat()
    }

    // MARK: Hooks called by AppModel

    func noteFiled(_ entry: ActivityEntry, now: Date = Date()) {
        if let digest = batcher.addFiling(entry, now: now) {
            deliver(digest)
        }
    }

    func noteError(_ entry: ActivityEntry, now: Date = Date()) {
        if let digest = batcher.addError(entry, now: now) {
            deliver(digest)
        }
    }

    func noteCleanupScan(_ candidates: [CleanupCandidate]) {
        if let digest = batcher.cleanupDigest(for: candidates) {
            deliver(digest)
        }
        batcher.pruneNotifiedCleanupURLs(stillPresent: candidates)
    }

    // MARK: Heartbeat

    private func startHeartbeat() {
        guard heartbeatTask == nil else { return }
        heartbeatTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(Self.heartbeatInterval * 1_000_000_000))
                guard !Task.isCancelled, let self else { return }
                self.checkHeartbeat()
            }
        }
    }

    private func stopHeartbeat() {
        heartbeatTask?.cancel()
        heartbeatTask = nil
    }

    private func checkHeartbeat() {
        let now = Date()
        if let digest = batcher.checkFilingQuietPeriod(now: now) {
            deliver(digest)
        }
        if let digest = batcher.checkErrorThrottle(now: now) {
            deliver(digest)
        }
    }

    // MARK: Delivery

    private func registerCategories() {
        let showActivity = UNNotificationAction(
            identifier: Self.showActivityActionID,
            title: "Show Activity",
            options: []
        )
        let undo = UNNotificationAction(
            identifier: Self.undoActionID,
            title: UndoCopy.undo,
            options: []
        )
        let filed = UNNotificationCategory(
            identifier: Self.filedCategoryID,
            actions: [undo, showActivity],
            intentIdentifiers: [],
            options: []
        )
        let errors = UNNotificationCategory(
            identifier: Self.errorsCategoryID,
            actions: [showActivity],
            intentIdentifiers: [],
            options: []
        )
        let cleanup = UNNotificationCategory(
            identifier: Self.cleanupCategoryID,
            actions: [showActivity],
            intentIdentifiers: [],
            options: []
        )
        UNUserNotificationCenter.current().setNotificationCategories([filed, errors, cleanup])
    }

    private func deliver(_ digest: NotificationDigest) {
        let content = UNMutableNotificationContent()
        content.title = digest.title
        content.body = digest.body
        content.categoryIdentifier = categoryID(for: digest.category)
        if digest.showsUndo, let undoActivityID = digest.undoActivityID {
            content.userInfo = [Self.undoActivityIDKey: undoActivityID.uuidString]
        }
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }

    private func categoryID(for category: NotificationDigest.Category) -> String {
        switch category {
        case .filed: Self.filedCategoryID
        case .errors: Self.errorsCategoryID
        case .cleanup: Self.cleanupCategoryID
        }
    }
}

extension NotificationDigestService: UNUserNotificationCenterDelegate {
    /// Show banners even while Intake is the active app.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let actionID = response.actionIdentifier
        let undoActivityID = (response.notification.request.content.userInfo[Self.undoActivityIDKey] as? String)
            .flatMap(UUID.init(uuidString:))
        defer { completionHandler() }
        Task { @MainActor [weak self] in
            switch actionID {
            case Self.undoActionID:
                if let undoActivityID {
                    self?.model?.undo(activityID: undoActivityID)
                }
            case UNNotificationDefaultActionIdentifier, Self.showActivityActionID:
                self?.model?.openActivity()
            default:
                break
            }
        }
    }
}
