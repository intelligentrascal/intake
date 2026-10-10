import Foundation
import IntakeCore
import llama

/// `LocalModelRuntime` on llama.cpp (pinned xcframework, see Package.swift).
///
/// Every llama.cpp call runs on one private serial queue, never on the Swift
/// cooperative pool: a load or a generation blocks for seconds. Callers go
/// through `OfflineModelSession`, which already serializes, so the queue is a
/// second guard, not the main one.
public final class LlamaRuntime: LocalModelRuntime, @unchecked Sendable {
    private let queue = DispatchQueue(label: "app.intake.offline-model.llama", qos: .utility)
    private let cancelLock = NSLock()
    private var cancelRequested = false

    // Touched only on `queue`.
    private var model: OpaquePointer?
    private var context: OpaquePointer?
    private var contextTokens: Int32 = 0

    private static let backendOnce: Void = {
        // Silence llama.cpp's stderr logging; nothing in it is user-facing.
        llama_log_set({ _, _, _ in }, nil)
        llama_backend_init()
    }()

    public init() {}

    deinit {
        if let context { llama_free(context) }
        if let model { llama_model_free(model) }
    }

    public func load(modelAt url: URL, configuration: LocalModelLoadConfiguration) async throws {
        try await run(qos: .utility) { [self] in
            _ = Self.backendOnce
            freeLocked()

            var modelParams = llama_model_default_params()
            // Apple silicon: every layer on Metal. Intel: CPU only.
            modelParams.n_gpu_layers = configuration.useGPU ? 999 : 0
            guard let loaded = url.path.withCString({ llama_model_load_from_file($0, modelParams) }) else {
                throw LocalModelRuntimeError.loadFailed
            }

            var contextParams = llama_context_default_params()
            let tokens = UInt32(max(configuration.contextTokens, 512))
            contextParams.n_ctx = tokens
            contextParams.n_batch = tokens
            contextParams.n_ubatch = min(tokens, 512)
            let threads = Int32(max(1, min(8, ProcessInfo.processInfo.activeProcessorCount - 2)))
            contextParams.n_threads = threads
            contextParams.n_threads_batch = threads
            contextParams.no_perf = true
            guard let created = llama_init_from_model(loaded, contextParams) else {
                llama_model_free(loaded)
                throw LocalModelRuntimeError.loadFailed
            }
            model = loaded
            context = created
            contextTokens = Int32(tokens)
        }
    }

    public func generate(_ request: LocalGenerationRequest) async throws -> String {
        setCancelled(false)
        return try await withTaskCancellationHandler {
            // Rename Now runs at .userInitiated; background work at .utility.
            let qos: DispatchQoS = Task.currentPriority >= .userInitiated ? .userInitiated : .utility
            return try await run(qos: qos) { [self] in
                try generateLocked(request)
            }
        } onCancel: {
            self.setCancelled(true)
        }
    }

    public func unload() async {
        try? await run(qos: .utility) { [self] in
            freeLocked()
        }
    }

    // MARK: Queue-confined work

    private func generateLocked(_ request: LocalGenerationRequest) throws -> String {
        guard let model, let context else { throw LocalModelRuntimeError.notLoaded }
        guard let vocab = llama_model_get_vocab(model) else { throw LocalModelRuntimeError.notLoaded }

        // Fresh conversation every time: no state carries over between files.
        llama_memory_clear(llama_get_memory(context), true)

        // The prompt string already carries every special token (`<bos>` for
        // Gemma), so no automatic BOS; special-token parsing on so the
        // template's control tokens map to their ids. Document text was
        // neutralized by `OfflineModelPrompt` beforehand.
        var tokens = tokenize(request.prompt, vocab: vocab)
        guard !tokens.isEmpty else { throw LocalModelRuntimeError.decodeFailed }
        guard tokens.count + request.maximumTokens <= Int(contextTokens) else {
            throw LocalModelRuntimeError.promptTooLong
        }

        guard let sampler = makeSampler(vocab: vocab, request: request) else {
            throw LocalModelRuntimeError.grammarFailed
        }
        defer { llama_sampler_free(sampler) }

        let status = tokens.withUnsafeMutableBufferPointer { buffer in
            llama_decode(context, llama_batch_get_one(buffer.baseAddress, Int32(buffer.count)))
        }
        guard status == 0 else { throw LocalModelRuntimeError.decodeFailed }

        var output = Data()
        for _ in 0..<request.maximumTokens {
            if isCancelled() { throw LocalModelRuntimeError.cancelled }
            // Samples with the grammar applied and accepts the token.
            var token = llama_sampler_sample(sampler, context, -1)
            if llama_vocab_is_eog(vocab, token) { break }
            output.append(piece(for: token, vocab: vocab))
            let next = withUnsafeMutablePointer(to: &token) { pointer in
                llama_decode(context, llama_batch_get_one(pointer, 1))
            }
            guard next == 0 else { throw LocalModelRuntimeError.decodeFailed }
        }
        tokens.removeAll()
        return String(decoding: output, as: UTF8.self)
    }

