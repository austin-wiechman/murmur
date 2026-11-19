/// What the capture engine is bound to, so `AudioCapture` knows when to build a new one.
///
/// An engine stays on the input it first used. With voice processing on it is also bound to the
/// output that was current when voice processing turned on, whose sound it cancels.
public struct MicEngineState: Equatable, Sendable {
    /// Nil until the engine's input node is first used.
    public private(set) var route: AudioRoute?
    public private(set) var voiceProcessing = false
    /// Where voice processing wouldn't start, or stayed silent after a rebuild for silence. Those routes
    /// record from the plain mic until the setting changes, even after other devices are used in between.
    public private(set) var voiceProcessingFailedOn: Set<AudioRoute> = []
    /// A voice processing take of a second or more that delivers no audio means a stale engine, which
    /// doesn't fail; a shorter take may just have ended before the first buffer. After one rebuild for
    /// silence, a route that still delivers nothing falls back to the plain mic instead of rebuilding again.
    private var silence = Silence.heard

    private enum Silence: Equatable, Sendable {
        case heard, heardNothing, rebuiltAwaitingAudio
    }

    public init() {}

    public func allowsVoiceProcessing(on now: AudioRoute) -> Bool {
        !voiceProcessingFailedOn.contains(now)
    }

    /// A running engine that rode out a rate change keeps going, so the rate only counts when it's
    /// stopped; that also ignores whatever rate a running voice processing engine reports.
    public func needsNewEngine(on now: AudioRoute, engineRunning: Bool) -> Bool {
        if silence == .heardNothing { return true }
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
        if silence == .heardNothing { silence = .rebuiltAwaitingAudio }
        route = nil
        voiceProcessing = false
    }

    public mutating func takeEnded(frames: Int, seconds: Double) {
        if frames > 0 {
            silence = .heard
            return
        }
        let silent = voiceProcessing && seconds >= 1
        guard silence == .rebuiltAwaitingAudio else {
            silence = silent ? .heardNothing : .heard
            return
        }
        if silent, let route { voiceProcessingFailedOn.insert(route) }
    }

    public mutating func voiceProcessingFailed(on now: AudioRoute) {
        voiceProcessingFailedOn.insert(now)
    }

    public mutating func settingChanged() {
        voiceProcessingFailedOn.removeAll()
    }
}
