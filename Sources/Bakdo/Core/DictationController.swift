import AppKit
import AVFoundation
import Observation

/// The dictation state machine: trigger key → record → transcribe → clean up → type into the focused app.
@MainActor
@Observable
final class DictationController {
    static let shared = DictationController()

    enum Phase: Equatable {
        case idle
        case recording
        case transcribing
        /// Correcting selected text via the fix shortcut.
        case fixing
        case message(String, isError: Bool)
    }

    enum EngineState: Equatable {
        case loading
        case ready
        case missing
        case failed(String)
    }

    private(set) var phase: Phase = .idle
    /// Recording continues without holding the key (entered by double-tapping it).
    private(set) var handsFree = false
    /// Becomes true once a press is long enough to be a real dictation; until then nothing is shown.
    private(set) var committed = false
    private(set) var levels: [Float] = Array(repeating: 0, count: 28)
    private(set) var recordingStartedAt: Date?
    private(set) var engineState: EngineState = .loading
    /// State of the grammar/typo model.
    private(set) var writerState: EngineState = .loading
    private(set) var lastTranscript: Transcript?
    /// Briefly set after text lands in the target app, so the pill can flash a confirmation.
    private(set) var doneFlash: String?
    private var doneTask: Task<Void, Never>?

    let engine = WhisperEngine()
    let writer = LlamaEngine()
    private let recorder = AudioRecorder()
    let hotkey = HotkeyMonitor()
    private let settings = AppSettings.shared

    private var pressedAt = Date.distantPast
    private var lastTapReleasedAt = Date.distantPast
    private var isSecondTap = false
    private var ignoreNextRelease = false
    private var commitTask: Task<Void, Never>?
    private var messageTask: Task<Void, Never>?
    private var maxLengthTask: Task<Void, Never>?
    private var frontmostApp: String?

    private let holdThreshold: TimeInterval = 0.28
    private let doubleTapWindow: TimeInterval = 0.45
    private let maxRecordingSeconds: TimeInterval = 300

    var isActive: Bool { phase == .recording || phase == .transcribing || phase == .fixing }

    func start() {
        recorder.onLevel = { [weak self] level in self?.pushLevel(level) }
        hotkey.triggerKey = settings.triggerKey
        hotkey.handler = { [weak self] event in self?.handle(event) }
        updateFixShortcut()
        hotkey.start()
        loadModel()
        loadWriter()
        NotificationCenter.default.addObserver(forName: .bakdoModelInstalled, object: nil, queue: .main) { [weak self] note in
            Task { @MainActor in
                guard let self else { return }
                if (note.object as? String) == ModelCatalog.writer.id { self.loadWriter() } else { self.loadModel() }
            }
        }
    }

    func shutdown() {
        _ = recorder.stop()
        hotkey.stop()
        engine.shutdown()
        writer.shutdown()
    }

    func updateFixShortcut() {
        hotkey.fixShortcut = settings.fixShortcutEnabled ? settings.fixShortcut : nil
    }

    var writerNeeded: Bool { settings.autoCorrect || settings.fixShortcutEnabled }

    func loadWriter() {
        let model = ModelCatalog.writer
        guard ModelManager.shared.isInstalled(model) else {
            writerState = .missing
            if writerNeeded { ModelManager.shared.download(model) }
            return
        }
        guard writerNeeded else { return }
        writerState = .loading
        Task {
            do {
                try await writer.load(path: ModelManager.path(for: model).path)
                writerState = .ready
            } catch {
                writerState = .failed(error.localizedDescription)
            }
        }
    }

    func updateTriggerKey() {
        hotkey.triggerKey = settings.triggerKey
    }

    func loadModel() {
        let model = ModelCatalog.speech
        guard ModelManager.shared.isInstalled(model) else {
            // First launch: fetch the model in the background; it loads as soon as it lands.
            engineState = .missing
            ModelManager.shared.download(model)
            return
        }
        engineState = .loading
        Task {
            do {
                try await engine.load(model)
                engineState = .ready
            } catch {
                engineState = .failed(error.localizedDescription)
            }
        }
    }

    // MARK: - Hotkey handling

    private func handle(_ event: HotkeyMonitor.Event) {
        switch event {
        case .pressed:
            if phase == .transcribing { ignoreNextRelease = true; return }
            if phase == .recording && handsFree {
                ignoreNextRelease = true
                finish()
                return
            }
            isSecondTap = Date().timeIntervalSince(lastTapReleasedAt) < doubleTapWindow
            pressedAt = Date()
            beginRecording()

        case .released:
            if ignoreNextRelease { ignoreNextRelease = false; return }
            guard phase == .recording, !handsFree else { return }
            let held = Date().timeIntervalSince(pressedAt)
            if held < holdThreshold {
                if isSecondTap {
                    handsFree = true
                    commit()
                } else {
                    lastTapReleasedAt = Date()
                    cancel(silently: true)
                }
                return
            }
            finish()

        case .chord:
            if phase == .recording && !handsFree {
                ignoreNextRelease = true
                cancel(silently: true)
            }

        case .escape:
            if phase == .recording { cancel(silently: false) }

        case .fixShortcut:
            fixSelection()
        }
    }

