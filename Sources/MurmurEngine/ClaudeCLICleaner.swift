import Foundation
import MurmurCore

/// Cleans up through the user's own Claude Code login by running the unmodified `claude` binary.
/// The app never reads or stores Claude credentials.
///
/// Startup costs 2–3 s, so the process is spawned at key-down and waits on stdin; at key-up only
/// the API round trip remains (measured 0.7–1.2 s with Haiku). The flags strip tools, MCP, user
/// settings, hooks and session files, which also cut the context from ~31k to ~0.7k tokens.
public struct ClaudeCLICleaner: Cleaner {
    public var model: String
    public var executable: URL?

    public init(model: String, executable: URL? = ClaudeCLICleaner.locate()) {
        self.model = model
        self.executable = executable
    }

    public func prepare(instructions: String) -> CleanupSession {
        Session(executable: executable, model: model, instructions: instructions)
    }

    /// GUI apps get a minimal PATH, so look where installers put `claude`.
    public static func locate() -> URL? {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let candidates = [
            "\(home)/.local/bin/claude", "\(home)/.claude/local/claude", "/opt/homebrew/bin/claude",
            "/usr/local/bin/claude", "\(home)/.npm-global/bin/claude", "\(home)/.bun/bin/claude",
        ]
        if let hit = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) {
            return URL(fileURLWithPath: hit)
        }
        let shell = Process()
        shell.executableURL = URL(fileURLWithPath: "/bin/zsh")
        shell.arguments = ["-lc", "command -v claude"]
        let out = Pipe()
        shell.standardOutput = out
        shell.standardError = FileHandle.nullDevice
        guard (try? shell.run()) != nil else { return nil }
        // The login shell runs the user's profile, which can hang.
        DispatchQueue.global().asyncAfter(deadline: .now() + 5) { if shell.isRunning { shell.terminate() } }
        shell.waitUntilExit()
        guard shell.terminationReason == .exit else { return nil }
        let path = String(decoding: out.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return path.isEmpty ? nil : URL(fileURLWithPath: path)
    }

    final class Session: CleanupSession, @unchecked Sendable {
        private let process = Process()
        private let stdin = Pipe()
        private let stdout = Pipe()
        private let stderr = Pipe()
        /// Launching a process can block, so it runs off the caller's thread; nil once running.
        private let launch: Task<String?, Never>

        init(executable: URL?, model: String, instructions: String) {
            guard let executable else {
                launch = Task { "claude not found" }
                return
            }
            process.executableURL = executable
            process.arguments = [
                // Thinking can't be turned off for Haiku 5.5; low effort keeps it short. Measured: long
                // dictations 11 s -> 2.6 s, short ones unchanged at ~1.7 s, same cleanup quality.
                "-p", "--model", model, "--effort", "low", "--input-format", "stream-json", "--output-format", "stream-json", "--verbose",
                "--tools", "", "--strict-mcp-config", "--no-session-persistence",
                "--disable-slash-commands", "--setting-sources", "",
                "--system-prompt", instructions,
            ]
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
                    return "could not start claude: \(error.localizedDescription)"
                }
            }
        }

        func clean(_ prompt: CleanupPrompt) async throws -> String {
            if let launchError = await launch.value { throw CleanupError.unavailable(launchError) }
            let message: [String: Any] = ["type": "user", "message": ["role": "user", "content": prompt.input]]
            var line = try JSONSerialization.data(withJSONObject: message)
            line.append(0x0A)
            let input = stdin.fileHandleForWriting
            // claude may have exited since launch; without this the write raises SIGPIPE and kills the app.
            _ = fcntl(input.fileDescriptor, F_SETNOSIGPIPE, 1)
            try input.write(contentsOf: line)
            try? input.close()
            let handle = stdout.fileHandleForReading
            let errHandle = stderr.fileHandleForReading
            let data: Data = try await withTaskCancellationHandler {
                try await Task.detached { try handle.readToEnd() ?? Data() }.value
            } onCancel: { [process] in
                if process.isRunning { process.terminate() }
            }
            process.waitUntilExit()
            let result = data.split(separator: 0x0A).lazy
                .compactMap { try? JSONSerialization.jsonObject(with: Data($0)) as? [String: Any] }
                .first { $0["type"] as? String == "result" }
            guard let json = result else {
                let err = String(decoding: (try? errHandle.readToEnd()) ?? Data(), as: UTF8.self)
                throw CleanupError.failed("claude exited \(process.terminationStatus): \(err.prefix(300))")
            }
            if (json["is_error"] as? Bool) == true {
                throw CleanupError.failed("claude: \(json["result"] as? String ?? "error")")
            }
            return json["result"] as? String ?? ""
        }

        func discard() {
            Task { [launch, process] in
                if await launch.value == nil, process.isRunning { process.terminate() }
            }
        }
    }
}
