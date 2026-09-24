import Foundation

/// An extra requirement a `RoutingRule` can carry beyond its extension set.
/// All of a rule's conditions are combined with AND. Matching only ever looks
/// at `FileFacts` gathered from local file-system metadata — no network.
public enum RuleCondition: Equatable, Sendable, Hashable, Codable {
    /// The file's source host, or any of its parent domains, ignoring case.
    /// `sourceDomain("bank.com")` matches `secure.bank.com`.
    case sourceDomain(String)
    /// The file name without its extension contains this text, ignoring case.
    case nameContains(String)
    /// The file name without its extension starts with this text, ignoring case.
    case nameStartsWith(String)
    /// The file name without its extension matches this `*`/`?` wildcard pattern, ignoring case.
    case nameMatchesWildcard(String)
    /// File size in bytes, inclusive lower bound.
    case sizeAtLeast(Int64)
    /// File size in bytes, inclusive upper bound.
    case sizeAtMost(Int64)

    public enum Kind: String, CaseIterable, Sendable {
        case sourceDomain
        case nameContains
        case nameStartsWith
        case nameMatchesWildcard
        case sizeAtLeast
        case sizeAtMost

        public var label: String {
            switch self {
            case .sourceDomain: "Source is"
            case .nameContains: "Name contains"
            case .nameStartsWith: "Name starts with"
            case .nameMatchesWildcard: "Name matches"
            case .sizeAtLeast: "Size at least"
            case .sizeAtMost: "Size at most"
            }
        }
    }

    public var kind: Kind {
        switch self {
        case .sourceDomain: .sourceDomain
        case .nameContains: .nameContains
        case .nameStartsWith: .nameStartsWith
        case .nameMatchesWildcard: .nameMatchesWildcard
        case .sizeAtLeast: .sizeAtLeast
        case .sizeAtMost: .sizeAtMost
        }
    }

    /// A short human-readable summary, e.g. "from bank.com" or "at least 10 MB".
    public var summary: String {
        switch self {
        case .sourceDomain(let domain):
            "from \(domain)"
        case .nameContains(let text):
            "name contains “\(text)”"
        case .nameStartsWith(let text):
            "name starts with “\(text)”"
        case .nameMatchesWildcard(let pattern):
            "name matches “\(pattern)”"
        case .sizeAtLeast(let bytes):
            "at least \(Self.formattedSize(bytes))"
        case .sizeAtMost(let bytes):
            "at most \(Self.formattedSize(bytes))"
        }
    }

    public func matches(_ facts: FileFacts) -> Bool {
        switch self {
        case .sourceDomain(let domain):
            guard let host = facts.sourceHost else { return false }
            return Self.host(host, matchesDomain: domain)
        case .nameContains(let text):
            let needle = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !needle.isEmpty else { return true }
            return facts.baseName.range(of: needle, options: .caseInsensitive) != nil
        case .nameStartsWith(let text):
            let needle = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !needle.isEmpty else { return true }
            return facts.baseName.range(
                of: needle,
                options: [.caseInsensitive, .anchored]
            ) != nil
        case .nameMatchesWildcard(let pattern):
            return Self.wildcard(pattern, matches: facts.baseName)
        case .sizeAtLeast(let bytes):
            return facts.size >= bytes
        case .sizeAtMost(let bytes):
            return facts.size <= bytes
        }
    }

    /// `host` matches `domain` when it is the same host or any subdomain of it,
    /// ignoring case: `secure.bank.com` matches `bank.com`.
    static func host(_ host: String, matchesDomain domain: String) -> Bool {
        let host = host.lowercased()
        let domain = domain.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !domain.isEmpty else { return false }
        return host == domain || host.hasSuffix(".\(domain)")
    }

    static func wildcard(_ pattern: String, matches text: String) -> Bool {
        let trimmed = pattern.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return true }
        var regexPattern = "^"
        for character in trimmed {
            switch character {
            case "*":
                regexPattern += ".*"
            case "?":
                regexPattern += "."
            default:
                regexPattern += NSRegularExpression.escapedPattern(for: String(character))
            }
        }
        regexPattern += "$"
        guard let regex = try? NSRegularExpression(pattern: regexPattern, options: [.caseInsensitive]) else {
            return false
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.firstMatch(in: text, options: [], range: range) != nil
    }

    private static func formattedSize(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}
