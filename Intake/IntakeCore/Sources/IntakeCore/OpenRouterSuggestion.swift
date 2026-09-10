import Foundation

public struct AIFolderSuggestion: Equatable, Sendable {
    public var folderName: String
    public var reason: String

    public init(folderName: String, reason: String) {
        self.folderName = folderName
        self.reason = reason
    }
}

public struct OpenRouterConfiguration: Equatable, Sendable {
    public static let defaultBaseURL = "https://openrouter.ai/api/v1"
    public static let defaultModel = "openai/gpt-4o-mini"

    public static let curatedModels: [String] = [
        "openai/gpt-4o-mini",
        "openai/gpt-4o",
        "anthropic/claude-3.5-sonnet",
        "google/gemini-2.0-flash-001",
        "meta-llama/llama-3.3-70b-instruct",
    ]

    public var baseURL: String
    public var model: String

    public init(
        baseURL: String = Self.defaultBaseURL,
        model: String = Self.defaultModel
    ) {
        self.baseURL = baseURL
        self.model = model
    }
}

public enum OpenRouterRequestBuilder: Sendable {
    public static func chatCompletionsURL(baseURL: String) -> URL? {
        let trimmed = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !trimmed.isEmpty else { return nil }
        return URL(string: trimmed + "/chat/completions")
    }

    public static func body(
        model: String,
        fileName: String,
        folders: [String]
    ) throws -> Data {
        let folderList = folders.joined(separator: ", ")
        let payload: [String: Any] = [
            "model": model,
            "temperature": 0.2,
            "messages": [
                [
                    "role": "system",
                    "content": """
                    You suggest a destination folder for a downloaded file. \
                    You receive only a file name and extension — never file contents. \
                    Prefer one of these existing folders when it fits: \(folderList). \
                    Reply with compact JSON only: {"folder":"...","reason":"..."}. \
                    Folder names should be short English labels without slashes.
                    """,
                ],
                [
                    "role": "user",
                    "content": "File name: \(fileName)",
                ],
            ],
        ]
        return try JSONSerialization.data(withJSONObject: payload)
    }
}

public enum OpenRouterChatParser: Sendable {
    public enum ParseError: Error, Equatable, Sendable {
        case missingContent
        case invalidJSON
        case missingFolder
    }

    public static func messageContent(from data: Data) throws -> String {
        let object = try JSONSerialization.jsonObject(with: data)
        guard let root = object as? [String: Any],
              let choices = root["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any],
              let content = message["content"] as? String
        else {
            throw ParseError.missingContent
        }
        return content
    }

    public static func folderSuggestion(from content: String) throws -> AIFolderSuggestion {
        let json = unwrapJSON(content)
        guard let data = json.data(using: .utf8),
              let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            throw ParseError.invalidJSON
        }
        guard let folder = object["folder"] as? String,
              let parsed = try? FolderNameToken.parse(folder).get()
        else {
            throw ParseError.missingFolder
        }
        let reason = (object["reason"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            ?? "Suggested from the file name."
        return AIFolderSuggestion(folderName: parsed, reason: reason)
    }

    public static func httpErrorMessage(statusCode: Int) -> String {
        switch statusCode {
        case 401, 403:
            "Unauthorized. Check the OpenRouter API key."
        case 429:
            "Rate limited. Try again in a moment."
        case 500...599:
            "OpenRouter is unavailable (\(statusCode))."
        default:
            "OpenRouter request failed (\(statusCode))."
        }
    }

    private static func unwrapJSON(_ content: String) -> String {
        var text = content.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("```") {
            text = text.replacingOccurrences(of: "```json", with: "")
            text = text.replacingOccurrences(of: "```", with: "")
            text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let start = text.firstIndex(of: "{"), let end = text.lastIndex(of: "}") {
            return String(text[start...end])
        }
        return text
    }
}
