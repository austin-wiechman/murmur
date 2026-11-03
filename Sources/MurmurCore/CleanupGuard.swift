import Foundation

/// Decides whether a cleanup model's output can replace the raw transcript.
///
/// Small models sometimes answer the dictated question, wrap the text in a preamble, or drop a
/// negation and flip the meaning. Any of those means the raw transcript is the safer paste.
public enum CleanupGuard {
    public enum Verdict: Equatable, Sendable {
        case accept(String)
        case reject(Reason)
    }

    public enum Reason: String, Equatable, Sendable {
        case empty
        case tooLong
        case unrelated
        case droppedNegation
        case placeholder
    }

    public static func review(raw: String, output: String) -> Verdict {
        let cleaned = sanitize(output)
        let rawWords = words(raw)
        if cleaned.isEmpty { return rawWords.isEmpty ? .accept("") : .reject(.empty) }
        let cleanedWords = words(cleaned)
        if cleaned.count > raw.count * 2 + 80 { return .reject(.tooLong) }
        if rawWords.count >= 4 && overlap(rawWords, cleanedWords) < 0.5 { return .reject(.unrelated) }
        if negations(in: rawWords) > negations(in: cleanedWords) { return .reject(.droppedNegation) }
        if hasPlaceholder(cleaned) && !hasPlaceholder(raw) { return .reject(.placeholder) }
        return .accept(cleaned)
    }

    /// Strips reasoning blocks, echoed tags, preambles, and wrapping quotes.
    public static func sanitize(_ output: String) -> String {
        var text = output
        text = text.replacingOccurrences(of: #"(?s)<think>.*?</think>"#, with: "", options: .regularExpression)
        text = text.replacingOccurrences(of: #"(?s)^.*</think>"#, with: "", options: .regularExpression)
        text = text.replacingOccurrences(of: #"</?transcript>"#, with: "", options: .regularExpression)
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let preamble = #"^(?i)(here(?:['\x{2019}]s| is) (?:the )?cleaned(?: up)? (?:transcript|text)|cleaned (?:transcript|text))\s*:\s*"#
        text = text.replacingOccurrences(of: preamble, with: "", options: .regularExpression)
        if text.count >= 2, let first = text.first, let last = text.last,
           (first == "\"" && last == "\"") || (first == "\u{201C}" && last == "\u{201D}") {
            let inner = text.dropFirst().dropLast()
            if !inner.contains("\"") && !inner.contains("\u{201C}") { text = String(inner) }
        }
        // Models put a blank line before list items however they're told; pasted into chat it reads as a gap.
        text = text.replacingOccurrences(of: #"\n[ \t]*\n(?=[ \t]*(?:[-*•]|\d+[.)])[ \t])"#, with: "\n",
                                         options: .regularExpression)
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func words(_ text: String) -> [String] {
        text.lowercased()
            .replacingOccurrences(of: "\u{2019}", with: "'")
            .components(separatedBy: CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "'")).inverted)
            .filter { !$0.isEmpty }
    }

    /// Share of the cleaned text's words that also appear in the raw transcript.
    static func overlap(_ raw: [String], _ cleaned: [String]) -> Double {
        guard !cleaned.isEmpty else { return 0 }
        let rawSet = Set(raw)
        return Double(cleaned.filter { rawSet.contains($0) }.count) / Double(cleaned.count)
    }

    static func hasPlaceholder(_ text: String) -> Bool {
        text.range(of: #"\[[^\]\n]{1,40}\]"#, options: .regularExpression) != nil
    }

    static func negations(in words: [String]) -> Int {
        var count = 0
        var previous: String?
        for word in words {
            let isNegation = word == "not" || word == "never" || word == "cannot" || word.hasSuffix("n't")
            if isNegation && word != previous { count += 1 }
            previous = word
        }
        return count
    }
}
