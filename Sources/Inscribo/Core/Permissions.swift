import AppKit
import AVFoundation
import Observation

@MainActor
@Observable
final class Permissions {
    static let shared = Permissions()

    private(set) var microphone: AVAuthorizationStatus = .notDetermined
    private(set) var accessibility = false
    /// What the Globe key does by itself (System Settings › Keyboard). Anything other than
    /// "Do Nothing" pops a system UI every time fn is used for dictation.
    private(set) var fnKeyDoesNothing = true

    private var timer: Timer?

    var allGranted: Bool { microphone == .authorized && accessibility }

    init() {
        refresh()
    }

    func refresh() {
        microphone = AVCaptureDevice.authorizationStatus(for: .audio)
        accessibility = AXIsProcessTrusted()
        let fnUsage = UserDefaults(suiteName: "com.apple.HIToolbox")?.object(forKey: "AppleFnUsageType") as? Int
        fnKeyDoesNothing = fnUsage == 0
    }

    /// Polls while onboarding or settings are visible so the UI updates as soon as the user flips a switch.
    func startPolling() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            Task { @MainActor in Permissions.shared.refresh() }
        }
    }

    func stopPolling() {
        timer?.invalidate()
        timer = nil
    }

    func requestMicrophone() async -> Bool {
        if microphone == .denied || microphone == .restricted {
            openSettings("Privacy_Microphone")
            return false
        }
        let granted = await AVCaptureDevice.requestAccess(for: .audio)
        refresh()
        return granted
    }

    func requestAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        if !AXIsProcessTrustedWithOptions(options) {
            openSettings("Privacy_Accessibility")
        }
        refresh()
    }

    func openKeyboardSettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension")!)
    }

    func openSettings(_ anchor: String) {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)")!)
    }
}