    /// Start/stop from the UI (menu bar, hands-free pill buttons).
    func toggleHandsFree() {
        if phase == .recording {
            finish()
        } else if phase == .idle || isMessage {
            pressedAt = Date()
            beginRecording()
            if phase == .recording {
                handsFree = true
                commit()
            }
        }
    }

    func cancelFromUI() {
        if phase == .recording { cancel(silently: false) }
    }

    private var downloadMessage: String {
        if case .downloading(let progress) = ModelManager.shared.state(for: ModelCatalog.speech) {
            return "Downloading speech model… \(Int(progress * 100))%"
        }
        return "Speech model isn't downloaded yet"
    }

    // MARK: - Hold Space inside Bakdo's own window

    var canStartInApp: Bool { engineState == .ready && (phase == .idle || isMessage) }

    func inAppHoldBegan() {
        guard canStartInApp else { return }
        pressedAt = Date()
        isSecondTap = false
        beginRecording()
    }

    /// Returns true when the press was only a tap (recording discarded), so the caller can type a space.
    func inAppHoldEnded() -> Bool {
        ignoreNextRelease = false
        guard phase == .recording, !handsFree else { return false }
        if Date().timeIntervalSince(pressedAt) < holdThreshold {
            cancel(silently: true)
            return true
        }
        finish()
        return false
    }

    private var isMessage: Bool {
        if case .message = phase { return true }
        return false
    }

    // MARK: - Recording

    private func beginRecording() {
        doneFlash = nil
        guard engineState == .ready else {
            switch engineState {
            case .missing: show(downloadMessage, isError: false)
            case .loading: show("Loading speech model…", isError: false)
            case .failed(let reason): show(reason, isError: true)
            case .ready: break
            }
            ignoreNextRelease = true
            return
        }

        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            break
        case .notDetermined:
            ignoreNextRelease = true
            Task { _ = await Permissions.shared.requestMicrophone() }
            return
        default:
            show("Microphone access is off", isError: true)
            ignoreNextRelease = true
            Permissions.shared.openSettings("Privacy_Microphone")
            return
        }

        do {
            try recorder.start(deviceUID: settings.inputDeviceUID)
        } catch {
            show(error.localizedDescription, isError: true)
            ignoreNextRelease = true
            return
        }

        messageTask?.cancel()
        levels = Array(repeating: 0, count: levels.count)
        frontmostApp = TextInserter.frontmostAppName()
        recordingStartedAt = Date()
        handsFree = false
        committed = false
        phase = .recording
        hotkey.capturesEscape = true

