import Foundation
#if canImport(CryptoKit)
import CryptoKit
#endif

/// Network as onboarding needs it (`NWPathMonitor`: satisfied / isExpensive / isConstrained).
public enum OfflineNetworkStatus: Equatable, Sendable {
    case offline
    /// Hotspot (`isExpensive`) or Low Data Mode (`isConstrained`).
    case metered
    case unmetered
}

public enum OfflineDownloadFailure: Equatable, Sendable {
    /// Not enough space to start or to finish; `shortBytes` more is needed.
    case lowDisk(shortBytes: Int64)
    /// The pinned revision is gone (HTTP 401/403/404).
    case unavailable
    /// SHA-256 mismatch; the file was deleted. `attempt` counts failures.
    case checksumMismatch(attempt: Int)
    /// The model didn't produce valid fields in time on this Mac.
    case selfTestFailed
    /// The model couldn't be loaded (out of memory, damaged).
    case loadFailed
}

/// Download → verify → self-test state (SPEC §7, §8.2–8.4, §14). Pure: the
/// app turns `Effect`s into URLSession / file / inference work and feeds the
/// results back as events.
public struct OfflineModelDownloadMachine: Equatable, Sendable {
    public enum Phase: Equatable, Sendable {
        case idle
        /// Offline at start or network lost: auto-starts/resumes when back.
        case waitingForNetwork(OfflineModelTier, receivedBytes: Int64)
        /// Asked "Download {size} now?" on a metered connection.
        case confirmingMetered(OfflineModelTier)
        /// "Wait for Wi-Fi": starts when the path is neither expensive nor constrained.
        case waitingForUnmetered(OfflineModelTier)
        case downloading(OfflineModelTier, receivedBytes: Int64)
        case paused(OfflineModelTier, receivedBytes: Int64)
        case verifyingChecksum(OfflineModelTier)
        case selfTesting(OfflineModelTier)
        case ready(OfflineModelTier)
        case failed(OfflineModelTier, OfflineDownloadFailure)
    }

    public enum Event: Equatable, Sendable {
        /// Download pressed. `partialBytes` is what's already on disk for this tier.
        case requestDownload(OfflineModelTier, network: OfflineNetworkStatus, freeBytes: Int64, partialBytes: Int64)
        case meteredChoice(downloadAnyway: Bool)
        case networkChanged(OfflineNetworkStatus)
        case progress(receivedBytes: Int64)
        case pause
        case resume(network: OfflineNetworkStatus)
        case cancel
        case transferFailedNetwork(receivedBytes: Int64)
        case transferFailedHTTP(status: Int)
        case transferFailedDiskFull(shortBytes: Int64)
        case transferFinished(totalBytes: Int64)
        case checksumResult(matches: Bool)
        case selfTestResult(passed: Bool)
        case loadFailed
        /// Relaunch with a partial file from a previous session.
        case restore(OfflineModelTier, partialBytes: Int64, wasPaused: Bool, network: OfflineNetworkStatus)
        case reset
    }

    public enum Effect: Equatable, Sendable {
        /// Start or resume the HTTP transfer with `Range: bytes=<fromByte>-`.
        case startTransfer(OfflineModelTier, fromByte: Int64)
        /// Stop the transfer; the partial file stays on disk.
        case stopTransfer
        /// Record the partial for 24 h retention (Cancel Download).
        case retainPartial(OfflineModelTier)
        case deletePartial(OfflineModelTier)
        /// Atomic move from `.partial/`; check free space first.
        case verifyChecksum(OfflineModelTier)
        case runSelfTest(OfflineModelTier)
        case install(OfflineModelTier)
        case deleteModel(OfflineModelTier)
    }

    public private(set) var phase: Phase = .idle
    /// Checksum failures for the current tier (second failure → Send Feedback).
    public private(set) var checksumFailures: Int = 0
    /// The user said "Download Anyway" for this download.
    public private(set) var meteredApproved = false
    /// Where the next transfer resumes (bytes already in the partial file).
    public private(set) var resumeOffset: Int64 = 0

