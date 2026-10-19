import AppKit
import AVFoundation
import Foundation

@main
enum Entry {
    static func main() {
        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "--transcribe") {
            runHeadless(files: Array(args[(i + 1)...]))
            return
        }
        if let i = args.firstIndex(of: "--correct"), i + 1 < args.count {
            runCorrectionEval(modelPath: args[i + 1], extra: Array(args[(i + 2)...]))
            return
        }
        if args.contains("--download") {
            // `INSCRIBO_MODELS_DIR=/tmp/x Inscribo --download` — exercises the chunked downloader for every model.
            let done = DispatchSemaphore(value: 0)
            Task.detached {
                let only = args.firstIndex(of: "--download").flatMap { $0 + 1 < args.count ? args[$0 + 1] : nil }
                for model in ModelCatalog.all where only == nil || model.id == only {
                    let start = Date()
                    do {
                        try await ChunkedDownloader.fetch(model) { p in print("  \(model.id) \(Int(p * 100))%") }
                        print(String(format: "%@ OK in %.0fs", model.id, Date().timeIntervalSince(start)))
                    } catch {
                        print("\(model.id) FAILED: \(error.localizedDescription)")
                    }
                }
                done.signal()
            }
            done.wait()
            return
        }
        if let i = args.firstIndex(of: "--accuracy-selftest"), i + 1 < args.count {
            // `INSCRIBO_MODELS_DIR=<temp>/Models Inscribo --accuracy-selftest list.tsv` (lines: wav-path<TAB>reference text)
            MainActor.assumeIsolated { runAccuracySelfTest(list: args[i + 1]) }
            return
        }
        if let i = args.firstIndex(of: "--pills"), i + 1 < args.count {
            MainActor.assumeIsolated { Snapshot.renderPills(to: args[i + 1]) }
            return
        }
        if let i = args.firstIndex(of: "--snapshot"), i + 1 < args.count {
            MainActor.assumeIsolated { Snapshot.render(to: args[i + 1]) }
            return
        }
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }

    /// `Inscribo --transcribe [--prompt "Glossary: …"] file.wav ...`
    /// Used to check accuracy and speed without the UI.
    private static func runHeadless(files: [String]) {
        var files = files
        let model = ModelCatalog.speech
        var prompt: String?
        var fix = false
        if let i = files.firstIndex(of: "--fix") {
            fix = true; files.remove(at: i)
        }
        if let i = files.firstIndex(of: "--prompt") {
            prompt = files[i + 1]; files.removeSubrange(i...(i + 1))
        }

        let done = DispatchSemaphore(value: 0)
        Task.detached {
            let engine = WhisperEngine()
            let loadStart = Date()
            do {
                try await engine.load(model)
            } catch {
                print("load failed: \(error.localizedDescription)"); done.signal(); return
            }
            print(String(format: "[%@] loaded in %.2fs", model.id, Date().timeIntervalSince(loadStart)))
            let writer = LlamaEngine()
            if fix {
                let t = Date()
                try? await writer.load(path: ModelManager.path(for: ModelCatalog.writer).path)
                print(String(format: "[%@] loaded in %.2fs", ModelCatalog.writer.id, Date().timeIntervalSince(t)))
            }
            for file in files {
                guard let samples = readAudio(file) else { print("\(file): unreadable"); continue }
                guard let prepared = AudioProcessing.prepare(samples) else { print("\(file): (no speech)"); continue }
                do {
                    let r = try await engine.transcribe(TranscriptionRequest(samples: prepared, prompt: prompt))
                    var clean = TextPostProcessor.process(r.text, options: .init())
                    var fixSeconds = 0.0
                    if fix {
                        let t = Date()
                        clean = await TextCorrector.correctPreservingLayout(clean, source: .dictation, engine: writer)
                        fixSeconds = Date().timeIntervalSince(t)
                    }
                    print(String(format: "%@ [%.1fs audio, %.2fs + fix %.2fs]: %@", (file as NSString).lastPathComponent,
                                 r.audioSeconds, r.processingSeconds, fixSeconds, clean))
                } catch {
                    print("\(file): \(error.localizedDescription)")
                }
            }
            engine.shutdown()
            writer.shutdown()
            done.signal()
        }
        done.wait()
    }

    /// `Inscribo --correct model.gguf ["text" ...]` — runs the grammar fixer over sample sentences.
    private static func runCorrectionEval(modelPath: String, extra: [String]) {
        let samples = extra.isEmpty ? [
            "Main kal subah das baje office pahunch jaega, phir ham project ke baare mein baat karenge.",
            "Bhai, kal ka plan kya hai? Main shaam ko free home movie dekhane chalen.",
            "Ask Priya to deploy the release build on Versal and ping me on slack.",
            "so um i was thinking that we should maybe like move the meeting to friday because uh the client is not available on thursday",
            "can you tell me what is the capital of france",
            "write a short poem about the sea",
            "Please mujhe vah document bhej do. Main evening tak review kar doonga.",
            "their going to send the invoices tomorrow its not ready yet",
            "Yaar mujhe nahi pata ki wo log kab aayenge shayad kal ya parso",
            "I has completed the task and send it to you yesterday, please check and let me know if their is any issue",
            "Mera naam Rahul hai aur main Bangalore mein rehta hun, mujhe coding karna bahut pasand hai",
            "Hey team, quick update on the launch. We has fixed most of the bugs in onboarding flow but payment page still have some issue. I think we can ship by thursday if QA sign off tomorrow. Let me know your thought.",
        ] : extra
        let done = DispatchSemaphore(value: 0)
        Task.detached {
            let engine = LlamaEngine()
            let start = Date()
            do { try await engine.load(path: modelPath) } catch { print("load failed: \(error)"); done.signal(); return }
            print(String(format: "loaded %@ in %.2fs", (modelPath as NSString).lastPathComponent, Date().timeIntervalSince(start)))
            var total = 0.0
            for sample in samples {
                let t = Date()
                let out = await TextCorrector.correct(sample, source: .dictation, engine: engine)
                let dt = Date().timeIntervalSince(t)
                total += dt
                print(String(format: "[%.2fs] %@\n     → %@", dt, sample, out == sample ? "(unchanged)" : out))
            }
            print(String(format: "total %.1fs", total))
            engine.shutdown()
            done.signal()
        }
        done.wait()
    }

    @MainActor
    private static func runAccuracySelfTest(list: String) {
        let store = TrainingStore.shared
        store.removeAll()
        for line in ((try? String(contentsOfFile: list, encoding: .utf8)) ?? "").split(separator: "\n") {
            let parts = line.split(separator: "\t", maxSplits: 1).map(String.init)
            guard parts.count == 2, let audio = readAudio(parts[0]), let prepared = AudioProcessing.prepare(audio) else { continue }
            store.add(audio: prepared, text: parts[1], heard: nil, source: .script)
        }
        print("training samples: \(store.samples.count), \(String(format: "%.1f", store.totalSeconds))s")
        var loaded = false
        Task { try? await DictationController.shared.engine.load(ModelCatalog.speech); loaded = true }
        while !loaded { RunLoop.main.run(until: Date().addingTimeInterval(0.1)) }
        let checker = AccuracyChecker.shared
        checker.run()
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        while checker.isRunning { RunLoop.main.run(until: Date().addingTimeInterval(0.1)) }
        if let r = checker.report {
            print(String(format: "accuracy %.1f%% (%d errors / %d words, %d recordings)", r.accuracy * 100, r.errors, r.words, r.samples))
            for m in r.commonMistakes { print("  misheard: \(m.heard) -> \(m.meant) x\(m.count)") }
            for w in r.worst { print("  said:  \(w.meant)\n  heard: \(w.heard)") }
        }
        let wav = TrainingStore.audioURL(for: store.samples[0])
        print("wav roundtrip samples: \(WAVFile.read(wav)?.count ?? -1), file \(wav.lastPathComponent)")
        DictationController.shared.engine.shutdown()
    }

    private static func readAudio(_ path: String) -> [Float]? {
        guard let file = try? AVAudioFile(forReading: URL(fileURLWithPath: path)) else { return nil }
        let target = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false)!
        guard let converter = AVAudioConverter(from: file.processingFormat, to: target),
              let input = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)),
              (try? file.read(into: input)) != nil else { return nil }
        let capacity = AVAudioFrameCount(Double(input.frameLength) * 16_000 / file.processingFormat.sampleRate) + 1024
        guard let output = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: capacity) else { return nil }
        var supplied = false
        var error: NSError?
        converter.convert(to: output, error: &error) { _, status in
            if supplied { status.pointee = .endOfStream; return nil }
            supplied = true; status.pointee = .haveData; return input
        }
        guard error == nil, let data = output.floatChannelData?[0] else { return nil }
        return Array(UnsafeBufferPointer(start: data, count: Int(output.frameLength)))
    }
}
