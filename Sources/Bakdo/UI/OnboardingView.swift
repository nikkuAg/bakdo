import SwiftUI

struct OnboardingView: View {
    @State private var step: Int

    init(step: Int = 0) {
        _step = State(initialValue: step)
    }
    @State private var settings = AppSettings.shared
    @State private var permissions = Permissions.shared
    @State private var manager = ModelManager.shared
    @State private var controller = DictationController.shared

    private let stepCount = 4

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                ForEach(0..<stepCount, id: \.self) { i in
                    Capsule()
                        .fill(i <= step ? Theme.accent : Color.primary.opacity(0.12))
                        .frame(width: i == step ? 26 : 8, height: 6)
                }
            }
            .animation(.spring(response: 0.35), value: step)
            .padding(.top, 46)

            Spacer(minLength: 20)

            Group {
                switch step {
                case 0: welcome
                case 1: permissionsStep
                case 2: modelStep
                default: tryStep
                }
            }
            .frame(maxWidth: 560)
            .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity),
                                    removal: .move(edge: .leading).combined(with: .opacity)))
            .id(step)

            Spacer(minLength: 20)

            HStack {
                if step > 0 {
                    Button("Back") { go(step - 1) }.buttonStyle(SecondaryButtonStyle())
                }
                Spacer()
                Button(step == stepCount - 1 ? "Start using Bakdo" : "Continue") {
                    if step == stepCount - 1 {
                        withAnimation { settings.hasCompletedOnboarding = true }
                    } else {
                        go(step + 1)
                    }
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(!canContinue)
                .opacity(canContinue ? 1 : 0.5)
            }
            .frame(maxWidth: 560)
            .padding(.bottom, 34)
        }
        .padding(.horizontal, 40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            ZStack {
                Color(nsColor: .windowBackgroundColor)
                RadialGradient(colors: [Theme.accent.opacity(0.13), .clear], center: .top, startRadius: 0, endRadius: 520)
            }
        )
        .onAppear { permissions.startPolling() }
    }

    private var canContinue: Bool {
        switch step {
        case 1: return permissions.allGranted
        case 2: return manager.isInstalled(ModelCatalog.speech)
        default: return true
        }
    }

    private func go(_ target: Int) {
        withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) { step = target }
    }

    private var welcome: some View {
        VStack(spacing: 18) {
            AppMark(size: 76)
                .shadow(color: Theme.accent.opacity(0.35), radius: 18, y: 8)
            Text("Bas bak do.")
                .font(Theme.title(40))
            Text("Say it in English, Hindi or Hinglish — Bakdo types it into any app and fixes the grammar too. It runs completely on your Mac, so it's private and works offline.")
                .font(.system(size: 15))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 24) {
                Feature(symbol: "keyboard", text: "Works in every text box")
                Feature(symbol: "lock.shield", text: "100% on-device")
                Feature(symbol: "character.bubble", text: "Understands Hinglish")
            }
            .padding(.top, 10)
        }
    }

    private var permissionsStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Two quick permissions").font(Theme.title(30))
            Text("Bakdo listens only while you hold the shortcut, and types by pasting into whatever text box you're in.")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
            PermissionsCard()
            if permissions.microphone == .authorized && !permissions.accessibility {
                Text("After switching Bakdo on in System Settings › Privacy & Security › Accessibility, come back here — this page updates by itself.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var modelStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Getting the models").font(Theme.title(30))
            Text("One model understands English, Hindi and Hinglish, and a small writing model fixes grammar and typos — no settings to pick. They download once (about 1.9 GB), then everything runs offline on your Mac's GPU.")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Card {
                VStack(alignment: .leading, spacing: 14) {
                    ModelDownloadStatus(model: ModelCatalog.speech)
                    ModelDownloadStatus(model: ModelCatalog.writer)
                }
            }
            VStack(alignment: .leading, spacing: 6) {
                Example(say: "Send me the report by tomorrow evening.", type: "Send me the report by tomorrow evening.")
                Example(say: "यार, आज की meeting बहुत लंबी थी", type: "Yaar, aaj ki meeting bahut lambi thi.")
                Example(say: "um so i has send the file yesterday", type: "So I sent the file yesterday.")
            }
            .padding(.top, 4)
        }
        .onAppear {
            for model in ModelCatalog.all where !manager.isInstalled(model) { manager.download(model) }
        }
    }

    private var tryStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Give it a try").font(Theme.title(30))
            HStack(spacing: 6) {
                Text("Hold")
                KeyCap(text: "space")
                Text("here, or")
                KeyCap(text: settings.triggerKey.shortLabel)
                Text("in any app, and speak. Let go to insert.")
            }
            .font(.system(size: 14))
            .foregroundStyle(.secondary)

            if settings.triggerKey == .fn && !permissions.fnKeyDoesNothing {
                HStack(spacing: 8) {
                    Image(systemName: "globe").foregroundStyle(Theme.warm)
                    Text("Tip: set System Settings › Keyboard › “Press 🌐 key to” → Do Nothing.")
                        .font(.system(size: 12))
                    Spacer()
                    Button("Open") { permissions.openKeyboardSettings() }.buttonStyle(SecondaryButtonStyle())
                }
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 10).fill(Theme.warm.opacity(0.08)))
            }

            TryBox()

            HStack(spacing: 6) {
                Text("Prefer another key?").foregroundStyle(.secondary)
                Picker("", selection: $settings.triggerKey) {
                    ForEach(TriggerKey.allCases) { Text($0.label).tag($0) }
                }
                .labelsHidden()
                .frame(width: 180)
                .onChange(of: settings.triggerKey) { controller.updateTriggerKey() }
            }
            .font(.system(size: 12.5))
        }
    }
}

private struct Example: View {
    let say: String
    let type: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "waveform").foregroundStyle(Theme.accent).frame(width: 16)
            Text("“\(say)”").foregroundStyle(.secondary)
            Image(systemName: "arrow.right").font(.system(size: 10)).foregroundStyle(.tertiary)
            Text(type).fontWeight(.medium)
        }
        .font(.system(size: 12.5))
    }
}

private struct Feature: View {
    let symbol: String
    let text: String

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 18))
                .foregroundStyle(Theme.accent)
                .frame(width: 42, height: 42)
                .background(Circle().fill(Theme.accentSoft))
            Text(text).font(.system(size: 12)).foregroundStyle(.secondary)
        }
    }
}

private struct TryBox: View {
    @State private var text = ""
    @State private var controller = DictationController.shared
    @FocusState private var focused: Bool

    var body: some View {
        Card(padding: 12) {
            VStack(alignment: .leading, spacing: 6) {
                TextEditor(text: $text)
                    .font(.system(size: 15))
                    .scrollContentBackground(.hidden)
                    .focused($focused)
                    .frame(height: 110)
                HStack {
                    statusText
                    Spacer()
                    if !text.isEmpty {
                        Button("Clear") { text = "" }.buttonStyle(.plain).font(.system(size: 12)).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .holdSpaceToDictate(focus: $focused)
    }

    @ViewBuilder
    private var statusText: some View {
        Group {
            switch controller.phase {
            case .recording: Label("Listening…", systemImage: "waveform").foregroundStyle(Theme.accent)
            case .transcribing: Label("Transcribing…", systemImage: "ellipsis").foregroundStyle(.secondary)
            default:
                switch controller.engineState {
                case .loading: Label("Loading model…", systemImage: "hourglass").foregroundStyle(.secondary)
                case .ready: Label("Ready", systemImage: "checkmark.circle").foregroundStyle(.green)
                default: EmptyView()
                }
            }
        }
        .font(.system(size: 12, weight: .medium))
    }
}
