import ClaudeCodeRunner
import Foundation
import MurmurCore

/// Cleans up through the user's own Claude Code login.
///
/// Startup costs 2–3 s, so the process is spawned at key-down and waits on stdin; at key-up only
/// the API round trip remains (measured 0.7–1.2 s with Haiku).
public struct ClaudeCLICleaner: Cleaner {
    public var model: String
    public var executable: URL?

    public init(model: String, executable: URL?) {
        self.model = model
        self.executable = executable
    }

    public func prepare(instructions: String) -> CleanupSession {
        // Thinking can't be turned off for Haiku 5.5; low effort keeps it short. Measured: long
        // dictations 11 s -> 2.6 s, short ones unchanged at ~1.7 s, same cleanup quality.
        let request = ClaudeCodeRequest(model: model, effort: .low, systemPrompt: instructions)
        return Session(claude: ClaudeCode(executable: executable).prepare(request))
    }

    struct Session: CleanupSession {
        let claude: ClaudeCodeSession

        func clean(_ prompt: CleanupPrompt) async throws -> String {
            do {
                return try await claude.run(prompt.input).text
            } catch let error as ClaudeCodeError {
                switch error {
                case .notInstalled, .launchFailed: throw CleanupError.unavailable(error.description)
                case .signedOut(let message): throw CleanupError.failed(ClaudeCodeError.failed(message).description)
                default: throw CleanupError.failed(error.description)
                }
            }
        }

        func discard() {
            claude.cancel()
        }
    }
}
