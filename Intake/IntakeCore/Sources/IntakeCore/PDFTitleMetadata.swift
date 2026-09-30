import Foundation

/// Non-junk PDF `Title` document attribute, surfaced to content namers as a hint.
/// Extraction stays on-Mac; this type only formats and filters the string.
public enum PDFTitleMetadata: Sendable {
    public static let hintLabel = "PDF title metadata"

    /// Returns the trimmed title when it is useful as a naming hint; otherwise `nil`.
    /// Junk = empty, equal to the current file base name (case-insensitive), or only
    /// generic words such as "Untitled" / "Document".
    public static func nonJunkTitle(_ raw: String?, fileBaseName: String) -> String? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let base = fileBaseName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !base.isEmpty, trimmed.caseInsensitiveCompare(base) == .orderedSame {
            return nil
        }
        if isGenericTitle(trimmed) { return nil }
        return trimmed
    }

    /// Hint line for the namer prompt, e.g. `PDF title metadata: Quarterly Report`.
    public static func hintLine(title: String?, fileBaseName: String) -> String? {
        guard let title = nonJunkTitle(title, fileBaseName: fileBaseName) else { return nil }
        return "\(hintLabel): \(title)"
    }

    private static func isGenericTitle(_ title: String) -> Bool {
        let words = title
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
        guard !words.isEmpty else { return true }
        return words.allSatisfy { ContentNameTemplate.genericWords.contains($0) }
    }
}
