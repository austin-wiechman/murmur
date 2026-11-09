import Foundation

/// How to invoke `claude`. The prompt itself goes to `ClaudeCodeSession.run`.
public struct ClaudeCodeRequest: Sendable, Equatable {
    public enum Effort: String, Sendable {
        case low, medium, high, xhigh, max
    }

    public var model: String
    /// nil leaves the choice to Claude Code.
    public var effort: Effort?
    /// Replaces Claude Code's own system prompt.
    public var systemPrompt: String?
    /// A JSON Schema the answer must match; the result then carries `structuredOutput`.
    public var jsonSchema: String?
    /// Runs without tools, MCP servers, slash commands, or the user's settings and hooks. Besides
    /// keeping the run predictable, this cuts the context from ~31k to ~0.7k tokens.
    public var isolated: Bool
    public var workingDirectory: URL

    public init(model: String, effort: Effort? = nil, systemPrompt: String? = nil, jsonSchema: String? = nil,
                isolated: Bool = true, workingDirectory: URL = FileManager.default.temporaryDirectory) {
        self.model = model
        self.effort = effort
        self.systemPrompt = systemPrompt
        self.jsonSchema = jsonSchema
        self.isolated = isolated
        self.workingDirectory = workingDirectory
    }

    /// stream-json input lets `claude` start before the prompt exists; it requires stream-json output,
    /// which in turn requires `--verbose`.
    var arguments: [String] {
        var args = ["-p", "--model", model, "--input-format", "stream-json", "--output-format", "stream-json",
                    "--verbose", "--no-session-persistence"]
        if let effort { args += ["--effort", effort.rawValue] }
        if isolated {
            args += ["--tools", "", "--strict-mcp-config", "--disable-slash-commands", "--setting-sources", ""]
        }
        if let systemPrompt { args += ["--system-prompt", systemPrompt] }
        if let jsonSchema { args += ["--json-schema", jsonSchema] }
        return args
    }
}
