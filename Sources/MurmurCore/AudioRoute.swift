/// The audio devices a capture engine was built on: the default input, and the default output,
/// whose sound voice processing cancels.
public struct AudioRoute: Equatable, Sendable {
    public var input: UInt32
    public var output: UInt32

    public init(input: UInt32, output: UInt32) {
        self.input = input
        self.output = output
    }

    /// An engine stays bound to the devices it was built on, so it can't follow a new input.
    /// The output only binds it while voice processing is on.
    public func needsNewEngine(builtOn built: AudioRoute, voiceProcessing: Bool) -> Bool {
        input != built.input || (voiceProcessing && output != built.output)
    }
}
