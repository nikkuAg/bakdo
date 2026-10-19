import AppKit
import AVFoundation
import SwiftUI

/// Records read-aloud sentences for personal training data.
@MainActor
@Observable
final class TrainingRecorder {
    private(set) var isRecording = false
    private(set) var level: Float = 0
    private(set) var message: String?
    var index = 0
    private(set) var lastSavedIndex: Int?

    private let recorder = AudioRecorder()
    private var monitor: Any?
    private var spaceHeld = false

    var prompts: [String] { TrainingScript.all(vocabulary: AppSettings.shared.vocabulary) }
    var currentPrompt: String? { index < prompts.count ? prompts[index] : nil }

    init() {
        recorder.onLevel = { [weak self] value in self?.level = value }
        index = nextUnrecorded(from: 0)
    }

    func nextUnrecorded(from start: Int) -> Int {
        let done = TrainingStore.shared.recordedPrompts
        let all = prompts
        return (start..<all.count).first { !done.contains($0) } ?? all.count
    }

    func toggle() {
        isRecording ? stop() : start()
    }

    func start() {
        guard !isRecording, currentPrompt != nil, !DictationController.shared.isActive else { return }
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: break
        case .notDetermined:
            Task { _ = await Permissions.shared.requestMicrophone() }
            return
        default:
            message = "Microphone access is off — turn it on in Settings."
            return
        }
        do {
            try recorder.start(deviceUID: AppSettings.shared.inputDeviceUID)
            isRecording = true
            message = nil
            Sounds.play(.start)
        } catch {
            message = error.localizedDescription
        }
    }

    func stop() {
        guard isRecording else { return }
        let audio = recorder.stop()
        isRecording = false
        level = 0
        Sounds.play(.stop)
        guard let prompt = currentPrompt else { return }
        guard let prepared = AudioProcessing.prepare(audio),
              Double(prepared.count) / Double(WhisperEngine.sampleRate) >= 0.8 else {
            message = "Didn't hear that clearly — try again."
            return
        }
        TrainingStore.shared.add(audio: prepared, text: prompt, heard: nil, source: .script, promptIndex: index)
        lastSavedIndex = index
        message = nil
        withAnimation(.spring(response: 0.4)) { index = nextUnrecorded(from: index + 1) }
    }

    func skip() {
        withAnimation(.spring(response: 0.4)) { index = min(prompts.count, index + 1) }
    }

    func redoLast() {
        guard let last = lastSavedIndex else { return }
        withAnimation(.spring(response: 0.4)) { index = last }
    }

    func restart() {
        withAnimation(.spring(response: 0.4)) { index = nextUnrecorded(from: 0) }
    }

    /// Hold Space to record while this page is visible.
    func installSpaceMonitor() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp]) { [weak self] event in
            guard let self, event.keyCode == 49, event.window?.isKeyWindow == true,
                  !(event.window?.firstResponder is NSTextView) else { return event }
            if event.type == .keyDown {
                if !event.isARepeat && !self.spaceHeld {
                    self.spaceHeld = true
                    self.start()
                }
            } else {
                self.spaceHeld = false
                self.stop()
            }
            return nil
        }
    }

    func removeSpaceMonitor() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        if isRecording { stop() }
    }
}

struct VoiceTrainingView: View {
    @State private var store = TrainingStore.shared
    @State private var settings = AppSettings.shared
    @State private var recorder = TrainingRecorder()
    @State private var checker = AccuracyChecker.shared
    @State private var confirmDelete = false

    private let goalMinutes = 20.0

    var body: some View {
        PageScaffold(title: "Voice training",
                     subtitle: "Teach Inscribo your voice and accent. Recordings stay on this Mac and are only used to measure and train your personal model.") {
            progressCard
            readAloudCard
            accuracyCard
        }
        .onAppear { recorder.installSpaceMonitor() }
        .onDisappear { recorder.removeSpaceMonitor() }
    }

    // MARK: Progress

