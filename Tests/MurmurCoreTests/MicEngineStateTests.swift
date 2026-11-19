import Testing
@testable import MurmurCore

struct MicEngineStateTests {
    private let micX = AudioRoute(input: 10, inputRate: 48_000, output: 20)
    private let micY = AudioRoute(input: 10, inputRate: 48_000, output: 21)
    private let otherMic = AudioRoute(input: 11, inputRate: 48_000, output: 20)
    private let micXAt16k = AudioRoute(input: 10, inputRate: 16_000, output: 20)

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

    @Test func theOutputOnlyBindsWhileVoiceProcessingIsOn() {
        var state = MicEngineState()
        state.usedInput(on: micX)
        #expect(!state.needsNewEngine(on: micY, engineRunning: false))

        state.voiceProcessingChanged(to: true, on: micY)
        #expect(!state.needsNewEngine(on: micY, engineRunning: false))
        #expect(state.needsNewEngine(on: micX, engineRunning: false))

        state.voiceProcessingChanged(to: false, on: micX)
        #expect(!state.needsNewEngine(on: micX, engineRunning: false))
    }

    @Test func anUnboundEngineIsNeverReplaced() {
        var state = MicEngineState()
        #expect(!state.needsNewEngine(on: otherMic, engineRunning: false))

        state.voiceProcessingChanged(to: true, on: micX)
        state.replaced()
        #expect(!state.needsNewEngine(on: otherMic, engineRunning: false))
        #expect(!state.voiceProcessing)
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

    @Test func silenceRebuildsOnceThenFallsBackToThePlainMic() {
        var state = MicEngineState()
        state.voiceProcessingChanged(to: true, on: micX)
        state.takeEnded(frames: 0, seconds: 4)
        state.replaced()
        state.voiceProcessingChanged(to: true, on: micX)
        state.takeEnded(frames: 16_000, seconds: 1)
        state.takeEnded(frames: 0, seconds: 4)
        #expect(state.needsNewEngine(on: micX, engineRunning: true))

        state.replaced()
        state.voiceProcessingChanged(to: true, on: micX)
        state.takeEnded(frames: 0, seconds: 4)
        #expect(!state.needsNewEngine(on: micX, engineRunning: true))
        #expect(!state.allowsVoiceProcessing(on: micX))
    }

    @Test func aSilentPlainTakeKeepsTheEngine() {
        var state = MicEngineState()
        state.usedInput(on: micX)
        state.takeEnded(frames: 0, seconds: 4)
        #expect(!state.needsNewEngine(on: micX, engineRunning: false))
    }

    @Test func voiceProcessingFailuresHoldForTheirRoutesUntilTheSettingChanges() {
        var state = MicEngineState()
        state.voiceProcessingFailed(on: micX)
        state.replaced()
        #expect(!state.allowsVoiceProcessing(on: micX))
        #expect(state.allowsVoiceProcessing(on: micY))

        state.voiceProcessingFailed(on: micY)
        state.replaced()
        #expect(!state.allowsVoiceProcessing(on: micX))
        #expect(!state.allowsVoiceProcessing(on: micY))

        state.settingChanged()
        #expect(state.allowsVoiceProcessing(on: micX))
        #expect(state.allowsVoiceProcessing(on: micY))
    }}
