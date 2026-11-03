/// How long to wait for cleanup: the user's limit, plus time for the model to write out a long
/// dictation. Output time grows with length, so a flat limit always fails long dictations.
public enum CleanupDeadline {
    public static let secondsPer100Words = 1.0

    public static func seconds(limit: Double, transcript: String) -> Double {
        let words = transcript.split(whereSeparator: \.isWhitespace).count
        return limit + Double(words) / 100 * secondsPer100Words
    }
}
