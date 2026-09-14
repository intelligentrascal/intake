import Foundation
import Testing
@testable import IntakeCore

struct FeedbackIssueComposerTests {
    @Test
    func featureTitleLabelsAndBody() throws {
        let draft = FeedbackIssueDraft(
            type: .feature,
            title: "  Dark mode toggle  ",
            details: "Please add a dark mode preference.",
            email: "user@example.com",
            includeDiagnostics: false,
            screenshotCount: 0
        )
        #expect(FeedbackIssueComposer.issueTitle(type: .feature, userTitle: draft.title)
            == "[Feature] Dark mode toggle")
        #expect(draft.type.githubLabels == ["enhancement", "from-app"])

        let url = try #require(FeedbackIssueComposer.makeURL(for: draft))
        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        let items = Dictionary(
            uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") }
        )
        #expect(items["title"] == "[Feature] Dark mode toggle")
        #expect(items["labels"] == "enhancement,from-app")
        #expect(items["body"]?.contains("### Type\nFeature") == true)
        #expect(items["body"]?.contains("### Details\nPlease add a dark mode preference.") == true)
        #expect(items["body"]?.contains("### Contact\nuser@example.com") == true)
        #expect(items["body"]?.contains("### Diagnostics\nNot included") == true)
        #expect(items["body"]?.contains("None attached in app.") == true)
        #expect(url.absoluteString.hasPrefix("https://github.com/intelligentrascal/intake/issues/new?"))
    }

    @Test
    func bugTitleLabelsAndDiagnosticsOn() throws {
        let draft = FeedbackIssueDraft(
            type: .bug,
            title: "Wrong folder",
            details: "PDF went to Images.",
            email: nil,
            includeDiagnostics: true,
            diagnosticsText: "Intake 1.1.0 (2) · macOS 26.6.2\nrenamed Report.pdf",
            screenshotCount: 2
        )
        #expect(FeedbackIssueComposer.issueTitle(type: .bug, userTitle: draft.title)
            == "[Bug] Wrong folder")
        #expect(draft.type.githubLabels == ["bug", "from-app"])

        let url = try #require(FeedbackIssueComposer.makeURL(for: draft))
        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        let items = Dictionary(
            uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") }
        )
        #expect(items["title"] == "[Bug] Wrong folder")
        #expect(items["labels"] == "bug,from-app")
        #expect(items["body"]?.contains("### Type\nBug") == true)
        #expect(items["body"]?.contains("### Contact\nnone") == true)
        #expect(items["body"]?.contains("Intake 1.1.0 (2) · macOS 26.6.2") == true)
        #expect(items["body"]?.contains("Paste from clipboard (⌘V) — Intake copied 2 images.") == true)
    }

    @Test
    func urgentTitleLabelsAndRejectsEmpty() {
        let draft = FeedbackIssueDraft(
            type: .urgent,
            title: "Watcher deleted files",
            details: "Data loss risk in Downloads.",
            includeDiagnostics: false,
            screenshotCount: 1
        )
        #expect(FeedbackIssueComposer.issueTitle(type: .urgent, userTitle: draft.title)
            == "[Urgent] Watcher deleted files")
        #expect(draft.type.githubLabels == ["bug", "urgent", "from-app"])

        let url = FeedbackIssueComposer.makeURL(for: draft)
        #expect(url != nil)
        let components = URLComponents(url: url!, resolvingAgainstBaseURL: false)
        let labels = components?.queryItems?.first(where: { $0.name == "labels" })?.value
        #expect(labels == "bug,urgent,from-app")
        #expect(components?.queryItems?.first(where: { $0.name == "body" })?.value?
            .contains("Paste from clipboard (⌘V) — Intake copied 1 image.") == true)

        let emptyTitle = FeedbackIssueDraft(type: .bug, title: "  ", details: "x")
        #expect(FeedbackIssueComposer.makeURL(for: emptyTitle) == nil)
        let emptyDetails = FeedbackIssueDraft(type: .bug, title: "x", details: "\n")
        #expect(FeedbackIssueComposer.makeURL(for: emptyDetails) == nil)
    }

    @Test
    func redactsHomePaths() {
        let raw = "moved /Users/rahil/Downloads/a.pdf → Documents"
        #expect(
            FeedbackIssueComposer.redactHomePaths(in: raw)
                == "moved /Users/<redacted>/Downloads/a.pdf → Documents"
        )
    }

    @Test
    func diagnosticsDefaultOffInDraftInit() {
        let draft = FeedbackIssueDraft(type: .bug, title: "t", details: "d")
        #expect(draft.includeDiagnostics == false)
    }
}
