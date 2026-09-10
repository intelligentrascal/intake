import Foundation

public enum FileEventKind: String, Sendable, Equatable {
    case appeared
    case modified
    case removed
    case metadataOnly
}

public struct DownloadIgnorePolicy: Sendable, Equatable {
    public static let incompleteExtensions: Set<String> = [
        "download",
        "crdownload",
        "part",
        "partial",
        "tmp",
        "temp",
        "downloading",
    ]

    public var managedFolderNames: Set<String>

    public init(managedFolderNames: Set<String> = DefaultTaxonomy.managedFolderNames) {
        self.managedFolderNames = managedFolderNames
    }

    public func shouldIgnore(url: URL, kind: FileEventKind, isDirectory: Bool) -> Bool {
        if kind == .metadataOnly || kind == .removed {
            return true
        }
        if isDirectory {
            return true
        }

        let name = url.lastPathComponent
        if name.hasPrefix(".") || name == "Icon\r" {
            return true
        }
        if managedFolderNames.contains(name) {
            return true
        }

        if url.pathComponents.contains(where: Self.isIncompleteDownloadComponent) {
            return true
        }

        let lowerName = name.lowercased()
        if lowerName.hasSuffix(".download") || lowerName.contains(".download.") {
            return true
        }
        if lowerName.hasPrefix("unconfirmed ") {
            return true
        }
        if lowerName.hasPrefix(".com.google.chrome.") {
            return true
        }

        return false
    }

    private static func isIncompleteDownloadComponent(_ component: String) -> Bool {
        let ext = URL(fileURLWithPath: component).pathExtension.lowercased()
        if incompleteExtensions.contains(ext) {
            return true
        }
        let lower = component.lowercased()
        return lower.hasSuffix(".download") || lower.contains(".download.")
    }
}
