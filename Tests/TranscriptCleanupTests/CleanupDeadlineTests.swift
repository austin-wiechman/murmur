import Testing
import TranscriptCleanup

struct CleanupDeadlineTests {
    @Test func longDictationsGetASecondPerHundredWords() {
        let short = "Testing murmur one two three"
        let long = Array(repeating: "word", count: 300).joined(separator: " ")
        #expect(CleanupDeadline.seconds(limit: 3, transcript: short) == 3.05)
        #expect(CleanupDeadline.seconds(limit: 3, transcript: long) == 6)
    }
}
