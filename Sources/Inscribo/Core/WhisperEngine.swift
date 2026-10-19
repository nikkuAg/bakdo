import Foundation
import whisper

struct TranscriptionRequest {
    var samples: [Float]
    var prompt: String?
}

struct TranscriptionResult {
    var text: String
    var audioSeconds: Double
    var processingSeconds: Double
}

enum WhisperError: LocalizedError {
    case modelMissing
    case loadFailed
    case notLoaded
    case inferenceFailed

    var errorDescription: String? {
        switch self {
        case .modelMissing: return "Speech model isn't downloaded yet"
        case .loadFailed: return "Couldn't load the speech model"
        case .notLoaded: return "Speech model is still loading"
        case .inferenceFailed: return "Transcription failed"
        }
    }
}

/// Owns a whisper.cpp context. All work runs on one serial queue so the context is never
/// touched from two threads at once.
final class WhisperEngine: @unchecked Sendable {
    static let sampleRate = 16_000

    private let queue = DispatchQueue(label: "inscribo.whisper", qos: .userInitiated)
    private var context: OpaquePointer?
    private(set) var loadedModel: ModelInfo?

    private var threads: Int32 {
        // Metal does the heavy lifting; a few CPU threads are plenty and keep the machine responsive.
        Int32(max(2, min(6, ProcessInfo.processInfo.activeProcessorCount - 2)))
    }

    init() {
        if ProcessInfo.processInfo.environment["INSCRIBO_DEBUG"] == nil {
            whisper_log_set({ _, _, _ in }, nil)
        }
    }

    deinit {
        if let context { whisper_free(context) }
    }

    func load(_ model: ModelInfo) async throws {
        try await run {
            if self.loadedModel?.id == model.id, self.context != nil { return }
            let path = ModelManager.path(for: model).path
            guard FileManager.default.fileExists(atPath: path) else { throw WhisperError.modelMissing }

            if let old = self.context {
                whisper_free(old)
                self.context = nil
                self.loadedModel = nil
            }

            var cparams = whisper_context_default_params()
            cparams.use_gpu = true
            cparams.flash_attn = true
            guard let ctx = whisper_init_from_file_with_params(path, cparams) else {
                throw WhisperError.loadFailed
            }
            self.context = ctx
            self.loadedModel = model

            // Warm up so the first real dictation doesn't pay for Metal pipeline compilation.
            let silence = [Float](repeating: 0, count: Self.sampleRate)
            _ = try? self.decode(ctx: ctx, samples: silence, beamSearch: false, prompt: nil)
        }
    }

    /// Frees the Metal context synchronously; must run before process exit or ggml asserts.
    func shutdown() {
        queue.sync {
            if let ctx = self.context { whisper_free(ctx) }
            self.context = nil
            self.loadedModel = nil
        }
    }

    func unload() {
        queue.async {
            if let ctx = self.context { whisper_free(ctx) }
            self.context = nil
            self.loadedModel = nil
        }
    }

    func transcribe(_ request: TranscriptionRequest) async throws -> TranscriptionResult {
        try await run {
            guard let ctx = self.context else { throw WhisperError.notLoaded }
            let start = Date()
            let samples = Self.padded(request.samples)
            let text = try self.decode(ctx: ctx, samples: samples, beamSearch: true, prompt: request.prompt)
            return TranscriptionResult(
                text: text,
                audioSeconds: Double(request.samples.count) / Double(Self.sampleRate),
                processingSeconds: Date().timeIntervalSince(start)
            )
        }
    }

    // MARK: - Internals

    private func run<T>(_ work: @escaping () throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                continuation.resume(with: Result { try work() })
            }
        }
    }

    /// Beam search costs almost nothing extra here (the encoder dominates), so real dictation always uses it.
    private func decode(ctx: OpaquePointer, samples: [Float], beamSearch: Bool, prompt: String?) throws -> String {
        let strategy = beamSearch ? WHISPER_SAMPLING_BEAM_SEARCH : WHISPER_SAMPLING_GREEDY
        var params = whisper_full_default_params(strategy)
        params.n_threads = threads
        params.translate = false
        params.no_context = true
        params.no_timestamps = true
        params.single_segment = false
        params.print_progress = false
        params.print_realtime = false
        params.print_special = false
        params.print_timestamps = false
        params.suppress_blank = true
        params.suppress_nst = true
        params.temperature = 0
        params.temperature_inc = 0.2
        params.beam_search.beam_size = 5
        params.greedy.best_of = 1

        // The Hinglish fine-tune was trained with the English token; it still transcribes Hindi (in Roman script).
        let cLanguage = strdup("en")
        let cPrompt = prompt.flatMap { $0.isEmpty ? nil : strdup($0) }
        defer {
            free(cLanguage)
            if let cPrompt { free(cPrompt) }
        }
        params.language = UnsafePointer(cLanguage)
        if let cPrompt { params.initial_prompt = UnsafePointer(cPrompt) }

        let status = samples.withUnsafeBufferPointer { buffer in
            whisper_full(ctx, params, buffer.baseAddress, Int32(buffer.count))
        }
        guard status == 0 else { throw WhisperError.inferenceFailed }

        var text = ""
        for i in 0..<whisper_full_n_segments(ctx) {
            if let segment = whisper_full_get_segment_text(ctx, i) {
                text += String(cString: segment)
            }
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Whisper struggles with clips under a second; surround the audio with a little silence.
    private static func padded(_ samples: [Float]) -> [Float] {
        let lead = sampleRate / 5
        let minimum = Int(Double(sampleRate) * 1.2)
        let trail = max(sampleRate / 4, minimum - samples.count - lead)
        return [Float](repeating: 0, count: lead) + samples + [Float](repeating: 0, count: trail)
    }
}
