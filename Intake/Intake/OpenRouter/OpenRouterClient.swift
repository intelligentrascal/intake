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

enum OpenRouterLookupFailure: Error, Equatable, Sendable {
    case missingKey
    case badURL
    case offline
    case unauthorized(String)
    case outOfCredit(String)
    case server(String)
    case parse

    var userMessage: String {
        switch self {
        case .missingKey:
            "Add an OpenRouter API key to enable lookups."
        case .badURL:
            "The OpenRouter base URL isn’t valid."
        case .offline:
            "Offline. Intake couldn’t reach OpenRouter."
        case .unauthorized(let message):
            message
        case .outOfCredit(let message):
            message
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

struct FolderSuggestionWithCost: Equatable, Sendable {
    var suggestion: AIFolderSuggestion
    var cost: Double?

    nonisolated init(suggestion: AIFolderSuggestion, cost: Double? = nil) {
        self.suggestion = suggestion
        self.cost = cost
    }
}


struct ContentNamingFieldsWithCost: Equatable, Sendable {
    var fields: ContentNamingFields
    var cost: Double?

    nonisolated init(fields: ContentNamingFields, cost: Double? = nil) {
        self.fields = fields
        self.cost = cost
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
    ) async -> Result<FolderSuggestionWithCost, OpenRouterFailure> {
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
                let cost = (try? OpenRouterChatParser.usage(from: data))?.cost
                return .success(FolderSuggestionWithCost(suggestion: suggestion, cost: cost))
            } catch {
                return .failure(.parse)
            }
        } catch {
            return .failure(.offline)
        }
    }


    static func suggestContentFields(
        input: ContentNamingInput,
        apiKey: String,
        configuration: OpenRouterConfiguration,
        session: URLSession = .shared
    ) async -> Result<ContentNamingFieldsWithCost, OpenRouterFailure> {
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty else {
            return .failure(.missingKey)
        }
        guard let url = OpenRouterRequestBuilder.chatCompletionsURL(baseURL: configuration.baseURL) else {
            return .failure(.badURL)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("Bearer \(trimmedKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Intake", forHTTPHeaderField: "X-Title")
        request.setValue(
            "https://github.com/intelligentrascal/intake",
            forHTTPHeaderField: "HTTP-Referer"
        )
        do {
            request.httpBody = try OpenRouterRequestBuilder.contentNamingBody(
                model: configuration.model,
                fileName: input.facts.name,
                fileExtension: input.facts.fileExtension,
                text: input.text
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
                let fields = try OpenRouterChatParser.contentNamingFields(from: content)
                let cost = (try? OpenRouterChatParser.usage(from: data))?.cost
                return .success(ContentNamingFieldsWithCost(fields: fields, cost: cost))
            } catch {
                return .failure(.parse)
            }
        } catch {
            return .failure(.offline)
        }
    }

    static func fetchKeyInfo(
        apiKey: String,
        baseURL: String,
        session: URLSession = .shared
    ) async -> Result<OpenRouterKeyInfo, OpenRouterLookupFailure> {
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty else {
            return .failure(.missingKey)
        }
        guard let url = OpenRouterRequestBuilder.keyInfoURL(baseURL: baseURL) else {
            return .failure(.badURL)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 20
        request.setValue("Bearer \(trimmedKey)", forHTTPHeaderField: "Authorization")
        request.setValue("Intake", forHTTPHeaderField: "X-Title")
        request.setValue(
            "https://github.com/intelligentrascal/intake",
            forHTTPHeaderField: "HTTP-Referer"
        )

        do {
            let (data, response) = try await session.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            if status == 401 {
                return .failure(.unauthorized(OpenRouterChatParser.httpErrorMessage(statusCode: 401)))
            }
            if status == 402 {
                return .failure(.outOfCredit(OpenRouterChatParser.httpErrorMessage(statusCode: 402)))
            }
            if !(200...299).contains(status) {
                return .failure(.server(OpenRouterChatParser.httpErrorMessage(statusCode: status)))
            }
            do {
                let info = try OpenRouterKeyInfoParser.keyInfo(from: data)
                return .success(info)
            } catch {
                return .failure(.parse)
            }
        } catch {
            return .failure(.offline)
        }
    }

    static func fetchCreditsInfo(
        apiKey: String,
        baseURL: String,
        session: URLSession = .shared
    ) async -> Result<OpenRouterCreditsInfo, OpenRouterLookupFailure> {
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty else {
            return .failure(.missingKey)
        }
        guard let url = OpenRouterRequestBuilder.creditsURL(baseURL: baseURL) else {
            return .failure(.badURL)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 20
        request.setValue("Bearer \(trimmedKey)", forHTTPHeaderField: "Authorization")
        request.setValue("Intake", forHTTPHeaderField: "X-Title")
        request.setValue(
            "https://github.com/intelligentrascal/intake",
            forHTTPHeaderField: "HTTP-Referer"
        )

        do {
            let (data, response) = try await session.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            if status == 401 {
                return .failure(.unauthorized(OpenRouterChatParser.httpErrorMessage(statusCode: 401)))
            }
            if status == 402 {
                return .failure(.outOfCredit(OpenRouterChatParser.httpErrorMessage(statusCode: 402)))
            }
            if !(200...299).contains(status) {
                return .failure(.server(OpenRouterChatParser.httpErrorMessage(statusCode: status)))
            }
            do {
                let info = try OpenRouterCreditsParser.creditsInfo(from: data)
                return .success(info)
            } catch {
                return .failure(.parse)
            }
        } catch {
            return .failure(.offline)
        }
    }
}
