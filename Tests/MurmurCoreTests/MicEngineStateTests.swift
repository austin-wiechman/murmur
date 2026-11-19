import Testing
@testable import MurmurCore

struct MicEngineStateTests {
    private let micX = AudioRoute(input: 10, inputRate: 48_000, output: 20)
    private let micY = AudioRoute(input: 10, inputRate: 48_000, output: 21)
    private let otherMic = AudioRoute(input: 11, inputRate: 48_000, output: 20)
    private let micXAt16k = AudioRoute(input: 10, inputRate: 16_000, output: 20)

    @Test func anUnusedEngineIsNeverReplaced() {
        #expect(!MicEngineState().needsNewEngine(on: otherMic, engineRunning: false))
    }

    @Test func aRateChangeReplacesOnlyAStoppedEngine() {
        var state = MicEngineState()
        state.voiceProcessingChanged(to: true, on: micX)
        #expect(state.needsNewEngine(on: micXAt16k, engineRunning: false))
        #expect(!state.needsNewEngine(on: micXAt16k, engineRunning: true))
    }

    @Test func aNewInputReplacesTheEngineInEitherMode() {
        var plain = MicEngineState()
        plain.usedInput(on: micX)
        #expect(plain.needsNewEngine(on: otherMic, engineRunning: false))

        var processed = MicEngineState()
        processed.voiceProcessingChanged(to: true, on: micX)
        #expect(processed.needsNewEngine(on: otherMic, engineRunning: false))
    }

    @Test func aNewOutputOnlyMattersWithVoiceProcessing() {
        var state = MicEngineState()
        state.usedInput(on: micX)
        #expect(!state.needsNewEngine(on: micY, engineRunning: false))

        state.voiceProcessingChanged(to: true, on: micX)
        #expect(state.needsNewEngine(on: micY, engineRunning: false))
    }

    @Test func voiceProcessingBindsTheOutputCurrentWhenItTurnsOn() {
        var state = MicEngineState()
        state.usedInput(on: micX)
        state.voiceProcessingChanged(to: true, on: micY)
        #expect(!state.needsNewEngine(on: micY, engineRunning: false))
        #expect(state.needsNewEngine(on: micX, engineRunning: false))
    }

    @Test func turningVoiceProcessingOffFreesTheOutput() {
        var state = MicEngineState()
        state.voiceProcessingChanged(to: true, on: micX)
        state.voiceProcessingChanged(to: false, on: micY)
        #expect(!state.needsNewEngine(on: micY, engineRunning: false))
    }

    @Test func aReplacedEngineStartsUnbound() {
        var state = MicEngineState()
        state.voiceProcessingChanged(to: true, on: micX)
        state.replaced()
        #expect(state == MicEngineState())
    }

    @Test func aVoiceProcessingFailureHoldsOnlyForItsRouteUntilTheSettingChanges() {
        var state = MicEngineState()
        state.voiceProcessingFailed(on: micX)
        state.replaced()
        #expect(!state.allowsVoiceProcessing(on: micX))
        #expect(state.allowsVoiceProcessing(on: micY))

        state.settingChanged()
        #expect(state.allowsVoiceProcessing(on: micX))
    }
}
