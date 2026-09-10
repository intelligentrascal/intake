import Foundation

public enum DefaultTaxonomy: Sendable {
    public static let rules: [RoutingRule] = FileCategory.allCases.compactMap { category in
        guard category != .other else { return nil }
        return RoutingRule(category: category, extensions: category.defaultExtensions)
    }

    public static let managedFolderNames: Set<String> = Set(
        FileCategory.allCases.map(\.folderName)
    )

    public static func managedFolderNames(from rules: [RoutingRule]) -> Set<String> {
        managedFolderNames.union(Set(rules.map(\.folderName)))
    }

    public static func matchingRule(
        forExtension ext: String,
        rules: [RoutingRule] = rules
    ) -> RoutingRule? {
        let key = ext.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return nil }
        for rule in rules where rule.isEnabled && rule.extensions.contains(key) {
            return rule
        }
        return nil
    }

    public static func matchingRule(
        for url: URL,
        rules: [RoutingRule] = rules
    ) -> RoutingRule? {
        matchingRule(forExtension: url.pathExtension, rules: rules)
    }

    public static func category(
        forExtension ext: String,
        rules: [RoutingRule] = rules
    ) -> FileCategory {
        matchingRule(forExtension: ext, rules: rules)?.category ?? .other
    }

    public static func category(
        for url: URL,
        rules: [RoutingRule] = rules
    ) -> FileCategory {
        category(forExtension: url.pathExtension, rules: rules)
    }

    public static func destinationFolderName(
        forExtension ext: String,
        rules: [RoutingRule] = rules
    ) -> String {
        matchingRule(forExtension: ext, rules: rules)?.folderName ?? FileCategory.other.folderName
    }
}
