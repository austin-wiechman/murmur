import Foundation

public enum CleanupEngine: String, Codable, CaseIterable, Sendable {
    case off
    case onDevice
    case claude
}

extension CleanupEngine {
    /// The engine a dictation uses. Claude needs Claude Code and a network connection, and falls back
    /// to on-device cleanup, which needs Apple Intelligence. With neither, cleanup is off.
    public func resolved(claudeInstalled: Bool, onDeviceAvailable: Bool, online: Bool) -> CleanupEngine {
        switch self {
        case .claude where claudeInstalled && online: .claude
        case .claude, .onDevice: onDeviceAvailable ? .onDevice : .off
        case .off: .off
        }
    }
}
