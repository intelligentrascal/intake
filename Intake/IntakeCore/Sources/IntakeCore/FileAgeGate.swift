import Foundation

/// Wait after a download is **stable** before live auto-organize files it.
/// Organize Existing does not use this gate.
public enum OrganizingWait: Int, CaseIterable, Identifiable, Sendable, Codable {
    case immediately = 0
    case fifteenMinutes = 900
    case oneHour = 3_600
    case twoHours = 7_200
    case oneDay = 86_400

    public static let `default` = twoHours
    public static let defaultsKey = "intake.minimumOrganizingAge"

    public var id: Int { rawValue }
    public var seconds: TimeInterval { TimeInterval(rawValue) }

    public var title: String {
        switch self {
        case .immediately: "Immediately"
        case .fifteenMinutes: "15 minutes"
        case .oneHour: "1 hour"
        case .twoHours: "2 hours"
        case .oneDay: "1 day"
        }
    }

    public init(storedSeconds: Int?) {
        if let storedSeconds, let value = OrganizingWait(rawValue: storedSeconds) {
            self = value
        } else {
            self = .default
        }
    }

    public static func load(from defaults: UserDefaults) -> OrganizingWait {
        if defaults.object(forKey: defaultsKey) == nil {
            return .default
        }
        return OrganizingWait(storedSeconds: defaults.integer(forKey: defaultsKey))
    }

    public static func persist(_ value: OrganizingWait, to defaults: UserDefaults) {
        defaults.set(value.rawValue, forKey: defaultsKey)
    }
}

/// A watch-root file that has passed stability debounce; the wait clock starts here.
public struct PendingStableFile: Equatable, Sendable {
    public var url: URL
    public var stableAt: Date

    public init(url: URL, stableAt: Date) {
        self.url = url.standardizedFileURL
        self.stableAt = stableAt
    }
}

public enum FileAgeGate: Sendable {
    public static func isEligible(
        stableAt: Date,
        wait: OrganizingWait,
        now: Date = Date()
    ) -> Bool {
        isEligible(age: now.timeIntervalSince(stableAt), wait: wait)
    }

    public static func isEligible(age: TimeInterval, wait: OrganizingWait) -> Bool {
        wait == .immediately || age >= wait.seconds
    }

    public static func delayUntilEligible(
        stableAt: Date,
        wait: OrganizingWait,
        now: Date = Date()
    ) -> TimeInterval {
        delayUntilEligible(age: now.timeIntervalSince(stableAt), wait: wait)
    }

    public static func delayUntilEligible(age: TimeInterval, wait: OrganizingWait) -> TimeInterval {
        if wait == .immediately {
            return 0
        }
        return max(0, wait.seconds - age)
    }

    /// Re-evaluates from each item’s original `stableAt`. Missing files are dropped
    /// (moved/deleted) and never appear in `ready` or `waiting`.
    public static func partition(
        pending: [PendingStableFile],
        wait: OrganizingWait,
        now: Date = Date(),
        stillExists: (URL) -> Bool = { url in
            FileManager.default.fileExists(atPath: url.path)
        }
    ) -> (ready: [PendingStableFile], waiting: [PendingStableFile]) {
        var ready: [PendingStableFile] = []
        var waiting: [PendingStableFile] = []
        for item in pending {
            guard stillExists(item.url) else { continue }
            if isEligible(stableAt: item.stableAt, wait: wait, now: now) {
                ready.append(item)
            } else {
                waiting.append(item)
            }
        }
        return (ready, waiting)
    }
}
