import CryptoKit
import Foundation
import Observation

struct ModelInfo: Identifiable, Hashable {
    let id: String
    let name: String
    let fileName: String
    let url: URL
    let sizeBytes: Int64
    /// Hugging Face's LFS SHA-256; downloads are verified against it.
    let sha256: String
}

enum ModelCatalog {
    /// Whisper large-v3-turbo fine-tuned by Oriserve on ~700 h of Indian-accented speech.
    /// One model covers English, Hindi and Hinglish: English stays English, Hindi comes out in
    /// Roman script. It is trained with the English language token, so no language detection is needed.
    static let speech = ModelInfo(
        id: "hinglish-apex",
        name: "Whisper large-v3-turbo · Hinglish",
        fileName: "ggml-hindi2hinglish-apex-q5_1.bin",
        url: URL(string: "https://huggingface.co/voquill/whisper-hindi2hinglish-apex-ggml/resolve/main/ggml-hindi2hinglish-apex-q5_1.bin")!,
        sizeBytes: 624_065_675,
        sha256: "be4392ef7d61721933868bbf7824a2c06f341f22238616067a2719ef62b79d1d"
    )

    /// Small instruction-tuned LLM that fixes grammar, spelling and punctuation (llama.cpp).
    /// Picked over Qwen3.5 0.8B (missed half the fixes), LFM2.5 1.2B (mangled Hinglish) and a 3-bit
    /// Qwen3.5 2B (occasionally dropped words): it fixed every English error in testing, kept Hinglish
    /// in Roman script, and never answered or followed the dictated text.
    static let writer = ModelInfo(
        id: "writer-qwen35-2b",
        name: "Qwen3.5 2B",
        fileName: "Qwen3.5-2B-Q4_K_M.gguf",
        url: URL(string: "https://huggingface.co/unsloth/Qwen3.5-2B-GGUF/resolve/main/Qwen3.5-2B-Q4_K_M.gguf")!,
        sizeBytes: 1_280_835_840,
        sha256: "aaf42c8b7c3cab2bf3d69c355048d4a0ee9973d48f16c731c0520ee914699223"
    )

    static let all = [speech, writer]
}

/// Tracks which models are on disk and downloads missing ones.
@MainActor
@Observable
final class ModelManager {
    static let shared = ModelManager()

    enum DownloadState: Equatable {
        case idle
        case downloading(progress: Double)
        case failed(String)
    }

    private(set) var downloads: [String: DownloadState] = [:]
    private(set) var installed: Set<String> = []

    private var tasks: [String: Task<Void, Never>] = [:]

    nonisolated static var modelsDirectory: URL {
        let base: URL
        if let override = ProcessInfo.processInfo.environment["INSCRIBO_MODELS_DIR"] {
            base = URL(fileURLWithPath: override, isDirectory: true)
        } else {
            base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("Inscribo/Models", isDirectory: true)
        }
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }

    nonisolated static func path(for model: ModelInfo) -> URL {
        modelsDirectory.appendingPathComponent(model.fileName)
    }

    init() {
        refresh()
    }

    /// A model counts as installed only once the verified file has been moved into place.
    func refresh() {
        installed = Set(ModelCatalog.all.filter { model in
            let attrs = try? FileManager.default.attributesOfItem(atPath: Self.path(for: model).path)
            return (attrs?[.size] as? Int64) == model.sizeBytes
        }.map(\.id))
    }

    func isInstalled(_ model: ModelInfo) -> Bool { installed.contains(model.id) }

    func state(for model: ModelInfo) -> DownloadState { downloads[model.id] ?? .idle }

    func download(_ model: ModelInfo) {
        if case .downloading = state(for: model) { return }
        if isInstalled(model) { return }
        downloads[model.id] = .downloading(progress: 0)
        tasks[model.id] = Task { [weak self] in
            do {
                try await ChunkedDownloader.fetch(model) { progress in
                    Task { @MainActor in
                        guard let self, case .downloading = self.downloads[model.id] else { return }
                        self.downloads[model.id] = .downloading(progress: progress)
                    }
                }
                guard let self else { return }
                self.downloads[model.id] = .idle
                self.tasks[model.id] = nil
                self.refresh()
                NotificationCenter.default.post(name: .inscriboModelInstalled, object: model.id)
            } catch {
                guard let self else { return }
                self.tasks[model.id] = nil
                self.downloads[model.id] = Task.isCancelled || error is CancellationError
                    ? .idle : .failed(error.localizedDescription)
            }
        }
    }

