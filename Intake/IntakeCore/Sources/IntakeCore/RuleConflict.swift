import Foundation

public struct RuleConflict: Identifiable, Equatable, Sendable {
    public var fileExtension: String
    public var winnerID: String
    public var winnerFolderName: String
    public var loserFolderNames: [String]

    public var id: String { fileExtension }

    public var summary: String {
        let others = loserFolderNames.joined(separator: ", ")
        return ".\(fileExtension) matches \(winnerFolderName) first; also listed under \(others)."
    }

    public init(
        fileExtension: String,
        winnerID: String,
        winnerFolderName: String,
        loserFolderNames: [String]
    ) {
        self.fileExtension = fileExtension
        self.winnerID = winnerID
        self.winnerFolderName = winnerFolderName
        self.loserFolderNames = loserFolderNames
    }

    /// A rule an earlier enabled rule already matches everything of, so it can
    /// never be reached no matter its own conditions.
    public struct UnreachableRule: Identifiable, Equatable, Sendable {
        public var ruleID: String
        public var folderName: String
        public var shadowedByID: String
        public var shadowedByFolderName: String

        public var id: String { ruleID }

        public var summary: String {
            "\(folderName) can never match — \(shadowedByFolderName) always matches first."
        }

        public init(ruleID: String, folderName: String, shadowedByID: String, shadowedByFolderName: String) {
            self.ruleID = ruleID
            self.folderName = folderName
            self.shadowedByID = shadowedByID
            self.shadowedByFolderName = shadowedByFolderName
        }
    }

    /// Flags rules that an earlier, enabled rule already fully subsumes: the
    /// earlier rule matches every extension and file the later rule would, so
    /// first-match-wins means the later rule is dead code.
    public static func unreachableRules(in rules: [RoutingRule]) -> [UnreachableRule] {
        let enabled = rules.filter(\.isEnabled)
        var result: [UnreachableRule] = []
        for (index, rule) in enabled.enumerated() where rule.isValid {
            for earlier in enabled[..<index] where subsumes(earlier, rule) {
                result.append(
                    UnreachableRule(
                        ruleID: rule.id,
                        folderName: rule.folderName,
                        shadowedByID: earlier.id,
                        shadowedByFolderName: earlier.folderName
                    )
                )
                break
            }
        }
        return result
    }

    /// True when `earlier` matches every file `later` would: `earlier`'s
    /// extension set is empty or a superset of `later`'s, and every one of
    /// `earlier`'s conditions also appears in `later`'s (so `later` can never
    /// be more permissive than `earlier`).
    static func subsumes(_ earlier: RoutingRule, _ later: RoutingRule) -> Bool {
        let extensionsCoverAll: Bool
        if earlier.extensions.isEmpty {
            extensionsCoverAll = true
        } else if later.extensions.isEmpty {
            extensionsCoverAll = false
        } else {
            extensionsCoverAll = earlier.extensions.isSuperset(of: later.extensions)
        }
        guard extensionsCoverAll else { return false }
        return Set(earlier.conditions).isSubset(of: Set(later.conditions))
    }

    public static func inRules(_ rules: [RoutingRule]) -> [RuleConflict] {
        var owners: [String: [RoutingRule]] = [:]
        for rule in rules where rule.isEnabled {
            for ext in rule.extensions {
                owners[ext, default: []].append(rule)
            }
        }
        return owners.keys.sorted().compactMap { ext in
            let claimed = owners[ext] ?? []
            guard claimed.count > 1, let winner = claimed.first else {
                return nil
            }
            return RuleConflict(
                fileExtension: ext,
                winnerID: winner.id,
                winnerFolderName: winner.folderName,
                loserFolderNames: claimed.dropFirst().map(\.folderName)
            )
        }
    }
}
