import Foundation

public struct RoutingRule: Identifiable, Equatable, Sendable, Codable, Hashable {
    public var category: FileCategory
    public var extensions: Set<String>
    public var isEnabled: Bool

    public var id: FileCategory { category }

    public var extensionsDisplay: String {
        extensions.sorted().joined(separator: ", ")
    }

    public init(category: FileCategory, extensions: Set<String>, isEnabled: Bool = true) {
        self.category = category
        self.extensions = Set(extensions.map { $0.lowercased() })
        self.isEnabled = isEnabled
    }
}
