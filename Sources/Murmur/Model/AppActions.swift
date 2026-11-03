import Foundation

/// What views can ask the app to do. `DictationController` implements it; previews can stub it.
@MainActor
protocol AppActions: AnyObject {
    func stopLocked()
    func cancelDictation()
    func pasteLast()
    func copy(_ entry: HistoryEntry)
    func repaste(_ entry: HistoryEntry)
    func openSettings(section: SettingsSection)
    /// Returns whether the menu should play the one-time "ready" confirmation now.
    func takeSetupConfirmation() -> Bool
    /// Asks for the permission, or opens its System Settings pane once macOS stops asking.
    func grant(_ permission: Permission)
    /// Pauses dictation keys while Settings records a new shortcut.
    func setRecordingShortcut(_ recording: Bool)
    func checkForUpdates()
    /// Checks again for Claude Code and Apple Intelligence, so turning either on while Murmur runs
    /// enables its cleanup option.
    func refreshCleanupEngines()
    func quit()
}

enum Permission: CaseIterable, Identifiable {
    case accessibility, microphone
    var id: Self { self }
}

enum SettingsSection: String, CaseIterable, Identifiable {
    case general, speech, cleanup, history
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    var symbol: String {
        switch self {
        case .general: "gearshape"
        case .speech: "waveform"
        case .cleanup: "sparkle"
        case .history: "clock"
        }
    }
}

/// Status the menu and the Speech settings show.
enum EngineStatus: Equatable {
    case ready
    case preparingSpeechModel
    case needsPermission(String)
}
