import Foundation

/// One `claude` process that answers one prompt. Blocking pipe and process work runs on Dispatch
/// threads, so callers on the main actor or the cooperative pool never wait on it.
public final class ClaudeCodeSession: Sendable {
    private let process = Process()
    private let stdin = Pipe()
    private let stdout = Pipe()
    private let stderr = Pipe()
    private let expectsStructuredOutput: Bool
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
        process.currentDirectoryURL = FileManager.default.temporaryDirectory
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = executable.deletingLastPathComponent().path + ":/usr/bin:/bin:" + (env["PATH"] ?? "")
        process.environment = env
        process.standardInput = stdin
        process.standardOutput = stdout
        process.standardError = stderr
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
    /// deadline, stops `claude` and returns without waiting for it to exit.
    public func run(_ prompt: String, timeout: Duration? = nil) async throws -> ClaudeCodeResult {
        // Unstructured tasks: a task group would wait for claude's pipes to close and its exit.
        let (results, deliver) = AsyncStream.makeStream(of: Result<ClaudeCodeResult, Error>.self)
        Task {
            do { deliver.yield(.success(try await answer(prompt))) } catch { deliver.yield(.failure(error)) }
        }
        let timer = timeout.map { timeout in
            Task {
                try await Task.sleep(for: timeout)
                deliver.yield(.failure(ClaudeCodeError.timedOut))
            }
        }
        var iterator = results.makeAsyncIterator()
        let first = await iterator.next()
        deliver.finish()
        timer?.cancel()
        guard let first else {
            cancel()
            throw CancellationError()
        }
        if case .failure = first { cancel() }
        return try first.get()
    }

    /// Stops `claude`, killing it if it has not exited after a short grace period.
    public func cancel() {
        Task { [launch, process] in
            guard await launch.value == nil, process.isRunning else { return }
            process.terminate()
            try? await Task.sleep(for: .seconds(2))
            if process.isRunning { kill(process.processIdentifier, SIGKILL) }
        }
    }

    private func answer(_ prompt: String) async throws -> ClaudeCodeResult {
        if let launchError = await launch.value { throw launchError }
        let out = stdout.fileHandleForReading, err = stderr.fileHandleForReading
        async let output = onDispatchThread { (try? out.readToEnd()) ?? Data() }
        async let errors = onDispatchThread { (try? err.readToEnd()) ?? Data() }
        await Self.send(prompt, to: stdin.fileHandleForWriting)
        let status = await onDispatchThread { [process] in
            process.waitUntilExit()
            return process.terminationStatus
        }
        return try ClaudeCodeOutput.parse(await output, errors: await errors, status: status,
                                          expectsStructuredOutput: expectsStructuredOutput)
    }

    private static func send(_ prompt: String, to input: FileHandle) async {
        let message: [String: Any] = ["type": "user", "message": ["role": "user", "content": prompt]]
        guard let json = try? JSONSerialization.data(withJSONObject: message) else { return }
        let line = json + [0x0A]
        // claude may have exited already; without this the write raises SIGPIPE and kills the app.
        _ = fcntl(input.fileDescriptor, F_SETNOSIGPIPE, 1)
        await onDispatchThread {
            // A failed write means claude exited; its status and stderr explain why.
            try? input.write(contentsOf: line)
            try? input.close()
        }
    }
}

func onDispatchThread<T: Sendable>(_ work: @escaping @Sendable () -> T) async -> T {
    await withCheckedContinuation { done in
        DispatchQueue.global(qos: .userInitiated).async { done.resume(returning: work()) }
    }
}
