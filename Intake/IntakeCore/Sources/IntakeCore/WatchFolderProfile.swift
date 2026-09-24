import Foundation

/// One folder Intake watches, with its own live-ingest settings. Profiles are
/// persisted as an ordered list; the first one is usually `~/Downloads`.
public struct WatchFolderProfile: Identifiable, Equatable, Sendable, Codable, Hashable {
    /// Stable id of the profile migrated from the single 1.2 watch folder.
    /// Activity rows written before multiple watch folders count as this one.
    public static let primaryID = "primary"
    /// v1 limit, to keep watcher and resource cost bounded.
    public static let softCap = 5

    public var id: String
    public var displayName: String
    /// Last known absolute path. Used for display, validation, and as the
    /// folder when no bookmark exists (the default Downloads folder).
    public var path: String
    /// Security-scoped bookmark from the folder picker. `nil` for the
    /// default Downloads folder the user never had to pick.
    public var bookmark: Data?
    public var renameWhenDownloadFinishes: Bool
    public var organizingWait: OrganizingWait
    /// Per-folder setting: file into category folders after Wait.
    public var automaticOrganizing: Bool
    /// Pause / Resume for this folder only. Paused behaves like Automatic
    /// organizing off (rename can still run) without changing the setting.
    public var isPaused: Bool

    public init(
        id: String = "folder-\(UUID().uuidString)",
        displayName: String? = nil,
        path: String,
        bookmark: Data? = nil,
        renameWhenDownloadFinishes: Bool = true,
        organizingWait: OrganizingWait = .default,
        automaticOrganizing: Bool = true,
        isPaused: Bool = false
    ) {
        self.id = id
        self.path = URL(fileURLWithPath: path).standardizedFileURL.path
        self.displayName = displayName ?? URL(fileURLWithPath: path).lastPathComponent
        self.bookmark = bookmark
        self.renameWhenDownloadFinishes = renameWhenDownloadFinishes
        self.organizingWait = organizingWait
        self.automaticOrganizing = automaticOrganizing
        self.isPaused = isPaused
    }

    public var url: URL {
        URL(fileURLWithPath: path, isDirectory: true)
    }

    /// Files are routed after Wait only when the setting is on and the folder
    /// isn't paused.
    public var isOrganizing: Bool {
        automaticOrganizing && !isPaused
    }

    public var liveIngestPolicy: LiveIngestPolicy {
        LiveIngestPolicy(
            renameWhenDownloadFinishes: renameWhenDownloadFinishes,
            automaticOrganizing: isOrganizing
        )
    }

    private enum CodingKeys: String, CodingKey {
        case id, displayName, path, bookmark, renameWhenDownloadFinishes
        case organizingWait, automaticOrganizing, isPaused
    }

    /// Missing settings fall back to the product defaults so a partially
    /// written or future profile still loads.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        path = try container.decode(String.self, forKey: .path)
        displayName = try container.decodeIfPresent(String.self, forKey: .displayName)
            ?? URL(fileURLWithPath: path).lastPathComponent
        bookmark = try container.decodeIfPresent(Data.self, forKey: .bookmark)
        renameWhenDownloadFinishes = try container.decodeIfPresent(
            Bool.self,
            forKey: .renameWhenDownloadFinishes
        ) ?? true
        organizingWait = OrganizingWait(
            storedSeconds: try container.decodeIfPresent(Int.self, forKey: .organizingWait)
        )
        automaticOrganizing = try container.decodeIfPresent(Bool.self, forKey: .automaticOrganizing) ?? true
        isPaused = try container.decodeIfPresent(Bool.self, forKey: .isPaused) ?? false
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(displayName, forKey: .displayName)
        try container.encode(path, forKey: .path)
        try container.encodeIfPresent(bookmark, forKey: .bookmark)
        try container.encode(renameWhenDownloadFinishes, forKey: .renameWhenDownloadFinishes)
        try container.encode(organizingWait.rawValue, forKey: .organizingWait)
        try container.encode(automaticOrganizing, forKey: .automaticOrganizing)
        try container.encode(isPaused, forKey: .isPaused)
    }
}

/// Persists the ordered watch folder list, migrating the single 1.2 watch
/// folder (bookmark + global settings + Wait queue) into profile #1.
public enum WatchFolderProfileStore: Sendable {
    public static let defaultsKey = "intake.watchFolderProfiles"
    /// The 1.2 single-folder bookmark key. Left in place after migration.
    public static let legacyBookmarkKey = "intake.watchFolderBookmark"

    public static func encode(_ profiles: [WatchFolderProfile]) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(profiles)
    }

    public static func decode(_ data: Data) throws -> [WatchFolderProfile] {
        try JSONDecoder().decode([WatchFolderProfile].self, from: data)
    }

    public static func save(_ profiles: [WatchFolderProfile], to defaults: UserDefaults) {
        if let data = try? encode(profiles) {
            defaults.set(data, forKey: defaultsKey)
        }
    }

    /// Profile #1 built from the 1.2 single-folder settings, so upgrading
    /// changes nothing: same folder, bookmark, Rename, Wait and Automatic
    /// organizing.
    public static func legacyProfile(from defaults: UserDefaults, folder: URL) -> WatchFolderProfile {
        WatchFolderProfile(
            id: WatchFolderProfile.primaryID,
            displayName: folder.lastPathComponent,
            path: folder.path,
            bookmark: defaults.data(forKey: legacyBookmarkKey),
            renameWhenDownloadFinishes: RenameWhenDownloadFinishesPreference.isEnabled(in: defaults),
            organizingWait: OrganizingWait.load(from: defaults),
            automaticOrganizing: AutomaticOrganizingPreference.isEnabled(in: defaults),
            isPaused: false
        )
    }

    /// Stored profiles when present; otherwise migrates the single 1.2 watch
    /// folder into profile #1 (including its Wait queue) and saves the result.
    /// Never returns an empty list. `legacyFolder` resolves the 1.2 folder
    /// (bookmark or Downloads) and is only called when migrating.
    public static func load(
        from defaults: UserDefaults,
        legacyFolder: () -> URL
    ) -> [WatchFolderProfile] {
        if let data = defaults.data(forKey: defaultsKey),
           let decoded = try? decode(data),
           !decoded.isEmpty {
            return decoded
        }
        let migrated = [legacyProfile(from: defaults, folder: legacyFolder())]
        WaitingForAgeStore.migrateLegacyQueue(to: WatchFolderProfile.primaryID, in: defaults)
        save(migrated, to: defaults)
        return migrated
    }
}
