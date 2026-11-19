/// What the capture engine is bound to, so `AudioCapture` knows when to build a new one.
///
/// An engine stays on the input it first used. With voice processing on it is also bound to the
/// output that was current when voice processing turned on, whose sound it cancels.
public struct MicEngineState: Equatable, Sendable {
    /// Nil until the engine's input node is first used.
    public private(set) var route: AudioRoute?
    public private(set) var voiceProcessing = false
    /// Where voice processing turned on but the engine wouldn't start. That route records from the
    /// plain mic until the devices or the setting change; it survives replacing the engine.
    public private(set) var voiceProcessingFailedOn: AudioRoute?

    public init() {}

    public func allowsVoiceProcessing(on now: AudioRoute) -> Bool {
        voiceProcessingFailedOn != now
    }

    /// A running engine that rode out a rate change keeps going, so the rate only counts when it's
    /// stopped; that also ignores whatever rate a running voice processing engine reports.
    public func needsNewEngine(on now: AudioRoute, engineRunning: Bool) -> Bool {
        guard let route else { return false }
        if now.input != route.input { return true }
        if !engineRunning, now.inputRate != route.inputRate { return true }
        return voiceProcessing && now.output != route.output
    }

    public mutating func usedInput(on now: AudioRoute) {
        if route == nil { route = now }
    }

    public mutating func voiceProcessingChanged(to enabled: Bool, on now: AudioRoute) {
        voiceProcessing = enabled
        if enabled || route == nil { route = now }
    }

    public mutating func replaced() {
        route = nil
        voiceProcessing = false
    }

    public mutating func voiceProcessingFailed(on now: AudioRoute) {
        voiceProcessingFailedOn = now
    }

    public mutating func settingChanged() {
        voiceProcessingFailedOn = nil
    }
}
