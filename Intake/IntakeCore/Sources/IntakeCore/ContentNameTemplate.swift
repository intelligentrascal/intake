import Foundation

/// Why a content-aware name was not used. Any rejection keeps the Title Case name.
public enum ContentNameRejection: String, Equatable, Sendable {
    /// The namer returned nothing.
    case noResult
    /// The namer's confidence was under the threshold.
    case lowConfidence
    /// Nothing was left after dropping empty tokens.
    case empty
    /// Only generic words (and maybe a date) were left, e.g. "Document".
    case generic
}

public enum ContentNameOutcome: Equatable, Sendable {
    /// A validated file name, extension included.
    case accepted(String)
    case rejected(ContentNameRejection)

    public var acceptedFileName: String? {
        if case .accepted(let name) = self { return name }
        return nil
    }
}

/// Deterministic template renderer + validator for content-aware names.
/// Tokens: `{date} {type} {organization} {subject} {original}`.
public struct ContentNameTemplate: Equatable, Sendable {
    public static let defaultTemplate = "{date} {type} {organization}"
    public static let defaultMinimumConfidence = 0.6
    /// Cap on the base name (extension not counted).
    public static let maximumBaseNameLength = 80

    public enum Token: String, CaseIterable, Sendable {
        case date, type, organization, subject, original

        public var placeholder: String { "{\(rawValue)}" }
    }

    /// Words that on their own don't tell a person anything about the file.
    public static let genericWords: Set<String> = [
        "document", "documents", "doc", "file", "files", "scan", "scanned", "image",
        "images", "photo", "picture", "img", "untitled", "unknown", "none", "n/a", "na",
        "null", "nil", "pdf", "page", "pages", "download", "downloaded", "copy", "other",
        "misc", "miscellaneous", "screenshot", "text", "attachment", "item", "new",
    ]

    public var template: String
    public var minimumConfidence: Double
    public var normalizer: FileNameNormalizer

    public init(
        template: String = ContentNameTemplate.defaultTemplate,
        minimumConfidence: Double = ContentNameTemplate.defaultMinimumConfidence,
        normalizer: FileNameNormalizer = FileNameNormalizer()
    ) {
        let trimmed = template.trimmingCharacters(in: .whitespacesAndNewlines)
        self.template = trimmed.isEmpty ? Self.defaultTemplate : trimmed
        self.minimumConfidence = minimumConfidence
        self.normalizer = normalizer
    }

    /// Validates `fields` and renders them for the file currently named
    /// `currentFileName` (its extension is kept; its base is `{original}`).
    public func outcome(for fields: ContentNamingFields?, currentFileName: String) -> ContentNameOutcome {
        guard let fields else { return .rejected(.noResult) }
        guard fields.confidence.isFinite, fields.confidence >= minimumConfidence else {
            return .rejected(.lowConfidence)
        }
        let url = URL(fileURLWithPath: currentFileName)
        let ext = url.pathExtension
        let originalBase = ext.isEmpty ? currentFileName : String(currentFileName.dropLast(ext.count + 1))

        let base = renderBaseName(fields: fields, originalBaseName: originalBase)
        if base.isEmpty {
            return .rejected(.empty)
        }
        if isAllGeneric(base, originalBaseName: originalBase) {
            return .rejected(.generic)
        }
        return .accepted(ext.isEmpty ? base : "\(base).\(ext)")
    }

    /// The rendered, sanitized, capped base name (no extension). Empty when
    /// every token was empty.
    public func renderBaseName(fields: ContentNamingFields, originalBaseName: String) -> String {
        let values: [Token: String] = [
            .date: Self.validatedISODate(fields.date) ?? "",
            .type: cleanField(fields.documentType),
            .organization: cleanField(fields.organization),
            .subject: cleanField(fields.subject),
            .original: Self.sanitize(originalBaseName),
        ]

        var pieces: [String] = []
        var pendingLiteral = ""
        for piece in Self.parse(template) {
            switch piece {
            case .literal(let text):
                pendingLiteral = Self.mergeLiterals(pendingLiteral, Self.sanitizeLiteral(text))
            case .token(let token):
                let value = values[token] ?? ""
                if value.isEmpty {
                    // Drop the token; the literal on either side collapses into one.
                    continue
                }
                if pieces.isEmpty {
                    // Leading separators before the first real value go away,
                    // but real words ("Invoice from ") stay.
                    let kept = Self.isSeparatorOnly(pendingLiteral) ? "" : pendingLiteral
                    if !kept.isEmpty { pieces.append(kept) }
                } else {
                    pieces.append(pendingLiteral.isEmpty ? " " : pendingLiteral)
                }
                pendingLiteral = ""
                pieces.append(value)
            }
        }
        if !pieces.isEmpty, !Self.isSeparatorOnly(pendingLiteral) {
            pieces.append(pendingLiteral)
        }

        var name = pieces.joined()
        name = name.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        name = Self.trimSeparators(name)
        name = Self.capped(name, to: Self.maximumBaseNameLength)
        return name
    }

    // MARK: Validation helpers

    /// `YYYY-MM-DD` that is a real calendar date between 1900 and 2100, else nil.
    public static func validatedISODate(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil else {
            return nil
        }
        let parts = trimmed.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        let (year, month, day) = (parts[0], parts[1], parts[2])
        guard (1900...2100).contains(year), (1...12).contains(month), day >= 1 else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .current
        let components = DateComponents(year: year, month: month, day: day)
        guard let date = calendar.date(from: components) else { return nil }
        let back = calendar.dateComponents([.year, .month, .day], from: date)
        guard back.year == year, back.month == month, back.day == day else { return nil }
        return trimmed
    }

