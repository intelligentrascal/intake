import Foundation

/// LIFO undo stack for Intake rename/move (cap 20). Persisted locally with Activity.
public struct UndoService: Equatable, Sendable {
    public static let maximumEntries = 20
    public static let defaultsKey = "intake.undoStack"
    public static let toastDuration: TimeInterval = 10

    public private(set) var actions: [UndoAction]

    public init(actions: [UndoAction] = []) {
        self.actions = Array(actions.prefix(Self.maximumEntries))
    }

    public var last: UndoAction? { actions.first }

    public mutating func push(_ action: UndoAction) {
        actions.insert(action, at: 0)
        if actions.count > Self.maximumEntries {
            actions = Array(actions.prefix(Self.maximumEntries))
        }
    }

    public func action(forActivityID id: UUID) -> UndoAction? {
        actions.first { $0.activityID == id }
    }

    public func containsActivityID(_ id: UUID) -> Bool {
        actions.contains { $0.activityID == id }
    }

    /// Eligibility for an Activity row.
    public func eligibility(
        for entry: ActivityEntry,
        fileManager: FileManager = .default
    ) -> UndoEligibility {
        guard entry.kind == .renamed || entry.kind == .moved else {
            return .notUndoable
        }
        guard let action = action(forActivityID: entry.id) else {
            // Has paths but dropped from stack → too old; else not undoable.
            if entry.beforePath != nil, entry.afterPath != nil {
                return .tooOld
            }
            return .notUndoable
        }
        return eligibility(for: action, fileManager: fileManager)
    }

    public func eligibility(
        for action: UndoAction,
        fileManager: FileManager = .default
    ) -> UndoEligibility {
        let after = action.afterURL.standardizedFileURL
        let before = action.beforeURL.standardizedFileURL
        guard fileManager.fileExists(atPath: after.path) else {
            return .missingFile
        }
        // A case-only rename's old name resolves to the file itself on APFS.
        if fileManager.fileExists(atPath: before.path),
           before.standardizedFileURL != after.standardizedFileURL,
           !FileIdentity.isSameFile(before, after) {
            return .collision
        }
        return .eligible
    }

    public mutating func perform(
        _ action: UndoAction,
        fileManager: FileManager = .default
    ) -> UndoPerformResult {
        let status = eligibility(for: action, fileManager: fileManager)
        guard status == .eligible else {
            return .failure(status)
        }
        let after = action.afterURL.standardizedFileURL
        let before = action.beforeURL.standardizedFileURL
        do {
            let parent = before.deletingLastPathComponent()
            try fileManager.createDirectory(at: parent, withIntermediateDirectories: true)
            try fileManager.moveItem(at: after, to: before)
            actions.removeAll { $0.id == action.id || $0.activityID == action.activityID }
            return .success(restoredURL: before)
        } catch {
            // If move failed because target appeared, surface collision; else missing.
            if fileManager.fileExists(atPath: before.path) {
                return .failure(.collision)
            }
            return .failure(.missingFile)
        }
    }

    public mutating func performLast(fileManager: FileManager = .default) -> UndoPerformResult {
        guard let action = last else {
            return .failure(.notUndoable)
        }
        return perform(action, fileManager: fileManager)
    }

    // MARK: Persistence

    public static func load(from defaults: UserDefaults) -> UndoService {
        guard let data = defaults.data(forKey: defaultsKey) else {
            return UndoService()
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let actions = (try? decoder.decode([UndoAction].self, from: data)) ?? []
        return UndoService(actions: actions)
    }

    public func save(to defaults: UserDefaults) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        if actions.isEmpty {
            defaults.removeObject(forKey: Self.defaultsKey)
            return
        }
        if let data = try? encoder.encode(actions) {
            defaults.set(data, forKey: Self.defaultsKey)
        }
    }

    public static func makeAction(from entry: ActivityEntry) -> UndoAction? {
        guard entry.kind == .renamed || entry.kind == .moved,
              let before = entry.beforePath,
              let after = entry.afterPath,
              !before.isEmpty,
              !after.isEmpty
        else {
            return nil
        }
        let kind: UndoAction.Kind = entry.kind == .renamed ? .rename : .move
        return UndoAction(
            activityID: entry.id,
            kind: kind,
            beforePath: before,
            afterPath: after,
            createdAt: entry.date,
            displayName: entry.fileName,
            destinationFolder: entry.destinationFolder
        )
    }

    public static func toastMessage(for action: UndoAction) -> String {
        switch action.kind {
        case .rename:
            return UndoCopy.toastRenamed(name: action.displayName)
        case .move:
            if let folder = action.destinationFolder {
                return UndoCopy.toastMoved(folder: folder)
            }
            return UndoCopy.toastMoved(folder: action.afterURL.deletingLastPathComponent().lastPathComponent)
        }
    }
}
