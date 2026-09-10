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
