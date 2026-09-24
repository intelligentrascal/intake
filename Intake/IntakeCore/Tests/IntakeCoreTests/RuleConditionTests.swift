import Foundation
import Testing
@testable import IntakeCore

struct RuleConditionMatchingTests {
    @Test
    func sourceDomainMatchesHostAndSubdomainsIgnoringCase() {
        let condition = RuleCondition.sourceDomain("Bank.com")
        let exact = FileFacts(name: "statement.pdf", fileExtension: "pdf", sourceURLs: [URL(string: "https://bank.com/s.pdf")!])
        let subdomain = FileFacts(name: "statement.pdf", fileExtension: "pdf", sourceURLs: [URL(string: "https://secure.BANK.com/s.pdf")!])
        let other = FileFacts(name: "statement.pdf", fileExtension: "pdf", sourceURLs: [URL(string: "https://evil-bank.com/s.pdf")!])
        #expect(condition.matches(exact))
        #expect(condition.matches(subdomain))
        #expect(condition.matches(other) == false)
    }

    @Test
    func sourceDomainFallsBackToReferrerWhenFirstURLHasNoHost() {
        let condition = RuleCondition.sourceDomain("github.com")
        let facts = FileFacts(
            name: "archive.zip",
            fileExtension: "zip",
            sourceURLs: [URL(string: "file:///tmp/archive.zip")!, URL(string: "https://github.com/foo")!]
        )
        #expect(condition.matches(facts))
    }

    @Test
    func sourceDomainNeverMatchesWithNoKnownSource() {
        let condition = RuleCondition.sourceDomain("bank.com")
        let facts = FileFacts(name: "statement.pdf", fileExtension: "pdf")
        #expect(condition.matches(facts) == false)
    }

    @Test
    func nameConditionsIgnoreCaseAndUseBaseNameOnly() {
        let facts = FileFacts(name: "Invoice_Acme.PDF", fileExtension: "pdf")
        #expect(RuleCondition.nameContains("invoice").matches(facts))
        #expect(RuleCondition.nameContains("ACME").matches(facts))
        #expect(RuleCondition.nameContains("pdf").matches(facts) == false)
        #expect(RuleCondition.nameStartsWith("invoice").matches(facts))
        #expect(RuleCondition.nameStartsWith("acme").matches(facts) == false)
    }

    @Test
    func wildcardSupportsStarAndQuestionMarkIgnoringCase() {
        let img = FileFacts(name: "IMG_0042.heic", fileExtension: "heic")
        #expect(RuleCondition.nameMatchesWildcard("img_*").matches(img))
        #expect(RuleCondition.nameMatchesWildcard("img_00??").matches(img))
        #expect(RuleCondition.nameMatchesWildcard("img_004").matches(img) == false)
        #expect(RuleCondition.nameMatchesWildcard("*0042").matches(img))
    }

    @Test
    func sizeConditionsAreInclusiveBounds() {
        let facts = FileFacts(name: "movie.mp4", fileExtension: "mp4", size: 1_000)
        #expect(RuleCondition.sizeAtLeast(1_000).matches(facts))
        #expect(RuleCondition.sizeAtLeast(1_001).matches(facts) == false)
        #expect(RuleCondition.sizeAtMost(1_000).matches(facts))
        #expect(RuleCondition.sizeAtMost(999).matches(facts) == false)
    }
}

struct RoutingRuleValidationAndMatchingTests {
    @Test
    func aRuleWithNoExtensionsAndNoConditionsIsInvalid() {
        let empty = RoutingRule.custom(folderName: "Nothing", extensions: [])
        #expect(empty.isValid == false)

        let extensionOnly = RoutingRule.custom(folderName: "Docs", extensions: ["pdf"])
        #expect(extensionOnly.isValid)

        let conditionOnly = RoutingRule.custom(
            folderName: "GitHub",
            extensions: [],
            conditions: [.sourceDomain("github.com")]
        )
        #expect(conditionOnly.isValid)
    }

