import SwiftUI

/// Progress / state of the single speech model. It downloads automatically on first launch;
/// this view only reports on it and offers a retry if the download failed.
struct ModelDownloadStatus: View {
    var model: ModelInfo = ModelCatalog.speech
    var compact = false
    @State private var manager = ModelManager.shared
    @State private var controller = DictationController.shared

    private var title: String { model.id == ModelCatalog.writer.id ? "Writing model" : "Speech model" }
    private var engineState: DictationController.EngineState {
        model.id == ModelCatalog.writer.id ? controller.writerState : controller.engineState
    }

    var body: some View {
        switch manager.state(for: model) {
        case .downloading(let progress):
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(compact ? "Downloading model" : "Downloading \(title.lowercased())…")
                        .font(.system(size: 12, weight: .semibold))
                    Spacer()
                    Text("\(Int(progress * 100))%")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                ProgressView(value: progress)
                if !compact {
                    Text("\(ByteCountFormatter.string(fromByteCount: Int64(Double(model.sizeBytes) * progress), countStyle: .file)) of \(ByteCountFormatter.string(fromByteCount: model.sizeBytes, countStyle: .file))")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }
            }
        case .failed(let reason):
            VStack(alignment: .leading, spacing: 6) {
                Label("\(title) download failed", systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.warm)
                Text(reason).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(2)
                Button("Try again") { manager.download(model) }
                    .buttonStyle(SecondaryButtonStyle())
            }
        case .idle:
            if manager.isInstalled(model) {
                HStack(spacing: 8) {
                    if engineState == .loading {
                        ProgressView().controlSize(.small)
                        Text("Loading \(title.lowercased())…").font(.system(size: 12, weight: .medium))
                    } else {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                        Text("\(title) ready").font(.system(size: 12, weight: .semibold))
                    }
                }
            } else {
                Button("Download \(title.lowercased())") { manager.download(model) }
                    .buttonStyle(PrimaryButtonStyle())
            }
        }
    }
}

/// Settings card describing what runs under the hood.
struct SpeechModelCard: View {
    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: "On-device models",
                              detail: "Automatic. One model understands English, Hindi and Hinglish — English is typed as English, Hindi in Roman script (\"kal milte hain\"). A second, small model fixes grammar and typos. Nothing leaves your Mac.")
                ModelDownloadStatus(model: ModelCatalog.speech)
                ModelDownloadStatus(model: ModelCatalog.writer)
                Text("\(ModelCatalog.speech.name) via whisper.cpp · \(ModelCatalog.writer.name) via llama.cpp · both on Metal")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }
        }
    }
}
