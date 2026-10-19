import AppKit
import CoreGraphics

/// Watches the trigger key system-wide through a CGEventTap (needs Accessibility permission).
final class HotkeyMonitor {
    enum Event {
        case pressed
        case released
        /// Another key was pressed while the trigger was held (e.g. fn+arrow), so it isn't a dictation.
        case chord
        case escape
        /// The "fix selected text" shortcut.
        case fixShortcut
    }

    var triggerKey: TriggerKey = .fn
    /// When true, Esc is swallowed and reported as `.escape`.
    var capturesEscape = false
    var handler: ((Event) -> Void)?
    var fixShortcut: KeyShortcut?
    /// Set while the user is recording a new shortcut in Settings, so keys reach the recorder.
    var shortcutsSuspended = false

    private(set) var isRunning = false
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var retryTimer: Timer?
    private var triggerDown = false
    private var triggerDownAt = Date.distantPast

    /// Keys pressed this soon after the trigger make it a shortcut rather than dictation.
    private let chordWindow: TimeInterval = 0.5

    func start() {
        guard !isRunning else { return }
        if installTap() { return }
        // Accessibility not granted yet: keep trying quietly until it is.
        retryTimer?.invalidate()
        retryTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] timer in
            if self?.installTap() == true { timer.invalidate() }
        }
    }

    func stop() {
        retryTimer?.invalidate()
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        tap = nil
        source = nil
        isRunning = false
    }

    private func installTap() -> Bool {
        guard AXIsProcessTrusted() else { return false }
        let mask = (1 << CGEventType.flagsChanged.rawValue) | (1 << CGEventType.keyDown.rawValue)
        let callback: CGEventTapCallBack = { _, type, event, refcon in
            guard let refcon else { return Unmanaged.passUnretained(event) }
            let monitor = Unmanaged<HotkeyMonitor>.fromOpaque(refcon).takeUnretainedValue()
            return monitor.handle(type: type, event: event)
        }
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap,
                                          options: .defaultTap, eventsOfInterest: CGEventMask(mask),
                                          callback: callback,
                                          userInfo: Unmanaged.passUnretained(self).toOpaque()) else {
            return false
        }
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        self.tap = tap
        self.source = source
        isRunning = true
        NotificationCenter.default.post(name: .bakdoHotkeyReady, object: nil)
        return true
    }

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)

        case .flagsChanged:
            let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
            if keyCode == triggerKey.keyCode {
                let down = isTriggerFlagSet(event.flags)
                if down && !triggerDown {
                    triggerDown = true
                    triggerDownAt = Date()
                    handler?(.pressed)
                } else if !down && triggerDown {
                    triggerDown = false
                    handler?(.released)
                }
            } else if triggerDown, Date().timeIntervalSince(triggerDownAt) < chordWindow {
                handler?(.chord)
            }
            return Unmanaged.passUnretained(event)

        case .keyDown:
            let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
            if keyCode == 53, capturesEscape {
                handler?(.escape)
                return nil
            }
            if !shortcutsSuspended, let shortcut = fixShortcut, keyCode == shortcut.keyCode,
               event.flags.rawValue & KeyShortcut.relevantModifiers == shortcut.modifiers {
                if event.getIntegerValueField(.keyboardEventAutorepeat) == 0 { handler?(.fixShortcut) }
                return nil
            }
            if triggerDown, Date().timeIntervalSince(triggerDownAt) < chordWindow {
                handler?(.chord)
            }
            return Unmanaged.passUnretained(event)

        default:
            return Unmanaged.passUnretained(event)
        }
    }

    private func isTriggerFlagSet(_ flags: CGEventFlags) -> Bool {
        switch triggerKey {
        case .fn: return flags.contains(.maskSecondaryFn)
        case .rightOption: return flags.contains(.maskAlternate)
        case .rightCommand: return flags.contains(.maskCommand)
        case .rightControl: return flags.contains(.maskControl)
        }
    }
}

extension Notification.Name {
    static let bakdoHotkeyReady = Notification.Name("bakdoHotkeyReady")
}
