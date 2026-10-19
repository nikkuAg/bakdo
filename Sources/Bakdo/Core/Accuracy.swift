import Foundation
import Observation

/// Word-level alignment between what was meant and what was heard.
enum WordAlignment {
    enum Op: Equatable {
        case match(String)
        case substitute(meant: String, heard: String)
        case missed(String)   // meant but not heard
        case extra(String)    // heard but not meant
    }

    /// Lower-cased words without punctuation. Common Hinglish spelling variants are folded together
    /// so "nahin" vs "nahi" doesn't count as a recognition mistake.
    static func words(_ text: String) -> [String] {
        let variants = ["nahin": "nahi", "hun": "hoon", "hu": "hoon", "ok": "okay", "mai": "main", "thik": "theek"]
        return text.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "'")).inverted)
            .filter { !$0.isEmpty }
            .map { variants[$0] ?? $0 }
    }

    /// Levenshtein alignment over words.
    static func align(meant: [String], heard: [String]) -> [Op] {
        let n = meant.count, m = heard.count
        var cost = [[Int]](repeating: [Int](repeating: 0, count: m + 1), count: n + 1)
        for i in 0...n { cost[i][0] = i }
        for j in 0...m { cost[0][j] = j }
        if n > 0 && m > 0 {
            for i in 1...n {
                for j in 1...m {
                    let sub = cost[i - 1][j - 1] + (meant[i - 1] == heard[j - 1] ? 0 : 1)
                    cost[i][j] = min(sub, cost[i - 1][j] + 1, cost[i][j - 1] + 1)
                }
            }
        }
        var ops: [Op] = []
        var i = n, j = m
        while i > 0 || j > 0 {
            if i > 0, j > 0, cost[i][j] == cost[i - 1][j - 1] + (meant[i - 1] == heard[j - 1] ? 0 : 1) {
                ops.append(meant[i - 1] == heard[j - 1] ? .match(meant[i - 1]) : .substitute(meant: meant[i - 1], heard: heard[j - 1]))
                i -= 1; j -= 1
            } else if i > 0, cost[i][j] == cost[i - 1][j] + 1 {
                ops.append(.missed(meant[i - 1])); i -= 1
            } else {
                ops.append(.extra(heard[j - 1])); j -= 1
            }
        }
        return ops.reversed()
    }

    /// Fraction of meant words that were wrong, missed, or had extra words around them.
    static func errorRate(meant: String, heard: String) -> (errors: Int, words: Int) {
        let ops = align(meant: words(meant), heard: words(heard))
        let errors = ops.filter { if case .match = $0 { return false }; return true }.count
        return (errors, max(1, words(meant).count))
    }

    /// Groups consecutive mistakes into "heard → meant" phrases, e.g. ("versal", "vercel").
    static func mistakes(meant: String, heard: String) -> [(heard: String, meant: String)] {
        var result: [(String, String)] = []
        var heardRun: [String] = [], meantRun: [String] = []
        func flush() {
            if !heardRun.isEmpty, !meantRun.isEmpty, heardRun.count <= 3, meantRun.count <= 3 {
                result.append((heardRun.joined(separator: " "), meantRun.joined(separator: " ")))
            }
            heardRun = []; meantRun = []
        }
        for op in align(meant: words(meant), heard: words(heard)) {
            switch op {
            case .match: flush()
            case .substitute(let m, let h): meantRun.append(m); heardRun.append(h)
            case .missed(let m): meantRun.append(m)
            case .extra(let h): heardRun.append(h)
            }
        }
        flush()
        return result
    }
}

/// Runs the current speech model over the user's training recordings and reports how often it gets
/// their words wrong, plus which words it mishears most.
@MainActor
@Observable
final class AccuracyChecker {
    static let shared = AccuracyChecker()

    struct Report {
        struct Example: Identifiable {
            let id = UUID()
            let meant: String
            let heard: String
            let errorRate: Double
        }
        struct Mistake: Identifiable {
            var id: String { heard + "→" + meant }
            let heard: String
            let meant: String
            let count: Int
        }

        let date = Date()
        let samples: Int
        let words: Int
        let errors: Int
        let worst: [Example]
        let commonMistakes: [Mistake]

        var accuracy: Double { 1 - Double(errors) / Double(max(1, words)) }
    }

    private(set) var isRunning = false
    private(set) var progress = 0.0
    private(set) var report: Report?

    func run() {
        guard !isRunning else { return }
        let samples = TrainingStore.shared.samples
        guard !samples.isEmpty else { return }
        isRunning = true
        progress = 0
        let engine = DictationController.shared.engine
        let vocabulary = AppSettings.shared.vocabulary.filter { !$0.isEmpty }
        let prompt = vocabulary.isEmpty ? nil : "Glossary: " + vocabulary.prefix(60).joined(separator: ", ") + "."

        Task {
            var totalWords = 0, totalErrors = 0
            var examples: [Report.Example] = []
            var counts: [String: (heard: String, meant: String, count: Int)] = [:]
            for (index, sample) in samples.enumerated() {
                defer { progress = Double(index + 1) / Double(samples.count) }
                guard let audio = WAVFile.read(TrainingStore.audioURL(for: sample)),
                      let result = try? await engine.transcribe(TranscriptionRequest(samples: audio, prompt: prompt)) else { continue }
                let heard = TextPostProcessor.process(result.text, options: .init(removeFillers: true, spokenCommands: false))
                let (errors, words) = WordAlignment.errorRate(meant: sample.text, heard: heard)
                totalErrors += errors
                totalWords += words
                examples.append(.init(meant: sample.text, heard: heard, errorRate: Double(errors) / Double(words)))
                for mistake in WordAlignment.mistakes(meant: sample.text, heard: heard) {
                    let key = mistake.heard + "→" + mistake.meant
                    counts[key, default: (mistake.heard, mistake.meant, 0)].count += 1
                }
            }
            report = Report(
                samples: examples.count, words: totalWords, errors: totalErrors,
                worst: Array(examples.filter { $0.errorRate > 0 }.sorted { $0.errorRate > $1.errorRate }.prefix(8)),
                commonMistakes: counts.values.sorted { $0.count > $1.count }.prefix(12)
                    .map { Report.Mistake(heard: $0.heard, meant: $0.meant, count: $0.count) }
            )
            isRunning = false
        }
    }
}
