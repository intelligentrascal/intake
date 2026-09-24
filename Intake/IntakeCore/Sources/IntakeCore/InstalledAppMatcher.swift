import Foundation

/// Matches installer files (`.dmg`/`.pkg`/`.mpkg`) against apps already
/// present in `/Applications` or `~/Applications`, so Cleanup can suggest
/// deleting an installer once its app is installed and newer than it.
public enum InstalledAppMatcher {
    /// A `.app` bundle found in one of the Applications folders.
    public struct InstalledApp: Equatable, Sendable {
        public var url: URL
        /// `CFBundleDisplayName`, falling back to the bundle's filename.
        public var displayName: String
        /// `CFBundleName`, falling back to the bundle's filename.
        public var bundleName: String
        /// Added-to-directory date, falling back to content modification date —
        /// the point the installed copy of the app appeared or last changed.
        public var date: Date

        public init(url: URL, displayName: String, bundleName: String, date: Date) {
            self.url = url
            self.displayName = displayName
            self.bundleName = bundleName
            self.date = date
        }
    }

    /// `/Applications` and the current user's `~/Applications`.
    public static func defaultApplicationsFolders(fileManager: FileManager = .default) -> [URL] {
        [
            URL(fileURLWithPath: "/Applications", isDirectory: true),
            fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Applications", isDirectory: true),
        ]
    }

    /// Top-level `.app` bundles in the given folders (non-recursive), with the
    /// metadata needed to match them against installer files.
    public static func installedApps(
        in folders: [URL],
        fileManager: FileManager = .default
    ) -> [InstalledApp] {
        var apps: [InstalledApp] = []
        for folder in folders {
            let contents = (try? fileManager.contentsOfDirectory(
                at: folder,
                includingPropertiesForKeys: [
                    .isDirectoryKey,
                    .contentModificationDateKey,
                    .addedToDirectoryDateKey,
                ],
                options: [.skipsHiddenFiles]
            )) ?? []
            for url in contents where url.pathExtension.lowercased() == "app" {
                if let app = installedApp(at: url, fileManager: fileManager) {
                    apps.append(app)
                }
            }
        }
        return apps
    }

    private static func installedApp(at url: URL, fileManager: FileManager) -> InstalledApp? {
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            return nil
        }
        let bundleFileName = url.deletingPathExtension().lastPathComponent
        var displayName = bundleFileName
        var bundleName = bundleFileName
        let infoPlistURL = url.appendingPathComponent("Contents/Info.plist")
        if let data = try? Data(contentsOf: infoPlistURL),
           let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any]
        {
            if let name = plist["CFBundleDisplayName"] as? String, !name.isEmpty {
                displayName = name
            }
            if let name = plist["CFBundleName"] as? String, !name.isEmpty {
                bundleName = name
            }
        }
        // Content modification date is the reliable signal here: dragging an
        // app into place (or a `.pkg` payload writing it) touches the bundle,
        // while `addedToDirectoryDate` reflects the OS's own bookkeeping and
        // isn't something callers (or tests, with a fake Applications
        // folder) can control the same way.
        let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .addedToDirectoryDateKey])
        let date = values?.contentModificationDate ?? values?.addedToDirectoryDate ?? .distantPast
        return InstalledApp(url: url, displayName: displayName, bundleName: bundleName, date: date)
    }

    /// Normalizes a file or app name for matching: lowercases it, drops a
    /// trailing installer/app extension, turns separators into spaces, then
    /// strips version-number tokens (`2.3`, `v1`, …), architecture tokens
    /// (`arm64`, `x86_64`, `universal`, …) and common installer words
    /// (`installer`, `setup`, …).
    public static func normalize(_ name: String) -> String {
        var value = name
        for ext in ["mpkg", "pkg", "dmg", "app"] where value.lowercased().hasSuffix(".\(ext)") {
            value.removeLast(ext.count + 1)
            break
        }
        value = value.lowercased()
        for separator in ["_", "-", "."] {
            value = value.replacingOccurrences(of: separator, with: " ")
        }

        let stopWords: Set<String> = [
            "installer", "install", "setup", "release", "final", "stable",
            "signed", "notarized", "notarised", "portable", "latest",
            "universal", "online", "offline",
            "x86", "x64", "x8664", "amd64", "arm", "arm64", "aarch64",
            "intel", "apple", "silicon", "macos", "mac", "osx",
        ]
        let versionPattern = #"^v?\d+([._]\d+)*[a-z]?$"#

        let tokens = value.split(separator: " ").map(String.init).filter { token in
            guard !token.isEmpty else { return false }
            if stopWords.contains(token) { return false }
            if token.range(of: versionPattern, options: .regularExpression) != nil { return false }
            return true
        }
        return tokens.joined(separator: " ").trimmingCharacters(in: .whitespaces)
    }

    /// The installed app whose display or bundle name normalizes to the same
    /// value as the installer's file name, if any.
    public static func bestMatch(forInstallerNamed fileName: String, in apps: [InstalledApp]) -> InstalledApp? {
        let target = normalize(fileName)
        guard !target.isEmpty else { return nil }
        return apps.first { normalize($0.displayName) == target || normalize($0.bundleName) == target }
    }
}
