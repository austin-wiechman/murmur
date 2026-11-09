import Foundation

public struct ClaudeCodeResult: Sendable, Equatable {
    public struct Usage: Sendable, Equatable {
        public var inputTokens: Int
        public var outputTokens: Int
        public var cacheReadInputTokens: Int
        public var cacheCreationInputTokens: Int

        public init(inputTokens: Int, outputTokens: Int, cacheReadInputTokens: Int, cacheCreationInputTokens: Int) {
            self.inputTokens = inputTokens
            self.outputTokens = outputTokens
            self.cacheReadInputTokens = cacheReadInputTokens
            self.cacheCreationInputTokens = cacheCreationInputTokens
        }
    }

    public var text: String
    /// The answer as JSON, present when the request carried a schema.
    public var structuredOutput: Data?
    public var costUSD: Double?
    public var usage: Usage?

    public func decode<T: Decodable>(_ type: T.Type) throws -> T {
        guard let structuredOutput else { throw ClaudeCodeError.schemaViolation(text) }
        return try JSONDecoder().decode(type, from: structuredOutput)
    }
}

public enum ClaudeCodeError: Error, Equatable, CustomStringConvertible {
    case notInstalled
    case launchFailed(String)
    /// Claude Code has no valid login; the user needs to run `claude` and `/login`.
    case signedOut(String)
    case timedOut
    /// `claude` exited without printing a result, usually with a non-zero status.
    case exited(status: Int32, stderr: String)
    /// `claude` returned an error result, such as an API error.
    case failed(String)
    /// The request carried a schema and the answer did not match it.
    case schemaViolation(String)

    public var description: String {
        switch self {
        case .notInstalled: "claude not found"
        case .launchFailed(let why): "could not start claude: \(why)"
        case .signedOut(let message): "claude is signed out: \(message)"
        case .timedOut: "timed out"
        case .exited(let status, let stderr): "claude exited \(status): \(stderr.prefix(300))"
        case .failed(let message): "claude: \(message)"
        case .schemaViolation(let text): "claude's answer did not match the schema: \(text.prefix(300))"
        }
    }
}
