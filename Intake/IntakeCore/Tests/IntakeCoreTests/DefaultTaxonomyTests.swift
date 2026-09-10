import Foundation
import Testing
@testable import IntakeCore

struct DefaultTaxonomyTests {
    @Test(arguments: [
        ("pdf", FileCategory.documents),
        ("doc", .documents),
        ("docx", .documents),
        ("pages", .documents),
        ("txt", .documents),
        ("rtf", .documents),
        ("odt", .documents),
        ("md", .documents),
        ("xls", .spreadsheets),
        ("xlsx", .spreadsheets),
        ("numbers", .spreadsheets),
        ("csv", .spreadsheets),
        ("tsv", .spreadsheets),
        ("ppt", .presentations),
        ("pptx", .presentations),
        ("key", .presentations),
        ("odp", .presentations),
        ("png", .images),
        ("jpg", .images),
        ("jpeg", .images),
        ("heic", .images),
        ("webp", .images),
        ("gif", .images),
        ("svg", .images),
        ("tiff", .images),
        ("mp4", .video),
        ("mov", .video),
        ("m4v", .video),
        ("mkv", .video),
        ("webm", .video),
        ("mp3", .audio),
        ("m4a", .audio),
        ("wav", .audio),
        ("aiff", .audio),
        ("flac", .audio),
        ("zip", .archives),
        ("7z", .archives),
        ("rar", .archives),
        ("tar", .archives),
        ("gz", .archives),
        ("dmg", .installers),
        ("pkg", .installers),
        ("xyz", .other),
        ("", .other),
    ] as [(String, FileCategory)])
    func mapsListedExtensions(_ ext: String, _ expected: FileCategory) {
        #expect(DefaultTaxonomy.category(forExtension: ext) == expected)
    }

    @Test
    func matchingIsCaseInsensitive() {
        #expect(DefaultTaxonomy.category(forExtension: "PDF") == .documents)
        #expect(DefaultTaxonomy.category(forExtension: "Heic") == .images)
    }

    @Test
    func tarGzUsesGzAndStaysInArchives() {
        let url = URL(fileURLWithPath: "/tmp/Downloads/bundle.tar.gz")
        #expect(DefaultTaxonomy.category(for: url) == .archives)
    }

    @Test
    func disabledRuleFallsThroughToOther() {
        let rules = [
            RoutingRule(category: .documents, extensions: ["pdf"], isEnabled: false),
        ]
        #expect(DefaultTaxonomy.category(forExtension: "pdf", rules: rules) == .other)
    }

    @Test
    func defaultRulesCoverEveryCategoryExceptOther() {
        let categories = Set(DefaultTaxonomy.rules.map(\.category))
        #expect(categories.contains(.other) == false)
        for category in FileCategory.allCases where category != .other {
            #expect(categories.contains(category))
        }
    }

    @Test
    func customFolderNamesJoinTheManagedSet() {
        let rules = RuleMutation.addingCustom(
            DefaultTaxonomy.rules,
            folderName: "Design",
            extensions: ["psd"]
        )
        let names = DefaultTaxonomy.managedFolderNames(from: rules)
        #expect(names.contains("Design"))
        #expect(names.contains("Documents"))
    }
}
