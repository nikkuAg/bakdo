import Foundation
import Observation

struct Transcript: Codable, Identifiable, Hashable {
    var id = UUID()
    var date: Date
    var text: String
    var rawText: String
    var audioSeconds: Double
    var processingSeconds: Double
    var language: String
    var appName: String?
    /// Set when the audio was kept as training data (see TrainingStore).
    var trainingID: UUID?

    var wordCount: Int { TextPostProcessor.wordCount(text) }
}

@MainActor
@Observable
final class HistoryStore {
    static let shared = HistoryStore()

    private(set) var items: [Transcript] = []
    private let limit = 5_000

    private var fileURL: URL {
        ModelManager.modelsDirectory.deletingLastPathComponent().appendingPathComponent("history.json")
    }

    init() {
        if let data = try? Data(contentsOf: fileURL),
           let decoded = try? JSONDecoder().decode([Transcript].self, from: data) {
            items = decoded
        }
    }

    /// Replaces the in-memory list without touching disk (used for UI snapshots).
    func loadForPreview(_ list: [Transcript]) {
        items = list
    }

    func add(_ transcript: Transcript) {
        items.insert(transcript, at: 0)
        if items.count > limit { items.removeLast(items.count - limit) }
        save()
    }

    /// Saves a user correction; the paired training recording (if any) learns the corrected text too.
    func update(_ transcript: Transcript, text: String) {
        guard let index = items.firstIndex(where: { $0.id == transcript.id }) else { return }
        items[index].text = text
        save()
        if let trainingID = transcript.trainingID {
            TrainingStore.shared.updateText(id: trainingID, text: text)
        }
    }

    func delete(_ transcript: Transcript) {
        items.removeAll { $0.id == transcript.id }
        save()
    }

    func clear() {
        items.removeAll()
        save()
    }

    private func save() {
        let snapshot = items
        let url = fileURL
        DispatchQueue.global(qos: .utility).async {
            if let data = try? JSONEncoder().encode(snapshot) {
                try? data.write(to: url, options: .atomic)
            }
        }
    }

    // MARK: - Stats

    var totalWords: Int { items.reduce(0) { $0 + $1.wordCount } }

    var totalAudioSeconds: Double { items.reduce(0) { $0 + $1.audioSeconds } }

    /// Speaking speed across all dictations.
    var wordsPerMinute: Int {
        guard totalAudioSeconds > 5 else { return 0 }
        return Int(Double(totalWords) / (totalAudioSeconds / 60))
    }

    /// Minutes saved compared with typing at 40 wpm.
    var minutesSaved: Int {
        max(0, Int(Double(totalWords) / 40 - totalAudioSeconds / 60))
    }

    /// Consecutive days, ending today or yesterday, with at least one dictation.
    var streakDays: Int {
        let calendar = Calendar.current
        let days = Set(items.map { calendar.startOfDay(for: $0.date) })
        var day = calendar.startOfDay(for: Date())
        if !days.contains(day) { day = calendar.date(byAdding: .day, value: -1, to: day)! }
        var streak = 0
        while days.contains(day) {
            streak += 1
            day = calendar.date(byAdding: .day, value: -1, to: day)!
        }
        return streak
    }

    var wordsToday: Int {
        let calendar = Calendar.current
        return items.filter { calendar.isDateInToday($0.date) }.reduce(0) { $0 + $1.wordCount }
    }
}
