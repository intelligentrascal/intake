import Foundation
import IntakeCore

enum OpenRouterFailure: Error, Equatable, Sendable {
    case skipped
    case missingKey
    case badURL
    case offline
    case server(String)
    case parse

    var userMessage: String {
        switch self {
        case .skipped:
            "AI suggestions are off."
        case .missingKey:
            "Add an OpenRouter API key to enable suggestions."
        case .badURL:
            "The OpenRouter base URL isn’t valid."
        case .offline:
            "Offline. Intake couldn’t reach OpenRouter."
        case .server(let message):
            message
        case .parse:
            "OpenRouter returned a response Intake couldn’t read."
        }
    }
}

struct PendingAISuggestion: Identifiable, Equatable, Sendable {
    var id: UUID
    var fileName: String
    var url: URL?
    var fileExtension: String
    var proposedFolder: String
    var reason: String

    init(
        id: UUID = UUID(),
        fileName: String,
        url: URL?,
        fileExtension: String,
        proposedFolder: String,
        reason: String
    ) {
        self.id = id
        self.fileName = fileName
        self.url = url
        self.fileExtension = fileExtension
        self.proposedFolder = proposedFolder
        self.reason = reason
    }
}

/// HTTPS client for OpenRouter chat completions. Lives in the app target so
/// IntakeCore stays free of network I/O.
nonisolated enum OpenRouterClient: Sendable {
    static func suggestFolder(
        fileName: String,
        folders: [String],
        apiKey: String,
        configuration: OpenRouterConfiguration,
        session: URLSession = .shared
    ) async -> Result<AIFolderSuggestion, OpenRouterFailure> {
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty else {
            return .failure(.missingKey)
        }
        guard let url = OpenRouterRequestBuilder.chatCompletionsURL(baseURL: configuration.baseURL) else {
            return .failure(.badURL)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.setValue("Bearer \(trimmedKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Intake", forHTTPHeaderField: "X-Title")
        request.setValue(
            "https://github.com/intelligentrascal/intake",
            forHTTPHeaderField: "HTTP-Referer"
        )
        do {
            request.httpBody = try OpenRouterRequestBuilder.body(
                model: configuration.model,
                fileName: fileName,
                folders: folders
            )
        } catch {
            return .failure(.parse)
        }

        do {
            let (data, response) = try await session.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            if status == 401 || status == 403 || status == 429 || !(200...299).contains(status) {
                return .failure(.server(OpenRouterChatParser.httpErrorMessage(statusCode: status)))
            }
            do {
                let content = try OpenRouterChatParser.messageContent(from: data)
                let suggestion = try OpenRouterChatParser.folderSuggestion(from: content)
                return .success(suggestion)
            } catch {
                return .failure(.parse)
            }
        } catch {
            return .failure(.offline)
        }
    }
}
