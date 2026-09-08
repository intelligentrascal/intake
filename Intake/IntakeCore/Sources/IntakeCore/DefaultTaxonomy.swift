import Foundation

public enum DefaultTaxonomy: Sendable {
    public static let rules: [RoutingRule] = FileCategory.allCases.compactMap { category in
        guard category != .other else { return nil }
        return RoutingRule(category: category, extensions: category.defaultExtensions)
    }

    public static let managedFolderNames: Set<String> = Set(
        FileCategory.allCases.map(\.folderName)
    )

    public static func category(
        forExtension ext: String,
        rules: [RoutingRule] = rules
    ) -> FileCategory {
        let key = ext.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return .other }
        for rule in rules where rule.isEnabled && rule.extensions.contains(key) {
            return rule.category
        }
        return .other
    }

    public static func category(
        for url: URL,
        rules: [RoutingRule] = rules
    ) -> FileCategory {
        category(forExtension: url.pathExtension, rules: rules)
    }
}
