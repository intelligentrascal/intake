import Foundation

/// Which watch folders a routing rule applies to. Rules stay one global
/// ordered list; the scope only narrows where a rule is considered.
public enum RuleScope: Equatable, Hashable, Sendable {
    /// Every watch folder — the default, and what pre-1.4 rules decode as.
    case allWatchFolders
    /// Only these watch folder profile ids. An empty set applies nowhere.
    case watchFolders(Set<String>)

    public func includes(_ profileID: String) -> Bool {
        switch self {
        case .allWatchFolders:
            true
        case .watchFolders(let ids):
            ids.contains(profileID)
        }
    }

    public var isAll: Bool {
        self == .allWatchFolders
    }

    /// True when every folder `other` applies to is also in this scope.
    public func covers(_ other: RuleScope) -> Bool {
        switch (self, other) {
        case (.allWatchFolders, _):
            true
        case (.watchFolders, .allWatchFolders):
            false
        case (.watchFolders(let mine), .watchFolders(let theirs)):
            mine.isSuperset(of: theirs)
        }
    }

    /// True when at least one folder is in both scopes.
    public func overlaps(_ other: RuleScope) -> Bool {
        switch (self, other) {
        case (.allWatchFolders, .allWatchFolders):
            true
        case (.allWatchFolders, .watchFolders(let ids)), (.watchFolders(let ids), .allWatchFolders):
            !ids.isEmpty
        case (.watchFolders(let mine), .watchFolders(let theirs)):
            !mine.isDisjoint(with: theirs)
        }
    }

    /// Scope with `profileID` removed. Returns `nil` when the rule would be
    /// left applying to no folder at all.
    public func removing(_ profileID: String) -> RuleScope? {
        switch self {
        case .allWatchFolders:
            return self
        case .watchFolders(var ids):
            ids.remove(profileID)
            return ids.isEmpty ? nil : .watchFolders(ids)
        }
    }
}

extension RuleScope: Codable {
    private enum CodingKeys: String, CodingKey {
        case kind, profileIDs
    }

    private enum Kind: String, Codable {
        case all, folders
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .kind) {
        case .all:
            self = .allWatchFolders
        case .folders:
            self = .watchFolders(try container.decodeIfPresent(Set<String>.self, forKey: .profileIDs) ?? [])
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .allWatchFolders:
            try container.encode(Kind.all, forKey: .kind)
        case .watchFolders(let ids):
            try container.encode(Kind.folders, forKey: .kind)
            try container.encode(ids.sorted(), forKey: .profileIDs)
        }
    }
}

extension RoutingRule {
    /// The global rule list narrowed to the rules that apply to one watch
    /// folder, order preserved. `IngestPipeline` is built per profile from
    /// this, so its API stays unchanged.
    public static func scoped(_ rules: [RoutingRule], toWatchFolder profileID: String) -> [RoutingRule] {
        rules.filter { $0.scope.includes(profileID) }
    }
}
