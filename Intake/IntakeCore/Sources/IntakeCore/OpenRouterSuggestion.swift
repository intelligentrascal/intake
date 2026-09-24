import Foundation

public struct AIFolderSuggestion: Equatable, Sendable {
    public var folderName: String
    public var reason: String

    public init(folderName: String, reason: String) {
        self.folderName = folderName
        self.reason = reason
    }
}

public struct OpenRouterUsageInfo: Equatable, Sendable {
    public var promptTokens: Int
    public var completionTokens: Int
    public var cost: Double

    public init(promptTokens: Int, completionTokens: Int, cost: Double) {
        self.promptTokens = promptTokens
        self.completionTokens = completionTokens
        self.cost = cost
    }
}

public struct OpenRouterKeyInfo: Equatable, Sendable {
    public var label: String
    public var usage: Double
    public var limit: Double
    public var limitRemaining: Double

    public init(label: String, usage: Double, limit: Double, limitRemaining: Double) {
        self.label = label
        self.usage = usage
        self.limit = limit
        self.limitRemaining = limitRemaining
    }
}

public struct OpenRouterCreditsInfo: Equatable, Sendable {
    public var totalCredits: Double
    public var totalUsage: Double

    public init(totalCredits: Double, totalUsage: Double) {
        self.totalCredits = totalCredits
        self.totalUsage = totalUsage
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
            "usage": ["include": true],
        ]
        return try JSONSerialization.data(withJSONObject: payload)
    }

    public static func keyInfoURL(baseURL: String) -> URL? {
        let trimmed = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !trimmed.isEmpty else { return nil }
        return URL(string: trimmed + "/key")
    }

    public static func creditsURL(baseURL: String) -> URL? {
        let trimmed = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !trimmed.isEmpty else { return nil }
        return URL(string: trimmed + "/credits")
    }
}

public enum OpenRouterChatParser: Sendable {
    public enum ParseError: Error, Equatable, Sendable {
        case missingContent
        case invalidJSON
        case missingFolder
        case missingUsage
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

    public static func usage(from data: Data) throws -> OpenRouterUsageInfo {
        let object = try JSONSerialization.jsonObject(with: data)
        guard let root = object as? [String: Any],
              let usage = root["usage"] as? [String: Any],
              let promptTokens = usage["prompt_tokens"] as? Int,
              let completionTokens = usage["completion_tokens"] as? Int,
              let cost = usage["total_cost"] as? Double
        else {
            throw ParseError.missingUsage
        }
        return OpenRouterUsageInfo(
            promptTokens: promptTokens,
            completionTokens: completionTokens,
            cost: cost
        )
    }

    public static func httpErrorMessage(statusCode: Int) -> String {
        switch statusCode {
        case 401:
            "Invalid OpenRouter API key. Check it in Settings."
        case 402:
            "Out of credit on OpenRouter. Add funds and try again."
        case 403:
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

public enum OpenRouterKeyInfoParser: Sendable {
    public enum ParseError: Error, Equatable, Sendable {
        case invalidJSON
        case missingData
    }

    public static func keyInfo(from data: Data) throws -> OpenRouterKeyInfo {
        let object = try JSONSerialization.jsonObject(with: data)
        guard let root = object as? [String: Any],
              let info = root["data"] as? [String: Any]
        else {
            throw ParseError.invalidJSON
        }
        guard let label = info["label"] as? String,
              let usage = info["usage"] as? Double,
              let limit = info["limit"] as? Double,
              let limitRemaining = info["limit_remaining"] as? Double
        else {
            throw ParseError.missingData
        }
        return OpenRouterKeyInfo(
            label: label,
            usage: usage,
            limit: limit,
            limitRemaining: limitRemaining
        )
    }
}

public enum OpenRouterCreditsParser: Sendable {
    public enum ParseError: Error, Equatable, Sendable {
        case invalidJSON
        case missingData
    }

    public static func creditsInfo(from data: Data) throws -> OpenRouterCreditsInfo {
        let object = try JSONSerialization.jsonObject(with: data)
        guard let root = object as? [String: Any],
              let info = root["data"] as? [String: Any]
        else {
            throw ParseError.invalidJSON
        }
        guard let totalCredits = info["total_credits"] as? Double,
              let totalUsage = info["total_usage"] as? Double
        else {
            throw ParseError.missingData
        }
        return OpenRouterCreditsInfo(
            totalCredits: totalCredits,
            totalUsage: totalUsage
        )
    }
}
