import ClaudeCodeRunner
import Foundation
import Testing

/// Each test runs a shell script in place of `claude` that prints what the real CLI prints.
struct ClaudeCodeTests {
    private let request = ClaudeCodeRequest(model: "haiku")

    @Test func returnsTheResultTextCostAndUsage() async throws {
        let claude = try fakeClaude("""
            cat > /dev/null
            echo '{"type":"system","subtype":"init"}'
            echo '{"type":"result","subtype":"success","is_error":false,"result":"Send it by Friday.","total_cost_usd":0.25,"usage":{"input_tokens":12,"output_tokens":3,"cache_read_input_tokens":40,"cache_creation_input_tokens":5}}'
            """)
        let result = try await claude.run(request, prompt: "send it by friday")
        #expect(result.text == "Send it by Friday.")
        #expect(result.costUSD == 0.25)
        #expect(result.usage == ClaudeCodeResult.Usage(inputTokens: 12, outputTokens: 3,
                                                       cacheReadInputTokens: 40, cacheCreationInputTokens: 5))
    }

    @Test func decodesStructuredOutputWhenClaudeGetsTheSchema() async throws {
        let claude = try fakeClaude("""
            cat > /dev/null
            case "$*" in
            *--json-schema*) echo '{"type":"result","is_error":false,"result":"","structured_output":{"color":"red"}}' ;;
            *) echo '{"type":"result","is_error":false,"result":"red"}' ;;
            esac
            """)
        struct Answer: Decodable, Equatable { var color: String }
        var request = request
        request.jsonSchema = #"{"type":"object","properties":{"color":{"type":"string"}}}"#
        let result = try await claude.run(request, prompt: "Name a color.")
        #expect(try result.decode(Answer.self) == Answer(color: "red"))
    }

    @Test func reportsASchemaViolationWhenTheResultHasNoStructuredOutput() async throws {
        let claude = try fakeClaude("""
            cat > /dev/null
            echo '{"type":"result","is_error":false,"result":"red, I think"}'
            """)
        var request = request
        request.jsonSchema = #"{"type":"object"}"#
        await #expect(throws: ClaudeCodeError.schemaViolation("red, I think")) {
            try await claude.run(request, prompt: "Name a color.")
        }
    }

    @Test func reportsASchemaViolationWhenStructuredOutputIsNull() async {
        await #expect(processExitsWith: .success) {
            let claude = try fakeClaude("""
                cat > /dev/null
                echo '{"type":"result","is_error":false,"result":"","structured_output":null}'
                """)
            let request = ClaudeCodeRequest(model: "haiku", jsonSchema: #"{"type":"object"}"#)
            do {
                _ = try await claude.run(request, prompt: "Name a color.")
                exit(1)
            } catch ClaudeCodeError.schemaViolation {}
        }
    }

    @Test(arguments: ["Not logged in · Please run /login", "OAuth token has expired."])
    func reportsSignedOutWhenClaudeNeedsALogin(message: String) async throws {
        let claude = try fakeClaude("""
            cat > /dev/null
            echo '{"type":"result","subtype":"success","is_error":true,"result":"\(message)"}'
            exit 1
            """)
        await #expect(throws: ClaudeCodeError.signedOut(message)) {
            try await claude.run(request, prompt: "hi")
        }
    }

    @Test func reportsAnErrorResultAsAFailure() async throws {
        let claude = try fakeClaude("""
            cat > /dev/null
            echo '{"type":"result","subtype":"success","is_error":true,"result":"API Error: 529 overloaded"}'
            exit 1
            """)
        await #expect(throws: ClaudeCodeError.failed("API Error: 529 overloaded")) {
            try await claude.run(request, prompt: "hi")
        }
    }

    @Test func reportsTheErrorsOfAnErrorResultWithoutText() async throws {
        let claude = try fakeClaude("""
            cat > /dev/null
            echo '{"type":"result","subtype":"error_during_execution","is_error":true,"errors":["boom"]}'
            exit 1
            """)
        await #expect(throws: ClaudeCodeError.failed("boom")) {
            try await claude.run(request, prompt: "hi")
        }
    }

    @Test func reportsAnExitWithoutAResult() async throws {
        let claude = try fakeClaude("""
            echo "error: unknown option '--effort'" >&2
            exit 2
            """)
        await #expect(throws: ClaudeCodeError.exited(status: 2, stderr: "error: unknown option '--effort'\n")) {
            try await claude.run(request, prompt: "hi")
        }
    }

    @Test func reportsNotInstalledWithoutAnExecutable() async {
        await #expect(throws: ClaudeCodeError.notInstalled) {
            try await ClaudeCode(executable: nil).run(request, prompt: "hi")
        }
    }

    @Test func cancellingTheTaskStopsClaude() async throws {
        let pidFile = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let claude = try fakeClaude("""
            echo $$ > '\(pidFile.path)'
            cat > /dev/null
            exec sleep 30
            """)
        let run = Task { try await claude.run(request, prompt: "hi") }
        var pid: Int32?
        try await poll { pid = (try? String(contentsOf: pidFile, encoding: .utf8)).flatMap { Int32($0.dropLast()) }; return pid != nil }
        run.cancel()
        await #expect(throws: CancellationError.self) { try await run.value }
        #expect(try await poll { kill(try #require(pid), 0) != 0 })
    }

    /// A prompt larger than the pipe buffer deadlocks if stdin is written before stdout is read.
    @Test func deliversAPromptLargerThanThePipeBuffer() async throws {
        let claude = try fakeClaude("""
            bytes=$(wc -c | tr -d ' ')
            echo "{\\"type\\":\\"result\\",\\"is_error\\":false,\\"result\\":\\"$bytes\\"}"
            """)
        let prompt = String(repeating: "word ", count: 200_000)
        let result = try await claude.run(request, prompt: prompt)
        #expect(try #require(Int(result.text)) > prompt.utf8.count)
    }

    @Test func aPreparedSessionAnswersThePromptSentLater() async throws {
        let claude = try fakeClaude("""
            read -r line
            case "$line" in
            *'"content":"send it by friday"'*) echo '{"type":"result","is_error":false,"result":"Send it by Friday."}' ;;
            *) echo '{"type":"result","is_error":true,"result":"unexpected input"}' ;;
            esac
            """)
        let session = claude.prepare(request)
        try await Task.sleep(for: .milliseconds(100))
        let result = try await session.run("send it by friday")
        #expect(result.text == "Send it by Friday.")
    }
}

/// Checks `condition` until it holds or three seconds pass, and returns whether it held.
@discardableResult
func poll(_ condition: () throws -> Bool) async throws -> Bool {
    let deadline = ContinuousClock.now + .seconds(3)
    while try !condition() {
        guard ContinuousClock.now < deadline else { return false }
        try await Task.sleep(for: .milliseconds(20))
    }
    return true
}

func fakeClaude(_ body: String) throws -> ClaudeCode {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let script = directory.appendingPathComponent("claude")
    try ("#!/bin/sh\n" + body + "\n").write(to: script, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
    return ClaudeCode(executable: script)
}
