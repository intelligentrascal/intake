import Foundation

/// Pure checks run before a folder becomes (or replaces) a watch folder.
/// Overlapping watch folders would make files bounce between watchers, and
/// watching a category folder Intake files into would re-ingest its own work.
public enum WatchFolderValidation: Sendable {
    /// A watch folder that already exists, with the category folder names
    /// Intake manages inside it.
    public struct ExistingFolder: Equatable, Sendable {
        public var id: String
        public var displayName: String
        public var url: URL
        public var managedFolderNames: Set<String>

        public init(id: String, displayName: String, url: URL, managedFolderNames: Set<String>) {
            self.id = id
            self.displayName = displayName
            self.url = url
            self.managedFolderNames = managedFolderNames
        }
    }

    public enum Problem: Equatable, Sendable {
        case limitReached(Int)
        case sameAsExisting(String)
        case insideExisting(String)
        case containsExisting(String)
        /// A category folder (or a date subfolder in one) Intake files into.
        case managedFolder(folderName: String, watchFolderName: String)

        public var message: String {
            switch self {
            case .limitReached(let cap):
                "Intake can watch up to \(cap) folders. Remove one to add another."
            case .sameAsExisting(let name):
                "Intake already watches this folder (“\(name)”)."
            case .insideExisting(let name):
                "This folder is inside “\(name)”, which Intake already watches. Watch folders can’t overlap."
            case .containsExisting(let name):
                "This folder contains “\(name)”, which Intake already watches. Watch folders can’t overlap."
            case .managedFolder(let folderName, let watchFolderName):
                "“\(folderName)” is a folder Intake files into inside “\(watchFolderName)”. Choose a different folder."
            }
        }
    }

    /// Returns why `candidate` can't be used, or `nil` when it's fine.
    /// `replacing` is the id of the profile whose folder is being changed or
    /// re-granted: it's left out of the overlap checks and the cap, but its
    /// category folders are still off limits.
    public static func validate(
        _ candidate: URL,
        existing: [ExistingFolder],
        replacing: String? = nil,
        softCap: Int = WatchFolderProfile.softCap
    ) -> Problem? {
        if replacing == nil, existing.count >= softCap {
            return .limitReached(softCap)
        }
        let candidateComponents = normalizedComponents(candidate)

        for folder in existing {
            let root = normalizedComponents(folder.url)
            guard candidateComponents.count > root.count,
                  Array(candidateComponents.prefix(root.count)) == root
            else {
                continue
            }
            let firstBelowRoot = candidateComponents[root.count]
            let managed = Set(folder.managedFolderNames.map { $0.lowercased() })
            if managed.contains(firstBelowRoot) {
                let original = folder.managedFolderNames.first { $0.lowercased() == firstBelowRoot }
                return .managedFolder(
                    folderName: original ?? firstBelowRoot,
                    watchFolderName: folder.displayName
                )
            }
        }

        for folder in existing where folder.id != replacing {
            let root = normalizedComponents(folder.url)
            if candidateComponents == root {
                return .sameAsExisting(folder.displayName)
            }
            if candidateComponents.count > root.count,
               Array(candidateComponents.prefix(root.count)) == root {
                return .insideExisting(folder.displayName)
            }
            if root.count > candidateComponents.count,
               Array(root.prefix(candidateComponents.count)) == candidateComponents {
                return .containsExisting(folder.displayName)
            }
        }
        return nil
    }

    /// Symlink-resolved, standardized, case-insensitive (like APFS) path
    /// components, so `/tmp/x` and `/private/tmp/X` compare equal.
    static func normalizedComponents(_ url: URL) -> [String] {
        url.resolvingSymlinksInPath()
            .standardizedFileURL
            .pathComponents
            .map { $0.lowercased() }
    }
}

/// Where macOS saves screenshots, offered as a one-click watch folder. Access
/// is still granted through the folder picker (sandbox).
public enum ScreenshotLocation: Sendable {
    public static let defaultsDomain = "com.apple.screencapture"
    public static let locationKey = "location"

    /// The `com.apple.screencapture` `location` default when set, with `~`
    /// expanded against `homeDirectory`; otherwise the Desktop.
    public static func resolve(storedLocation: String?, homeDirectory: URL) -> URL {
        let desktop = homeDirectory.appendingPathComponent("Desktop", isDirectory: true)
        guard let raw = storedLocation?.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty
        else {
            return desktop
        }
        if raw == "~" {
            return homeDirectory
        }
        if raw.hasPrefix("~/") {
            return homeDirectory.appendingPathComponent(String(raw.dropFirst(2)), isDirectory: true)
        }
        guard raw.hasPrefix("/") else {
            return desktop
        }
        return URL(fileURLWithPath: raw, isDirectory: true).standardizedFileURL
    }
}

/// Menu bar status summarizing every watch folder. With a single folder the
/// strings match 1.2 exactly.
public struct WatchFolderStatus: Equatable, Sendable {
    public struct Folder: Equatable, Sendable {
        public var displayName: String
        public var isOrganizing: Bool
        public var accessLost: Bool

        public init(displayName: String, isOrganizing: Bool, accessLost: Bool) {
            self.displayName = displayName
            self.isOrganizing = isOrganizing
            self.accessLost = accessLost
        }
    }

    public var title: String
    public var subtitle: String
    public var accessibilityLabel: String
    /// True when no folder is organizing (drives the Paused glyph and the
    /// Pause / Resume verb).
    public var isPaused: Bool
    public var watchingCount: Int

    public static func summarize(_ folders: [Folder]) -> WatchFolderStatus {
        let watching = folders.filter { $0.isOrganizing && !$0.accessLost }
        let lost = folders.filter(\.accessLost)
        let isPaused = watching.isEmpty

        if folders.count <= 1 {
            let folder = folders.first
            if folder?.accessLost == true {
                return WatchFolderStatus(
                    title: "Attention",
                    subtitle: "Needs folder access",
                    accessibilityLabel: "Intake needs folder access",
                    isPaused: isPaused,
                    watchingCount: watching.count
                )
            }
            let name = folder?.displayName ?? ""
            if isPaused {
                return WatchFolderStatus(
                    title: "Paused",
                    subtitle: "Organizing is paused · \(name)",
                    accessibilityLabel: "Intake paused",
                    isPaused: true,
                    watchingCount: 0
                )
            }
            return WatchFolderStatus(
                title: "Watching",
                subtitle: "New files in \(name)",
                accessibilityLabel: "Intake watching",
                isPaused: false,
                watchingCount: 1
            )
        }

        if !lost.isEmpty {
            let subtitle = lost.count == 1
                ? "\(lost[0].displayName) needs folder access"
                : "\(lost.count) folders need folder access"
            return WatchFolderStatus(
                title: "Attention",
                subtitle: subtitle,
                accessibilityLabel: "Intake needs folder access",
                isPaused: isPaused,
                watchingCount: watching.count
            )
        }
        if isPaused {
            return WatchFolderStatus(
                title: "Paused",
                subtitle: "Organizing is paused · \(folders.count) folders",
                accessibilityLabel: "Intake paused",
                isPaused: true,
                watchingCount: 0
            )
        }
        let names = watching.map(\.displayName).joined(separator: ", ")
        let pausedCount = folders.count - watching.count
        let subtitle = pausedCount > 0
            ? "New files in \(names) · \(pausedCount) paused"
            : "New files in \(names)"
        return WatchFolderStatus(
            title: "Watching \(watching.count)",
            subtitle: subtitle,
            accessibilityLabel: "Intake watching \(watching.count) folders",
            isPaused: false,
            watchingCount: watching.count
        )
    }
}
