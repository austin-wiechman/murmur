import ClaudeCodeRunner
import Foundation
import Testing

/// `run(timeout:)` and task cancellation promise to stop waiting on `claude`. These fakes model a
/// `claude` that takes ten seconds to exit after SIGTERM (a shutdown handler, a flush, a child that
/// still holds stdout); the caller should get control back at the deadline, not when claude exits.
struct ClaudeCodeDeadlineTests {
    private let request = ClaudeCodeRequest(model: "haiku")
    private let slowToExit = """
        trap 'sleep 10; exit 143' TERM
        cat > /dev/null
        sleep 30 &
        wait $!
        """

    @Test func runReturnsAtTheDeadlineEvenWhenClaudeIsSlowToExit() async throws {
        let claude = try fakeClaude(slowToExit)
        let start = ContinuousClock.now
        await #expect(throws: ClaudeCodeError.timedOut) {
            try await claude.run(request, prompt: "hi", timeout: .milliseconds(200))
        }
        #expect(ContinuousClock.now - start < .seconds(3))
    }

    @Test func cancellingReturnsPromptlyEvenWhenClaudeIsSlowToExit() async throws {
        let claude = try fakeClaude(slowToExit)
        let run = Task { try await claude.run(request, prompt: "hi") }
        try await Task.sleep(for: .milliseconds(300))
        let start = ContinuousClock.now
        run.cancel()
        _ = try? await run.value
        #expect(ContinuousClock.now - start < .seconds(3))
    }
}
