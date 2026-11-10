import FluidAudio

/// A FluidAudio model repository and the files a manager needs from it.
public struct SpeechModel: Sendable, Hashable {
    public var repo: Repo
    /// Paths relative to the repository folder.
    public var requiredFiles: Set<String>
    /// FluidAudio's download variant, such as "fp16".
    public var variant: String?

    public init(repo: Repo, requiredFiles: Set<String>, variant: String? = nil) {
        self.repo = repo
        self.requiredFiles = requiredFiles
        self.variant = variant
    }

    /// The files `StreamingUnifiedAsrManager.loadModels` loads for this tier and precision.
    public static func parakeetUnifiedStreaming(config: UnifiedConfig, precision: UnifiedEncoderPrecision) -> SpeechModel {
        let names = ModelNames.ParakeetUnified.self
        return SpeechModel(
            repo: .parakeetUnified,
            requiredFiles: [
                names.streamingEncoderFile(precision: precision, contextSuffix: config.contextSuffix),
                names.decoderFile, names.jointDecisionFile, names.vocab,
            ],
            variant: precision == .fp16 ? "fp16" : nil)
    }
}

/// The speech model Murmur dictates with, so another app can share its download.
///
/// The 1.12 s look-ahead tier matched batch output on real dictations, while the 2.08 s tier
/// misplaced punctuation. int8 is required on M1; fp16 falls back to the CPU.
public enum DictationModel {
    public static let config = UnifiedConfig(leftFrames: 70, chunkFrames: 7, rightFrames: 7)
    public static let encoderPrecision = UnifiedEncoderPrecision.int8
    public static let speechModel = SpeechModel.parakeetUnifiedStreaming(config: config, precision: encoderPrecision)
}