    public init(phase: Phase = .idle) {
        self.phase = phase
    }

    public var tier: OfflineModelTier? {
        switch phase {
        case .idle: nil
        case .waitingForNetwork(let tier, _), .confirmingMetered(let tier), .waitingForUnmetered(let tier),
             .downloading(let tier, _), .paused(let tier, _), .verifyingChecksum(let tier),
             .selfTesting(let tier), .ready(let tier), .failed(let tier, _):
            tier
        }
    }

    /// True while bytes are moving or about to (menu ring, Settings inline progress).
    public var isActive: Bool {
        switch phase {
        case .waitingForNetwork, .waitingForUnmetered, .downloading, .paused, .verifyingChecksum, .selfTesting:
            true
        case .idle, .confirmingMetered, .ready, .failed:
            false
        }
    }

    public var receivedBytes: Int64 {
        switch phase {
        case .downloading(_, let bytes), .paused(_, let bytes), .waitingForNetwork(_, let bytes): bytes
        default: 0
        }
    }

    @discardableResult
    public mutating func handle(_ event: Event) -> [Effect] {
        switch (phase, event) {
        case (_, .reset):
            phase = .idle
            checksumFailures = 0
            meteredApproved = false
            resumeOffset = 0
            return []

        case (_, .requestDownload(let tier, let network, let freeBytes, let partialBytes)):
            if tier != self.tier { checksumFailures = 0 }
            meteredApproved = false
            let entry = OfflineModelManifest.entry(for: tier)
            let needed = entry.requiredFreeBytes - partialBytes
            if freeBytes < needed {
                phase = .failed(tier, .lowDisk(shortBytes: needed - freeBytes))
                return []
            }
            return begin(tier, network: network, fromByte: partialBytes)

        case (.confirmingMetered(let tier), .meteredChoice(let downloadAnyway)):
            if downloadAnyway {
                meteredApproved = true
                phase = .downloading(tier, receivedBytes: resumeOffset)
                return [.startTransfer(tier, fromByte: resumeOffset)]
            }
            phase = .waitingForUnmetered(tier)
            return []

        case (.waitingForNetwork(let tier, let bytes), .networkChanged(let network)):
            return begin(tier, network: network, fromByte: bytes)

        case (.waitingForUnmetered(let tier), .networkChanged(.unmetered)):
            phase = .downloading(tier, receivedBytes: resumeOffset)
            return [.startTransfer(tier, fromByte: resumeOffset)]

        case (.downloading(let tier, let bytes), .networkChanged(.offline)):
            phase = .waitingForNetwork(tier, receivedBytes: bytes)
            return [.stopTransfer]

        case (.downloading(let tier, let bytes), .networkChanged(.metered)) where !meteredApproved:
            // Moved onto a hotspot mid-download: stop and ask again.
            resumeOffset = bytes
            phase = .confirmingMetered(tier)
            return [.stopTransfer]

        case (.downloading(let tier, _), .progress(let received)):
            phase = .downloading(tier, receivedBytes: received)
            resumeOffset = received
            return []

        case (.downloading(let tier, let bytes), .pause):
            phase = .paused(tier, receivedBytes: bytes)
            return [.stopTransfer]

        case (.paused(let tier, let bytes), .resume(let network)):
            return begin(tier, network: network, fromByte: bytes)

        case (.downloading(let tier, _), .transferFailedNetwork(let bytes)):
            phase = .waitingForNetwork(tier, receivedBytes: bytes)
            return []

        case (.downloading(let tier, _), .transferFailedHTTP(let status)):
            if [401, 403, 404, 410].contains(status) {
                phase = .failed(tier, .unavailable)
                return [.deletePartial(tier)]
            }
            phase = .waitingForNetwork(tier, receivedBytes: receivedBytes)
            return []

        case (.downloading(let tier, _), .transferFailedDiskFull(let short)),
             (.verifyingChecksum(let tier), .transferFailedDiskFull(let short)):
            // Keep the partial: "Needs X more space to finish."
            phase = .failed(tier, .lowDisk(shortBytes: short))
            return [.stopTransfer]

        case (.downloading(let tier, _), .transferFinished(let total)):
            let entry = OfflineModelManifest.entry(for: tier)
            guard total == entry.byteSize else {
                // Wrong size can never match the pinned SHA-256.
                checksumFailures += 1
                phase = .failed(tier, .checksumMismatch(attempt: checksumFailures))
                return [.deletePartial(tier)]
            }
            phase = .verifyingChecksum(tier)
            return [.verifyChecksum(tier)]

        case (.verifyingChecksum(let tier), .checksumResult(let matches)):
            guard matches else {
                checksumFailures += 1
                phase = .failed(tier, .checksumMismatch(attempt: checksumFailures))
                // "The download was damaged. Intake deleted it." Never loaded.
                return [.deletePartial(tier)]
            }
            phase = .selfTesting(tier)
            return [.runSelfTest(tier)]

        case (.selfTesting(let tier), .selfTestResult(let passed)):
            if passed {
                phase = .ready(tier)
                checksumFailures = 0
                return [.install(tier)]
            }
            phase = .failed(tier, .selfTestFailed)
            return [.deleteModel(tier)]

        case (.selfTesting(let tier), .loadFailed):
            phase = .failed(tier, .loadFailed)
            return [.deleteModel(tier)]

        case (_, .cancel):
            guard let tier, isActive || phase == .confirmingMetered(tier) || isLowDiskFailure else { return [] }
            phase = .idle
            meteredApproved = false
            return [.stopTransfer, .retainPartial(tier)]

        case (.idle, .restore(let tier, let bytes, let wasPaused, let network)),
             (.failed, .restore(let tier, let bytes, let wasPaused, let network)):
            if wasPaused {
                phase = .paused(tier, receivedBytes: bytes)
                return []
            }
            // "After quit, it resumes on next launch" — but ask again on a metered network.
            return begin(tier, network: network, fromByte: bytes)

        default:
            return []
        }
    }

