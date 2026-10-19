import CoreGraphics
import Foundation
import Observation

enum TriggerKey: String, CaseIterable, Identifiable, Codable {
    case fn, rightOption, rightCommand, rightControl

    var id: String { rawValue }

    var label: String {
        switch self {
        case .fn: return "fn (Globe)"
        case .rightOption: return "Right ⌥ Option"
        case .rightCommand: return "Right ⌘ Command"
        case .rightControl: return "Right ⌃ Control"
        }
    }

    var shortLabel: String {
        switch self {
        case .fn: return "fn"
        case .rightOption: return "right ⌥"
        case .rightCommand: return "right ⌘"
        case .rightControl: return "right ⌃"
        }
    }

    /// Virtual key code delivered with the flagsChanged event.
    var keyCode: Int64 {
        switch self {
        case .fn: return 63
        case .rightOption: return 61
        case .rightCommand: return 54
        case .rightControl: return 62
        }
    }
}

/// A global key combination, e.g. ⌃⌥G.
struct KeyShortcut: Codable, Equatable {
    var keyCode: Int64
    /// Raw CGEventFlags restricted to ⌘ ⌥ ⌃ ⇧.
    var modifiers: UInt64
    /// Printable key name captured when the shortcut was recorded.
    var key: String

    static let relevantModifiers: UInt64 = CGEventFlags.maskCommand.rawValue | CGEventFlags.maskAlternate.rawValue
        | CGEventFlags.maskControl.rawValue | CGEventFlags.maskShift.rawValue

    static let defaultFix = KeyShortcut(keyCode: 5,
                                        modifiers: CGEventFlags.maskControl.rawValue | CGEventFlags.maskAlternate.rawValue,
                                        key: "G")

    var display: String {
        var s = ""
        if modifiers & CGEventFlags.maskControl.rawValue != 0 { s += "⌃" }
        if modifiers & CGEventFlags.maskAlternate.rawValue != 0 { s += "⌥" }
        if modifiers & CGEventFlags.maskShift.rawValue != 0 { s += "⇧" }
        if modifiers & CGEventFlags.maskCommand.rawValue != 0 { s += "⌘" }
        return s + key
    }
}

struct Replacement: Codable, Identifiable, Hashable {
    var id = UUID()
    var from: String
    var to: String
}

/// User preferences, persisted in UserDefaults. Every property writes through on change.
@Observable
final class AppSettings {
    static let shared = AppSettings()

    private let defaults = UserDefaults.standard

    var triggerKey: TriggerKey { didSet { defaults.set(triggerKey.rawValue, forKey: "triggerKey") } }
    var removeFillers: Bool { didSet { defaults.set(removeFillers, forKey: "removeFillers") } }
    var spokenCommands: Bool { didSet { defaults.set(spokenCommands, forKey: "spokenCommands") } }
    var smartSpacing: Bool { didSet { defaults.set(smartSpacing, forKey: "smartSpacing") } }
    /// Fix grammar, spelling and punctuation of every dictation with the local writing model.
    var autoCorrect: Bool { didSet { defaults.set(autoCorrect, forKey: "autoCorrect") } }
    var fixShortcutEnabled: Bool { didSet { defaults.set(fixShortcutEnabled, forKey: "fixShortcutEnabled") } }
    var fixShortcut: KeyShortcut {
        didSet { defaults.set(try? JSONEncoder().encode(fixShortcut), forKey: "fixShortcut") }
    }
    var playSounds: Bool { didSet { defaults.set(playSounds, forKey: "playSounds") } }
    var showIdlePill: Bool { didSet { defaults.set(showIdlePill, forKey: "showIdlePill") } }
    var showInDock: Bool { didSet { defaults.set(showInDock, forKey: "showInDock") } }
    /// Keep each dictation's audio (with its final text) as data for a personal fine-tune.
    var keepTrainingAudio: Bool { didSet { defaults.set(keepTrainingAudio, forKey: "keepTrainingAudio") } }
    var inputDeviceUID: String { didSet { defaults.set(inputDeviceUID, forKey: "inputDeviceUID") } }
    var hasCompletedOnboarding: Bool { didSet { defaults.set(hasCompletedOnboarding, forKey: "hasCompletedOnboarding") } }
    var vocabulary: [String] { didSet { defaults.set(vocabulary, forKey: "vocabulary") } }
    var replacements: [Replacement] {
        didSet { defaults.set(try? JSONEncoder().encode(replacements), forKey: "replacements") }
    }

    private init() {
        defaults.register(defaults: [
            "triggerKey": TriggerKey.fn.rawValue,
            "removeFillers": true,
            "spokenCommands": true,
            "smartSpacing": true,
            "autoCorrect": true,
            "fixShortcutEnabled": true,
            "playSounds": true,
            "showIdlePill": false,
            "showInDock": true,
            "keepTrainingAudio": false,
            "inputDeviceUID": "",
            "hasCompletedOnboarding": false,
        ])
        triggerKey = TriggerKey(rawValue: defaults.string(forKey: "triggerKey") ?? "") ?? .fn
        removeFillers = defaults.bool(forKey: "removeFillers")
        spokenCommands = defaults.bool(forKey: "spokenCommands")
        smartSpacing = defaults.bool(forKey: "smartSpacing")
        autoCorrect = defaults.bool(forKey: "autoCorrect")
        fixShortcutEnabled = defaults.bool(forKey: "fixShortcutEnabled")
        if let data = defaults.data(forKey: "fixShortcut"),
           let shortcut = try? JSONDecoder().decode(KeyShortcut.self, from: data) {
            fixShortcut = shortcut
        } else {
            fixShortcut = .defaultFix
        }
        playSounds = defaults.bool(forKey: "playSounds")
        showIdlePill = defaults.bool(forKey: "showIdlePill")
        showInDock = defaults.bool(forKey: "showInDock")
        keepTrainingAudio = defaults.bool(forKey: "keepTrainingAudio")
        inputDeviceUID = defaults.string(forKey: "inputDeviceUID") ?? ""
        hasCompletedOnboarding = defaults.bool(forKey: "hasCompletedOnboarding")
        vocabulary = defaults.stringArray(forKey: "vocabulary") ?? []
        if let data = defaults.data(forKey: "replacements"),
           let list = try? JSONDecoder().decode([Replacement].self, from: data) {
            replacements = list
        } else {
            replacements = []
        }
    }
}
