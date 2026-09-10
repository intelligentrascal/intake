import Foundation

public enum RuleMutation: Sendable {
    public static func moving(_ rules: [RoutingRule], from source: IndexSet, to destination: Int) -> [RoutingRule] {
        var next = rules
        let extracted = source.sorted().map { next[$0] }
        for index in source.sorted().reversed() {
            next.remove(at: index)
        }
        let removedBeforeDestination = source.filter { $0 < destination }.count
        next.insert(contentsOf: extracted, at: destination - removedBeforeDestination)
        return next
    }

    public static func settingEnabled(_ rules: [RoutingRule], id: String, isEnabled: Bool) -> [RoutingRule] {
        rules.map { rule in
            guard rule.id == id else { return rule }
            var copy = rule
            copy.isEnabled = isEnabled
            return copy
        }
    }

    public static func updating(
        _ rules: [RoutingRule],
        id: String,
        folderName: String,
        extensions: Set<String>,
        isEnabled: Bool
    ) -> [RoutingRule] {
        rules.map { rule in
            guard rule.id == id else { return rule }
            var copy = rule
            copy.folderName = folderName
            copy.extensions = Set(extensions.map { $0.lowercased() })
            copy.isEnabled = isEnabled
            return copy
        }
    }

    public static func addingCustom(
        _ rules: [RoutingRule],
        folderName: String,
        extensions: Set<String>,
        isEnabled: Bool = true
    ) -> [RoutingRule] {
        rules + [
            .custom(folderName: folderName, extensions: extensions, isEnabled: isEnabled),
        ]
    }

    public static func deletingCustom(_ rules: [RoutingRule], id: String) -> [RoutingRule] {
        rules.filter { rule in
            if rule.id == id {
                return rule.isBuiltIn
            }
            return true
        }
    }

    public static func resettingBuiltIn(_ rules: [RoutingRule], id: String) -> [RoutingRule] {
        rules.map { rule in
            guard rule.id == id, let category = rule.builtInCategory else {
                return rule
            }
            var copy = rule
            copy.folderName = category.folderName
            copy.systemImage = category.systemImage
            copy.extensions = category.defaultExtensions
            return copy
        }
    }

    public static func accepting(_ suggestion: RuleSuggestion, into rules: [RoutingRule]) -> [RoutingRule] {
        if let targetID = suggestion.targetRuleID,
           rules.contains(where: { $0.id == targetID }) {
            return rules.map { rule in
                guard rule.id == targetID else { return rule }
                var copy = rule
                copy.extensions.formUnion(suggestion.extensions)
                copy.isEnabled = true
                return copy
            }
        }
        return addingCustom(
            rules,
            folderName: suggestion.proposedFolderName,
            extensions: suggestion.extensions,
            isEnabled: true
        )
    }
}
