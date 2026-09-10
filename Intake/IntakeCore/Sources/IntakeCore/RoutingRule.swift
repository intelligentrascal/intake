import Foundation

public struct RoutingRule: Identifiable, Equatable, Sendable, Codable, Hashable {
    public var id: String
    public var folderName: String
    public var systemImage: String
    public var extensions: Set<String>
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

    public init(
        id: String,
        folderName: String,
        systemImage: String = "folder",
        extensions: Set<String>,
        isEnabled: Bool = true,
        isBuiltIn: Bool = false,
        builtInCategory: FileCategory? = nil
    ) {
        self.id = id
        self.folderName = folderName
        self.systemImage = systemImage
        self.extensions = Set(extensions.map { $0.lowercased() })
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
        isEnabled: Bool = true,
        id: String = "custom-\(UUID().uuidString)"
    ) -> RoutingRule {
        RoutingRule(
            id: id,
            folderName: folderName,
            systemImage: "folder.badge.plus",
            extensions: extensions,
            isEnabled: isEnabled,
            isBuiltIn: false,
            builtInCategory: nil
        )
    }
}
