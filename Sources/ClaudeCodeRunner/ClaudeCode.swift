import Foundation

/// Runs the user's own `claude` CLI non-interactively, so the app never reads or stores Claude
/// credentials.
public struct ClaudeCode: Sendable {
    public var executable: URL?

    /// Pass the result of `locate()`; nil makes every run fail with `.notInstalled`.
    public init(executable: URL?) {
        self.executable = executable
    }

    /// Starts `claude` now and sends the prompt later. Startup costs 2–3 s, which a caller can hide
    /// behind other work. Call `cancel()` on a session you won't run.
    public func prepare(_ request: ClaudeCodeRequest) -> ClaudeCodeSession {
        ClaudeCodeSession(executable: executable, request: request)
    }

    public func run(_ request: ClaudeCodeRequest, prompt: String, timeout: Duration? = nil) async throws -> ClaudeCodeResult {
        try await prepare(request).run(prompt, timeout: timeout)
    }

    /// GUI apps get a minimal PATH, so this looks where installers put `claude` before asking a login
    /// shell.
    public static func locate() async -> URL? {
        await onDispatchThread { locateBlocking() }
    }

    private static func locateBlocking() -> URL? {
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
}
