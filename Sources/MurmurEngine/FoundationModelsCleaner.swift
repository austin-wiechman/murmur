import Foundation
import FoundationModels
import MurmurCore

/// Apple's on-device model. Measured on an M1 Pro at 0.6–1.2 s per cleanup once warm; a cold first
/// call costs 1.6–5 s, which `prewarm()` at key-down hides behind the recording.
public struct FoundationModelsCleaner: Cleaner {
    public init() {}

    public static var availability: String? {
        switch SystemLanguageModel.default.availability {
        case .available: nil
        case .unavailable(let reason): String(describing: reason)
        }
    }

    public func prepare(instructions: String) -> CleanupSession {
        Session(instructions: instructions)
    }

    final class Session: CleanupSession, @unchecked Sendable {
        private let session: LanguageModelSession?

        init(instructions: String) {
            if FoundationModelsCleaner.availability == nil {
                let s = LanguageModelSession(instructions: instructions)
                s.prewarm()
                session = s
            } else {
                session = nil
            }
        }

        func clean(_ prompt: CleanupPrompt) async throws -> String {
            guard let session else {
                throw CleanupError.unavailable(FoundationModelsCleaner.availability ?? "unknown")
            }
            let options = GenerationOptions(temperature: 0)
            do {
                return try await session.respond(to: prompt.input, options: options).content
            } catch let error as LanguageModelSession.GenerationError {
                throw CleanupError.failed(String(describing: error))
            }
        }

        func discard() {}
    }
}
