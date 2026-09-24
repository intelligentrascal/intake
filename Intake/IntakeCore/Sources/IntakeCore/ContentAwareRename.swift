import Foundation

/// File types content-aware rename can read. Text extraction only covers
/// PDFs (text layer, then on-device recognition) and images (recognition).
public enum ContentAwareFileType: String, CaseIterable, Codable, Sendable, Identifiable {
    case pdf
    case images

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .pdf: "PDFs"
        case .images: "Images"
        }
    }

    public var extensions: Set<String> {
        switch self {
        case .pdf: ["pdf"]
        // No SVG / GIF: nothing useful to recognize.
        case .images: ["png", "jpg", "jpeg", "heic", "heif", "tiff", "tif", "webp"]
        }
    }
}

/// Settings for on-device content-aware rename. Off by default.
public struct ContentAwareRenameSettings: Equatable, Codable, Sendable {
    public static let defaultsKey = "intake.contentAwareRename"
    /// How long filing waits for a content name before using the Title Case one.
    public static let filingTimeout: TimeInterval = 30
    /// Files bigger than this are never read.
    public static let maximumFileSize: Int64 = 50 * 1024 * 1024

    public var isEnabled: Bool
    public var fileTypes: Set<ContentAwareFileType>
    public var template: String

    public init(
        isEnabled: Bool = false,
        fileTypes: Set<ContentAwareFileType> = [.pdf, .images],
        template: String = ContentNameTemplate.defaultTemplate
    ) {
        self.isEnabled = isEnabled
        self.fileTypes = fileTypes
        self.template = template
    }

    public var nameTemplate: ContentNameTemplate {
        ContentNameTemplate(template: template)
    }

    /// True when the feature is on and `url`'s type is selected (size not checked).
    public func isEligible(_ url: URL) -> Bool {
        guard isEnabled else { return false }
        let ext = url.pathExtension.lowercased()
        return fileTypes.contains { $0.extensions.contains(ext) }
    }

    private enum CodingKeys: String, CodingKey {
        case isEnabled, fileTypes, template
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? false
        let rawTypes = try container.decodeIfPresent([String].self, forKey: .fileTypes)
        fileTypes = rawTypes.map { Set($0.compactMap(ContentAwareFileType.init(rawValue:))) }
            ?? [.pdf, .images]
        template = try container.decodeIfPresent(String.self, forKey: .template)
            ?? ContentNameTemplate.defaultTemplate
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(isEnabled, forKey: .isEnabled)
        try container.encode(fileTypes.map(\.rawValue).sorted(), forKey: .fileTypes)
        try container.encode(template, forKey: .template)
    }

    public static func load(from defaults: UserDefaults) -> ContentAwareRenameSettings {
        guard let data = defaults.data(forKey: defaultsKey),
              let decoded = try? JSONDecoder().decode(ContentAwareRenameSettings.self, from: data)
        else {
            return ContentAwareRenameSettings()
        }
        return decoded
    }

    public func save(to defaults: UserDefaults) {
        if let data = try? JSONEncoder().encode(self) {
            defaults.set(data, forKey: Self.defaultsKey)
        }
    }
}

/// Why a file kept its Title Case name instead of a content-aware one.
public enum ContentNameFallback: Equatable, Sendable {
    /// Feature off or type not selected.
    case notEligible
    /// Over the 50 MB cap.
    case tooLarge
    /// Missing or empty (still-writing) file.
    case unreadable
    /// No text could be extracted (encrypted PDF, blank image, …).
    case noText
    case rejected(ContentNameRejection)
}

public enum ContentNameProposal: Equatable, Sendable {
    /// Validated file name (extension kept) for the file as it's named now.
    case proposed(String)
    case fallback(ContentNameFallback)

    public var fileName: String? {
        if case .proposed(let name) = self { return name }
        return nil
    }
}

/// Extract → name → validate. Pure apart from reading the file; never
/// renames anything and never leaves the Mac (the extractor and namer are
/// on-device implementations in the app).
public struct ContentAwareRenamer: Sendable {
    public var settings: ContentAwareRenameSettings
    public var extractor: any ContentTextExtractor
    public var namer: any ContentNamer