    /// Removes control characters and path separators, collapses whitespace.
    public static func sanitize(_ raw: String) -> String {
        var scalars = String.UnicodeScalarView()
        for scalar in raw.unicodeScalars {
            if CharacterSet.controlCharacters.contains(scalar)
                || scalar == "/" || scalar == "\\" || scalar == ":"
                || (0xE000...0xF8FF).contains(scalar.value)
            {
                scalars.append(" ")
            } else {
                scalars.append(scalar)
            }
        }
        var text = String(scalars)
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
        // A leading dot would hide the file in Finder.
        while text.hasPrefix(".") {
            text.removeFirst()
            text = text.trimmingCharacters(in: .whitespaces)
        }
        return text
    }

    /// One model field: sanitized, then the normalizer's structural clean +
    /// Title Case — keeping short all-caps acronyms (IBM, IRS, W2) as written.
    func cleanField(_ raw: String?) -> String {
        guard let raw else { return "" }
        let placeholderish: Set<String> = ["n/a", "na", "none", "null", "nil", "unknown", "-"]
        if placeholderish.contains(raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()) {
            return ""
        }
        let sanitized = Self.trimSeparators(Self.sanitize(raw))
        guard !sanitized.isEmpty else { return "" }
        let cleaned = normalizer.cleanBaseName(sanitized)
        let acronyms = Set(
            sanitized.split(separator: " ").map(String.init).filter { word in
                let letters = word.filter(\.isLetter)
                return (2...5).contains(word.count) && !letters.isEmpty
                    && word == word.uppercased() && word.allSatisfy { $0.isLetter || $0.isNumber }
            }
        )
        guard !acronyms.isEmpty else { return cleaned }
        let byLower = Dictionary(acronyms.map { ($0.lowercased(), $0) }, uniquingKeysWith: { a, _ in a })
        return cleaned.split(separator: " ").map { word in
            byLower[word.lowercased()] ?? String(word)
        }.joined(separator: " ")
    }

    func isAllGeneric(_ base: String, originalBaseName: String) -> Bool {
        let words = base
            .components(separatedBy: CharacterSet.alphanumerics.inverted.subtracting(CharacterSet(charactersIn: "-/")))
            .map { $0.lowercased() }
            .filter { !$0.isEmpty }
        let meaningful = words.filter { word in
            if Self.genericWords.contains(word) { return false }
            if Self.validatedISODate(word) != nil { return false }
            if word.allSatisfy({ $0.isNumber || $0 == "-" }) { return false }
            return true
        }
        return meaningful.isEmpty
    }

    // MARK: Template parsing

    enum Piece: Equatable {
        case literal(String)
        case token(Token)
    }

    static func parse(_ template: String) -> [Piece] {
        var pieces: [Piece] = []
        var literal = ""
        var index = template.startIndex
        while index < template.endIndex {
            if template[index] == "{",
               let close = template[index...].firstIndex(of: "}") {
                let name = template[template.index(after: index)..<close].lowercased()
                if let token = Token(rawValue: name) {
                    if !literal.isEmpty { pieces.append(.literal(literal)) }
                    literal = ""
                    pieces.append(.token(token))
                    index = template.index(after: close)
                    continue
                }
                // Unknown token: drop it entirely rather than leak braces.
                index = template.index(after: close)
                continue
            }
            literal.append(template[index])
            index = template.index(after: index)
        }
        if !literal.isEmpty { pieces.append(.literal(literal)) }
        return pieces
    }

    static let separatorCharacters = CharacterSet(charactersIn: " -–—_·,;|.+")
        .union(.whitespaces)

    static func isSeparatorOnly(_ text: String) -> Bool {
        text.unicodeScalars.allSatisfy { separatorCharacters.contains($0) }
    }

    /// Two literals around a dropped token: keep one separator, never both.
    static func mergeLiterals(_ lhs: String, _ rhs: String) -> String {
        if lhs.isEmpty { return rhs }
        if rhs.isEmpty { return lhs }
        if isSeparatorOnly(lhs) && isSeparatorOnly(rhs) {
            // Prefer the one with a visible separator (" - " over " ").
            let lhsVisible = lhs.trimmingCharacters(in: .whitespaces)
            return lhsVisible.isEmpty ? rhs : lhs
        }
        if isSeparatorOnly(lhs) { return rhs }
        if isSeparatorOnly(rhs) { return lhs }
        return lhs + rhs
    }

    static func sanitizeLiteral(_ text: String) -> String {
        var scalars = String.UnicodeScalarView()
        for scalar in text.unicodeScalars {
            if CharacterSet.controlCharacters.contains(scalar)
                || scalar == "/" || scalar == "\\" || scalar == ":"
            {
                scalars.append(" ")
            } else {
                scalars.append(scalar)
            }
        }
        return String(scalars)
    }

    static func trimSeparators(_ text: String) -> String {
        text.trimmingCharacters(in: separatorCharacters)
    }

    static func capped(_ text: String, to limit: Int) -> String {
        guard text.count > limit else { return text }
        let prefix = String(text.prefix(limit))
        // Cut at the last word boundary when there is one in the back half.
        if let space = prefix.lastIndex(of: " "),
           prefix.distance(from: prefix.startIndex, to: space) >= limit / 2 {
            return trimSeparators(String(prefix[..<space]))
        }
        return trimSeparators(prefix)
    }
}
