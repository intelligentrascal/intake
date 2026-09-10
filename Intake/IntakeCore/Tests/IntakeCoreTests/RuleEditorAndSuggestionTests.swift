import Foundation
import Testing
@testable import IntakeCore

struct ExtensionTokenTests {
    @Test
    func parsesCommaSeparatedTokensAndStripsDots() {
        let parsed = try? ExtensionToken.parse(" PSD, .Ai, png ").get()
        #expect(parsed == ["psd", "ai", "png"])
        #expect(ExtensionToken.display(["png", "psd"]) == "png, psd")
    }

    @Test
    func rejectsEmptyAndInvalidTokens() {
        #expect(ExtensionToken.parse("  , , ") == .failure(.empty))
        #expect(ExtensionToken.parse("foo.bar") == .failure(.invalid("foo.bar")))
        #expect(ExtensionToken.parse("../etc") == .failure(.invalid("../etc")))
        #expect(ExtensionToken.parse("*") == .failure(.invalid("*")))
    }

    @Test
    func folderNamesRejectPathPieces() {
        #expect(FolderNameToken.parse(" Design ") == .success("Design"))
        #expect(FolderNameToken.parse("") == .failure(.empty))
        #expect(FolderNameToken.parse("foo/bar") == .failure(.invalid))
        #expect(FolderNameToken.parse("foo:bar") == .failure(.invalid))
    }
}

struct RuleConflictAndMutationTests {
    @Test
    func firstEnabledRuleWinsConflictingExtensions() {
        let rules = [
            RoutingRule(category: .images, extensions: ["png", "psd"], isEnabled: true),
            RoutingRule.custom(folderName: "Design", extensions: ["psd", "ai"], isEnabled: true),
        ]
        #expect(DefaultTaxonomy.category(forExtension: "psd", rules: rules) == .images)
        #expect(DefaultTaxonomy.destinationFolderName(forExtension: "psd", rules: rules) == "Images")
        #expect(DefaultTaxonomy.destinationFolderName(forExtension: "ai", rules: rules) == "Design")

        let conflicts = RuleConflict.inRules(rules)
        #expect(conflicts.map(\.fileExtension) == ["psd"])
        #expect(conflicts.first?.winnerFolderName == "Images")
        #expect(conflicts.first?.loserFolderNames == ["Design"])
    }

    @Test
    func reorderingChangesTheWinner() {
        let images = RoutingRule(category: .images, extensions: ["psd"], isEnabled: true)
        let design = RoutingRule.custom(folderName: "Design", extensions: ["psd"], isEnabled: true)
        let reordered = RuleMutation.moving([images, design], from: IndexSet(integer: 1), to: 0)
        #expect(DefaultTaxonomy.destinationFolderName(forExtension: "psd", rules: reordered) == "Design")
    }

    @Test
    func addUpdateDeleteAndResetPersistTheTaxonomy() {
        var rules = DefaultTaxonomy.rules
        rules = RuleMutation.addingCustom(rules, folderName: "Design", extensions: ["psd", "ai"])
        #expect(rules.contains { $0.folderName == "Design" && $0.extensions == ["psd", "ai"] && !$0.isBuiltIn })

        let customID = rules.first { !$0.isBuiltIn }!.id
        rules = RuleMutation.updating(
            rules,
            id: customID,
            folderName: "Creative",
            extensions: ["psd"],
            isEnabled: false
        )
        #expect(rules.first { $0.id == customID }?.folderName == "Creative")
        #expect(rules.first { $0.id == customID }?.isEnabled == false)

        rules = RuleMutation.deletingCustom(rules, id: customID)
        #expect(rules.contains { $0.id == customID } == false)

        var documents = rules.first { $0.category == .documents }!
        documents.folderName = "Docs"
        documents.extensions = ["pdf"]
        rules = rules.map { $0.id == documents.id ? documents : $0 }
        rules = RuleMutation.resettingBuiltIn(rules, id: documents.id)
        let reset = rules.first { $0.id == documents.id }
        #expect(reset?.folderName == "Documents")
        #expect(reset?.extensions == FileCategory.documents.defaultExtensions)
    }