    public init(
        settings: ContentAwareRenameSettings,
        extractor: any ContentTextExtractor,
        namer: any ContentNamer
    ) {
        self.settings = settings
        self.extractor = extractor
        self.namer = namer
    }

    public func isEligible(_ url: URL, fileManager: FileManager = .default) -> Bool {
        guard settings.isEligible(url) else { return false }
        let size = DownloadWriteGate.fileSize(at: url, fileManager: fileManager)
        return DownloadWriteGate.allowsOrganizeOrRename(size: size)
            && size <= ContentAwareRenameSettings.maximumFileSize
    }

    /// `currentFileName` overrides the name used for `{original}` and the
    /// extension — the preview passes the Title Case name the file will have.
    public func proposal(
        for url: URL,
        currentFileName: String? = nil,
        fileManager: FileManager = .default
    ) async -> ContentNameProposal {
        guard settings.isEligible(url) else { return .fallback(.notEligible) }
        guard fileManager.fileExists(atPath: url.path) else { return .fallback(.unreadable) }
        let size = DownloadWriteGate.fileSize(at: url, fileManager: fileManager)
        guard DownloadWriteGate.allowsOrganizeOrRename(size: size) else {
            return .fallback(.unreadable)
        }
        guard size <= ContentAwareRenameSettings.maximumFileSize else {
            return .fallback(.tooLarge)
        }
        let raw = await extractor.text(
            from: url,
            maximumCharacters: ContentNamingInput.maximumTextCharacters
        )
        let text = (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return .fallback(.noText) }

        let facts = FileFacts.onDisk(at: url, fileManager: fileManager)
        let fields = await namer.fields(for: ContentNamingInput(facts: facts, text: text))
        switch settings.nameTemplate.outcome(
            for: fields,
            currentFileName: currentFileName ?? url.lastPathComponent
        ) {
        case .accepted(let name):
            return .proposed(name)
        case .rejected(let reason):
            return .fallback(.rejected(reason))
        }
    }
}

extension IngestPipeline {
    /// Renames a file to its content-aware name **where it is now**: the
    /// watch-folder root, or the category (and date sub-) folder it was
    /// already filed into. Same collision rules as the Title Case rename
    /// (case-insensitive, only a different file forces a suffix) and the
    /// same write gate. The row is `renamed` with source `contentAware`.
    public func applyContentRename(
        at fileURL: URL,
        to proposedFileName: String,
        fileManager: FileManager = .default,
        now: Date = Date()
    ) throws -> (url: URL, entries: [ActivityEntry]) {
        let requested = fileURL.standardizedFileURL
        guard isInsideWatchFolder(requested) else { return (requested, []) }
        guard fileManager.fileExists(atPath: requested.path) else { return (requested, []) }
        let source = FileIdentity.onDiskURL(for: requested, fileManager: fileManager)
        guard DownloadWriteGate.allowsOrganizeOrRename(at: source, fileManager: fileManager) else {
            return (source, [])
        }

        // Keep the file's real extension no matter what the proposal says.
        let ext = source.pathExtension
        let proposedBase = URL(fileURLWithPath: proposedFileName).deletingPathExtension().lastPathComponent
        let safeBase = ContentNameTemplate.sanitize(proposedBase)
        guard !safeBase.isEmpty else { return (source, []) }
        let proposed = ext.isEmpty ? safeBase : "\(safeBase).\(ext)"
        if proposed == source.lastPathComponent {
            return (source, [])
        }

        let directory = source.deletingLastPathComponent()
        var existing = existingNames(in: directory, fileManager: fileManager)
        existing.remove(source.lastPathComponent)
        let uniqueName = Self.uniqued(fileName: proposed, among: existing)
        let destination = directory.appendingPathComponent(uniqueName, isDirectory: false)
        if destination.standardizedFileURL == source.standardizedFileURL {
            return (source, [])
        }

        try fileManager.moveItem(at: source, to: destination)
        let isFiled = directory.standardizedFileURL != watchFolder.standardizedFileURL
        return (
            destination,
            [
                ActivityEntry(
                    date: now,
                    kind: .renamed,
                    detail: "Renamed \(source.lastPathComponent) to \(uniqueName) from its contents",
                    url: destination,
                    fileName: uniqueName,
                    destinationFolder: isFiled ? filedFolderName(for: directory) : nil,
                    beforePath: source.path,
                    afterPath: destination.path,
                    renameSource: .contentAware
                ),
            ]
        )
    }

