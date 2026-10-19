import ServiceManagement
import SwiftUI

struct SettingsView: View {
    @State private var settings = AppSettings.shared
    @State private var permissions = Permissions.shared
    @State private var devices: [AudioInputDevice] = []
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var confirmClear = false

    var body: some View {
        PageScaffold(title: "Settings") {
            PermissionsCard()

            SpeechModelCard()

            Card {
                VStack(alignment: .leading, spacing: 14) {
                    SectionHeader(title: "Shortcut", detail: "Hold to talk, release to insert. Double-tap for hands-free mode, then tap once to finish. Esc cancels.")
                    Picker("Dictation key", selection: $settings.triggerKey) {
                        ForEach(TriggerKey.allCases) { Text($0.label).tag($0) }
                    }
                    .frame(maxWidth: 360)
                    .onChange(of: settings.triggerKey) { DictationController.shared.updateTriggerKey() }

                    if settings.triggerKey == .fn && !permissions.fnKeyDoesNothing {
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: "globe").foregroundStyle(Theme.warm)
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Set “Press 🌐 key to” → “Do Nothing”")
                                    .font(.system(size: 12.5, weight: .semibold))
                                Text("Otherwise macOS opens the emoji picker or switches input source every time you dictate. It's in System Settings › Keyboard.")
                                    .font(.system(size: 12))
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                                Button("Open Keyboard Settings") { permissions.openKeyboardSettings() }
                                    .buttonStyle(SecondaryButtonStyle())
                            }
                        }
                        .padding(12)
                        .background(RoundedRectangle(cornerRadius: 10).fill(Theme.warm.opacity(0.08)))
                    }
                }
            }

            Card {
                VStack(alignment: .leading, spacing: 12) {
                    SectionHeader(title: "Reparo — fix selected text",
                                  detail: "Select text in any app and press the shortcut — Inscribo fixes typos and grammar in place.")
                    Toggle("Enable shortcut", isOn: $settings.fixShortcutEnabled)
                        .toggleStyle(.checkbox)
                        .onChange(of: settings.fixShortcutEnabled) {
                            DictationController.shared.updateFixShortcut()
                            DictationController.shared.loadWriter()
                        }
                    HStack(spacing: 10) {
                        Text("Shortcut").font(.system(size: 13))
                        ShortcutRecorder(shortcut: $settings.fixShortcut)
                            .onChange(of: settings.fixShortcut) { DictationController.shared.updateFixShortcut() }
                        if settings.fixShortcut != .defaultFix {
                            Button("Reset") { settings.fixShortcut = .defaultFix }
                                .buttonStyle(.plain)
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .disabled(!settings.fixShortcutEnabled)
                    .opacity(settings.fixShortcutEnabled ? 1 : 0.5)
                }
            }

            Card {
                VStack(alignment: .leading, spacing: 14) {
                    SectionHeader(title: "Microphone", detail: "Built-in mics work well. Bluetooth headsets switch to a lower call-quality mode while recording.")
                    Picker("Input", selection: $settings.inputDeviceUID) {
                        Text("System default").tag("")
                        ForEach(devices) { Text($0.name).tag($0.uid) }
                    }
                    .frame(maxWidth: 360)
                }
            }

            Card {
                VStack(alignment: .leading, spacing: 12) {
                    SectionHeader(title: "Writing", detail: "How Inscribo cleans up what you say before typing it.")
                    Toggle("Remove filler words (um, uh, hmm) and stutters", isOn: $settings.removeFillers)
                    Toggle("Voice commands (“new line”, “new paragraph”)", isOn: $settings.spokenCommands)
                    Toggle("Add a space when continuing a sentence", isOn: $settings.smartSpacing)
                    VStack(alignment: .leading, spacing: 4) {
                        Toggle("Auto-correct grammar, spelling and punctuation", isOn: $settings.autoCorrect)
                            .onChange(of: settings.autoCorrect) { DictationController.shared.loadWriter() }
                        Text("A small on-device writing model polishes every dictation — Hinglish stays Hinglish. Adds about a second.")
                            .font(.system(size: 11.5))
                            .foregroundStyle(.secondary)
                            .padding(.leading, 20)
                    }
                }
                .toggleStyle(.checkbox)
                .font(.system(size: 13))
            }

            Card {
                VStack(alignment: .leading, spacing: 12) {
                    SectionHeader(title: "App", detail: "")
                    Toggle("Show the dictation bar when idle", isOn: $settings.showIdlePill)
                    Toggle("Play sounds", isOn: $settings.playSounds)
                    Toggle("Show in Dock", isOn: $settings.showInDock)
                        .onChange(of: settings.showInDock) { AppDelegate.shared?.applyDockPreference() }
                    Toggle("Open at login", isOn: $launchAtLogin)
                        .onChange(of: launchAtLogin) { _, enabled in
                            do {
                                if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                            } catch {
                                launchAtLogin = SMAppService.mainApp.status == .enabled
                            }
                        }
                }
                .toggleStyle(.checkbox)
                .font(.system(size: 13))
            }

            Card {
                HStack {
                    SectionHeader(title: "History", detail: "\(HistoryStore.shared.items.count) dictations stored on this Mac.")
                    Spacer()
                    Button("Clear History…") { confirmClear = true }
                        .buttonStyle(SecondaryButtonStyle())
                }
            }
            .confirmationDialog("Delete all dictation history?", isPresented: $confirmClear) {
                Button("Delete All", role: .destructive) { HistoryStore.shared.clear() }
            }

            Text("Inscribo \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev") · Speech models by OpenAI (Whisper) and Oriserve, run with whisper.cpp")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
        }
        .onAppear {
            devices = AudioRecorder.inputDevices()
            permissions.startPolling()
        }
    }
}

struct PermissionsCard: View {
    @State private var permissions = Permissions.shared

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: "Permissions", detail: "Inscribo listens only while you hold the key, and types by pasting into the focused app.")
                PermissionRow(title: "Microphone", detail: "To hear you", symbol: "mic.fill",
                              granted: permissions.microphone == .authorized) {
                    Task { _ = await permissions.requestMicrophone() }
                }
                PermissionRow(title: "Accessibility", detail: "To detect the shortcut and type into other apps", symbol: "accessibility",
                              granted: permissions.accessibility) {
                    permissions.requestAccessibility()
                }
            }
        }
    }
}

struct PermissionRow: View {
    let title: String
    let detail: String
    let symbol: String
    let granted: Bool
    let action: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(granted ? Color.green : Theme.accent)
                .frame(width: 30, height: 30)
                .background(Circle().fill((granted ? Color.green : Theme.accent).opacity(0.12)))
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.system(size: 13, weight: .medium))
                Text(detail).font(.system(size: 11.5)).foregroundStyle(.secondary)
            }
            Spacer()
            if granted {
                Label("Granted", systemImage: "checkmark.circle.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.green)
            } else {
                Button("Grant", action: action).buttonStyle(PrimaryButtonStyle())
            }
        }
    }
}
