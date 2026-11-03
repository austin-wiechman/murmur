import Testing
@testable import MurmurCore

private struct StubSession: CleanupSession {
    var reply: @Sendable () async throws -> String
    func clean(_ prompt: CleanupPrompt) async throws -> String { try await reply() }
    func discard() {}
}

struct CleanupRunnerTests {
    @Test func pastesTheRawTextWhenCleanupMissesTheDeadline() async {
        let session = StubSession {
            try await Task.sleep(for: .seconds(10))
            return "Send it by Friday."
        }
        let outcome = await CleanupRunner.run(session, prompt: CleanupPrompt(transcript: "send it by friday"),
                                              raw: "send it by friday", timeout: .milliseconds(50))
        #expect(outcome.text == "send it by friday")
        #expect(outcome.source == .raw)
        #expect(outcome.note == "timed out")
    }

    @Test func pastesTheCleanedTextWhenTheGuardAcceptsIt() async {
        let session = StubSession { "Send it by Friday." }
        let outcome = await CleanupRunner.run(session, prompt: CleanupPrompt(transcript: "send it by friday"),
                                              raw: "send it by friday", timeout: .seconds(5))
        #expect(outcome.text == "Send it by Friday.")
        #expect(outcome.source == .cleaned)
    }
}