    private func isInsideWatchFolder(_ url: URL) -> Bool {
        let root = watchFolder.standardizedFileURL.path
        let prefix = root.hasSuffix("/") ? root : root + "/"
        return url.standardizedFileURL.path.hasPrefix(prefix)
    }

    /// The top-level category folder a filed file sits in.
    private func filedFolderName(for directory: URL) -> String? {
        let root = watchFolder.standardizedFileURL.pathComponents
        let parts = directory.standardizedFileURL.pathComponents
        guard parts.count > root.count else { return nil }
        return parts[root.count]
    }
}

/// Tracks background content-aware jobs for one watch folder so filing can
/// wait for the richer name — up to `timeout` — and a late result can find
/// the file wherever it was filed. Pure: the caller passes `now`.
public struct ContentRenameTracker: Equatable, Sendable {
    public struct Job: Equatable, Sendable {
        public var startedAt: Date
        /// Where the file is now (updated when it's filed or renamed).
        public var currentURL: URL
    }

    public var timeout: TimeInterval
    public private(set) var jobs: [UUID: Job] = [:]

    public init(timeout: TimeInterval = ContentAwareRenameSettings.filingTimeout) {
        self.timeout = timeout
    }

    public var isEmpty: Bool { jobs.isEmpty }

    @discardableResult
    public mutating func begin(for url: URL, at now: Date) -> UUID {
        let standardized = url.standardizedFileURL
        jobs = jobs.filter { $0.value.currentURL != standardized }
        let id = UUID()
        jobs[id] = Job(startedAt: now, currentURL: standardized)
        return id
    }

    public func jobID(for url: URL) -> UUID? {
        let standardized = url.standardizedFileURL
        return jobs.first { $0.value.currentURL == standardized }?.key
    }

    /// True while a job for `url` is running and younger than `timeout`.
    public func shouldHoldFiling(_ url: URL, now: Date) -> Bool {
        guard let id = jobID(for: url), let job = jobs[id] else { return false }
        return now.timeIntervalSince(job.startedAt) < timeout
    }

    /// Seconds until the earliest held file times out, or nil when none is held.
    public func nextRelease(now: Date) -> TimeInterval? {
        jobs.values
            .map { job in timeout - now.timeIntervalSince(job.startedAt) }
            .filter { $0 > 0 }
            .min()
    }

    /// The file moved (filed, or renamed by someone else) — follow it.
    public mutating func noteMoved(from old: URL, to new: URL) {
        guard let id = jobID(for: old) else { return }
        jobs[id]?.currentURL = new.standardizedFileURL
    }

    /// Ends a job and returns where its file is now.
    public mutating func finish(_ id: UUID) -> URL? {
        jobs.removeValue(forKey: id)?.currentURL
    }

    public mutating func cancelAll() {
        jobs.removeAll()
    }
}

extension ContentNameFallback {
    /// Plain-language reason for "Try on a file…".
    public var reasonText: String {
        switch self {
        case .notEligible: "This file type isn’t selected for content-aware rename."
        case .tooLarge: "The file is larger than 50 MB, so Intake doesn’t read it."
        case .unreadable: "The file is empty or missing."
        case .noText: "No readable text was found (encrypted PDFs are skipped)."
        case .rejected(.noResult): "The on-device model didn’t return a name."
        case .rejected(.lowConfidence): "The on-device model wasn’t confident enough."
        case .rejected(.empty): "The template came out empty for this file."
        case .rejected(.generic): "The result was too generic to be useful."
        }
    }
}
