import Foundation
import Testing
@testable import IntakeCore

struct DownloadIgnorePolicyTests {
    let policy = DownloadIgnorePolicy()

    @Test
    func keepsStableDownloads() {
        let url = URL(fileURLWithPath: "/tmp/Downloads/Quarterly Report.pdf")
        #expect(policy.shouldIgnore(url: url, kind: .appeared, isDirectory: false) == false)
        #expect(policy.shouldIgnore(url: url, kind: .modified, isDirectory: false) == false)
    }

    @Test(arguments: [
        "Invoice.pdf.download",
        "photo.jpg.crdownload",
        "archive.zip.part",
        "movie.mp4.partial",
        "setup.tmp",
        "payload.temp",
        "Safari.downloading",
    ])
    func ignoresIncompleteExtensions(_ name: String) {
        let url = URL(fileURLWithPath: "/tmp/Downloads/\(name)")
        #expect(policy.shouldIgnore(url: url, kind: .appeared, isDirectory: false))
    }

    @Test
    func ignoresSafariDownloadBundles() {
        let bundle = URL(fileURLWithPath: "/tmp/Downloads/File.pdf.download", isDirectory: true)
        #expect(policy.shouldIgnore(url: bundle, kind: .appeared, isDirectory: true))
        let nested = URL(fileURLWithPath: "/tmp/Downloads/File.pdf.download/File.pdf")
        #expect(policy.shouldIgnore(url: nested, kind: .appeared, isDirectory: false))
    }

    @Test
    func ignoresQuarantineMetadataChurn() {
        let url = URL(fileURLWithPath: "/tmp/Downloads/ready.pdf")
        #expect(policy.shouldIgnore(url: url, kind: .metadataOnly, isDirectory: false))
    }

    @Test
    func ignoresDotfilesAndFinderNoise() {
        #expect(
            policy.shouldIgnore(
                url: URL(fileURLWithPath: "/tmp/Downloads/.DS_Store"),
                kind: .appeared,
                isDirectory: false
            )
        )
        #expect(
            policy.shouldIgnore(
                url: URL(fileURLWithPath: "/tmp/Downloads/.localized"),
                kind: .appeared,
                isDirectory: false
            )
        )
    }

    @Test
    func ignoresChromeUnconfirmedAndTempNames() {
        #expect(
            policy.shouldIgnore(
                url: URL(fileURLWithPath: "/tmp/Downloads/Unconfirmed 12345.crdownload"),
                kind: .appeared,
                isDirectory: false
            )
        )
        #expect(
            policy.shouldIgnore(
                url: URL(fileURLWithPath: "/tmp/Downloads/.com.google.Chrome.a1b2c3"),
                kind: .appeared,
                isDirectory: false
            )
        )
    }

    @Test
    func ignoresDirectoriesIncludingCategoryFolders() {
        let documents = URL(fileURLWithPath: "/tmp/Downloads/Documents", isDirectory: true)
        #expect(policy.shouldIgnore(url: documents, kind: .appeared, isDirectory: true))
    }
}
