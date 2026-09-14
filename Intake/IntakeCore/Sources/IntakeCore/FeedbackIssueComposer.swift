import Foundation

/// Feedback type for IN-17 Option D (prefilled GitHub new-issue URL).
public enum FeedbackIssueType: String, CaseIterable, Identifiable, Sendable, Equatable {
    case feature
    case bug
    case urgent

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .feature: "Feature"
        case .bug: "Bug"
        case .urgent: "Urgent"
        }
    }

    public var titlePrefix: String {
        switch self {
        case .feature: "[Feature]"
        case .bug: "[Bug]"
        case .urgent: "[Urgent]"
        }
    }

    /// Comma-separated GitHub label names for the `labels` query param.
    public var githubLabels: [String] {
        switch self {
        case .feature: ["enhancement", "from-app"]
        case .bug: ["bug", "from-app"]
        case .urgent: ["bug", "urgent", "from-app"]
        }
    }
}

/// Immutable draft used to build a GitHub `issues/new` URL (no network, no PAT).
public struct FeedbackIssueDraft: Sendable, Equatable {
    public var type: FeedbackIssueType
    public var title: String
    public var details: String
    public var email: String?
    public var includeDiagnostics: Bool
    /// Pre-built diagnostics block from the app (version, macOS, optional Activity lines).
    /// Ignored when `includeDiagnostics` is false.
    public var diagnosticsText: String?
    public var screenshotCount: Int

    public init(
        type: FeedbackIssueType,
        title: String,
        details: String,
        email: String? = nil,
        includeDiagnostics: Bool = false,
        diagnosticsText: String? = nil,
        screenshotCount: Int = 0
    ) {
        self.type = type
        self.title = title
        self.details = details
        self.email = email
        self.includeDiagnostics = includeDiagnostics
        self.diagnosticsText = diagnosticsText
        self.screenshotCount = screenshotCount
    }
}

public enum FeedbackIssueComposer {
    public static let newIssueBaseURL = URL(
        string: "https://github.com/intelligentrascal/intake/issues/new"
    )!

    public static func issueTitle(type: FeedbackIssueType, userTitle: String) -> String {
        let trimmed = userTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return type.titlePrefix
        }
        return "\(type.titlePrefix) \(trimmed)"
    }

    public static func issueBody(for draft: FeedbackIssueDraft) -> String {
        let contact: String = {
            let trimmed = draft.email?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return trimmed.isEmpty ? "none" : trimmed
        }()

        let diagnosticsBlock: String = {
            guard draft.includeDiagnostics else { return "Not included" }
            let text = draft.diagnosticsText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return text.isEmpty ? "Not included" : text
        }()

        let screenshotsLine: String = {
            if draft.screenshotCount <= 0 {
                return "None attached in app."
            }
            let n = draft.screenshotCount
            let noun = n == 1 ? "image" : "images"
            return "Paste from clipboard (⌘V) — Intake copied \(n) \(noun)."
        }()

        return """
        ### Type
        \(draft.type.displayName)

        ### Details
        \(draft.details.trimmingCharacters(in: .whitespacesAndNewlines))

        ### Contact
        \(contact)

        ### Diagnostics
        \(diagnosticsBlock)

        ### Screenshots
        \(screenshotsLine)
        """
    }

    /// Builds `https://github.com/…/issues/new?title=&body=&labels=` with proper encoding.
    /// Returns `nil` if title or details are empty after trim.
    public static func makeURL(for draft: FeedbackIssueDraft) -> URL? {
        let trimmedTitle = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedDetails = draft.details.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty, !trimmedDetails.isEmpty else { return nil }

        var components = URLComponents(
            url: newIssueBaseURL,
            resolvingAgainstBaseURL: false
        )!
        components.queryItems = [
            URLQueryItem(name: "title", value: issueTitle(type: draft.type, userTitle: trimmedTitle)),
            URLQueryItem(name: "body", value: issueBody(for: draft)),
            URLQueryItem(name: "labels", value: draft.type.githubLabels.joined(separator: ",")),
        ]
        return components.url
    }

    /// Redacts `/Users/<name>` path segments for optional diagnostics / Activity lines.
    public static func redactHomePaths(in text: String) -> String {
        guard let regex = try? NSRegularExpression(
            pattern: #"/Users/[^/\s]+"#,
            options: []
        ) else {
            return text
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.stringByReplacingMatches(
            in: text,
            options: [],
            range: range,
            withTemplate: "/Users/<redacted>"
        )
    }
}