    @Test
    func acceptingASuggestionAddsToAnExistingRuleOrCreatesCustom() {
        let withImages = RuleMutation.accepting(
            RuleSuggestion(
                id: "ext:psd",
                title: "Images",
                subtitle: "Often seeing .psd → add to Images?",
                extensions: ["psd"],
                proposedFolderName: "Images",
                systemImage: "photo",
                targetRuleID: FileCategory.images.rawValue,
                hitCount: 8
            ),
            into: DefaultTaxonomy.rules
        )
        let images = withImages.first { $0.category == .images }
        #expect(images?.extensions.contains("psd") == true)
        #expect(images?.isEnabled == true)

        let created = RuleMutation.accepting(
            RuleSuggestion(
                id: "ext:ai",
                title: "Design",
                subtitle: "Create folder Design for .ai",
                extensions: ["ai"],
                proposedFolderName: "Design",
                systemImage: "folder.badge.plus",
                targetRuleID: nil,
                hitCount: 8
            ),
            into: DefaultTaxonomy.rules
        )
        #expect(created.contains { $0.folderName == "Design" && $0.extensions.contains("ai") && !$0.isBuiltIn })
    }
}

struct RulePersistenceRoundTripTests {
    @Test
    func storesFullEditableRulesAndMigratesLegacyEnabledFlags() throws {
        var rules = DefaultTaxonomy.rules
        rules = RuleMutation.addingCustom(rules, folderName: "Design", extensions: ["psd"])
        rules[0].isEnabled = false
        let data = try RulePersistence.encode(rules)
        let decoded = try RulePersistence.decode(data)
        #expect(decoded == rules)

        let migrated = RulePersistence.load(
            storedRules: nil,
            enabledByCategory: ["documents": false]
        )
        #expect(migrated.first { $0.category == .documents }?.isEnabled == false)
        #expect(migrated.first { $0.category == .images }?.isEnabled == true)
        #expect(migrated.contains { $0.folderName == "Design" } == false)

        let loaded = RulePersistence.load(storedRules: data, enabledByCategory: [:])
        #expect(loaded.contains { $0.folderName == "Design" })
        #expect(loaded.first { $0.category == .documents }?.isEnabled == false)
    }

    @Test
    func mergesBuiltInsMissingFromOlderSavedLists() throws {
        let customOnly = [RoutingRule.custom(folderName: "Design", extensions: ["ai"])]
        let data = try RulePersistence.encode(customOnly)
        let loaded = RulePersistence.load(storedRules: data, enabledByCategory: [:])
        #expect(loaded.contains { $0.category == .documents })
        #expect(loaded.contains { $0.folderName == "Design" })
    }
}

struct RuleSuggestionEngineTests {
    @Test
    func coldStartStaysEmptyWithoutEnoughSignal() {
        let activity = (0..<3).map {
            ActivityEntry(kind: .skipped, detail: "skip", fileName: "file-\($0).psd")
        }
        let suggestions = RuleSuggestionEngine.suggestions(
            activity: activity,
            watchRootHistogram: ["psd": 2],
            rules: DefaultTaxonomy.rules,
            memory: SuggestionMemory()
        )
        #expect(suggestions.isEmpty)
    }

    @Test
    func histogramHitsProduceASuggestionForUncoveredTypes() {
        let suggestions = RuleSuggestionEngine.suggestions(
            activity: [],
            watchRootHistogram: ["psd": 8],
            rules: DefaultTaxonomy.rules,
            memory: SuggestionMemory()
        )
        #expect(suggestions.count == 1)
        #expect(suggestions.first?.extensions == ["psd"])
        #expect(suggestions.first?.proposedFolderName == "Images")
        #expect(suggestions.first?.targetRuleID == FileCategory.images.rawValue)
    }

    @Test
    func recentActivityCanQualifyWithFewerThanEightHits() {
        let now = Date()
        let activity = (0..<5).map { index in
            ActivityEntry(
                date: now.addingTimeInterval(-Double(index) * 3600),
                kind: .moved,
                detail: "Other",
                fileName: "logo-\(index).ai",
                destinationFolder: "Other"
            )
        }
        let suggestions = RuleSuggestionEngine.suggestions(
            activity: activity,
            watchRootHistogram: [:],
            rules: DefaultTaxonomy.rules,
            memory: SuggestionMemory(),
            now: now
        )
        #expect(suggestions.first?.extensions == ["ai"])
        #expect(suggestions.first?.proposedFolderName == "Design")
        #expect(suggestions.first?.targetRuleID == nil)
    }

