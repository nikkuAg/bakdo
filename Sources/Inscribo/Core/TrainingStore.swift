import Foundation
import Observation

/// One recording of the user's voice paired with the text that was actually meant.
/// These pairs are what a personal fine-tune of the speech model learns from.
struct TrainingSample: Codable, Identifiable, Hashable {
    enum Source: String, Codable { case script, dictation }

    var id = UUID()
    var date = Date()
    var source: Source
    /// What the user meant to say: the read-aloud sentence, or the (possibly corrected) dictation.
    var text: String
    /// What the speech model heard, before any clean-up.
    var heard: String?
    var seconds: Double
    /// Index into `TrainingScript.sentences` for read-aloud samples.
    var promptIndex: Int?

    var fileName: String { "\(id.uuidString).wav" }
}

/// Stores training recordings as 16 kHz mono WAV files plus a manifest, all under
/// ~/Library/Application Support/Inscribo/Training. Nothing leaves the Mac.
@MainActor
@Observable
final class TrainingStore {
    static let shared = TrainingStore()

    private(set) var samples: [TrainingSample] = []

    nonisolated static var directory: URL {
        let dir = ModelManager.modelsDirectory.deletingLastPathComponent().appendingPathComponent("Training", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir.appendingPathComponent("audio"), withIntermediateDirectories: true)
        return dir
    }

    nonisolated static func audioURL(for sample: TrainingSample) -> URL {
        directory.appendingPathComponent("audio").appendingPathComponent(sample.fileName)
    }

    private var manifestURL: URL { Self.directory.appendingPathComponent("manifest.json") }

    init() {
        if let data = try? Data(contentsOf: manifestURL),
           let decoded = try? JSONDecoder().decode([TrainingSample].self, from: data) {
            samples = decoded
        }
    }

    var totalSeconds: Double { samples.reduce(0) { $0 + $1.seconds } }
    var scriptCount: Int { samples.filter { $0.source == .script }.count }
    var dictationCount: Int { samples.filter { $0.source == .dictation }.count }
    var recordedPrompts: Set<Int> { Set(samples.compactMap(\.promptIndex)) }

    @discardableResult
    func add(audio: [Float], text: String, heard: String?, source: TrainingSample.Source, promptIndex: Int? = nil) -> TrainingSample? {
        let sample = TrainingSample(source: source, text: text, heard: heard,
                                    seconds: Double(audio.count) / Double(WhisperEngine.sampleRate),
                                    promptIndex: promptIndex)
        guard (try? WAVFile.write(audio, to: Self.audioURL(for: sample))) != nil else { return nil }
        // Re-recording a prompt replaces the earlier take.
        if let promptIndex, let old = samples.first(where: { $0.promptIndex == promptIndex }) {
            remove(old)
        }
        samples.append(sample)
        save()
        return sample
    }

    func updateText(id: UUID, text: String) {
        guard let index = samples.firstIndex(where: { $0.id == id }) else { return }
        samples[index].text = text
        save()
    }

    func remove(_ sample: TrainingSample) {
        try? FileManager.default.removeItem(at: Self.audioURL(for: sample))
        samples.removeAll { $0.id == sample.id }
        save()
    }

    func removeAll() {
        for sample in samples { try? FileManager.default.removeItem(at: Self.audioURL(for: sample)) }
        samples.removeAll()
        save()
    }

    private func save() {
        let snapshot = samples
        let url = manifestURL
        DispatchQueue.global(qos: .utility).async {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            if let data = try? encoder.encode(snapshot) { try? data.write(to: url, options: .atomic) }
        }
    }
}

/// Minimal 16-bit PCM mono WAV reader/writer at Whisper's 16 kHz.
enum WAVFile {
    static func write(_ samples: [Float], to url: URL) throws {
        let rate = UInt32(WhisperEngine.sampleRate)
        var pcm = Data(capacity: samples.count * 2)
        for s in samples {
            var v = Int16(max(-1, min(1, s.isFinite ? s : 0)) * 32767).littleEndian
            withUnsafeBytes(of: &v) { pcm.append(contentsOf: $0) }
        }
        var header = Data()
        func append<T: FixedWidthInteger>(_ value: T) {
            var v = value.littleEndian
            withUnsafeBytes(of: &v) { header.append(contentsOf: $0) }
        }
        header.append(contentsOf: Array("RIFF".utf8)); append(UInt32(36 + pcm.count))
        header.append(contentsOf: Array("WAVE".utf8))
        header.append(contentsOf: Array("fmt ".utf8)); append(UInt32(16)); append(UInt16(1)); append(UInt16(1))
        append(rate); append(rate * 2); append(UInt16(2)); append(UInt16(16))
        header.append(contentsOf: Array("data".utf8)); append(UInt32(pcm.count))
        try (header + pcm).write(to: url, options: .atomic)
    }

    static func read(_ url: URL) -> [Float]? {
        guard let data = try? Data(contentsOf: url), data.count > 44 else { return nil }
        let pcm = data.subdata(in: 44..<data.count)
        return pcm.withUnsafeBytes { raw in
            raw.bindMemory(to: Int16.self).map { Float(Int16(littleEndian: $0)) / 32767 }
        }
    }
}
