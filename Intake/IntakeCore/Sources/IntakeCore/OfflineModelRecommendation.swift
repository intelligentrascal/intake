import Foundation

/// What onboarding knows about this Mac (SPEC §8.1). The app probes it with
/// sysctl / ProcessInfo / volume capacity; tests build it directly.
public struct MacHardwareProfile: Equatable, Sendable {
    public var architecture: MacArchitecture
    public var memoryBytes: UInt64
    /// `machdep.cpu.brand_string`, display only. `nil` falls back to
    /// "Apple silicon" / "Intel".
    public var chipName: String?
    /// `volumeAvailableCapacityForImportantUsage` on Application Support.
    public var freeDiskBytes: Int64

    public init(architecture: MacArchitecture, memoryBytes: UInt64, chipName: String? = nil, freeDiskBytes: Int64) {
        self.architecture = architecture
        self.memoryBytes = memoryBytes
        self.chipName = chipName
        self.freeDiskBytes = freeDiskBytes
    }

    /// An arm64 build, or an x86_64 build translated by Rosetta, is Apple silicon.
    public static func architecture(isARM64Build: Bool, isTranslated: Bool) -> MacArchitecture {
        (isARM64Build || isTranslated) ? .appleSilicon : .intel
    }

    /// Installed memory in whole GB, as Apple markets it (16 GiB → 16).
    public var memoryGB: Int {
        Int((Double(memoryBytes) / 1_073_741_824).rounded())
    }

    public var chipDisplayName: String {
        let trimmed = chipName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !trimmed.isEmpty { return trimmed }
        return architecture == .appleSilicon ? "Apple silicon" : "Intel"
    }

    /// "M2 · 16 GB memory · 214 GB free"
    public var macLine: String {
        "\(chipDisplayName) · \(memoryGB) GB memory · \(OfflineModelFormat.bytes(freeDiskBytes)) free"
    }
}

/// Why a tier can't be picked on this Mac (SPEC §8.3).
public enum OfflineTierDisabledReason: Equatable, Sendable {
    case notOnIntel
    case needsMemory(gigabytes: Int)
    case needsSpace(label: String)

    public var text: String {
        switch self {
        case .notOnIntel: "Not available on Intel Macs"
        case .needsMemory(let gigabytes): "Needs \(gigabytes) GB memory"
        case .needsSpace(let label): "Needs \(label) free space"
        }
    }
}

public struct OfflineTierOption: Equatable, Sendable, Identifiable {
    public var tier: OfflineModelTier
    public var line: OfflineTierLine
    public var isRecommended: Bool
    public var disabledReason: OfflineTierDisabledReason?

    public var id: OfflineModelTier { tier }
    public var isEnabled: Bool { disabledReason == nil }
}

public struct OfflineModelRecommendation: Equatable, Sendable {
    public enum Status: Equatable, Sendable {
        /// Download this tier (it fits on disk).
        case recommended(OfflineModelTier)
        /// Intel under 8 GB, or every tier failed its self-test.
        case unsupported
        /// Hardware allows a tier, but none fits on disk.
        case noTierFits
    }

    public var status: Status
    public var architecture: MacArchitecture
    /// The tier this Mac's hardware calls for, ignoring disk space.
    public var hardwareTier: OfflineModelTier?
    /// Picker rows. Intel lists Lite (CPU) only (SPEC §13 AC3).
    public var options: [OfflineTierOption]
    public var freeDiskBytes: Int64

    public var recommendedTier: OfflineModelTier? {
        if case .recommended(let tier) = status { return tier }
        return nil
    }

    /// The hardware tier doesn't fit: "Best needs 2.5 GB plus 2 GB free. This Mac has 3.9 GB free."
    public var noSpaceMessage: String? {
        guard let hardwareTier else { return nil }
        if case .recommended(let tier) = status, tier == hardwareTier { return nil }
        if status == .unsupported { return nil }
        let entry = OfflineModelManifest.entry(for: hardwareTier)
        let name = OfflineModelManifest.displayName(for: hardwareTier, on: architecture)
        return "\(name) needs \(entry.sizeLabel) plus 2 GB free. This Mac has \(OfflineModelFormat.bytes(freeDiskBytes)) free."
    }

