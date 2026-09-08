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
        name = replaceNonDateHyphens(in: name)
        name = splitCamelCase(name)
        name = stripDownloadDecorations(name)
        name = name
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return titleCaseIfAllLowercase(name)
    }

    private func replaceNonDateHyphens(in name: String) -> String {
        let chars = Array(name)
        var result = ""
        result.reserveCapacity(chars.count)
        for index in chars.indices {
            let character = chars[index]
            if character == "-" {
                let previousIsDigit = index > 0 && chars[index - 1].isNumber
                let nextIsDigit = index + 1 < chars.count && chars[index + 1].isNumber
                result.append(previousIsDigit && nextIsDigit ? "-" : " ")
            } else {
                result.append(character)
            }
        }
        return result
    }

    private func splitCamelCase(_ name: String) -> String {
        let withLowerBreaks = name.replacingOccurrences(
            of: #"([a-z])([A-Z])"#,
            with: "$1 $2",
            options: .regularExpression
        )
        return withLowerBreaks.replacingOccurrences(
            of: #"([A-Z]+)([A-Z][a-z])"#,
            with: "$1 $2",
            options: .regularExpression
        )
    }

    private func stripDownloadDecorations(_ name: String) -> String {
        var current = name
        for _ in 0..<3 {
            let stripped = current.replacingOccurrences(
                of: #"(?i)(?:\s*\(\d+\)|\s+copy)\s*$"#,
                with: "",
                options: .regularExpression
            )
            if stripped == current || stripped.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                break
            }
            current = stripped
        }
        return current
    }

    private func titleCaseIfAllLowercase(_ name: String) -> String {
        let letters = name.filter(\.isLetter)
        guard !letters.isEmpty, letters.allSatisfy(\.isLowercase) else {
            return name
        }
        return name.split(separator: " ", omittingEmptySubsequences: false).map { word in
            guard let first = word.first else { return String(word) }
            return String(first).uppercased() + word.dropFirst()
        }.joined(separator: " ")
    }
}