    func cancel(_ model: ModelInfo) {
        tasks[model.id]?.cancel()
    }

    func delete(_ model: ModelInfo) {
        try? FileManager.default.removeItem(at: Self.path(for: model))
        refresh()
    }
}

/// Downloads a file as many 16 MB ranges over several connections (Hugging Face caps each connection
/// at roughly 1 MB/s), retries failed ranges, resumes after a quit, and verifies the SHA-256.
enum ChunkedDownloader {
    static let chunkSize: Int64 = 16 << 20
    static let connections = 8

    struct DownloadError: LocalizedError {
        let errorDescription: String?
    }

    static func fetch(_ model: ModelInfo, progress: @escaping @Sendable (Double) -> Void) async throws {
        let destination = ModelManager.path(for: model)
        let partial = destination.appendingPathExtension("partial")
        let ledger = destination.appendingPathExtension("chunks")
        let size = model.sizeBytes
        let chunkCount = Int((size + chunkSize - 1) / chunkSize)

        let fm = FileManager.default
        if !fm.fileExists(atPath: partial.path) {
            fm.createFile(atPath: partial.path, contents: nil)
            try? fm.removeItem(at: ledger)
        }
        let sizer = try FileHandle(forWritingTo: partial)
        try sizer.truncate(atOffset: UInt64(size))
        try sizer.close()

        var done = Set((try? JSONDecoder().decode([Int].self, from: Data(contentsOf: ledger))) ?? [])
        var pending = (0..<chunkCount).filter { !done.contains($0) }.makeIterator()
        let bytesFor = { (i: Int) -> Int64 in min(size, Int64(i + 1) * chunkSize) - Int64(i) * chunkSize }
        var completedBytes = done.reduce(Int64(0)) { $0 + bytesFor($1) }
        progress(Double(completedBytes) / Double(size))

        try await withThrowingTaskGroup(of: Int.self) { group in
            for _ in 0..<connections {
                guard let index = pending.next() else { break }
                group.addTask { try await fetchChunk(index, of: model, into: partial); return index }
            }
            while let index = try await group.next() {
                done.insert(index)
                completedBytes += bytesFor(index)
                try? JSONEncoder().encode(Array(done)).write(to: ledger)
                progress(min(0.99, Double(completedBytes) / Double(size)))
                if let next = pending.next() {
                    group.addTask { try await fetchChunk(next, of: model, into: partial); return next }
                }
            }
        }

        guard try sha256(of: partial) == model.sha256 else {
            try? fm.removeItem(at: partial)
            try? fm.removeItem(at: ledger)
            throw DownloadError(errorDescription: "Download was corrupted — please try again")
        }
        try? fm.removeItem(at: destination)
        try fm.moveItem(at: partial, to: destination)
        try? fm.removeItem(at: ledger)
        progress(1)
    }

    private static func fetchChunk(_ index: Int, of model: ModelInfo, into file: URL) async throws {
        let start = Int64(index) * chunkSize
        let end = min(model.sizeBytes, start + chunkSize) - 1
        var lastError: Error?
        for attempt in 0..<6 {
            try Task.checkCancellation()
            do {
                var request = URLRequest(url: model.url, timeoutInterval: 60)
                request.setValue("bytes=\(start)-\(end)", forHTTPHeaderField: "Range")
                let (data, response) = try await URLSession.shared.data(for: request)
                guard (response as? HTTPURLResponse)?.statusCode == 206, Int64(data.count) == end - start + 1 else {
                    throw DownloadError(errorDescription: "Unexpected response from the server")
                }
                let handle = try FileHandle(forWritingTo: file)
                try handle.seek(toOffset: UInt64(start))
                try handle.write(contentsOf: data)
                try handle.close()
                return
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                lastError = error
                try await Task.sleep(for: .seconds(Double(attempt + 1)))
            }
        }
        throw lastError ?? DownloadError(errorDescription: "Download failed")
    }

    private static func sha256(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let data = try handle.read(upToCount: 8 << 20), !data.isEmpty {
            hasher.update(data: data)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}

extension Notification.Name {
    static let inscriboModelInstalled = Notification.Name("inscriboModelInstalled")
}
