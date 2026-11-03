import Foundation
import MurmurCore
import MurmurEngine
import Observation

enum ClaudeModel: String, CaseIterable, Identifiable {
    case haiku, sonnet
    var id: String { rawValue }
    var label: String { self == .haiku ? "Haiku (fastest)" : "Sonnet (best formatting)" }
}

@MainActor @Observable
final class Preferences {
    private let defaults: UserDefaults

    /// Any of these starts and stops dictation; never empty.
    var hotkeys: [Hotkey] { didSet { save(try? JSONEncoder().encode(hotkeys), "hotkeys") } }
    var holdToTalk: Bool { didSet { save(holdToTalk, "holdToTalk") } }
    var keepMicWarmSeconds: Double { didSet { save(keepMicWarmSeconds, "keepMicWarmSeconds") } }
    var showLiveWords: Bool { didSet { save(showLiveWords, "showLiveWords") } }
    var startSound: Bool { didSet { save(startSound, "startSound") } }
    var cleanupEngine: CleanupEngine { didSet { save(cleanupEngine.rawValue, "cleanupEngine") } }
    var claudeModel: ClaudeModel { didSet { save(claudeModel.rawValue, "claudeModel") } }
    /// Base cleanup limit in seconds; `CleanupDeadline` extends it for long dictations.
    var cleanupTimeout: Double { didSet { save(cleanupTimeout, "cleanupTimeout") } }
    var customInstructions: String { didSet { save(customInstructions, "customInstructions") } }
    /// The one-time "Murmur is ready" confirmation has played or been skipped.
    var setupConfirmed: Bool { didSet { save(setupConfirmed, "setupConfirmed") } }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        hotkeys = defaults.data(forKey: "hotkeys").flatMap { try? JSONDecoder().decode([Hotkey].self, from: $0) }
            .flatMap { $0.isEmpty ? nil : $0 } ?? Hotkey.defaults
        holdToTalk = defaults.object(forKey: "holdToTalk") as? Bool ?? true
        keepMicWarmSeconds = defaults.object(forKey: "keepMicWarmSeconds") as? Double ?? 60
        showLiveWords = defaults.object(forKey: "showLiveWords") as? Bool ?? false
        startSound = defaults.object(forKey: "startSound") as? Bool ?? true
        cleanupEngine = CleanupEngine(rawValue: defaults.string(forKey: "cleanupEngine") ?? "") ?? .onDevice
        claudeModel = ClaudeModel(rawValue: defaults.string(forKey: "claudeModel") ?? "") ?? .haiku
        cleanupTimeout = defaults.object(forKey: "cleanupTimeout") as? Double ?? 3
        customInstructions = defaults.string(forKey: "customInstructions") ?? ""
        setupConfirmed = defaults.bool(forKey: "setupConfirmed")
    }

    var instructions: String {
        customInstructions.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? CleanupPrompt.defaultInstructions : customInstructions
    }

    private func save(_ value: Any?, _ key: String) {
        defaults.set(value, forKey: key)
    }
}
