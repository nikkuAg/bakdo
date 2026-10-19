import Foundation
import llama

enum LlamaError: LocalizedError {
    case modelMissing
    case loadFailed
    case notLoaded
    case promptTooLong
    case decodeFailed

    var errorDescription: String? {
        switch self {
        case .modelMissing: return "Writing model isn't downloaded yet"
        case .loadFailed: return "Couldn't load the writing model"
        case .notLoaded: return "Writing model is still loading"
        case .promptTooLong: return "Text is too long to correct in one go"
        case .decodeFailed: return "Correction failed"
        }
    }
}

struct ChatMessage {
    enum Role: String { case system, user, assistant }
    var role: Role
    var content: String
}

/// Small on-device language model (llama.cpp on Metal) used to fix grammar and typos.
/// All calls run on one serial queue; the context is reset before every request.
final class LlamaEngine: @unchecked Sendable {
    private let queue = DispatchQueue(label: "inscribo.llama", qos: .userInitiated)
    private var model: OpaquePointer?
    private var context: OpaquePointer?
    private var sampler: UnsafeMutablePointer<llama_sampler>?
    private(set) var loadedPath: String?
    private var template: String?
    /// Tokens currently held in the KV cache. Requests share a long system prompt + examples,
    /// so only the part after the common prefix needs to be processed again.
    private var cachedTokens: [llama_token] = []

    private let contextSize: UInt32 = 4096

    private var backendReady = false

    /// Metal setup compiles shaders (several seconds of CPU), so it waits until a model is actually loaded.
    private func initBackendIfNeeded() {
        guard !backendReady else { return }
        if ProcessInfo.processInfo.environment["INSCRIBO_DEBUG"] == nil {
            llama_log_set({ _, _, _ in }, nil)
        }
        llama_backend_init()
        backendReady = true
    }

    func load(path: String) async throws {
        try await run {
            if self.loadedPath == path, self.context != nil { return }
            guard FileManager.default.fileExists(atPath: path) else { throw LlamaError.modelMissing }
            self.freeAll()
            self.initBackendIfNeeded()

            var mparams = llama_model_default_params()
            mparams.n_gpu_layers = 999
            guard let model = llama_model_load_from_file(path, mparams) else { throw LlamaError.loadFailed }

            var cparams = llama_context_default_params()
            cparams.n_ctx = self.contextSize
            cparams.n_batch = self.contextSize
            cparams.n_ubatch = 512
            cparams.n_threads = 4
            cparams.n_threads_batch = 4
            cparams.no_perf = true
            cparams.swa_full = true // lets sliding-window models (Gemma) reuse the cached prefix
            guard let ctx = llama_init_from_model(model, cparams) else {
                llama_model_free(model)
                throw LlamaError.loadFailed
            }

            let chain = llama_sampler_chain_init(llama_sampler_chain_default_params())
            llama_sampler_chain_add(chain, llama_sampler_init_greedy())

            self.model = model
            self.context = ctx
            self.sampler = chain
            self.loadedPath = path
            self.template = llama_model_chat_template(model, nil).map { String(cString: $0) }

            // Warm up Metal pipelines.
            _ = try? self.generateLocked(messages: [ChatMessage(role: .user, content: "Hi")], maxTokens: 2)
        }
    }

    func shutdown() {
        queue.sync { self.freeAll() }
    }

    func generate(messages: [ChatMessage], maxTokens: Int) async throws -> String {
        try await run { try self.generateLocked(messages: messages, maxTokens: maxTokens) }
    }

    func tokenCount(_ text: String) async -> Int {
        (try? await run { self.tokenize(text, addSpecial: false).count }) ?? text.count / 3
    }

    // MARK: - Internals

