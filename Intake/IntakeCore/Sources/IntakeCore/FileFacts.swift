import Foundation

/// Everything a `RoutingRule` might need to know about one file: its name,
/// extension, size, and where it came from. Built once per file and passed
/// through matching, never read piecemeal so a rule can't see anything Intake
/// hasn't already gathered from local file-system metadata.
public struct FileFacts: Equatable, Sendable {
    public var name: String
    public var fileExtension: String
    public var size: Int64
    /// Where-from URLs in the order macOS recorded them (download URL, then
    /// referrer, when both are present). Empty when the source is unknown.
    public var sourceURLs: [URL]

    public init(name: String, fileExtension: String, size: Int64 = 0, sourceURLs: [URL] = []) {
        self.name = name
        self.fileExtension = fileExtension.lowercased()
        self.size = size
        self.sourceURLs = sourceURLs
    }

    public init(fileURL: URL, size: Int64 = 0, sourceURLs: [URL] = []) {
        self.init(
            name: fileURL.lastPathComponent,
            fileExtension: fileURL.pathExtension,
            size: size,
            sourceURLs: sourceURLs
        )
    }

    /// The file name without its extension — what name conditions match against.
    public var baseName: String {
        guard !fileExtension.isEmpty, name.count > fileExtension.count + 1 else { return name }
        let suffix = ".\(fileExtension)"
        guard name.lowercased().hasSuffix(suffix.lowercased()) else { return name }
        return String(name.dropLast(suffix.count))
    }

    /// The host to match `sourceDomain` conditions against: the first
    /// where-from URL's host, falling back to the next URL's (typically the
    /// referrer) when the first has none.
    public var sourceHost: String? {
        for url in sourceURLs {
            if let host = url.host, !host.isEmpty {
                return host
            }
        }
        return nil
    }

    /// Facts for a file already on disk: real size, and the where-from URLs
    /// read from the extended attribute macOS/browsers write on downloads. No
    /// network access.
    public static func onDisk(at url: URL, fileManager: FileManager = .default) -> FileFacts {
        let attributes = try? fileManager.attributesOfItem(atPath: url.path)
        let size = (attributes?[.size] as? NSNumber)?.int64Value ?? 0
        let sourceURLs = WhereFromMetadata.urls(atPath: url.path)
        return FileFacts(fileURL: url, size: size, sourceURLs: sourceURLs)
    }

    /// Returns the file's date added (contentModificationDate), if available.
    public static func dateAdded(for url: URL, fileManager: FileManager = .default) -> Date? {
        try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
    }

    /// Returns the file's creation date, if available.
    public static func creationDate(for url: URL, fileManager: FileManager = .default) -> Date? {
        try? url.resourceValues(forKeys: [.creationDateKey]).creationDate
    }
}