    private func makeSampler(vocab: OpaquePointer, request: LocalGenerationRequest) -> UnsafeMutablePointer<llama_sampler>? {
        var params = llama_sampler_chain_default_params()
        params.no_perf = true
        guard let chain = llama_sampler_chain_init(params) else { return nil }
        let grammar = request.grammar.withCString { grammarText in
            request.grammarRoot.withCString { root in
                llama_sampler_init_grammar(vocab, grammarText, root)
            }
        }
        guard let grammar else {
            llama_sampler_free(chain)
            return nil
        }
        llama_sampler_chain_add(chain, grammar)
        if request.temperature <= 0 {
            llama_sampler_chain_add(chain, llama_sampler_init_greedy())
        } else {
            llama_sampler_chain_add(chain, llama_sampler_init_temp(request.temperature))
            llama_sampler_chain_add(chain, llama_sampler_init_dist(UInt32.random(in: 1...UInt32.max)))
        }
        return chain
    }

    private func tokenize(_ text: String, vocab: OpaquePointer) -> [llama_token] {
        let utf8 = Array(text.utf8CString)
        let length = Int32(utf8.count - 1)
        var capacity = Int(length) + 16
        var tokens = [llama_token](repeating: 0, count: capacity)
        var count = utf8.withUnsafeBufferPointer { text in
            llama_tokenize(vocab, text.baseAddress, length, &tokens, Int32(capacity), false, true)
        }
        if count < 0 {
            capacity = Int(-count)
            tokens = [llama_token](repeating: 0, count: capacity)
            count = utf8.withUnsafeBufferPointer { text in
                llama_tokenize(vocab, text.baseAddress, length, &tokens, Int32(capacity), false, true)
            }
        }
        guard count > 0 else { return [] }
        return Array(tokens.prefix(Int(count)))
    }

    private func piece(for token: llama_token, vocab: OpaquePointer) -> Data {
        var buffer = [CChar](repeating: 0, count: 64)
        var written = llama_token_to_piece(vocab, token, &buffer, Int32(buffer.count), 0, false)
        if written < 0 {
            buffer = [CChar](repeating: 0, count: Int(-written))
            written = llama_token_to_piece(vocab, token, &buffer, Int32(buffer.count), 0, false)
        }
        guard written > 0 else { return Data() }
        return buffer.prefix(Int(written)).withUnsafeBufferPointer { Data(buffer: $0) }
    }

    private func freeLocked() {
        if let context { llama_free(context) }
        if let model { llama_model_free(model) }
        context = nil
        model = nil
        contextTokens = 0
    }

    // MARK: Plumbing

    private func run<T: Sendable>(qos: DispatchQoS, _ work: @escaping @Sendable () throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            queue.async(qos: qos) {
                continuation.resume(with: Result { try work() })
            }
        }
    }

    private func setCancelled(_ value: Bool) {
        cancelLock.withLock { cancelRequested = value }
    }

    private func isCancelled() -> Bool {
        cancelLock.withLock { cancelRequested }
    }
}
