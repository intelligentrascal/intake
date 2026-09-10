import Foundation

public enum RulePersistence: Sendable {
    public static func applying(
        _ enabledByCategory: [String: Bool],
        to rules: [RoutingRule]
    ) -> [RoutingRule] {
        rules.map { rule in
            var copy = rule
            if let enabled = enabledByCategory[rule.id] ?? enabledByCategory[rule.category.rawValue] {
                copy.isEnabled = enabled
            }
            return copy
        }
    }

    public static func enabledByCategory(from rules: [RoutingRule]) -> [String: Bool] {
        Dictionary(uniqueKeysWithValues: rules.map { ($0.id, $0.isEnabled) })
    }

    public static func encode(_ rules: [RoutingRule]) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(rules)
    }

    public static func decode(_ data: Data) throws -> [RoutingRule] {
        try JSONDecoder().decode([RoutingRule].self, from: data)
    }

    /// Full rule list when present; otherwise default taxonomy + legacy enabled flags.
    public static func load(storedRules: Data?, enabledByCategory: [String: Bool]) -> [RoutingRule] {
        if let storedRules, let decoded = try? decode(storedRules), !decoded.isEmpty {
            return mergingMissingBuiltIns(decoded)
        }
        return applying(enabledByCategory, to: DefaultTaxonomy.rules)
    }

    public static func mergingMissingBuiltIns(_ stored: [RoutingRule]) -> [RoutingRule] {
        var result = stored
        let ids = Set(stored.map(\.id))
        for rule in DefaultTaxonomy.rules where !ids.contains(rule.id) {
            result.append(rule)
        }
        return result
    }
}

public enum SuggestionMemoryPersistence: Sendable {
    public static func encode(_ memory: SuggestionMemory) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(memory)
    }

    public static func decode(_ data: Data) throws -> SuggestionMemory {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(SuggestionMemory.self, from: data)
    }
}
