import Foundation
import MurmurEngine

/// Everything the recording pill can show. The controller publishes one of these; the pill view
/// renders it and never reaches into the pipeline.
enum PillState: Equatable {
    case hidden
    /// Push-to-talk held. `heard` is true once speech-level audio has arrived.
    case listening(heard: Bool)
    /// Hands-free after a tap: shows stop and cancel.
    case locked(heard: Bool)
    case transcribing
    case cleaning(CleanupEngine)
    case inserted(app: String?, canUndoCleanup: Bool)
    case failure(Failure)

    enum Failure: Equatable {
        case noAudio(device: String?)
        case pasteBlocked
        case modelLoading
        case microphoneDenied
        case other(String)
    }
}

/// Live values the pill animates from, separate from `PillState` so 60 Hz updates don't
/// re-diff the whole state.
@MainActor @Observable
final class PillMeter {
    /// Recent input levels, 0...1, newest last.
    var levels: [Float] = Array(repeating: 0, count: 11)
    /// Tail of the live transcript, shown only when "Show live words" is on.
    var liveWords: String = ""
}