    private func run<T>(_ work: @escaping () throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            queue.async { continuation.resume(with: Result { try work() }) }
        }
    }

    private func freeAll() {
        if let sampler { llama_sampler_free(sampler) }
        if let context { llama_free(context) }
        if let model { llama_model_free(model) }
        sampler = nil
        context = nil
        model = nil
        loadedPath = nil
        cachedTokens = []
    }

    private func generateLocked(messages: [ChatMessage], maxTokens: Int) throws -> String {
        guard let ctx = context, let model, let sampler else { throw LlamaError.notLoaded }
        let vocab = llama_model_get_vocab(model)

        llama_sampler_reset(sampler)

        let tokens = tokenize(formatPrompt(messages), addSpecial: true)
        guard !tokens.isEmpty, tokens.count + maxTokens < Int(contextSize) else { throw LlamaError.promptTooLong }

        // Reuse the cached prefix when the memory supports trimming (recurrent models don't).
        let memory = llama_get_memory(ctx)
        var common = 0
        let limit = min(cachedTokens.count, tokens.count - 1)
        while common < limit && cachedTokens[common] == tokens[common] { common += 1 }
        if common == 0 || !llama_memory_seq_rm(memory, 0, llama_pos(common), -1) {
            llama_memory_clear(memory, true)
            common = 0
        }
        cachedTokens = Array(tokens.prefix(common))

        var pending = Array(tokens[common...])
        let promptStatus = pending.withUnsafeMutableBufferPointer { buffer in
            llama_decode(ctx, llama_batch_get_one(buffer.baseAddress, Int32(buffer.count)))
        }
        guard promptStatus == 0 else {
            llama_memory_clear(memory, true)
            cachedTokens = []
            throw LlamaError.decodeFailed
        }
        cachedTokens = tokens

        var output: [UInt8] = []
        var piece = [CChar](repeating: 0, count: 256)
        for _ in 0..<maxTokens {
            var token = llama_sampler_sample(sampler, ctx, -1)
            if llama_vocab_is_eog(vocab, token) { break }
            let n = llama_token_to_piece(vocab, token, &piece, Int32(piece.count), 0, false)
            if n > 0 { output.append(contentsOf: piece[0..<Int(n)].map { UInt8(bitPattern: $0) }) }
            let status = llama_decode(ctx, llama_batch_get_one(&token, 1))
            guard status == 0 else { break }
            cachedTokens.append(token)
        }
        return String(decoding: output, as: UTF8.self)
    }

    private func tokenize(_ text: String, addSpecial: Bool) -> [llama_token] {
        guard let model else { return [] }
        let vocab = llama_model_get_vocab(model)
        let length = Int32(text.utf8.count)
        let needed = -llama_tokenize(vocab, text, length, nil, 0, addSpecial, true)
        guard needed > 0 else { return [] }
        var tokens = [llama_token](repeating: 0, count: Int(needed))
        let written = llama_tokenize(vocab, text, length, &tokens, needed, addSpecial, true)
        return Array(tokens.prefix(Int(max(0, written))))
    }

    /// Uses the chat template embedded in the model file; falls back to ChatML.
    private func formatPrompt(_ messages: [ChatMessage]) -> String {
        let roles = messages.map { strdup($0.role.rawValue) }
        let contents = messages.map { strdup($0.content) }
        defer {
            roles.forEach { free($0) }
            contents.forEach { free($0) }
        }
        var chat = (0..<messages.count).map { llama_chat_message(role: roles[$0], content: contents[$0]) }

        var prompt: String?
        var buffer = [CChar](repeating: 0, count: 16_384)
        let written = llama_chat_apply_template(template, &chat, chat.count, true, &buffer, Int32(buffer.count))
        if written > 0 && Int(written) <= buffer.count {
            prompt = String(decoding: buffer[0..<Int(written)].map { UInt8(bitPattern: $0) }, as: UTF8.self)
        }
        var result = prompt ?? messages.map { "<|im_start|>\($0.role.rawValue)\n\($0.content)<|im_end|>\n" }.joined() + "<|im_start|>assistant\n"

        // Hybrid "thinking" models (Qwen3.5): skip the reasoning block and answer directly.
        if let template, template.contains("<think>"), !result.hasSuffix("</think>\n\n") {
            result += "<think>\n\n</think>\n\n"
        }
        return result
    }
}
