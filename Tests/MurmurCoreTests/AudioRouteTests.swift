import Testing
@testable import MurmurCore

struct AudioRouteTests {
    private let built = AudioRoute(input: 10, output: 20)

    @Test func aNewInputNeedsANewEngine() {
        let now = AudioRoute(input: 11, output: 20)
        #expect(now.needsNewEngine(builtOn: built, voiceProcessing: false))
        #expect(now.needsNewEngine(builtOn: built, voiceProcessing: true))
    }

    @Test func aNewOutputNeedsANewEngineOnlyWithVoiceProcessing() {
        let now = AudioRoute(input: 10, output: 21)
        #expect(now.needsNewEngine(builtOn: built, voiceProcessing: true))
        #expect(!now.needsNewEngine(builtOn: built, voiceProcessing: false))
    }

    @Test func theSameDevicesKeepTheEngine() {
        #expect(!built.needsNewEngine(builtOn: built, voiceProcessing: true))
    }
}
