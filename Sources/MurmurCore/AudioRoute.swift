/// The audio devices a capture engine is bound to: the default input, and the default output,
/// whose sound voice processing cancels.
public struct AudioRoute: Equatable, Sendable {
    public var input: UInt32
    public var output: UInt32

    public init(input: UInt32, output: UInt32) {
        self.input = input
        self.output = output
    }
}