        commitTask?.cancel()
        commitTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(self?.holdThreshold ?? 0.28))
            guard let self, !Task.isCancelled, self.phase == .recording else { return }
            self.commit()
        }
    }

    /// The press is a real dictation: show the pill and play the start sound.
    private func commit() {
        guard !committed, phase == .recording else { return }
        committed = true
        commitTask?.cancel()
        Sounds.play(.start)
        maxLengthTask?.cancel()
        maxLengthTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(self?.maxRecordingSeconds ?? 300))
            guard let self, !Task.isCancelled, self.phase == .recording else { return }
            self.finish()
        }
    }

    private func cancel(silently: Bool) {
        commitTask?.cancel()
        maxLengthTask?.cancel()
        _ = recorder.stop()
        hotkey.capturesEscape = false
        let wasCommitted = committed
        handsFree = false
        committed = false
        phase = .idle
        if !silently && wasCommitted {
            Sounds.play(.cancel)
            show("Cancelled", isError: false)
        }
    }

    private func finish() {
        commitTask?.cancel()
        maxLengthTask?.cancel()
        let samples = recorder.stop()
        hotkey.capturesEscape = false
        handsFree = false
        committed = true
        Sounds.play(.stop)

        let seconds = Double(samples.count) / Double(WhisperEngine.sampleRate)
        guard seconds >= 0.3 else {
            phase = .idle
            return
        }
        phase = .transcribing

        let request = TranscriptionRequest(
            samples: [],
            prompt: vocabularyPrompt()
        )
        let options = TextPostProcessor.Options(
            removeFillers: settings.removeFillers,
            spokenCommands: settings.spokenCommands,
            replacements: []
        )
        let replacements = settings.replacements
        let vocabulary = settings.vocabulary
        let autoCorrect = settings.autoCorrect && writerState == .ready
        let smartSpacing = settings.smartSpacing
        let keepAudio = settings.keepTrainingAudio
        let app = frontmostApp

        Task {
            let prepared = await Task.detached(priority: .userInitiated) { AudioProcessing.prepare(samples) }.value
            guard let prepared else {
                show("Didn't catch that", isError: false)
                return
            }
            do {
                var req = request
                req.samples = prepared
                let result = try await engine.transcribe(req)
                var text = TextPostProcessor.process(result.text, options: options)
                if autoCorrect, !text.isEmpty {
                    text = await TextCorrector.correctPreservingLayout(text, source: .dictation, engine: writer,
                                                                       vocabulary: vocabulary)
                }
                // Dictionary replacements run last so the writing model can't undo them.
                text = TextPostProcessor.process(text, options: .init(removeFillers: false, spokenCommands: false,
                                                                      replacements: replacements))
                guard !text.isEmpty else {
                    show("Didn't catch that", isError: false)
                    return
                }

                TextInserter.insert(text, smartSpacing: smartSpacing)
                let words = TextPostProcessor.wordCount(text)
                flashDone(words == 1 ? "Typed 1 word" : "Typed \(words) words")
                var transcript = Transcript(date: Date(), text: text, rawText: result.text,
                                            audioSeconds: seconds, processingSeconds: result.processingSeconds,
                                            language: "auto", appName: app)
                if keepAudio {
                    transcript.trainingID = TrainingStore.shared.add(audio: prepared, text: text, heard: result.text,
                                                                     source: .dictation)?.id
                }
                lastTranscript = transcript
                HistoryStore.shared.add(transcript)
                phase = .idle
                committed = false
            } catch {
                show(error.localizedDescription, isError: true)
            }
        }
    }

    // MARK: - Fix selected text

    func fixSelection() {
        guard phase == .idle || isMessage else { return }
        switch writerState {
        case .ready: break
        case .missing:
            if case .downloading(let progress) = ModelManager.shared.state(for: ModelCatalog.writer) {
                show("Downloading writing model… \(Int(progress * 100))%", isError: false)
            } else {
                show("Writing model isn't downloaded yet", isError: true)
                loadWriter()
            }
            return
        case .loading: show("Loading writing model…", isError: false); return
        case .failed(let reason): show(reason, isError: true); return
        }

        committed = true
        phase = .fixing
        Task {
            guard case .text(let selected) = await TextInserter.readSelection() else {
                show("Select some text first", isError: false)
                return
            }
            let corrected = await TextCorrector.correctPreservingLayout(selected, source: .selection, engine: writer,
                                                                        vocabulary: settings.vocabulary)
            guard phase == .fixing else { return }
            if corrected == selected {
                show("Looks good — nothing to fix", isError: false)
                return
            }
            TextInserter.replaceSelection(with: corrected)
            flashDone("Fixed")
            Sounds.play(.stop)
            phase = .idle
            committed = false
        }
    }

    private func vocabularyPrompt() -> String? {
        let words = settings.vocabulary.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        guard !words.isEmpty else { return nil }
        return "Glossary: " + words.prefix(60).joined(separator: ", ") + "."
    }

    // MARK: - UI helpers

    /// For `--snapshot` only: puts the pill into a given visual state.
    func debugShow(phase: Phase, handsFree: Bool = false, levels: [Float] = [], done: String? = nil) {
        self.phase = phase
        self.handsFree = handsFree
        committed = true
        recordingStartedAt = Date().addingTimeInterval(-7)
        if !levels.isEmpty { self.levels = levels }
        doneFlash = done
    }

    private func flashDone(_ text: String) {
        doneFlash = text
        doneTask?.cancel()
        doneTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.1))
            guard let self, !Task.isCancelled else { return }
            self.doneFlash = nil
        }
    }

    func show(_ text: String, isError: Bool) {
        committed = false
        phase = .message(text, isError: isError)
        messageTask?.cancel()
        messageTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(isError ? 2.4 : 1.4))
            guard let self, !Task.isCancelled, case .message = self.phase else { return }
            self.phase = .idle
        }
    }

    func pasteLastTranscript() {
        guard let text = lastTranscript?.text ?? HistoryStore.shared.items.first?.text else { return }
        TextInserter.insert(text, smartSpacing: settings.smartSpacing)
    }

    private func pushLevel(_ level: Float) {
        guard phase == .recording else { return }
        levels.removeFirst()
        levels.append(level)
    }
}

enum Sounds {
    enum Kind { case start, stop, cancel }

    private static let cache: [Kind: NSSound] = {
        var result: [Kind: NSSound] = [:]
        let names: [Kind: String] = [.start: "Tink", .stop: "Pop", .cancel: "Funk"]
        for (kind, name) in names {
            if let sound = NSSound(named: NSSound.Name(name))?.copy() as? NSSound {
                sound.volume = 0.25
                result[kind] = sound
            }
        }
        return result
    }()

    static func play(_ kind: Kind) {
        guard AppSettings.shared.playSounds, let sound = cache[kind] else { return }
        sound.stop()
        sound.play()
    }
}
