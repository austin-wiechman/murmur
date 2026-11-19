import Testing
@testable import MurmurCore

struct MicEngineStateTests {
    private let micX = AudioRoute(input: 10, output: 20)
    private let micY = AudioRoute(input: 10, output: 21)
    private let otherMic = AudioRoute(input: 11, output: 20)

    @Test func anUnusedEngineIsNeverReplaced() {
        #expect(!MicEngineState().needsNewEngine(on: otherMic))
    }

    @Test func aNewInputReplacesTheEngineInEitherMode() {
        var plain = MicEngineState()
        plain.usedInput(on: micX)
        #expect(plain.needsNewEngine(on: otherMic))

        var processed = MicEngineState()
        processed.voiceProcessingChanged(to: true, on: micX)
        #expect(processed.needsNewEngine(on: otherMic))
    }

    @Test func aNewOutputOnlyMattersWithVoiceProcessing() {
        var state = MicEngineState()
        state.usedInput(on: micX)
        #expect(!state.needsNewEngine(on: micY))

        state.voiceProcessingChanged(to: true, on: micX)
        #expect(state.needsNewEngine(on: micY))
    }

    @Test func voiceProcessingBindsTheOutputCurrentWhenItTurnsOn() {
        var state = MicEngineState()
        state.usedInput(on: micX)
        state.voiceProcessingChanged(to: true, on: micY)
        #expect(!state.needsNewEngine(on: micY))
        #expect(state.needsNewEngine(on: micX))
    }

    @Test func turningVoiceProcessingOffFreesTheOutput() {
        var state = MicEngineState()
        state.voiceProcessingChanged(to: true, on: micX)
        state.voiceProcessingChanged(to: false, on: micY)
        #expect(!state.needsNewEngine(on: micY))
    }

    @Test func aReplacedEngineStartsUnbound() {
        var state = MicEngineState()
        state.voiceProcessingChanged(to: true, on: micX)
        state.replaced()
        #expect(state == MicEngineState())
    }
}
