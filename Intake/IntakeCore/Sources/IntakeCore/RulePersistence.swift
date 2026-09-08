import Foundation

public enum RulePersistence: Sendable {
    public static func applying(
        _ enabledByCategory: [String: Bool],
        to rules: [RoutingRule]
    ) -> [RoutingRule] {
        rules.map { rule in
            var copy = rule
            if let enabled = enabledByCategory[rule.category.rawValue] {
                copy.isEnabled = enabled
            }
            return copy
        }
    }

    public static func enabledByCategory(from rules: [RoutingRule]) -> [String: Bool] {
        Dictionary(uniqueKeysWithValues: rules.map { ($0.category.rawValue, $0.isEnabled) })
    }
}
