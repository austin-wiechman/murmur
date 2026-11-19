/// The audio devices a capture engine is bound to: the default input and its sample rate, and the
/// default output, whose sound voice processing cancels.
public struct AudioRoute: Hashable, Sendable {
    public var input: UInt32
    public var inputRate: Double
    public var output: UInt32

    public init(input: UInt32, inputRate: Double, output: UInt32) {
        self.input = input
        self.inputRate = inputRate
        self.output = output
    }
}