    private var isLowDiskFailure: Bool {
        if case .failed(_, .lowDisk) = phase { return true }
        return false
    }

    private mutating func begin(_ tier: OfflineModelTier, network: OfflineNetworkStatus, fromByte: Int64) -> [Effect] {
        resumeOffset = fromByte
        switch network {
        case .offline:
            phase = .waitingForNetwork(tier, receivedBytes: fromByte)
            return []
        case .metered where !meteredApproved:
            phase = .confirmingMetered(tier)
            return []
        case .metered, .unmetered:
            phase = .downloading(tier, receivedBytes: fromByte)
            return [.startTransfer(tier, fromByte: fromByte)]
        }
    }
}

/// A cancelled download's partial file, kept 24 h so Settings can resume it
/// (SPEC v1.3.1 ruling 6).
public struct RetainedPartialDownload: Equatable, Codable, Sendable {
    public static let retention: TimeInterval = 24 * 60 * 60

    public var tier: OfflineModelTier
    public var cancelledAt: Date

    public init(tier: OfflineModelTier, cancelledAt: Date) {
        self.tier = tier
        self.cancelledAt = cancelledAt
    }

    public func isExpired(now: Date) -> Bool {
        now.timeIntervalSince(cancelledAt) >= Self.retention
    }

    /// Splits records into still-resumable and expired (delete their files).
    public static func partition(
        _ records: [RetainedPartialDownload],
        now: Date
    ) -> (kept: [RetainedPartialDownload], expired: [RetainedPartialDownload]) {
        (records.filter { !$0.isExpired(now: now) }, records.filter { $0.isExpired(now: now) })
    }
}

/// Where model files live: `<Application Support>/Intake/Models/`, with
/// in-progress files under `.partial/`. Never iCloud or Downloads.
public struct OfflineModelStorage: Sendable {
    public var root: URL

    public init(root: URL) {
        self.root = root
    }

    /// `<container>/Library/Application Support/Intake/Models`.
    public static func defaultRoot(fileManager: FileManager = .default) -> URL {
        let support = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return support.appendingPathComponent("Intake/Models", isDirectory: true)
    }

