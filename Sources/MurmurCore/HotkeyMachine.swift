import Foundation

/// Turns dictation-key events into commands. Recording starts on key-down so no words are lost
/// while deciding between a hold and a tap.
public struct HotkeyMachine: Sendable {
    public enum Command: Equatable, Sendable {
        case start
        case lock
        case finish
        case cancel
    }

    public enum Phase: Equatable, Sendable {
        case idle
        case pressed(at: TimeInterval)
        case holding
        case locked
        case lockedPressed
    }

    public private(set) var phase: Phase = .idle
    public var holdThreshold: TimeInterval

    public init(holdThreshold: TimeInterval = 0.25) {
        self.holdThreshold = holdThreshold
    }

    public var isRecording: Bool { phase != .idle }

    public mutating func keyDown(at time: TimeInterval) -> Command? {
        switch phase {
        case .idle:
            phase = .pressed(at: time)
            return .start
        case .locked:
            phase = .lockedPressed
            return .finish
        case .pressed, .holding, .lockedPressed:
            return nil
        }
    }

    public mutating func keyUp(at time: TimeInterval) -> Command? {
        switch phase {
        case .pressed(let downAt):
            if time - downAt >= holdThreshold {
                phase = .idle
                return .finish
            }
            phase = .locked
            return .lock
        case .holding:
            phase = .idle
            return .finish
        case .lockedPressed:
            phase = .idle
            return nil
        case .idle, .locked:
            return nil
        }
    }

    /// After this, another key no longer cancels: a long hold is dictation, not a Globe shortcut.
    public mutating func holdTimerFired() {
        if case .pressed = phase { phase = .holding }
    }

    /// Another key during a short hold means the user was typing a Globe shortcut (Globe+arrow).
    public mutating func otherKeyDown() -> Command? {
        guard case .pressed = phase else { return nil }
        phase = .idle
        return .cancel
    }

    public mutating func escape() -> Command? {
        switch phase {
        case .idle, .lockedPressed:
            return nil
        case .pressed, .holding, .locked:
            phase = .idle
            return .cancel
        }
    }

    /// The pipeline ended the session on its own (error, time limit) while recording.
    public mutating func reset() {
        phase = .idle
    }
}
