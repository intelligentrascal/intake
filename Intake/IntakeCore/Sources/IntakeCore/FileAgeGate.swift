import Foundation

/// Wait after a download is **stable** before live auto-organize **routes** it.
/// Rename-on-stable is not gated here. Organize Existing does not use this gate.
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
        guard let object = defaults.object(forKey: defaultsKey) else {
            return .default
        }
        // `defaults write … 7200` without -int can store a String; integer(forKey:)
        // then returns 0 → `.immediately`, which skipped Wait in live smoke.
        let seconds: Int?
        switch object {
        case let value as Int:
            seconds = value
        case let value as NSNumber:
            seconds = value.intValue
        case let value as String:
            seconds = Int(value.trimmingCharacters(in: .whitespacesAndNewlines))
        default:
            seconds = nil
        }
        return OrganizingWait(storedSeconds: seconds)
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
