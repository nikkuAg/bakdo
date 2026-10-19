import AppKit
import SwiftUI

/// Inside Inscribo's window: hold Space to dictate. If no text box has focus, the attached box is
/// focused first. A quick tap still types a normal space.
@MainActor
final class SpaceHoldMonitor {
    var focusTarget: () -> Void = {}

    private var monitor: Any?
    private var holding = false
    private var typedIntoFocusedField = false

    func install() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp]) { [weak self] event in
            guard let self else { return event }
            return self.handle(event)
        }
    }

    func remove() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        if holding { _ = DictationController.shared.inAppHoldEnded() }
        holding = false
    }

    private func handle(_ event: NSEvent) -> NSEvent? {
        guard event.keyCode == 49, let window = event.window, window.isKeyWindow else { return event }
        let controller = DictationController.shared

        switch event.type {
        case .keyDown:
            if holding { return nil } // swallow key repeat while dictating
            let modifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
            guard modifiers.isEmpty, !event.isARepeat, controller.canStartInApp,
                  !controller.hotkey.shortcutsSuspended else { return event }
            typedIntoFocusedField = Self.editingTextView(in: window) != nil
            if !typedIntoFocusedField { focusTarget() }
            holding = true
            controller.inAppHoldBegan()
            return nil

        case .keyUp:
            guard holding else { return event }
            holding = false
            let wasTap = controller.inAppHoldEnded()
            if wasTap, typedIntoFocusedField, let textView = Self.editingTextView(in: window) {
                textView.insertText(" ", replacementRange: NSRange(location: NSNotFound, length: 0))
            }
            return nil

        default:
            return event
        }
    }

    private static func editingTextView(in window: NSWindow) -> NSTextView? {
        guard let textView = window.firstResponder as? NSTextView, textView.isEditable else { return nil }
        return textView
    }
}

private struct HoldSpaceToDictate: ViewModifier {
    var focus: FocusState<Bool>.Binding
    @State private var monitor = SpaceHoldMonitor()

    func body(content: Content) -> some View {
        content
            .onAppear {
                monitor.focusTarget = { focus.wrappedValue = true }
                monitor.install()
            }
            .onDisappear { monitor.remove() }
    }
}

extension View {
    /// Hold Space anywhere in the window to dictate into this view (focusing it if nothing else has focus).
    func holdSpaceToDictate(focus: FocusState<Bool>.Binding) -> some View {
        modifier(HoldSpaceToDictate(focus: focus))
    }
}
