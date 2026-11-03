import Foundation
import Testing
@testable import MurmurCore

struct LevelMeterTests {
    private func rms(_ db: Float) -> Float { pow(10, db / 20) }

    /// Room noise wobbling ±3 dB around -48 dBFS, like the user's recordings.
    private func room(_ tick: Int) -> Float { rms(-48 + 3 * sin(Float(tick) * 1.7)) }

    @Test func roomNoiseStaysFlatAndAClickIsNotSpeech() {
        var meter = LevelMeter()
        for t in 0..<60 { meter.update(rms: room(t)) }
        #expect(meter.level < 0.02)

        meter.update(rms: rms(-30))
        for t in 0..<15 { meter.update(rms: room(t)) }
        #expect(!meter.heardSpeech)
        #expect(meter.level < 0.02)

        for _ in 0..<6 { meter.update(rms: rms(-30)) }
        #expect(meter.heardSpeech)
        #expect(meter.level > 0.6)

        for t in 0..<20 { meter.update(rms: room(t)) }
        #expect(meter.level < 0.05)
    }

    @Test func longSpeechKeepsTheBarsUpAndMissingAudioHoldsTheLevel() {
        var meter = LevelMeter()
        for t in 0..<30 { meter.update(rms: room(t)) }
        for t in 0..<150 { meter.update(rms: rms(t % 9 == 0 ? -40 : -30)) }
        #expect(meter.level > 0.6)

        let before = meter.level
        meter.update(rms: nil)
        meter.update(rms: nil)
        #expect(meter.level > before * 0.8)
    }
}
