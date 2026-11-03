import Foundation

/// Word-level diff between the raw transcript and the pasted text, for History's "Show changes".
public enum WordDiff {
    public enum Piece: Equatable, Sendable {
        case same(String)
        case removed(String)
        case added(String)
    }

    public static func diff(_ old: String, _ new: String) -> [Piece] {
        let a = tokens(old)
        let b = tokens(new)
        let n = a.count, m = b.count
        var lcs = Array(repeating: Array(repeating: 0, count: m + 1), count: n + 1)
        for i in stride(from: n - 1, through: 0, by: -1) {
            for j in stride(from: m - 1, through: 0, by: -1) {
                lcs[i][j] = a[i] == b[j] ? lcs[i + 1][j + 1] + 1 : max(lcs[i + 1][j], lcs[i][j + 1])
            }
        }
        var pieces: [Piece] = []
        var i = 0, j = 0
        while i < n || j < m {
            if i < n, j < m, a[i] == b[j] {
                pieces.append(.same(a[i])); i += 1; j += 1
            } else if i < n, j == m || lcs[i + 1][j] >= lcs[i][j + 1] {
                pieces.append(.removed(a[i])); i += 1
            } else {
                pieces.append(.added(b[j])); j += 1
            }
        }
        return merge(pieces)
    }

    private static let closing: Set<Character> = [".", ",", ";", ":", "!", "?", ")"]

    /// Words, with each line break and each trailing punctuation mark as its own token, so lists
    /// survive the diff and "error" → "error." reads as an added period.
    private static func tokens(_ text: String) -> [String] {
        text.replacingOccurrences(of: "\n", with: " \n ").split(separator: " ").flatMap { word -> [String] in
            var core = Substring(word)
            var trailing: [String] = []
            while core.count > 1, let last = core.last, closing.contains(last) {
                trailing.insert(String(last), at: 0)
                core = core.dropLast()
            }
            return [String(core)] + trailing
        }
    }

    /// Joins runs of the same kind so "if there is" strikes as one phrase.
    private static func merge(_ pieces: [Piece]) -> [Piece] {
        var out: [Piece] = []
        for piece in pieces {
            switch (out.last, piece) {
            case (.same(let x)?, .same(let y)): out[out.count - 1] = .same(join(x, y))
            case (.removed(let x)?, .removed(let y)): out[out.count - 1] = .removed(join(x, y))
            case (.added(let x)?, .added(let y)): out[out.count - 1] = .added(join(x, y))
            default: out.append(piece)
            }
        }
        return out
    }

    static func join(_ a: String, _ b: String) -> String { needsSpace(a, b) ? a + " " + b : a + b }

    public static func needsSpace(_ a: String, _ b: String) -> Bool {
        !(a.isEmpty || a.hasSuffix("\n") || b.hasPrefix("\n") || b.first.map(closing.contains) == true)
    }
}
