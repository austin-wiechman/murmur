import Foundation

/// Reads the `result` line of `claude`'s stream-json output.
enum ClaudeCodeOutput {
    static func parse(_ output: Data, errors: Data, status: Int32,
                      expectsStructuredOutput: Bool) throws(ClaudeCodeError) -> ClaudeCodeResult {
        let result = output.split(separator: 0x0A).lazy
            .compactMap { try? JSONSerialization.jsonObject(with: Data($0)) as? [String: Any] }
            .first { $0["type"] as? String == "result" }
        guard let json = result else {
            throw .exited(status: status, stderr: String(decoding: errors, as: UTF8.self))
        }
        let text = json["result"] as? String ?? ""
        if (json["is_error"] as? Bool) == true {
            if isSignedOut(text) { throw .signedOut(text) }
            if expectsStructuredOutput, (json["subtype"] as? String)?.contains("structured_output") == true {
                throw .schemaViolation(text)
            }
            throw .failed(text.isEmpty ? errorSummary(json) : text)
        }
        let structured = json["structured_output"].flatMap { try? JSONSerialization.data(withJSONObject: $0) }
        if expectsStructuredOutput, structured == nil { throw .schemaViolation(text) }
        return ClaudeCodeResult(text: text, structuredOutput: structured, costUSD: json["total_cost_usd"] as? Double,
                                usage: (json["usage"] as? [String: Any]).map(usage))
    }

    private static func isSignedOut(_ text: String) -> Bool {
        let lowered = text.lowercased()
        return ["not logged in", "/login", "invalid api key", "oauth token has expired"].contains { lowered.contains($0) }
    }

    private static func errorSummary(_ json: [String: Any]) -> String {
        if let errors = json["errors"] as? [String], !errors.isEmpty { return errors.joined(separator: "; ") }
        return json["subtype"] as? String ?? "error"
    }

    private static func usage(_ json: [String: Any]) -> ClaudeCodeResult.Usage {
        ClaudeCodeResult.Usage(inputTokens: json["input_tokens"] as? Int ?? 0,
                               outputTokens: json["output_tokens"] as? Int ?? 0,
                               cacheReadInputTokens: json["cache_read_input_tokens"] as? Int ?? 0,
                               cacheCreationInputTokens: json["cache_creation_input_tokens"] as? Int ?? 0)
    }
}
