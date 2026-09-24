import Foundation

/// What a content namer sees for one file: local facts plus text already
/// pulled out of the file on this Mac, capped so a prompt stays small.
public struct ContentNamingInput: Equatable, Sendable {
    /// Upper bound on extracted text handed to a namer.
    public static let maximumTextCharacters = 4_000

    public var facts: FileFacts
    public var text: String

    public init(facts: FileFacts, text: String) {
        self.facts = facts
        self.text = String(text.prefix(Self.maximumTextCharacters))
    }
}

/// Fields a content namer read out of a document. Every field is optional:
/// the template drops empty ones. `confidence` is 0…1.
public struct ContentNamingFields: Equatable, Sendable, Codable {
    public var date: String?
    public var documentType: String?
    public var organization: String?
    public var subject: String?
    public var confidence: Double

    public init(
        date: String? = nil,
        documentType: String? = nil,
        organization: String? = nil,
        subject: String? = nil,
        confidence: Double
    ) {
        self.date = date
        self.documentType = documentType
        self.organization = organization
        self.subject = subject
        self.confidence = confidence
    }
}

/// Reads fields out of a document's text. The app implements this with the
/// on-device Foundation Models framework; IntakeCore has no model dependency
/// and tests use a fake. Returning `nil` means "no usable answer" — the file
/// keeps its Title Case name.
public protocol ContentNamer: Sendable {
    func fields(for input: ContentNamingInput) async -> ContentNamingFields?
}

/// Pulls text out of a file on this Mac (PDF text layer, on-device text
/// recognition). `nil` when there's nothing to read or the file is skipped.
public protocol ContentTextExtractor: Sendable {
    func text(from url: URL, maximumCharacters: Int) async -> String?
}
