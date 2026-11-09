import Foundation

/// One cleanup request's lifetime: `prepare` runs at key-down so model warm-up overlaps speech,
/// and `clean` runs once the transcript is final.
public protocol CleanupSession: Sendable {
    func clean(_ prompt: CleanupPrompt) async throws -> String
    func discard()
}

public struct CleanupOutcome: Sendable {
    public enum Source: String, Sendable { case cleaned, raw }
    public var text: String
    public var source: Source
    public var note: String?
    public var seconds: Double
}

public enum CleanupRunner {
    /// Runs a prepared session with a deadline and reviews the result. Any failure pastes the raw text.
    public static func run(_ session: CleanupSession, prompt: CleanupPrompt, raw: String,
                           timeout: Duration) async -> CleanupOutcome {
        let clock = ContinuousClock()
        let start = clock.now
        // Unstructured tasks: a task group would wait for a session that is slow to notice cancellation.
        let (results, deliver) = AsyncStream.makeStream(of: Result<String, Error>?.self)
        let work = Task {
            do { deliver.yield(.success(try await session.clean(prompt))) } catch { deliver.yield(.failure(error)) }
        }
        let timer = Task {
            try? await Task.sleep(for: timeout)
            deliver.yield(nil)
        }
        var iterator = results.makeAsyncIterator()
        let first = await iterator.next() ?? nil
        deliver.finish()
        work.cancel()
        timer.cancel()
        let result = first ?? .failure(CleanupError.timedOut)
        let seconds = (clock.now - start) / .seconds(1)
        switch result {
        case .failure(let error):
            session.discard()
            return CleanupOutcome(text: raw, source: .raw, note: String(describing: error), seconds: seconds)
        case .success(let output):
            switch CleanupGuard.review(raw: raw, output: output) {
            case .accept(let text):
                return CleanupOutcome(text: text, source: .cleaned, note: nil, seconds: seconds)
            case .reject(let reason):
                return CleanupOutcome(text: raw, source: .raw, note: "rejected: \(reason.rawValue)", seconds: seconds)
            }
        }
    }
}

public enum CleanupError: Error, CustomStringConvertible {
    case timedOut
    case unavailable(String)
    case failed(String)

    public var description: String {
        switch self {
        case .timedOut: "timed out"
        case .unavailable(let why): "unavailable: \(why)"
        case .failed(let why): why
        }
    }
}
