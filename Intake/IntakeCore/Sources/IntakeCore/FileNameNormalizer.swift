import Foundation

public struct FileNameNormalizer: Sendable, Equatable {
    public init() {}

    public func proposedFileName(for url: URL) -> String {
        let ext = url.pathExtension
        let rawBase = url.deletingPathExtension().lastPathComponent
        let cleaned = cleanBaseName(rawBase)
        let base = cleaned.isEmpty ? rawBase : cleaned
        if ext.isEmpty {
            return base
        }
        return "\(base).\(ext)"
    }

    public func cleanBaseName(_ raw: String) -> String {
        var name = raw.removingPercentEncoding ?? raw
        name = name.replacingOccurrences(of: "+", with: " ")
        name = name.replacingOccurrences(of: "_", with: " ")
        return name
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
