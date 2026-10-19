import AppKit
import SwiftUI

/// Click, then press a key combination (must include ⌘, ⌥ or ⌃). Esc cancels.
struct ShortcutRecorder: View {
    @Binding var shortcut: KeyShortcut
    @State private var recording = false
    @State private var monitor: Any?

    var body: some View {
        Button {
            recording ? stop() : start()
        } label: {
            Text(recording ? "Press keys…" : shortcut.display)
                .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                .foregroundStyle(recording ? Theme.accent : Color.primary)
                .frame(minWidth: 96)
                .padding(.vertical, 5)
                .padding(.horizontal, 10)
                .background(RoundedRectangle(cornerRadius: 7).fill(recording ? Theme.accentSoft : Color.primary.opacity(0.07)))
                .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(recording ? Theme.accent : Color.primary.opacity(0.12)))
        }
        .buttonStyle(.plain)
        .help("Click to record a new shortcut")
        .onDisappear { stop() }
    }

    private func start() {
        recording = true
        DictationController.shared.hotkey.shortcutsSuspended = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53 { // esc
                stop()
                return nil
            }
            let flags = event.modifierFlags.intersection([.command, .option, .control, .shift])
            guard !flags.intersection([.command, .option, .control]).isEmpty else {
                NSSound.beep()
                return nil
            }
            var modifiers: UInt64 = 0
            if flags.contains(.command) { modifiers |= CGEventFlags.maskCommand.rawValue }
            if flags.contains(.option) { modifiers |= CGEventFlags.maskAlternate.rawValue }
            if flags.contains(.control) { modifiers |= CGEventFlags.maskControl.rawValue }
            if flags.contains(.shift) { modifiers |= CGEventFlags.maskShift.rawValue }
            shortcut = KeyShortcut(keyCode: Int64(event.keyCode), modifiers: modifiers, key: Self.keyName(event))
            stop()
            return nil
        }
    }

    private func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        recording = false
        DictationController.shared.hotkey.shortcutsSuspended = false
    }

    private static func keyName(_ event: NSEvent) -> String {
        let special: [UInt16: String] = [
            49: "Space", 36: "↩", 48: "⇥", 51: "⌫", 117: "⌦", 123: "←", 124: "→", 125: "↓", 126: "↑",
            122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6", 98: "F7", 100: "F8",
            101: "F9", 109: "F10", 103: "F11", 111: "F12",
        ]
        if let name = special[event.keyCode] { return name }
        return (event.charactersIgnoringModifiers ?? "?").uppercased()
    }
}
