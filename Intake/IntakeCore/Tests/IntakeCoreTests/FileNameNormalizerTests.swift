import Foundation
import Testing
@testable import IntakeCore

struct FileNameNormalizerTests {
    let normalizer = FileNameNormalizer()

    @Test
    func replacesUnderscoresAndCollapsesWhitespace() {
        let url = URL(fileURLWithPath: "/tmp/Quarterly_Report__Q1.pdf")
        #expect(normalizer.proposedFileName(for: url) == "Quarterly Report Q1.pdf")
    }

    @Test
    func decodesPercentEncodingAndPlusSigns() {
        let url = URL(fileURLWithPath: "/tmp/hello%20world+notes.txt")
        #expect(normalizer.proposedFileName(for: url) == "Hello World Notes.txt")
    }

    @Test
    func turnsKebabCaseIntoReadableWords() {
        let url = URL(fileURLWithPath: "/tmp/quarterly-report-q1.pdf")
        #expect(normalizer.proposedFileName(for: url) == "Quarterly Report Q1.pdf")
    }

    @Test
    func splitsCamelCaseWithoutTouchingExtensions() {
        let url = URL(fileURLWithPath: "/tmp/TeamNotes.md")
        #expect(normalizer.proposedFileName(for: url) == "Team Notes.md")
    }

    @Test
    func stripsDuplicateDownloadSuffixes() {
        #expect(
            normalizer.proposedFileName(
                for: URL(fileURLWithPath: "/tmp/Report (1).pdf")
            ) == "Report.pdf"
        )
        #expect(
            normalizer.proposedFileName(
                for: URL(fileURLWithPath: "/tmp/Report copy.docx")
            ) == "Report.docx"
        )
    }

    @Test
    func preservesHyphenatedDates() {
        let url = URL(fileURLWithPath: "/tmp/Invoice-2024-01-15.pdf")
        #expect(normalizer.proposedFileName(for: url) == "Invoice 2024-01-15.pdf")
    }

    @Test
    func preservesExtensionCase() {
        let url = URL(fileURLWithPath: "/tmp/Read_Me.DOCX")
        #expect(normalizer.proposedFileName(for: url) == "Read Me.DOCX")
    }

    @Test
    func alwaysReCasesMixedHumanishNames() {
        // C3: always run casing policy — "Family photo" becomes Title Case.
        let url = URL(fileURLWithPath: "/tmp/Family photo.heic")
        #expect(normalizer.proposedFileName(for: url) == "Family Photo.heic")
    }

    @Test
    func emptyCleanedBaseFallsBackToOriginal() {
        let url = URL(fileURLWithPath: "/tmp/___.pdf")
        #expect(normalizer.proposedFileName(for: url) == "___.pdf")
    }

    // MARK: IN-14 Title Case policy

    @Test
    func captainSmokeArcTidyCamelCaseReport() {
        let url = URL(fileURLWithPath: "/tmp/arc_Tidy_Camel_Case_Report.pdf")
        #expect(normalizer.proposedFileName(for: url) == "Arc Tidy Camel Case Report.pdf")
    }

    @Test
    func captainSmokeBoardUpdateDeckFinal() {
        let url = URL(fileURLWithPath: "/tmp/board Update deck final.pptx")
        #expect(normalizer.proposedFileName(for: url) == "Board Update Deck Final.pptx")
    }

    @Test
    func smallWordsStayLowercaseExceptEnds() {
        let url = URL(fileURLWithPath: "/tmp/the_end_of_the_world.txt")
        #expect(normalizer.proposedFileName(for: url) == "The End of the World.txt")
    }

    @Test
    func allowlistPreservesMacOS() {
        let url = URL(fileURLWithPath: "/tmp/macOS_All_New_Features.pdf")
        #expect(normalizer.proposedFileName(for: url) == "macOS All New Features.pdf")
    }

    @Test
    func helloWorldPreservesZipExtensionCase() {
        let url = URL(fileURLWithPath: "/tmp/HELLO_WORLD.ZIP")
        #expect(normalizer.proposedFileName(for: url) == "Hello World.ZIP")
    }

    @Test
    func versionTokensKeepLowercaseV() {
        #expect(
            normalizer.proposedFileName(for: URL(fileURLWithPath: "/tmp/App_v2.3_Release.dmg"))
                == "App v2.3 Release.dmg"
        )
        #expect(
            normalizer.proposedFileName(for: URL(fileURLWithPath: "/tmp/Build_B12_Notes.txt"))
                == "Build b12 Notes.txt"
        )
    }

    @Test
    func applyTitleCasePolicyIsPublicAndIdempotentOnTidyNames() {
        let once = normalizer.applyTitleCasePolicy("Arc Tidy Camel Case Report")
        let twice = normalizer.applyTitleCasePolicy(once)
        #expect(once == "Arc Tidy Camel Case Report")
        #expect(twice == once)
    }
}
