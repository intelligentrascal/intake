import Foundation

/// The three offline model sizes, smallest first. User-facing names are
/// Lite / Standard / Best (SPEC §4). The model behind each tier lives only in
/// `OfflineModelManifest` so a tier can be re-pointed (e.g. Best → Gemma 4 E2B)
/// without touching UI copy.
public enum OfflineModelTier: String, CaseIterable, Codable, Sendable, Identifiable, Comparable {
    case lite
    case standard
    case best

    public var id: String { rawValue }

    private var rank: Int {
        switch self {
        case .lite: 0
        case .standard: 1
        case .best: 2
        }
    }

    public static func < (lhs: OfflineModelTier, rhs: OfflineModelTier) -> Bool {
        lhs.rank < rhs.rank
    }

    /// The next tier down, offered when this one fails its self-test.
    public var nextSmaller: OfflineModelTier? {
        switch self {
        case .lite: nil
        case .standard: .lite
        case .best: .standard
        }
    }
}

public enum MacArchitecture: String, Codable, Sendable, Equatable {
    case appleSilicon
    case intel
}

/// How Intake hand-builds each model's prompt (SPEC §10.1). The xcframework
/// has no Jinja engine, so these mirror each model's HF chat template with
/// thinking disabled.
public enum OfflineModelPromptFormat: String, Codable, Sendable, Equatable {
    /// Qwen3.5: ChatML, contents trimmed, assistant turn pre-filled with an
    /// empty think block (`enable_thinking` false/unset). Never `/no_think`.
    case qwen35NonThinking
    /// Qwen3-Instruct-2507: non-thinking only. Plain ChatML, assistant turn opened.
    case qwen3Instruct
    /// Gemma 4 (challenger): turn format without `<|think|>`.
    case gemma4
}

/// One downloadable model file, pinned to an exact revision and checksum.
/// Everything a tier shows (name, sizes, caption) comes from here.
public struct OfflineModelManifestEntry: Equatable, Codable, Sendable, Identifiable {
    public var tier: OfflineModelTier
    /// Shown only in Settings › "About this model".
    public var modelName: String
    public var repository: String
    /// Full 40-character commit of the GGUF repo.
    public var revision: String
    public var fileName: String
    public var byteSize: Int64
    /// Lower-case hex SHA-256 of the file (HF `lfs.sha256`).
    public var sha256: String
    public var license: String
    public var licenseURL: URL
    public var minimumMemoryGB: Int
    public var architectures: Set<MacArchitecture>
    public var promptFormat: OfflineModelPromptFormat
    /// Display copy, kept with the bytes it describes.
    public var sizeLabel: String
    /// Free space needed (download + 2 GB), rounded for display.
    public var needLabel: String
    public var caption: String
    /// Whether the tier line says "download" after the size (SPEC v1.3.1 ruling 4).
    public var sizeSaysDownload: Bool

    public var id: OfflineModelTier { tier }

    public init(
        tier: OfflineModelTier,
        modelName: String,
        repository: String,
        revision: String,
        fileName: String,
        byteSize: Int64,
        sha256: String,
        license: String = "Apache 2.0",
        licenseURL: URL,
        minimumMemoryGB: Int,
        architectures: Set<MacArchitecture>,
        promptFormat: OfflineModelPromptFormat,
        sizeLabel: String,
        needLabel: String,
        caption: String,
        sizeSaysDownload: Bool
    ) {
        self.tier = tier
        self.modelName = modelName
        self.repository = repository
        self.revision = revision
        self.fileName = fileName
        self.byteSize = byteSize
        self.sha256 = sha256
        self.license = license
        self.licenseURL = licenseURL
        self.minimumMemoryGB = minimumMemoryGB
        self.architectures = architectures
        self.promptFormat = promptFormat
        self.sizeLabel = sizeLabel
        self.needLabel = needLabel
        self.caption = caption
        self.sizeSaysDownload = sizeSaysDownload
    }

    /// `huggingface.co/<repo>/resolve/<commit>/<file>`: no token, Range-capable.
    public var downloadURL: URL {
        URL(string: "https://huggingface.co/\(repository)/resolve/\(revision)/\(fileName)")!
    }

    /// Disk rule (SPEC §6): free space ≥ download + 2 GB.
    public var requiredFreeBytes: Int64 {
        byteSize + OfflineModelManifest.diskHeadroomBytes
    }

    public func runs(on architecture: MacArchitecture) -> Bool {
        architectures.contains(architecture)
    }
}

/// A tier's name and one-line description, e.g. **Best** — 2.5 GB download · most accurate.
public struct OfflineTierLine: Equatable, Sendable {
    /// Bold part: "Best", "Lite (CPU)".
    public var name: String
    /// "2.5 GB download · most accurate".
    public var detail: String

    public var text: String { "\(name) — \(detail)" }
}

/// The manifest for this app version (SPEC §4, §7). Byte sizes, revisions and
/// SHA-256 come from the HF API (2026-10-11).
public enum OfflineModelManifest {
    public static let manifestVersion = "1.4.0"
    /// Extra free space required beyond the download itself (decimal GB).
    public static let diskHeadroomBytes: Int64 = 2_000_000_000

