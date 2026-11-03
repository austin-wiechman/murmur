import AVFoundation
import FluidAudio

/// Streams microphone audio into Parakeet Unified while the user speaks, so only the last
/// chunk is left to decode at release (measured 62–114 ms on an M1 Pro).
///
/// The 1.12 s look-ahead tier is used: on the user's dictations it matched batch output, while
/// the 2.08 s tier misplaced punctuation. int8 is required on M1; fp16 falls back to the CPU.
public actor Transcriber {
    private let manager = StreamingUnifiedAsrManager(
        config: UnifiedConfig(leftFrames: 70, chunkFrames: 7, rightFrames: 7), encoderPrecision: .int8)
    private var loaded = false
    private var feeding: Task<Void, Never>?
    private var feedError: Error?

    public init() {}

    public enum LoadProgress: Sendable, Equatable {
        case downloading(Double)
        case preparing
    }

    /// Downloads (~580 MB) and compiles for the Neural Engine on first run, which takes ~30 s;
    /// later launches load in under a second and report no progress.
    public func load(progress: (@Sendable (LoadProgress) -> Void)? = nil) async throws {
        guard !loaded else { return }
        try await manager.loadModels(progressHandler: progress.map { report in
            { @Sendable update in
                switch update.phase {
                case .listing: report(.downloading(0))
                case .downloading: report(.downloading(update.fractionCompleted))
                case .compiling: report(.preparing)
                }
            }
        })
        loaded = true
    }

    /// Start the microphone without waiting for this: buffers that arrive while the decoder resets
    /// wait in the stream.
    public func begin(_ audio: AsyncStream<AVAudioPCMBuffer>, onPartial: (@Sendable (String) -> Void)? = nil) async throws {
        try await load()
        feeding?.cancel()
        try await manager.reset()
        feedError = nil
        await manager.setPartialTranscriptCallback(onPartial ?? { _ in })
        let stream = audio
        let manager = manager
        feeding = Task {
            for await buffer in stream {
                do {
                    try await manager.appendAudio(buffer)
                    try await manager.processBufferedAudio()
                } catch {
                    self.record(error)
                }
            }
        }
    }

    /// Finish the audio stream's continuation first; this waits for queued buffers to decode.
    public func finish() async throws -> String {
        await feeding?.value
        feeding = nil
        if let feedError { throw feedError }
        let text = try await manager.finish()
        return text.replacingOccurrences(of: #"\s{2,}"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public func cancel() async {
        feeding?.cancel()
        feeding = nil
        try? await manager.reset()
    }

    private func record(_ error: Error) {
        if feedError == nil { feedError = error }
    }
}
