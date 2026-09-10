import Foundation

public struct RuleSuggestion: Identifiable, Equatable, Sendable, Codable {
    public var id: String
    public var title: String
    public var subtitle: String
    public var extensions: Set<String>
    public var proposedFolderName: String
    public var systemImage: String
    public var targetRuleID: String?
    public var hitCount: Int

    public init(
        id: String,
        title: String,
        subtitle: String,
        extensions: Set<String>,
        proposedFolderName: String,
        systemImage: String,
        targetRuleID: String?,
        hitCount: Int
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.extensions = extensions
        self.proposedFolderName = proposedFolderName
        self.systemImage = systemImage
        self.targetRuleID = targetRuleID
        self.hitCount = hitCount
    }
}

public struct SuggestionMemory: Equatable, Sendable, Codable {
    public var dismissedUntil: [String: Date]
    public var neverExtensions: Set<String>

    public static let dismissCooldown: TimeInterval = 30 * 24 * 60 * 60

    public init(dismissedUntil: [String: Date] = [:], neverExtensions: Set<String> = []) {
        self.dismissedUntil = dismissedUntil
        self.neverExtensions = neverExtensions
    }

    public func dismissing(_ suggestion: RuleSuggestion, now: Date = Date()) -> SuggestionMemory {
        var next = self
        next.dismissedUntil[suggestion.id] = now.addingTimeInterval(Self.dismissCooldown)
        return next
    }

    public func nevering(_ suggestion: RuleSuggestion) -> SuggestionMemory {
        var next = self
        next.neverExtensions.formUnion(suggestion.extensions)
        next.dismissedUntil[suggestion.id] = nil
        return next
    }

    public func isDismissed(_ id: String, now: Date = Date()) -> Bool {
        guard let until = dismissedUntil[id] else { return false }
        return until > now
    }

    public func neverIncludes(_ ext: String) -> Bool {
        neverExtensions.contains(ext.lowercased())
    }
}

public enum RuleSuggestionEngine: Sendable {
    public static let minimumHits = 8
    public static let recentHitCount = 5
    public static let recentWindow: TimeInterval = 14 * 24 * 60 * 60
    public static let maximumSuggestions = 5

    public static func suggestions(
        activity: [ActivityEntry],
        watchRootHistogram: [String: Int],
        rules: [RoutingRule],
        memory: SuggestionMemory,
        now: Date = Date()
    ) -> [RuleSuggestion] {
        let covered = coveredExtensions(in: rules)
        var totals: [String: Int] = watchRootHistogram.mapValues { $0 }
        var recent: [String: Int] = [:]

        for entry in activity {
            guard let ext = fileExtension(from: entry) else { continue }
            if shouldCount(entry) {
                totals[ext, default: 0] += 1
            }
            if entry.date >= now.addingTimeInterval(-recentWindow) {
                recent[ext, default: 0] += 1
            }
        }

        var ranked: [RuleSuggestion] = []
        for ext in totals.keys.sorted() {
            let key = ext.lowercased()
            if key.isEmpty || covered.contains(key) { continue }
            if memory.neverIncludes(key) { continue }
            let hits = totals[key] ?? 0
            let recentHits = recent[key] ?? 0
            let qualifies = hits >= minimumHits || recentHits >= recentHitCount
            guard qualifies else { continue }
            let suggestion = makeSuggestion(extension: key, hitCount: max(hits, recentHits), rules: rules)
            if memory.isDismissed(suggestion.id, now: now) { continue }
            ranked.append(suggestion)
        }

        return Array(
            ranked
                .sorted { lhs, rhs in
                    if lhs.hitCount != rhs.hitCount {
                        return lhs.hitCount > rhs.hitCount
                    }
                    return lhs.id < rhs.id
                }
                .prefix(maximumSuggestions)
        )
    }

    public static func coveredExtensions(in rules: [RoutingRule]) -> Set<String> {
        var result: Set<String> = []
        for rule in rules where rule.isEnabled {
            result.formUnion(rule.extensions)
        }
        return result
    }

    public static func proposedMapping(
        forExtension ext: String,
        rules: [RoutingRule]
    ) -> (folderName: String, systemImage: String, targetRuleID: String?) {
        let key = ext.lowercased()
        if let category = affinities[key] {
            if let rule = rules.first(where: { $0.builtInCategory == category }) {
                return (rule.folderName, rule.systemImage, rule.id)
            }
            return (category.folderName, category.systemImage, nil)
        }
        if let customName = customFolderAffinities[key] {
            if let rule = rules.first(where: { $0.folderName.compare(customName, options: .caseInsensitive) == .orderedSame }) {
                return (rule.folderName, rule.systemImage, rule.id)
            }
            return (customName, "folder.badge.plus", nil)
        }
        let fallback = key.uppercased()
        if let rule = rules.first(where: { $0.folderName.compare(fallback, options: .caseInsensitive) == .orderedSame }) {
            return (rule.folderName, rule.systemImage, rule.id)
        }
        return (fallback, "folder.badge.plus", nil)
    }

    private static func makeSuggestion(
        extension ext: String,
        hitCount: Int,
        rules: [RoutingRule]
    ) -> RuleSuggestion {
        let mapping = proposedMapping(forExtension: ext, rules: rules)
        let title: String
        let subtitle: String
        if mapping.targetRuleID != nil {
            title = mapping.folderName
            subtitle = "Often seeing .\(ext) → add to \(mapping.folderName)?"
        } else {
            title = mapping.folderName
            subtitle = "Create folder \(mapping.folderName) for .\(ext)"
        }
        return RuleSuggestion(
            id: "ext:\(ext)",
            title: title,
            subtitle: subtitle,
            extensions: [ext],
            proposedFolderName: mapping.folderName,
            systemImage: mapping.systemImage,
            targetRuleID: mapping.targetRuleID,
            hitCount: hitCount
        )
    }

    private static func shouldCount(_ entry: ActivityEntry) -> Bool {
        switch entry.kind {
        case .skipped, .error:
            return true
        case .moved:
            return entry.destinationFolder == FileCategory.other.folderName
        case .renamed, .deleted, .folderRemoved:
            return false
        }
    }

    private static func fileExtension(from entry: ActivityEntry) -> String? {
        let name = entry.fileName
        let ext = URL(fileURLWithPath: name).pathExtension.lowercased()
        return ext.isEmpty ? nil : ext
    }

    /// Extra types that belong on an existing default bucket.
    private static let affinities: [String: FileCategory] = [
        "psd": .images,
        "psb": .images,
        "bmp": .images,
        "ico": .images,
        "raw": .images,
        "cr2": .images,
        "nef": .images,
        "arw": .images,
        "dng": .images,
        "heif": .images,
        "avif": .images,
        "epub": .documents,
        "mobi": .documents,
        "azw3": .documents,
        "flac": .audio,
        "ogg": .audio,
        "aac": .audio,
        "avi": .video,
        "wmv": .video,
        "mpeg": .video,
    ]

    /// Types that deserve their own lazy folder rather than Other.
    private static let customFolderAffinities: [String: String] = [
        "ai": "Design",
        "sketch": "Design",
        "fig": "Design",
        "figma": "Design",
        "indd": "Design",
        "xd": "Design",
        "afdesign": "Design",
        "otf": "Fonts",
        "ttf": "Fonts",
        "woff": "Fonts",
        "woff2": "Fonts",
        "obj": "3D",
        "fbx": "3D",
        "gltf": "3D",
        "glb": "3D",
        "blend": "3D",
    ]
}