    @Test
    func emptyExtensionsMatchAnyTypeWhenAConditionIsPresent() {
        let rule = RoutingRule.custom(
            folderName: "GitHub",
            extensions: [],
            conditions: [.sourceDomain("github.com")]
        )
        let zip = FileFacts(name: "release.zip", fileExtension: "zip", sourceURLs: [URL(string: "https://github.com/x")!])
        let pdf = FileFacts(name: "notes.pdf", fileExtension: "pdf", sourceURLs: [URL(string: "https://github.com/x")!])
        let elsewhere = FileFacts(name: "release.zip", fileExtension: "zip", sourceURLs: [URL(string: "https://example.com/x")!])
        #expect(rule.matches(zip))
        #expect(rule.matches(pdf))
        #expect(rule.matches(elsewhere) == false)
    }

    @Test
    func conditionsCombineWithAND() {
        let rule = RoutingRule.custom(
            folderName: "Finance",
            extensions: ["pdf"],
            conditions: [.sourceDomain("bank.com"), .sizeAtLeast(1_000)]
        )
        let matchingBoth = FileFacts(
            name: "statement.pdf",
            fileExtension: "pdf",
            size: 2_000,
            sourceURLs: [URL(string: "https://secure.bank.com/s.pdf")!]
        )
        let wrongDomain = FileFacts(
            name: "statement.pdf",
            fileExtension: "pdf",
            size: 2_000,
            sourceURLs: [URL(string: "https://example.com/s.pdf")!]
        )
        let tooSmall = FileFacts(
            name: "statement.pdf",
            fileExtension: "pdf",
            size: 10,
            sourceURLs: [URL(string: "https://secure.bank.com/s.pdf")!]
        )
        #expect(rule.matches(matchingBoth))
        #expect(rule.matches(wrongDomain) == false)
        #expect(rule.matches(tooSmall) == false)
    }
}

struct RuleConflictUnreachableTests {
    @Test
    func laterUnconditionalRuleDoesNotShadowAnEarlierMoreSpecificOne() {
        // The correct order: the specific rule first, the general one after.
        let rules = [
            RoutingRule.custom(folderName: "Finance", extensions: ["pdf"], conditions: [.sourceDomain("bank.com")]),
            RoutingRule(category: .documents, extensions: ["pdf"]),
        ]
        #expect(RuleConflict.unreachableRules(in: rules).isEmpty)
    }

    @Test
    func aGeneralEarlierRuleShadowsAMoreSpecificLaterOne() {
        // Reversed order: the general rule now steals every pdf first.
        let rules = [
            RoutingRule(category: .documents, extensions: ["pdf"]),
            RoutingRule.custom(folderName: "Finance", extensions: ["pdf"], conditions: [.sourceDomain("bank.com")]),
        ]
        let unreachable = RuleConflict.unreachableRules(in: rules)
        #expect(unreachable.count == 1)
        #expect(unreachable.first?.folderName == "Finance")
        #expect(unreachable.first?.shadowedByFolderName == "Documents")
    }

    @Test
    func anExtensionlessEarlierRuleShadowsALaterRuleWithTheSameConditions() {
        let rules = [
            RoutingRule.custom(folderName: "GitHub", extensions: [], conditions: [.sourceDomain("github.com")]),
            RoutingRule.custom(
                folderName: "GitHub Releases",
                extensions: [],
                conditions: [.sourceDomain("github.com"), .nameContains("release")]
            ),
        ]
        let unreachable = RuleConflict.unreachableRules(in: rules)
        #expect(unreachable.map(\.folderName) == ["GitHub Releases"])
    }

    @Test
    func disabledRulesNeverShadowAnything() {
        let rules = [
            RoutingRule(category: .documents, extensions: ["pdf"], isEnabled: false),
            RoutingRule.custom(folderName: "Finance", extensions: ["pdf"], conditions: [.sourceDomain("bank.com")]),
        ]
        #expect(RuleConflict.unreachableRules(in: rules).isEmpty)
    }
}
