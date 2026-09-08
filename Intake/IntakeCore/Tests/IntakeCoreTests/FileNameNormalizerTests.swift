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
        #expect(normalizer.proposedFileName(for: url) == "hello world notes.txt")
    }

    @Test
    func preservesExtensionCase() {
        let url = URL(fileURLWithPath: "/tmp/Read_Me.DOCX")
        #expect(normalizer.proposedFileName(for: url) == "Read Me.DOCX")
    }

    @Test
    func leavesAlreadyReadableNamesAlone() {
        let url = URL(fileURLWithPath: "/tmp/Family photo.heic")
        #expect(normalizer.proposedFileName(for: url) == "Family photo.heic")
    }

    @Test
    func emptyCleanedBaseFallsBackToOriginal() {
        let url = URL(fileURLWithPath: "/tmp/___.pdf")
        #expect(normalizer.proposedFileName(for: url) == "___.pdf")
    }
}
