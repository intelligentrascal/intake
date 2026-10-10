import Foundation

/// One file waiting for an offline content name. Stores paths and identity
/// only, never extracted text (SPEC §12).
public struct QueuedOfflineRename: Equatable, Codable, Sendable, Identifiable {
    public var id: UUID
    /// Where the file is now (updated when Intake files it).
    public var path: String
    /// The file's name when it was queued (its Title Case name).
    public var queuedFileName: String
    /// Volume file number at queue time, so a different file at the same
    /// path is never renamed. `nil` when it couldn't be read.
    public var fileIdentifier: UInt64?
    public var watchFolderID: String?
    public var enqueuedAt: Date
    public var reason: OfflineWaitReason

    public init(
        id: UUID = UUID(),
        url: URL,
        fileIdentifier: UInt64?,
        watchFolderID: String?,
        enqueuedAt: Date,
        reason: OfflineWaitReason
    ) {
        self.id = id
        self.path = url.standardizedFileURL.path
        self.queuedFileName = url.lastPathComponent
        self.fileIdentifier = fileIdentifier
        self.watchFolderID = watchFolderID
        self.enqueuedAt = enqueuedAt
        self.reason = reason
    }

    public var url: URL { URL(fileURLWithPath: path) }
    public var fileName: String { url.lastPathComponent }
}

/// What the app sees on disk for a queued file, right before renaming it.
public struct QueuedFileSnapshot: Equatable, Sendable {
    public var exists: Bool
    public var fileIdentifier: UInt64?
    /// Spotlight's last-used date (opened in an app), if any.
    public var lastOpened: Date?
    /// True when the path is inside an Intake watch folder (root or a filed folder).
    public var isInsideManagedFolder: Bool

    public init(exists: Bool, fileIdentifier: UInt64? = nil, lastOpened: Date? = nil, isInsideManagedFolder: Bool = true) {
        self.exists = exists
        self.fileIdentifier = fileIdentifier
        self.lastOpened = lastOpened
        self.isInsideManagedFolder = isInsideManagedFolder
    }
}

public enum QueuedRenameCheck: Equatable, Sendable {
    case proceed
    case skip(Reason)

    public enum Reason: Equatable, Sendable {
        /// Gone: deleted, or renamed / moved by the user (the tracked path is empty).
        case missing
        /// A different file now has that name.
        case replaced
        /// Opened since it arrived: the user has seen it by this name.
        case opened
        /// Moved out of the watch folder and its filed folders.
        case movedOut
    }

    /// Rename after filing (SPEC §9.3): only the same untouched file, still
    /// in an Intake-managed path.
    public static func evaluate(_ item: QueuedOfflineRename, snapshot: QueuedFileSnapshot) -> QueuedRenameCheck {
        guard snapshot.exists else { return .skip(.missing) }
        guard snapshot.isInsideManagedFolder else { return .skip(.movedOut) }
        if let expected = item.fileIdentifier, let actual = snapshot.fileIdentifier, expected != actual {
            return .skip(.replaced)
        }
        if let opened = snapshot.lastOpened, opened > item.enqueuedAt {
            return .skip(.opened)
        }
        return .proceed
    }
}

/// Persisted queue (SPEC §9.3): cap 500, items older than 7 days dropped,
/// newest first.
public struct OfflineRenameQueue: Equatable, Codable, Sendable {
    public static let defaultsKey = "intake.offlineModel.queue"
    public static let capacity = 500
    public static let maximumAge: TimeInterval = 7 * 24 * 60 * 60

    /// Newest first.
    public private(set) var items: [QueuedOfflineRename]
    /// Files dropped for the cap since the last overflow note.
    public private(set) var overflowDropped: Int

    public init(items: [QueuedOfflineRename] = [], overflowDropped: Int = 0) {
        self.items = items.sorted { $0.enqueuedAt > $1.enqueuedAt }
        self.overflowDropped = overflowDropped
    }

    public var count: Int { items.count }
    public var isEmpty: Bool { items.isEmpty }

    public func contains(path: String) -> Bool {
        items.contains { $0.path == path }
    }

    /// Adds (or refreshes) a file. Returns how many old items the cap dropped.
    @discardableResult
    public mutating func enqueue(_ item: QueuedOfflineRename) -> Int {
        items.removeAll { $0.path == item.path }
        let index = items.firstIndex { $0.enqueuedAt <= item.enqueuedAt } ?? items.endIndex
        items.insert(item, at: index)
        guard items.count > Self.capacity else { return 0 }
        let dropped = items.count - Self.capacity
        items.removeLast(dropped)
        overflowDropped += dropped
        return dropped
    }

    /// Drops items older than 7 days. Returns them (they keep Title Case names).
    @discardableResult
    public mutating func pruneExpired(now: Date) -> [QueuedOfflineRename] {
        let expired = items.filter { now.timeIntervalSince($0.enqueuedAt) > Self.maximumAge }
        items.removeAll { now.timeIntervalSince($0.enqueuedAt) > Self.maximumAge }
        return expired
    }

    /// The next chunk to process, newest first.
    public func nextChunk(size: Int = OfflineModelPolicy.drainChunkSize) -> [QueuedOfflineRename] {
        Array(items.prefix(max(size, 0)))
    }

    @discardableResult
    public mutating func remove(id: UUID) -> QueuedOfflineRename? {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return nil }
        return items.remove(at: index)
    }

    /// Rename Now jumps the queue: moves the item to the front.
    public mutating func prioritize(id: UUID) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        let item = items.remove(at: index)
        items.insert(item, at: 0)
    }

    /// Intake filed or renamed the file: follow it.
    public mutating func noteMoved(from old: URL, to new: URL) {
        let oldPath = old.standardizedFileURL.path
        guard let index = items.firstIndex(where: { $0.path == oldPath }) else { return }
        items[index].path = new.standardizedFileURL.path
    }

    public mutating func setReason(_ reason: OfflineWaitReason) {
        for index in items.indices {
            items[index].reason = reason
        }
    }

    /// "Too many files waiting. 37 kept their tidy names." — then reset.
    public mutating func takeOverflowNote() -> String? {
        guard overflowDropped > 0 else { return nil }
        defer { overflowDropped = 0 }
        return Self.overflowNote(dropped: overflowDropped)
    }

    public static func overflowNote(dropped: Int) -> String {
        "Too many files waiting. \(dropped) kept their tidy names."
    }

    public mutating func removeAll() {
        items.removeAll()
    }

    // MARK: Copy

    /// "3 files waiting to rename · Waiting for power" / "1 file waiting to rename · …"
    public static func menuLine(count: Int, reason: OfflineWaitReason) -> String {
        count == 1
            ? "1 file waiting to rename · \(reason.text)"
            : "\(count) files waiting to rename · \(reason.text)"
    }

    /// Settings card: "3 files waiting · Waiting for power"
    public static func settingsLine(count: Int, reason: OfflineWaitReason) -> String {
        "\(count) \(count == 1 ? "file" : "files") waiting · \(reason.text)"
    }

    public static func renameButtonTitle(count: Int) -> String {
        count == 1 ? "Rename Now" : "Rename All Now"
    }

    // MARK: Persistence

    public static func load(from defaults: UserDefaults) -> OfflineRenameQueue {
        guard let data = defaults.data(forKey: defaultsKey),
              let queue = try? JSONDecoder().decode(OfflineRenameQueue.self, from: data)
        else { return OfflineRenameQueue() }
        return queue
    }

    public func save(to defaults: UserDefaults) {
        if let data = try? JSONEncoder().encode(self) {
            defaults.set(data, forKey: Self.defaultsKey)
        }
    }
}