    @Test
    func coveredExtensionsAreNeverSuggested() {
        var rules = DefaultTaxonomy.rules
        rules = RuleMutation.accepting(
            RuleSuggestion(
                id: "ext:psd",
                title: "Images",
                subtitle: "",
                extensions: ["psd"],
                proposedFolderName: "Images",
                systemImage: "photo",
                targetRuleID: FileCategory.images.rawValue,
                hitCount: 8
            ),
            into: rules
        )
        let suggestions = RuleSuggestionEngine.suggestions(
            activity: [],
            watchRootHistogram: ["psd": 20, "png": 20],
            rules: rules,
            memory: SuggestionMemory()
        )
        #expect(suggestions.contains { $0.extensions.contains("psd") } == false)
        #expect(suggestions.contains { $0.extensions.contains("png") } == false)
    }

    @Test
    func dismissHidesForCooldownAndNeverSuppressesUntilReset() {
        let now = Date()
        let base = RuleSuggestionEngine.suggestions(
            activity: [],
            watchRootHistogram: ["psd": 9],
            rules: DefaultTaxonomy.rules,
            memory: SuggestionMemory(),
            now: now
        )
        guard let suggestion = base.first else {
            Issue.record("expected a .psd suggestion")
            return
        }

        let dismissed = SuggestionMemory().dismissing(suggestion, now: now)
        #expect(
            RuleSuggestionEngine.suggestions(
                activity: [],
                watchRootHistogram: ["psd": 9],
                rules: DefaultTaxonomy.rules,
                memory: dismissed,
                now: now
            ).isEmpty
        )
        #expect(
            RuleSuggestionEngine.suggestions(
                activity: [],
                watchRootHistogram: ["psd": 9],
                rules: DefaultTaxonomy.rules,
                memory: dismissed,
                now: now.addingTimeInterval(SuggestionMemory.dismissCooldown + 1)
            ).isEmpty == false
        )

        let never = SuggestionMemory().nevering(suggestion)
        #expect(
            RuleSuggestionEngine.suggestions(
                activity: [],
                watchRootHistogram: ["psd": 9],
                rules: DefaultTaxonomy.rules,
                memory: never,
                now: now.addingTimeInterval(SuggestionMemory.dismissCooldown * 4)
            ).isEmpty
        )
    }
}

struct WatchRootHistogramTests {
    @Test
    func countsLooseRootExtensionsAndIgnoresPartials() throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory.appendingPathComponent(
            "intake-histogram-\(UUID().uuidString)",
            isDirectory: true
        )
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: root) }

        try Data().write(to: root.appendingPathComponent("one.psd"))
        try Data().write(to: root.appendingPathComponent("two.psd"))
        try Data().write(to: root.appendingPathComponent("three.ai"))
        try Data().write(to: root.appendingPathComponent("movie.mp4.crdownload"))
        let images = root.appendingPathComponent("Images", isDirectory: true)
        try fileManager.createDirectory(at: images, withIntermediateDirectories: true)
        try Data().write(to: images.appendingPathComponent("nested.psd"))

        let counts = WatchRootHistogram.counts(watchFolder: root, fileManager: fileManager)
        #expect(counts["psd"] == 2)
        #expect(counts["ai"] == 1)
        #expect(counts["crdownload"] == nil)
    }
}

struct OpenRouterSuggestionTests {
    @Test
    func buildsAChatURLAndNeverPutsFileBytesInTheBody() throws {
        let url = OpenRouterRequestBuilder.chatCompletionsURL(
            baseURL: "https://openrouter.ai/api/v1/"
        )
        #expect(url?.absoluteString == "https://openrouter.ai/api/v1/chat/completions")
        let body = try OpenRouterRequestBuilder.body(
            model: "openai/gpt-4o-mini",
            fileName: "secret.psd",
            folders: ["Images", "Design"]
        )
        let json = String(decoding: body, as: UTF8.self)
        #expect(json.contains("secret.psd"))
        #expect(json.contains("Images"))
        #expect(json.lowercased().contains("never file contents"))
    }

    @Test
    func parsesFolderJSONFromAChatCompletion() throws {
        let payload = """
        {"choices":[{"message":{"content":"```json\\n{\\"folder\\":\\"Design\\",\\"reason\\":\\"Adobe file\\"}\\n```"}}]}
        """
        let content = try OpenRouterChatParser.messageContent(from: Data(payload.utf8))
        let suggestion = try OpenRouterChatParser.folderSuggestion(from: content)
        #expect(suggestion.folderName == "Design")
        #expect(suggestion.reason == "Adobe file")
        #expect(OpenRouterChatParser.httpErrorMessage(statusCode: 401).contains("Unauthorized"))
        #expect(OpenRouterChatParser.httpErrorMessage(statusCode: 429).contains("Rate limited"))
    }
}
