import Foundation

public struct RoutingRule: Identifiable, Equatable, Sendable, Codable, Hashable {
    public var id: String
    public var folderName: String
    public var systemImage: String
    public var extensions: Set<String>
    /// Extra requirements combined with AND, beyond the extension set. An
    /// empty extension set means "any type", but only once at least one
    /// condition is present — see `isValid`.
    public var conditions: [RuleCondition]
    public var isEnabled: Bool
    public var isBuiltIn: Bool
    public var builtInCategory: FileCategory?

    /// Built-in taxonomy category, or `.other` for custom rules.
    public var category: FileCategory {
        builtInCategory ?? .other
    }

    public var extensionsDisplay: String {
        ExtensionToken.display(extensions)
    }

    /// A rule with no extensions and no conditions can never match anything
    /// and can't be saved.
    public var isValid: Bool {
        !extensions.isEmpty || !conditions.isEmpty
    }

    public init(
        id: String,
        folderName: String,
        systemImage: String = "folder",
        extensions: Set<String>,
        conditions: [RuleCondition] = [],
        isEnabled: Bool = true,
        isBuiltIn: Bool = false,
        builtInCategory: FileCategory? = nil
    ) {
        self.id = id
        self.folderName = folderName
        self.systemImage = systemImage
        self.extensions = Set(extensions.map { $0.lowercased() })
        self.conditions = conditions
        self.isEnabled = isEnabled
        self.isBuiltIn = isBuiltIn
        self.builtInCategory = builtInCategory
    }

    public init(category: FileCategory, extensions: Set<String>, isEnabled: Bool = true) {
        self.init(
            id: category.rawValue,
            folderName: category.folderName,
            systemImage: category.systemImage,
            extensions: extensions,
            isEnabled: isEnabled,
            isBuiltIn: true,
            builtInCategory: category
        )
    }

    public static func custom(
        folderName: String,
        extensions: Set<String>,
        conditions: [RuleCondition] = [],
        isEnabled: Bool = true,
        id: String = "custom-\(UUID().uuidString)"
    ) -> RoutingRule {
        RoutingRule(
            id: id,
            folderName: folderName,
            systemImage: "folder.badge.plus",
            extensions: extensions,
            conditions: conditions,
            isEnabled: isEnabled,
            isBuiltIn: false,
            builtInCategory: nil
        )
    }

    /// Whether this rule matches the given file. The extension set matches
    /// any type when empty; every condition must also match (AND).
    public func matches(_ facts: FileFacts) -> Bool {
        let extensionMatches = extensions.isEmpty || extensions.contains(facts.fileExtension.lowercased())
        guard extensionMatches else { return false }
        return conditions.allSatisfy { $0.matches(facts) }
    }

    private enum CodingKeys: String, CodingKey {
        case id, folderName, systemImage, extensions, conditions, isEnabled, isBuiltIn, builtInCategory
    }

    /// Rules saved before conditions existed decode with an empty list, so
    /// persisted 1.2 rules load unchanged.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        folderName = try container.decode(String.self, forKey: .folderName)
        systemImage = try container.decode(String.self, forKey: .systemImage)
        extensions = try container.decode(Set<String>.self, forKey: .extensions)
        conditions = try container.decodeIfPresent([RuleCondition].self, forKey: .conditions) ?? []
        isEnabled = try container.decode(Bool.self, forKey: .isEnabled)
        isBuiltIn = try container.decode(Bool.self, forKey: .isBuiltIn)
        builtInCategory = try container.decodeIfPresent(FileCategory.self, forKey: .builtInCategory)
    }
}
