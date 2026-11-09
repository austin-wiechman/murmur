import Foundation
import Synchronization

/// One `claude` process that answers one prompt. Blocking pipe and process work runs on Dispatch
/// threads, so callers on the main actor or the cooperative pool never wait on it.
public final class ClaudeCodeSession: Sendable {
    private let process = Process()
    private let stdin = Pipe()
    private let stdout = Pipe()
    private let stderr = Pipe()
    private let expectsStructuredOutput: Bool
    private let exitStatus = ExitStatus()
    /// Launching a process can block, so it runs off the caller's thread; nil once running.
    private let launch: Task<ClaudeCodeError?, Never>

    init(executable: URL?, request: ClaudeCodeRequest) {
        expectsStructuredOutput = request.jsonSchema != nil
        guard let executable else {
            launch = Task { .notInstalled }
            return
        }
        process.executableURL = executable
        process.arguments = request.arguments
        process.currentDirectoryURL = request.workingDirectory
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = executable.deletingLastPathComponent().path + ":/usr/bin:/bin:" + (env["PATH"] ?? "")
        process.environment = env
        process.standardInput = stdin
        process.standardOutput = stdout
        process.standardError = stderr
        process.terminationHandler = { [exitStatus] process in exitStatus.record(process.terminationStatus) }
        launch = Task.detached(priority: .userInitiated) { [process] in
            do {
                try process.run()
                return nil
            } catch {
                return .launchFailed(error.localizedDescription)
            }
        }
    }

    /// Sends the prompt and waits for the answer. Cancelling the calling task, or passing the
    /// deadline, terminates `claude`.
    public func run(_ prompt: String, timeout: Duration? = nil) async throws -> ClaudeCodeResult {
        guard let timeout else { return try await answer(prompt) }
        return try await withThrowingTaskGroup(of: ClaudeCodeResult.self) { group in
            group.addTask { try await self.answer(prompt) }
            group.addTask {
                try await Task.sleep(for: timeout)
                throw ClaudeCodeError.timedOut
            }
            defer { group.cancelAll() }
            return try await group.next()!
        }
    }

    public func cancel() {
        Task { [launch, process] in
            if await launch.value == nil, process.isRunning { process.terminate() }
        }
    }

    private func answer(_ prompt: String) async throws -> ClaudeCodeResult {
        if let launchError = await launch.value { throw launchError }
        let status: Int32
        let output: Data
        let errors: Data
        (status, output, errors) = await withTaskCancellationHandler {
            async let output = Self.readToEnd(stdout.fileHandleForReading)
            async let errors = Self.readToEnd(stderr.fileHandleForReading)
            await Self.send(prompt, to: stdin.fileHandleForWriting)
            return (await exitStatus.value(), await output, await errors)
        } onCancel: { [process] in
            if process.isRunning { process.terminate() }
        }
        try Task.checkCancellation()
        return try ClaudeCodeOutput.parse(output, errors: errors, status: status,
                                          expectsStructuredOutput: expectsStructuredOutput)
    }

    private static func send(_ prompt: String, to input: FileHandle) async {
        let message: [String: Any] = ["type": "user", "message": ["role": "user", "content": prompt]]
        guard let json = try? JSONSerialization.data(withJSONObject: message) else { return }
        let line = json + [0x0A]
        // claude may have exited already; without this the write raises SIGPIPE and kills the app.
        _ = fcntl(input.fileDescriptor, F_SETNOSIGPIPE, 1)
        await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
            DispatchQueue.global(qos: .userInitiated).async {
                // A failed write means claude exited; its status and stderr explain why.
                try? input.write(contentsOf: line)
                try? input.close()
                done.resume()
            }
        }
    }

    private static func readToEnd(_ handle: FileHandle) async -> Data {
        await withCheckedContinuation { done in
            DispatchQueue.global(qos: .userInitiated).async {
                done.resume(returning: (try? handle.readToEnd()) ?? Data())
            }
        }
    }
}

/// The exit status from `Process.terminationHandler`, for any number of waiters.
private final class ExitStatus: Sendable {
    private let state = Mutex<(status: Int32?, waiters: [CheckedContinuation<Int32, Never>])>((nil, []))

    func record(_ status: Int32) {
        let waiters = state.withLock { state in
            state.status = status
            defer { state.waiters = [] }
            return state.waiters
        }
        for waiter in waiters { waiter.resume(returning: status) }
    }

    func value() async -> Int32 {
        await withCheckedContinuation { waiter in
            let status = state.withLock { state in
                if state.status == nil { state.waiters.append(waiter) }
                return state.status
            }
            if let status { waiter.resume(returning: status) }
        }
    }
}