    public static let lite = OfflineModelManifestEntry(
        tier: .lite,
        modelName: "Qwen3.5-0.8B",
        repository: "unsloth/Qwen3.5-0.8B-GGUF",
        revision: "6ab461498e2023f6e3c1baea90a8f0fe38ab64d0",
        fileName: "Qwen3.5-0.8B-Q4_K_M.gguf",
        byteSize: 532_517_120,
        sha256: "bd258782e35f7f458f8aced1adc053e6e92e89bc735ba3be89d38a06121dc517",
        licenseURL: URL(string: "https://huggingface.co/Qwen/Qwen3.5-0.8B/blob/main/LICENSE")!,
        minimumMemoryGB: 8,
        architectures: [.appleSilicon, .intel],
        promptFormat: .qwen35NonThinking,
        sizeLabel: "533 MB",
        needLabel: "2.5 GB",
        caption: "smallest, fine for simple documents",
        sizeSaysDownload: false
    )

    public static let standard = OfflineModelManifestEntry(
        tier: .standard,
        modelName: "Qwen3.5-2B",
        repository: "unsloth/Qwen3.5-2B-GGUF",
        revision: "f6d5376be1edb4d416d56da11e5397a961aca8ae",
        fileName: "Qwen3.5-2B-Q4_K_M.gguf",
        byteSize: 1_280_835_840,
        sha256: "aaf42c8b7c3cab2bf3d69c355048d4a0ee9973d48f16c731c0520ee914699223",
        licenseURL: URL(string: "https://huggingface.co/Qwen/Qwen3.5-2B/blob/main/LICENSE")!,
        minimumMemoryGB: 8,
        architectures: [.appleSilicon],
        promptFormat: .qwen35NonThinking,
        sizeLabel: "1.28 GB",
        needLabel: "3.3 GB",
        caption: "accurate for everyday files",
        sizeSaysDownload: true
    )

    public static let best = OfflineModelManifestEntry(
        tier: .best,
        modelName: "Qwen3-4B-Instruct-2507",
        repository: "unsloth/Qwen3-4B-Instruct-2507-GGUF",
        revision: "a06e946bb6b655725eafa393f4a9745d460374c9",
        fileName: "Qwen3-4B-Instruct-2507-Q4_K_M.gguf",
        byteSize: 2_497_281_120,
        sha256: "3605803b982cb64aead44f6c1b2ae36e3acdb41d8e46c8a94c6533bc4c67e597",
        licenseURL: URL(string: "https://huggingface.co/Qwen/Qwen3-4B-Instruct-2507/blob/main/LICENSE")!,
        minimumMemoryGB: 16,
        architectures: [.appleSilicon],
        promptFormat: .qwen3Instruct,
        sizeLabel: "2.5 GB",
        needLabel: "4.5 GB",
        caption: "most accurate",
        sizeSaysDownload: true
    )

    /// Eval-only challenger for Best (SPEC §4, §10). Ships only if it wins the
    /// §10 eval: then it replaces `best` here and nothing else changes.
    public static let bestChallenger = OfflineModelManifestEntry(
        tier: .best,
        modelName: "Gemma 4 E2B",
        repository: "unsloth/gemma-4-E2B-it-GGUF",
        revision: "0314792d7f1f7e229411f620751375812bb9faf2",
        fileName: "gemma-4-E2B-it-Q4_K_M.gguf",
        byteSize: 3_106_738_272,
        sha256: "740185b21d22ceb83a11c3aa62ad5842ef32c70f6096d756bbee85a1e4ec34b8",
        licenseURL: URL(string: "https://huggingface.co/google/gemma-4-E2B-it")!,
        minimumMemoryGB: 16,
        architectures: [.appleSilicon],
        promptFormat: .gemma4,
        sizeLabel: "3.1 GB",
        needLabel: "5.1 GB",
        caption: "most accurate",
        sizeSaysDownload: true
    )

    /// Shipping entries, smallest first.
    public static let entries: [OfflineModelManifestEntry] = [lite, standard, best]

    public static func entry(for tier: OfflineModelTier) -> OfflineModelManifestEntry {
        switch tier {
        case .lite: lite
        case .standard: standard
        case .best: best
        }
    }

    /// Tier line copy. On Intel, Lite is presented as "Lite (CPU)".
    public static func line(
        for tier: OfflineModelTier,
        on architecture: MacArchitecture = .appleSilicon
    ) -> OfflineTierLine {
        let entry = entry(for: tier)
        if tier == .lite, architecture == .intel {
            return OfflineTierLine(name: "Lite (CPU)", detail: "\(entry.sizeLabel) · renames when plugged in")
        }
        let size = entry.sizeSaysDownload ? "\(entry.sizeLabel) download" : entry.sizeLabel
        return OfflineTierLine(name: displayName(for: tier, on: architecture), detail: "\(size) · \(entry.caption)")
    }

    public static func displayName(for tier: OfflineModelTier, on architecture: MacArchitecture = .appleSilicon) -> String {
        switch tier {
        case .lite: architecture == .intel ? "Lite (CPU)" : "Lite"
        case .standard: "Standard"
        case .best: "Best"
        }
    }

    public static let licenseLine = "Model license: Apache 2.0"
}