    /// "Standard fits: 1.28 GB." when a smaller tier was recommended for space.
    public var smallerTierMessage: String? {
        guard noSpaceMessage != nil, let tier = recommendedTier else { return nil }
        let name = OfflineModelManifest.displayName(for: tier, on: architecture)
        return "\(name) fits: \(OfflineModelManifest.entry(for: tier).sizeLabel)."
    }

    public static let noSpaceNoneMessage = "Free up space and try again."
    public static let unsupportedTitle = "Offline renaming isn't available on this Mac"
    public static let unsupportedMessage = "Offline renaming needs at least 8 GB of memory. Intake will keep giving files tidy names. You can use OpenRouter in Settings › AI."
}

/// Per-Mac recommendation (SPEC §6). Pure: hardware + disk in, tier out.
public enum OfflineModelRecommender {
    public static let minimumIntelMemoryGB = 8
    public static let bestMemoryGB = 16

    /// - Parameter unsupportedTiers: tiers that failed their self-test on this Mac.
    public static func recommend(
        for profile: MacHardwareProfile,
        unsupportedTiers: Set<OfflineModelTier> = []
    ) -> OfflineModelRecommendation {
        let arch = profile.architecture
        let memory = profile.memoryGB

        let hardwareTier: OfflineModelTier?
        switch arch {
        case .intel:
            hardwareTier = memory >= minimumIntelMemoryGB ? .lite : nil
        case .appleSilicon:
            hardwareTier = memory >= bestMemoryGB ? .best : .standard
        }

        let listed: [OfflineModelTier] = arch == .intel ? [.lite] : [.lite, .standard, .best]
        var options: [OfflineTierOption] = listed.map { tier in
            let entry = OfflineModelManifest.entry(for: tier)
            var reason: OfflineTierDisabledReason?
            if !entry.runs(on: arch) {
                reason = .notOnIntel
            } else if memory < entry.minimumMemoryGB {
                reason = .needsMemory(gigabytes: entry.minimumMemoryGB)
            } else if profile.freeDiskBytes < entry.requiredFreeBytes {
                reason = .needsSpace(label: entry.needLabel)
            }
            return OfflineTierOption(
                tier: tier,
                line: OfflineModelManifest.line(for: tier, on: arch),
                isRecommended: false,
                disabledReason: reason
            )
        }

        guard let hardwareTier, hardwareTier.isSupported(excluding: unsupportedTiers) else {
            // Self-test failures push the hardware tier down.
            if let hardwareTier, let lower = hardwareTier.largestSupported(excluding: unsupportedTiers) {
                return finish(profile: profile, hardwareTier: lower, options: &options, unsupported: unsupportedTiers)
            }
            return OfflineModelRecommendation(
                status: .unsupported,
                architecture: arch,
                hardwareTier: hardwareTier,
                options: [],
                freeDiskBytes: profile.freeDiskBytes
            )
        }
        return finish(profile: profile, hardwareTier: hardwareTier, options: &options, unsupported: unsupportedTiers)
    }

    private static func finish(
        profile: MacHardwareProfile,
        hardwareTier: OfflineModelTier,
        options: inout [OfflineTierOption],
        unsupported: Set<OfflineModelTier>
    ) -> OfflineModelRecommendation {
        // Largest tier at or below the hardware tier that is enabled and fits.
        let candidate = options
            .filter { $0.tier <= hardwareTier && $0.isEnabled && !unsupported.contains($0.tier) }
            .map(\.tier)
            .max()
        let status: OfflineModelRecommendation.Status
        if let candidate {
            status = .recommended(candidate)
            for index in options.indices where options[index].tier == candidate {
                options[index].isRecommended = true
            }
        } else {
            status = .noTierFits
        }
        return OfflineModelRecommendation(
            status: status,
            architecture: profile.architecture,
            hardwareTier: hardwareTier,
            options: options,
            freeDiskBytes: profile.freeDiskBytes
        )
    }
}

