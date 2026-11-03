import AVFoundation
import MurmurCore
import MurmurEngine
import Observation

/// App-level status the menu and Settings show.
@MainActor @Observable
final class StatusStore {
    var engine: EngineStatus = .ready
    var launchAtLogin = false
    var accessibility = true
    var microphone: AVAuthorizationStatus = .authorized
    var claudeInstalled = true
    var onDeviceAvailable = true
    var setup = Setup(confirmed: true)
    var modelProgress: Transcriber.LoadProgress?
    var menuOpen = false
    var automaticUpdates = true

    var missingPermissions: [Permission] {
        (accessibility ? [] : [.accessibility]) + (microphone == .authorized ? [] : [.microphone])
    }
    /// Registers or unregisters the login item; AppDelegate supplies the implementation.
    var setLaunchAtLogin: (Bool) -> Void = { _ in }
    /// Saves the answer where Sparkle reads it, which also stops Sparkle asking on its own.
    var setAutomaticUpdates: (Bool) -> Void = { _ in }
}

extension Preferences {
    var shortcutHint: String {
        holdToTalk ? "Hold \(hotkeys.spoken) to talk, tap to lock" : "Tap \(hotkeys.spoken) to start and stop"
    }
}

extension Array where Element == Hotkey {
    /// "F13 or Globe", in the user's order.
    var spoken: String {
        let names = map(\.label)
        switch names.count {
        case 0: return "your shortcut"
        case 1: return names[0]
        default: return names.dropLast().joined(separator: ", ") + " or " + names.last!
        }
    }
}
