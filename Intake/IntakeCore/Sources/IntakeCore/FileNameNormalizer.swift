import Foundation

public struct FileNameNormalizer: Sendable, Equatable {
    public init() {}

    /// Small words stay lowercase unless first or last (Title Case + exceptions).
    public static let smallWords: Set<String> = [
        "a", "an", "the", "and", "or", "but", "for", "nor",
        "as", "at", "by", "in", "of", "on", "to", "vs", "via",
    ]

    /// Preserve known product / acronym casing (matched case-insensitively).
    public static let casingAllowlist: [String: String] = [
        "ai": "AI",
        "api": "API",
        "cpu": "CPU",
        "gpu": "GPU",
        "ios": "iOS",
        "macos": "macOS",
        "iphone": "iPhone",
        "ipad": "iPad",
        "id": "ID",
        "url": "URL",
        "http": "HTTP",
        "https": "HTTPS",
        "q1": "Q1",
        "q2": "Q2",
        "q3": "Q3",
        "q4": "Q4",
        "okrs": "OKRs",
        "okr": "OKR",
        "pdf": "PDF",
    ]

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
        // IN-14: always apply Title Case policy after structural clean (C3).
        return applyTitleCasePolicy(name)
    }

    /// Title Case + small-word exceptions + allowlist + version-token preserve.
    public func applyTitleCasePolicy(_ name: String) -> String {
        let words = name.split(separator: " ", omittingEmptySubsequences: false).map(String.init)
        guard !words.isEmpty else { return name }
        let lastIndex = words.count - 1
        return words.enumerated().map { index, word in
            formatWord(word, isFirst: index == 0, isLast: index == lastIndex)
        }.joined(separator: " ")
    }

    private func formatWord(_ word: String, isFirst: Bool, isLast: Bool) -> String {
        guard !word.isEmpty else { return word }

        // Preserve hyphenated date segments like 2024-01-15 as-is.
        if looksLikeHyphenatedDate(word) {
            return word
        }

        // Version / build tokens: v1, v2.3, b12 — keep leading letter lowercase.
        if let version = preservedVersionToken(word) {
            return version
        }

        let folded = word.lowercased()
        if let canonical = Self.casingAllowlist[folded] {
            return canonical
        }

        // Multi-part allowlist-ish: leave emoji / non-letter-leading alone for first char logic
        let lettersOnly = word.filter(\.isLetter)
        if lettersOnly.isEmpty {
            return word
        }

        if !isFirst && !isLast && Self.smallWords.contains(folded) {
            return folded
        }

        return titleCaseWord(word)
    }

    private func titleCaseWord(_ word: String) -> String {
        var didCapitalize = false
        var result = ""
        result.reserveCapacity(word.count)
        for character in word {
            if character.isLetter {
                if !didCapitalize {
                    result.append(contentsOf: String(character).uppercased())
                    didCapitalize = true
                } else {
                    result.append(contentsOf: String(character).lowercased())
                }
            } else {
                result.append(character)
            }
        }
        return result
    }

    private func looksLikeHyphenatedDate(_ word: String) -> Bool {
        // e.g. 2024-01-15
        word.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil
    }

    private func preservedVersionToken(_ word: String) -> String? {
        // v1, v2.3, V10 → v10 style (lowercase v + rest as typed digits/dots)
        if let _ = word.range(of: #"^[vV]\d+(\.\d+)*$"#, options: .regularExpression) {
            return "v" + word.dropFirst()
        }
        // b12 build tokens
        if let _ = word.range(of: #"^[bB]\d+$"#, options: .regularExpression) {
            return "b" + word.dropFirst()
        }
        return nil
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
}
