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

    @Test func aSilentVoiceProcessingTakeReplacesTheEngine() {
        var state = MicEngineState()
        state.voiceProcessingChanged(to: true, on: micX)
        state.takeEnded(frames: 0, seconds: 0.3)
        #expect(!state.needsNewEngine(on: micX, engineRunning: true))

        state.takeEnded(frames: 0, seconds: 4)
        #expect(state.needsNewEngine(on: micX, engineRunning: true))

        state.replaced()
        #expect(!state.needsNewEngine(on: micX, engineRunning: false))
    }

    @Test func aSilenceRebuildWaitsForAudioBeforeTheNext() {
        var state = MicEngineState()
        state.voiceProcessingChanged(to: true, on: micX)
        state.takeEnded(frames: 0, seconds: 4)
        state.replaced()
        state.voiceProcessingChanged(to: true, on: micX)
        state.takeEnded(frames: 0, seconds: 4)
        #expect(!state.needsNewEngine(on: micX, engineRunning: true))

        state.takeEnded(frames: 16_000, seconds: 1)
        state.takeEnded(frames: 0, seconds: 4)
        #expect(state.needsNewEngine(on: micX, engineRunning: true))
    }

    @Test func aSilentPlainTakeKeepsTheEngine() {
        var state = MicEngineState()
        state.usedInput(on: micX)
        state.takeEnded(frames: 0, seconds: 4)
        #expect(!state.needsNewEngine(on: micX, engineRunning: false))
    }

    @Test func aFailureMarkedOnTheEnginesRouteSkipsDevicesItNeverRanOn() throws {
        var state = MicEngineState()
        state.voiceProcessingChanged(to: true, on: micX)
        let failedRoute = state.route
        state.replaced()
        state.usedInput(on: otherMic)
        state.voiceProcessingFailed(on: try #require(failedRoute))
        #expect(!state.allowsVoiceProcessing(on: micX))
        #expect(state.allowsVoiceProcessing(on: otherMic))
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

    @Test func everyRouteWhereVoiceProcessingFailedStaysPlain() {
        var state = MicEngineState()
        state.voiceProcessingFailed(on: micX)
        state.replaced()
        state.voiceProcessingFailed(on: micY)
        state.replaced()

        #expect(!state.allowsVoiceProcessing(on: micX))
        #expect(!state.allowsVoiceProcessing(on: micY))
    }
}