private extension OfflineModelTier {
    func isSupported(excluding unsupported: Set<OfflineModelTier>) -> Bool {
        !unsupported.contains(self)
    }

    func largestSupported(excluding unsupported: Set<OfflineModelTier>) -> OfflineModelTier? {
        var tier: OfflineModelTier? = self
        while let current = tier {
            if !unsupported.contains(current) { return current }
            tier = current.nextSmaller
        }
        return nil
    }
}

/// Byte, ETA and progress strings for onboarding, Settings and the menu.
public enum OfflineModelFormat {
    /// Decimal units, like Finder: "900 MB", "3.9 GB", "214 GB", "1,842 GB".
    public static func bytes(_ value: Int64) -> String {
        let bytes = Double(max(value, 0))
        if bytes < 1_000_000_000 {
            let mb = Int((bytes / 1_000_000).rounded())
            return "\(mb) MB"
        }
        let gb = bytes / 1_000_000_000
        if gb < 10 {
            return String(format: "%.1f GB", (gb * 10).rounded(.down) / 10)
        }
        let whole = Int(gb.rounded(.down))
        return "\(grouped(whole)) GB"
    }

    private static func grouped(_ value: Int) -> String {
        let digits = String(value)
        var out = ""
        for (index, character) in digits.enumerated() {
            if index > 0, (digits.count - index) % 3 == 0 { out.append(",") }
            out.append(character)
        }
        return out
    }

    /// "about 3 minutes left", "about 1 hour 20 minutes left",
    /// "less than a minute left". `nil` while the rate is unknown.
    public static func timeRemaining(_ seconds: TimeInterval?) -> String? {
        guard let seconds, seconds.isFinite, seconds >= 0 else { return nil }
        if seconds < 60 { return "less than a minute left" }
        let totalMinutes = Int((seconds / 60).rounded())
        if totalMinutes < 60 {
            return "about \(totalMinutes) \(totalMinutes == 1 ? "minute" : "minutes") left"
        }
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        let hourText = "\(hours) \(hours == 1 ? "hour" : "hours")"
        if minutes == 0 { return "about \(hourText) left" }
        return "about \(hourText) \(minutes) \(minutes == 1 ? "minute" : "minutes") left"
    }

    /// "1.2 GB of 2.5 GB · about 3 minutes left"
    public static func progress(received: Int64, entry: OfflineModelManifestEntry, secondsRemaining: TimeInterval?) -> String {
        let base = "\(bytes(received)) of \(entry.sizeLabel)"
        guard let eta = timeRemaining(secondsRemaining) else { return base }
        return "\(base) · \(eta)"
    }

    /// "48%"
    public static func percent(received: Int64, total: Int64) -> String {
        guard total > 0 else { return "0%" }
        let value = Int((Double(received) / Double(total) * 100).rounded(.down))
        return "\(min(max(value, 0), 100))%"
    }
}

/// Moving-average download rate over a short window, for a live ETA.
public struct DownloadRateEstimator: Equatable, Sendable {
    public var window: TimeInterval
    private var samples: [Sample] = []

    private struct Sample: Equatable, Sendable {
        var time: Date
        var bytes: Int64
    }

    public init(window: TimeInterval = 10) {
        self.window = window
    }

    public mutating func record(bytes: Int64, at time: Date) {
        samples.append(Sample(time: time, bytes: bytes))
        samples.removeAll { time.timeIntervalSince($0.time) > window }
    }

    public mutating func reset() {
        samples.removeAll()
    }

    /// Bytes per second, or `nil` with too little data.
    public var bytesPerSecond: Double? {
        guard let first = samples.first, let last = samples.last else { return nil }
        let elapsed = last.time.timeIntervalSince(first.time)
        guard elapsed >= 1, last.bytes > first.bytes else { return nil }
        return Double(last.bytes - first.bytes) / elapsed
    }

    public func secondsRemaining(received: Int64, total: Int64) -> TimeInterval? {
        guard let rate = bytesPerSecond, rate > 0 else { return nil }
        return Double(max(total - received, 0)) / rate
    }
}
