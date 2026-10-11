import Foundation

/// Settings › AI › "Run the offline model" (SPEC §9.4).
public enum OfflineModelRunSetting: String, CaseIterable, Codable, Sendable, Identifiable {
    case smart
    case always
    case pluggedIn

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .smart: "Smart (recommended)"
        case .always: "Always"
        case .pluggedIn: "Only when plugged in"
        }
    }

    /// Approved helper copy (SPEC v1.3.1 ruling 9).
    public var help: String {
        switch self {
        case .smart:
            "Runs right away on power. On battery, Intake renames single files and saves bigger jobs for when you plug in. It pauses when your Mac is hot or low on memory."
        case .always:
            "Runs as soon as a file arrives, on battery too. It still pauses if your Mac gets very hot or runs out of memory."
        case .pluggedIn:
            "Runs only on power. On battery, files keep their tidy names and wait until you plug in. It also pauses when your Mac is hot or low on memory."
        }
    }

    public static let defaultsKey = "intake.offlineModel.runSetting"
}

public enum ThermalLevel: Int, Comparable, Codable, Sendable {
    case nominal
    case fair
    case serious
    case critical

    public static func < (lhs: ThermalLevel, rhs: ThermalLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

public enum MemoryPressureLevel: Int, Comparable, Codable, Sendable {
    case normal
    case warning
    case critical

    public static func < (lhs: MemoryPressureLevel, rhs: MemoryPressureLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

public enum PowerSource: Equatable, Codable, Sendable {
    case ac
    /// `percent` is nil when the battery level can't be read.
    case battery(percent: Int?)

    public var isOnBattery: Bool {
        if case .battery = self { return true }
        return false
    }
}

/// Everything the policy looks at, sampled on each change and before each
/// inference (SPEC §9.1).
public struct ResourceSignals: Equatable, Sendable {
    public var thermal: ThermalLevel
    public var memory: MemoryPressureLevel
    public var lowPowerMode: Bool
    public var power: PowerSource
    public var architecture: MacArchitecture

    public init(
        thermal: ThermalLevel = .nominal,
        memory: MemoryPressureLevel = .normal,
        lowPowerMode: Bool = false,
        power: PowerSource = .ac,
        architecture: MacArchitecture = .appleSilicon
    ) {
        self.thermal = thermal
        self.memory = memory
        self.lowPowerMode = lowPowerMode
        self.power = power
        self.architecture = architecture
    }
}

/// What the offline model is being asked to do.
public enum OfflineWorkKind: Equatable, Sendable {
    /// One file that just arrived.
    case singleNewFile
    /// Draining the queue, or Organize Existing.
    case batch
    /// The user pressed Rename Now / Rename All Now.
    case renameNow
}

/// Why a file is waiting. Shown in the menu, Settings and Activity.
public enum OfflineWaitReason: String, Codable, Sendable, Equatable {
    case waitingForPower
    case macIsHot
    case lowMemory
    case lowPowerMode

    public var text: String {
        switch self {
        case .waitingForPower: "Waiting for power"
        case .macIsHot: "Mac is hot"
        case .lowMemory: "Low memory"
        case .lowPowerMode: "Low Power Mode"
        }
    }
}

public enum OfflineUnloadDirective: Equatable, Sendable {
    case keep
    case now
    case after(TimeInterval)
}

public enum OfflineInferencePriority: Equatable, Sendable {
    /// Background work (`.utility`).
    case utility
    /// Rename Now (`.userInitiated`).
    case userInitiated
}

public enum OfflinePolicyDecision: Equatable, Sendable {
    /// Run now. `tier` is set when row 3 steps down to an installed backup.
    case run(priority: OfflineInferencePriority, tier: OfflineModelTier?)
    /// Queue; the file keeps its Title Case name for now.
    case wait(OfflineWaitReason, unload: OfflineUnloadDirective)

    public var shouldRun: Bool {
        if case .run = self { return true }
        return false
    }

    public var waitReason: OfflineWaitReason? {
        if case .wait(let reason, _) = self { return reason }
        return nil
    }
}

/// SPEC §9.2 "Smart" policy, rows 1–8 and 10 (row 9 is P1). First match wins.
/// Pure: the app feeds signals, the engine answers.
public enum OfflineModelPolicy {
    /// Row 2: unload this long after a serious thermal state starts.
    public static let seriousThermalUnloadDelay: TimeInterval = 60
    public static let lowBatteryPercent = 20
    public static let midBatteryPercent = 40
    /// Queue drains on AC in chunks of this many files (SPEC §9.5).
    public static let drainChunkSize = 20

    public static func decide(
        work: OfflineWorkKind,
        setting: OfflineModelRunSetting,
        signals: ResourceSignals,
        isModelLoaded: Bool,
        activeTier: OfflineModelTier,
        installedBackup: OfflineModelTier? = nil
    ) -> OfflinePolicyDecision {
        let priority: OfflineInferencePriority = work == .renameNow ? .userInitiated : .utility

        // Row 1: thermal critical or memory critical. Applies to everything,
        // Rename Now included.
        if signals.thermal == .critical {
            return .wait(.macIsHot, unload: .now)
        }
        if signals.memory == .critical {
            return .wait(.lowMemory, unload: .now)
        }
        // Rename Now bypasses rows 2–9.
        if work == .renameNow {
            return .run(priority: priority, tier: nil)
        }
        // Row 2: thermal serious. Applies to every setting.
        if signals.thermal == .serious {
            return .wait(.macIsHot, unload: .after(seriousThermalUnloadDelay))
        }
        // Row 3: memory warning (Smart and Only when plugged in; Always
        // ignores load). Step down only to an installed backup; Lite never steps down.
        if setting != .always, signals.memory == .warning {
            if activeTier != .lite, let backup = installedBackup, backup < activeTier {
                return .run(priority: priority, tier: backup)
            }
            return .wait(.lowMemory, unload: .now)
        }

        switch setting {
        case .always:
            return .run(priority: priority, tier: nil)
        case .pluggedIn:
            if signals.power.isOnBattery {
                return .wait(.waitingForPower, unload: .keep)
            }
            return .run(priority: priority, tier: nil)
        case .smart:
            break
        }

        // Row 4: Low Power Mode.
        if signals.lowPowerMode {
            return .wait(.lowPowerMode, unload: .keep)
        }
        guard case .battery(let percent) = signals.power else {
            // Row 10: AC power. Run; batches drain in chunks.
            return .run(priority: priority, tier: nil)
        }
        // Row 8: Intel on battery queues all work. Checked before the battery
        // bands so a charged Intel laptop still waits (SPEC §9.2 row 8 intent).
        if signals.architecture == .intel {
            return .wait(.waitingForPower, unload: .keep)
        }
        let level = percent ?? 100
        // Row 5: battery ≤ 20%.
        if level <= lowBatteryPercent {
            return .wait(.waitingForPower, unload: .keep)
        }
        // No batches on battery (rows 6–7).
        if work == .batch {
            return .wait(.waitingForPower, unload: .keep)
        }
        // Row 6: 21–40%: single files only if already loaded (no cold loads).
        if level <= midBatteryPercent {
            return isModelLoaded
                ? .run(priority: priority, tier: nil)
                : .wait(.waitingForPower, unload: .keep)
        }
        // Row 7: > 40%: single new files.
        return .run(priority: priority, tier: nil)
    }
}

/// Thermal / memory flapping guard (SPEC §9.5): after a row-1 or row-2
/// condition clears, keep treating it as present for 2 minutes.
public struct ResourceSignalHysteresis: Equatable, Sendable {
    public static let defaultHold: TimeInterval = 120

    public var hold: TimeInterval
    private var lastCriticalThermal: Date?
    private var lastSeriousThermal: Date?
    private var lastCriticalMemory: Date?

    public init(hold: TimeInterval = ResourceSignalHysteresis.defaultHold) {
        self.hold = hold
    }

    /// Feed every raw sample; returns the signals the policy should use.
    public mutating func effective(_ raw: ResourceSignals, now: Date) -> ResourceSignals {
        if raw.thermal == .critical { lastCriticalThermal = now }
        if raw.thermal >= .serious { lastSeriousThermal = now }
        if raw.memory == .critical { lastCriticalMemory = now }
        var signals = raw
        if let last = lastCriticalThermal, now.timeIntervalSince(last) < hold {
            signals.thermal = max(signals.thermal, .critical)
        } else if let last = lastSeriousThermal, now.timeIntervalSince(last) < hold {
            signals.thermal = max(signals.thermal, .serious)
        }
        if let last = lastCriticalMemory, now.timeIntervalSince(last) < hold {
            signals.memory = .critical
        }
        return signals
    }

    /// Seconds until a held condition expires (to schedule a re-check).
    public func nextRelease(now: Date) -> TimeInterval? {
        [lastCriticalThermal, lastSeriousThermal, lastCriticalMemory]
            .compactMap { $0 }
            .map { hold - now.timeIntervalSince($0) }
            .filter { $0 > 0 }
            .min()
    }
}