    public var partialDirectory: URL {
        root.appendingPathComponent(".partial", isDirectory: true)
    }

    public func modelURL(for entry: OfflineModelManifestEntry) -> URL {
        root.appendingPathComponent(entry.fileName, isDirectory: false)
    }

    public func partialURL(for entry: OfflineModelManifestEntry) -> URL {
        partialDirectory.appendingPathComponent(entry.fileName + ".part", isDirectory: false)
    }

    public func modelURL(for tier: OfflineModelTier) -> URL {
        modelURL(for: OfflineModelManifest.entry(for: tier))
    }

    public func partialURL(for tier: OfflineModelTier) -> URL {
        partialURL(for: OfflineModelManifest.entry(for: tier))
    }

    public func prepareDirectories(fileManager: FileManager = .default) throws {
        try fileManager.createDirectory(at: partialDirectory, withIntermediateDirectories: true)
    }

    public func partialBytes(for entry: OfflineModelManifestEntry, fileManager: FileManager = .default) -> Int64 {
        Self.size(of: partialURL(for: entry), fileManager: fileManager)
    }

    public func isInstalled(_ entry: OfflineModelManifestEntry, fileManager: FileManager = .default) -> Bool {
        Self.size(of: modelURL(for: entry), fileManager: fileManager) == entry.byteSize
    }

    /// Verified file → final location, replacing any older copy atomically.
    public func installPartial(for entry: OfflineModelManifestEntry, fileManager: FileManager = .default) throws -> URL {
        let source = partialURL(for: entry)
        let destination = modelURL(for: entry)
        if fileManager.fileExists(atPath: destination.path) {
            _ = try fileManager.replaceItemAt(destination, withItemAt: source)
        } else {
            try fileManager.moveItem(at: source, to: destination)
        }
        return destination
    }

    public func deletePartial(for entry: OfflineModelManifestEntry, fileManager: FileManager = .default) {
        try? fileManager.removeItem(at: partialURL(for: entry))
    }

    /// Delete Model: removes the model and any partial, so the space shown is freed.
    public func deleteModel(for entry: OfflineModelManifestEntry, fileManager: FileManager = .default) {
        try? fileManager.removeItem(at: modelURL(for: entry))
        deletePartial(for: entry, fileManager: fileManager)
    }

    /// Partials not belonging to `keep` (stale tiers, old manifests).
    public func strayPartials(keeping keep: Set<String>, fileManager: FileManager = .default) -> [URL] {
        let names = (try? fileManager.contentsOfDirectory(atPath: partialDirectory.path)) ?? []
        return names
            .filter { !keep.contains($0) }
            .map { partialDirectory.appendingPathComponent($0, isDirectory: false) }
    }

    static func size(of url: URL, fileManager: FileManager) -> Int64 {
        guard let attributes = try? fileManager.attributesOfItem(atPath: url.path),
              let size = attributes[.size] as? NSNumber
        else { return 0 }
        return size.int64Value
    }
}

/// Streaming SHA-256 so a multi-GB file never sits in memory (SPEC §7).
public enum OfflineModelFileVerifier {
    public static let chunkSize = 4 * 1024 * 1024

    public static func sha256Hex(of url: URL, chunkSize: Int = OfflineModelFileVerifier.chunkSize) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        var hasher = SHA256()
        while true {
            let chunk: Data
            do {
                guard let data = try handle.read(upToCount: chunkSize), !data.isEmpty else { break }
                chunk = data
            } catch {
                return nil
            }
            hasher.update(data: chunk)
            if Task.isCancelled { return nil }
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    /// Size and SHA-256 must both match the manifest. A mismatch is never loaded.
    public static func verify(_ url: URL, against entry: OfflineModelManifestEntry, fileManager: FileManager = .default) -> Bool {
        guard OfflineModelStorage.size(of: url, fileManager: fileManager) == entry.byteSize else { return false }
        return sha256Hex(of: url) == entry.sha256.lowercased()
    }
}
