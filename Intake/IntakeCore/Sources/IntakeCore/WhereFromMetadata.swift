import Foundation

/// Reads the `com.apple.metadata:kMDItemWhereFroms` extended attribute macOS
/// browsers write on a downloaded file — a binary plist array of strings,
/// typically `[downloadURL, referrerURL]`. Local file-system metadata only:
/// no network access, ever.
public enum WhereFromMetadata: Sendable {
    public static let attributeName = "com.apple.metadata:kMDItemWhereFroms"

    /// The where-from URLs recorded on the file at `path`, in the order macOS
    /// stored them. Empty when the attribute is absent, unreadable, or not a
    /// plist array of strings.
    public static func urls(atPath path: String) -> [URL] {
        guard let data = readAttribute(atPath: path) else { return [] }
        guard let plist = try? PropertyListSerialization.propertyList(
            from: data,
            options: [],
            format: nil
        ) else {
            return []
        }
        guard let strings = plist as? [String] else { return [] }
        return strings.compactMap { URL(string: $0) }
    }

    /// Writes the where-from attribute as browsers do. Used by tests to set up
    /// a real extended attribute on a temporary file; production code never
    /// writes this attribute.
    static func write(urls: [String], atPath path: String) throws {
        let data = try PropertyListSerialization.data(
            fromPropertyList: urls,
            format: .binary,
            options: 0
        )
        let result = path.withCString { cPath in
            data.withUnsafeBytes { bufferPtr -> Int32 in
                setxattr(cPath, attributeName, bufferPtr.baseAddress, data.count, 0, 0)
            }
        }
        guard result == 0 else {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
        }
    }

    private static func readAttribute(atPath path: String) -> Data? {
        let size = path.withCString { cPath in
            getxattr(cPath, attributeName, nil, 0, 0, 0)
        }
        guard size > 0 else { return nil }
        var buffer = [UInt8](repeating: 0, count: size)
        let read = path.withCString { cPath in
            buffer.withUnsafeMutableBytes { bufferPtr in
                getxattr(cPath, attributeName, bufferPtr.baseAddress, size, 0, 0)
            }
        }
        guard read == size else { return nil }
        return Data(buffer)
    }
}
