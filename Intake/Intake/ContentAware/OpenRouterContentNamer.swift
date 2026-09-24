import Foundation
import IntakeCore

/// `ContentNamer` that sends extracted document text to OpenRouter and maps
/// the JSON fields back into `ContentNamingFields`. File contents leave the
/// Mac when this namer runs — only use it when the user picked OpenRouter.
nonisolated struct OpenRouterContentNamer: ContentNamer {
    var apiKey: String
    var configuration: OpenRouterConfiguration
    var session: URLSession
    /// Optional hook so the app can record spend without the namer knowing
    /// about UserDefaults.
    var onCost: (@Sendable (Double) -> Void)?

    init(
        apiKey: String,
        configuration: OpenRouterConfiguration,
        session: URLSession = .shared,
        onCost: (@Sendable (Double) -> Void)? = nil
    ) {
        self.apiKey = apiKey
        self.configuration = configuration
        self.session = session
        self.onCost = onCost
    }

    @concurrent
    func fields(for input: ContentNamingInput) async -> ContentNamingFields? {
        let result = await OpenRouterClient.suggestContentFields(
            input: input,
            apiKey: apiKey,
            configuration: configuration,
            session: session
        )
        switch result {
        case .success(let wrapped):
            if let cost = wrapped.cost {
                onCost?(cost)
            }
            return wrapped.fields
        case .failure:
            return nil
        }
    }
}
