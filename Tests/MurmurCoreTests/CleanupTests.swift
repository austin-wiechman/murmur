import Testing
@testable import MurmurCore

struct CleanupGuardTests {
    @Test func stripsAPreambleWithEitherApostrophe() {
        #expect(CleanupGuard.sanitize("Here's the cleaned transcript: Send it by Friday.") == "Send it by Friday.")
        #expect(CleanupGuard.sanitize("Here\u{2019}s the cleaned transcript: Send it by Friday.") == "Send it by Friday.")
    }

    @Test func listsSitDirectlyUnderTheirLeadIn() {
        let output = "This is a list of items:\n\n1. Books\n\n2. Pizza\n\nThat's all."
        #expect(CleanupGuard.sanitize(output) == "This is a list of items:\n1. Books\n2. Pizza\n\nThat's all.")
    }

    let raw = "On Q4, yes, include the archived notes but put them at the end. Ask Sam to check the order Five I agree, the button should say export instead of save"

    @Test func acceptsAReformattedList() {
        let out = "- Q4: Yes, include the archived notes, but put them at the end. Ask Sam to check the order.\n- Q5: I agree, the button should say Export instead of Save."
        #expect(CleanupGuard.review(raw: raw, output: out) == .accept(out))
    }

    @Test func rejectsAnAnswerInsteadOfACleanup() {
        let verdict = CleanupGuard.review(
            raw: "what's the capital of france",
            output: "The capital of France is Paris, a city known for its art and history.")
        #expect(verdict == .reject(.unrelated))
    }

    @Test func rejectsDroppedNegation() {
        let verdict = CleanupGuard.review(
            raw: "um we should not ship this on friday",
            output: "We should ship this on Friday.")
        #expect(verdict == .reject(.droppedNegation))
        #expect(CleanupGuard.review(raw: "we cannot ship this on friday", output: "We can ship this on Friday.")
            == .reject(.droppedNegation))
    }

    @Test func rejectsInventedPlaceholders() {
        let verdict = CleanupGuard.review(
            raw: "Give me a short list of things to pack for the camping trip.",
            output: "- Things to pack for the camping trip:\n  - [Item 1]\n  - [Item 2]")
        #expect(verdict == .reject(.placeholder))
    }

    @Test func collapsedStutteredNegationIsFine() {
        let verdict = CleanupGuard.review(raw: "it's not not working", output: "It's not working.")
        #expect(verdict == .accept("It's not working."))
    }

    @Test func stripsThinkingTagsAndPreamble() {
        let out = "<think>hmm</think>\nHere is the cleaned transcript: <transcript>Send it by Friday.</transcript>"
        #expect(CleanupGuard.review(raw: "send it by thursday no wait friday", output: out) == .accept("Send it by Friday."))
    }

    @Test func emptyOutputForAudibleSpeechFallsBack() {
        #expect(CleanupGuard.review(raw: "send it now", output: "  ") == .reject(.empty))
    }
}