    private var progressCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    Text(String(format: "%.1f", store.totalSeconds / 60))
                        .font(.system(size: 30, weight: .semibold, design: .rounded))
                        .contentTransition(.numericText())
                    Text("of \(Int(goalMinutes)) minutes recorded")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(store.scriptCount) read aloud · \(store.dictationCount) from dictations")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                ProgressView(value: min(1, store.totalSeconds / 60 / goalMinutes))
                    .tint(Theme.accent)
                Divider()
                VStack(alignment: .leading, spacing: 4) {
                    Toggle("Also keep my everyday dictations as training data", isOn: $settings.keepTrainingAudio)
                        .toggleStyle(.checkbox)
                    Text("Fix any mistake in Home › History and the recording learns the corrected text.")
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                        .padding(.leading, 20)
                }
                HStack {
                    Button("Show recordings in Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting([TrainingStore.directory])
                    }
                    .buttonStyle(SecondaryButtonStyle())
                    Spacer()
                    if !store.samples.isEmpty {
                        Button("Delete all recordings…") { confirmDelete = true }
                            .buttonStyle(.plain)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .confirmationDialog("Delete all \(store.samples.count) training recordings?", isPresented: $confirmDelete) {
            Button("Delete All", role: .destructive) {
                store.removeAll()
                recorder.restart()
            }
        }
    }

    // MARK: Read aloud

    private var readAloudCard: some View {
        Card(padding: 22) {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Label("Read aloud", systemImage: "text.bubble")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.accent)
                    Spacer()
                    Text("Sentence \(min(recorder.index + 1, recorder.prompts.count)) of \(recorder.prompts.count)")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(.secondary)
                }

                if let prompt = recorder.currentPrompt {
                    Text(prompt)
                        .font(.system(size: 22, weight: .medium, design: .serif))
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, minHeight: 70, alignment: .topLeading)
                        .id(recorder.index)
                        .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity),
                                                removal: .move(edge: .leading).combined(with: .opacity)))

                    HStack(spacing: 14) {
                        Button { recorder.toggle() } label: {
                            ZStack {
                                Circle()
                                    .fill(recorder.isRecording ? Color.red : Theme.accent)
                                    .frame(width: 52, height: 52)
                                    .scaleEffect(recorder.isRecording ? 1 + CGFloat(recorder.level) * 0.18 : 1)
                                    .animation(.easeOut(duration: 0.1), value: recorder.level)
                                Image(systemName: recorder.isRecording ? "stop.fill" : "mic.fill")
                                    .font(.system(size: 18, weight: .semibold))
                                    .foregroundStyle(.white)
                            }
                        }
                        .buttonStyle(.plain)

                        VStack(alignment: .leading, spacing: 3) {
                            Text(recorder.isRecording ? "Listening… release Space or click to save" : "Hold Space (or click) and read it naturally")
                                .font(.system(size: 13, weight: .medium))
                            if let message = recorder.message {
                                Text(message).font(.system(size: 12)).foregroundStyle(Theme.warm)
                            } else {
                                Text("Speak the way you normally do — your accent is exactly what Inscribo should learn.")
                                    .font(.system(size: 12)).foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        Button("Skip") { recorder.skip() }
                            .buttonStyle(SecondaryButtonStyle())
                            .disabled(recorder.isRecording)
                        if recorder.lastSavedIndex != nil {
                            Button("Redo last") { recorder.redoLast() }
                                .buttonStyle(SecondaryButtonStyle())
                                .disabled(recorder.isRecording)
                        }
                    }
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("You've gone through every sentence", systemImage: "checkmark.seal.fill")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.green)
                        Text("Add names and terms in Dictionary to get more sentences, or start over to re-record skipped ones.")
                            .font(.system(size: 12.5))
                            .foregroundStyle(.secondary)
                        Button("Go back to skipped sentences") { recorder.restart() }
                            .buttonStyle(SecondaryButtonStyle())
                    }
                }
            }
        }
    }

    // MARK: Accuracy

    private var accuracyCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top) {
                    SectionHeader(title: "How well does Inscribo understand you?",
                                  detail: "Runs the speech model over your recordings and compares what it heard with what you said.")
                    Spacer()
                    Button(checker.isRunning ? "Checking…" : "Check accuracy") { checker.run() }
                        .buttonStyle(PrimaryButtonStyle())
                        .disabled(checker.isRunning || store.samples.isEmpty)
                        .opacity(store.samples.isEmpty ? 0.5 : 1)
                }
                if checker.isRunning {
                    ProgressView(value: checker.progress).tint(Theme.accent)
                }
                if let report = checker.report, !checker.isRunning {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("\(Int((report.accuracy * 100).rounded()))%")
                            .font(.system(size: 34, weight: .semibold, design: .rounded))
                            .foregroundStyle(report.accuracy > 0.9 ? .green : (report.accuracy > 0.8 ? Theme.warm : .red))
                        Text("of words recognised correctly · \(report.errors) mistakes in \(report.words) words across \(report.samples) recordings")
                            .font(.system(size: 12.5))
                            .foregroundStyle(.secondary)
                    }
                    if !report.commonMistakes.isEmpty {
                        Text("Most misheard").font(.system(size: 13, weight: .semibold))
                        VStack(spacing: 0) {
                            ForEach(report.commonMistakes) { mistake in
                                MistakeRow(mistake: mistake)
                                Divider()
                            }
                        }
                    }
                    if !report.worst.isEmpty {
                        Text("Hardest recordings").font(.system(size: 13, weight: .semibold)).padding(.top, 4)
                        ForEach(report.worst) { example in
                            VStack(alignment: .leading, spacing: 3) {
                                Text("You said: \(example.meant)").font(.system(size: 12.5))
                                Text("Heard: \(example.heard)").font(.system(size: 12.5)).foregroundStyle(Theme.warm)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                } else if store.samples.isEmpty {
                    Text("Record a few sentences above first.")
                        .font(.system(size: 12))
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }
}

private struct MistakeRow: View {
    let mistake: AccuracyChecker.Report.Mistake
    @State private var settings = AppSettings.shared

    private var alreadyAdded: Bool {
        settings.replacements.contains { $0.from.lowercased() == mistake.heard && $0.to.lowercased() == mistake.meant }
    }

    var body: some View {
        HStack(spacing: 10) {
            Text(mistake.heard).strikethrough().foregroundStyle(.secondary)
            Image(systemName: "arrow.right").font(.system(size: 10)).foregroundStyle(.tertiary)
            Text(mistake.meant).fontWeight(.medium)
            Text("×\(mistake.count)").font(.system(size: 11, design: .monospaced)).foregroundStyle(.tertiary)
            Spacer()
            if alreadyAdded {
                Label("Fix added", systemImage: "checkmark").font(.system(size: 11.5)).foregroundStyle(.green)
            } else {
                Button("Always fix this") {
                    settings.replacements.append(Replacement(from: mistake.heard, to: mistake.meant))
                }
                .buttonStyle(.plain)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.accent)
            }
        }
        .font(.system(size: 13))
        .padding(.vertical, 7)
    }
}
