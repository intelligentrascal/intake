import Foundation

/// One grammar-constrained generation.
public struct LocalGenerationRequest: Equatable, Sendable {
    public var prompt: String
    public var grammar: String
    public var grammarRoot: String
    public var maximumTokens: Int
    /// 0 = greedy (deterministic).
    public var temperature: Float

    public init(
        prompt: String,
        grammar: String = OfflineModelPrompt.grammar,
        grammarRoot: String = OfflineModelPrompt.grammarRoot,
        maximumTokens: Int = OfflineModelPrompt.maximumOutputTokens,
        temperature: Float = 0
    ) {
        self.prompt = prompt
        self.grammar = grammar
        self.grammarRoot = grammarRoot
        self.maximumTokens = maximumTokens
        self.temperature = temperature
    }
}

public struct LocalModelLoadConfiguration: Equatable, Sendable {
    /// Context window. 4,000 chars of text plus instructions fit in 4,096.
    public var contextTokens: Int
    /// Offload everything to Metal on Apple silicon; CPU only on Intel.
    public var useGPU: Bool

    public init(contextTokens: Int = 4_096, useGPU: Bool) {
        self.contextTokens = contextTokens
        self.useGPU = useGPU
    }
}

public enum LocalModelRuntimeError: Error, Equatable, Sendable {
    case loadFailed
    case notLoaded
    case promptTooLong
    case decodeFailed
    case grammarFailed
    case cancelled
}

/// The inference engine. The app links llama.cpp's xcframework behind this
/// protocol; IntakeCore tests use fakes. Implementations must be safe to call
/// from one actor at a time (`OfflineModelSession` serializes calls).
public protocol LocalModelRuntime: Sendable {
    func load(modelAt url: URL, configuration: LocalModelLoadConfiguration) async throws
    func generate(_ request: LocalGenerationRequest) async throws -> String
    func unload() async
}

/// Lazy load, idle unload (SPEC §7, §9.3). Owns the runtime and is the only
/// path to it, so loads and generations never overlap.
public actor OfflineModelSession {
    public enum State: Equatable, Sendable {
        case unloaded
        case loaded(model: URL, lastUsed: Date)
    }

    /// Unload after this long without a generation (SPEC §9.3, [T]).
    public static let defaultIdleTimeout: TimeInterval = 180

    public let idleTimeout: TimeInterval
    private let runtime: any LocalModelRuntime
    private let now: @Sendable () -> Date
    public private(set) var state: State = .unloaded
    /// True while a load or generation is running.
    public private(set) var isBusy = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    public init(
        runtime: any LocalModelRuntime,
        idleTimeout: TimeInterval = OfflineModelSession.defaultIdleTimeout,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.runtime = runtime
        self.idleTimeout = idleTimeout
        self.now = now
    }

    public var isLoaded: Bool {
        if case .loaded = state { return true }
        return false
    }

    public var loadedModel: URL? {
        if case .loaded(let model, _) = state { return model }
        return nil
    }

    /// Loads `model` if needed (swapping out another file), then generates.
    public func generate(
        _ request: LocalGenerationRequest,
        model: URL,
        configuration: LocalModelLoadConfiguration
    ) async throws -> String {
        await acquire()
        defer { release() }
        if Task.isCancelled { throw LocalModelRuntimeError.cancelled }
        if loadedModel != model {
            if isLoaded {
                await runtime.unload()
                state = .unloaded
            }
            do {
                try await runtime.load(modelAt: model, configuration: configuration)
            } catch {
                await runtime.unload()
                state = .unloaded
                throw LocalModelRuntimeError.loadFailed
            }
            state = .loaded(model: model, lastUsed: now())
        }
        defer {
            if case .loaded(let model, _) = state {
                state = .loaded(model: model, lastUsed: now())
            }
        }
        return try await runtime.generate(request)
    }

    /// Loads without generating (self-test warm-up, pre-load on AC).
    public func load(model: URL, configuration: LocalModelLoadConfiguration) async throws {
        await acquire()
        defer { release() }
        guard loadedModel != model else { return }
        if isLoaded {
            await runtime.unload()
            state = .unloaded
        }
        do {
            try await runtime.load(modelAt: model, configuration: configuration)
        } catch {
            await runtime.unload()
            throw LocalModelRuntimeError.loadFailed
        }
        state = .loaded(model: model, lastUsed: now())
    }

    /// Called by a timer: unloads when idle past `idleTimeout`. Returns true
    /// when it unloaded.
    @discardableResult
    public func unloadIfIdle() async -> Bool {
        guard !isBusy, case .loaded(_, let lastUsed) = state else { return false }
        guard now().timeIntervalSince(lastUsed) >= idleTimeout else { return false }
        await runtime.unload()
        state = .unloaded
        return true
    }

    /// Memory critical, thermal, delete, sleep: unload now. Waits for an
    /// in-flight generation to return first (the caller cancels its task).
    public func unload() async {
        await acquire()
        defer { release() }
        guard isLoaded else { return }
        await runtime.unload()
        state = .unloaded
    }

    // MARK: Serialization (actor reentrancy across awaits)

    private func acquire() async {
        if !isBusy {
            isBusy = true
            return
        }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    private func release() {
        if waiters.isEmpty {
            isBusy = false
        } else {
            waiters.removeFirst().resume()
        }
    }
}

/// `ContentNamer` for the Offline model provider. File contents never leave
/// the Mac: the prompt goes to a local runtime, no network is involved.
public struct OfflineModelContentNamer: ContentNamer {
    public var session: OfflineModelSession
    public var entry: OfflineModelManifestEntry
    public var modelURL: URL
    public var configuration: LocalModelLoadConfiguration
    public var temperature: Float

    public init(
        session: OfflineModelSession,
        entry: OfflineModelManifestEntry,
        modelURL: URL,
        configuration: LocalModelLoadConfiguration,
        temperature: Float = 0
    ) {
        self.session = session
        self.entry = entry
        self.modelURL = modelURL
        self.configuration = configuration
        self.temperature = temperature
    }

    public func prompt(for input: ContentNamingInput) -> String {
        OfflineModelPrompt.build(format: entry.promptFormat, input: input)
    }

    public func fields(for input: ContentNamingInput) async -> ContentNamingFields? {
        let request = LocalGenerationRequest(prompt: prompt(for: input), temperature: temperature)
        guard let raw = try? await session.generate(request, model: modelURL, configuration: configuration) else {
            // Load failure, timeout, cancellation: keep the Title Case name.
            return nil
        }
        return OfflineModelOutputParser.fields(from: raw)
    }
}

/// Post-download self-test (SPEC §6): a bundled sample must give valid
/// fields within 30 s, or the tier is marked unsupported on this Mac.
public enum OfflineModelSelfTest {
    public static let timeLimit: TimeInterval = 30

    /// Synthetic sample: no personal data.
    public static let sampleInput = ContentNamingInput(
        facts: FileFacts(name: "scan_0042.pdf", fileExtension: "pdf"),
        text: """
        ACME PROPERTY MANAGEMENT
        INVOICE
        Invoice number: INV-2026-0314
        Invoice date: 2026-03-14
        Bill to: Sample Tenant
        Description: Rent for March 2026
        Amount due: 1,200.00 EUR
        """
    )

    public static func passed(_ fields: ContentNamingFields?, elapsed: TimeInterval) -> Bool {
        guard elapsed <= timeLimit, let fields else { return false }
        let values = [fields.date, fields.documentType, fields.organization, fields.subject]
        return values.contains { !($0 ?? "").isEmpty }
    }
}
