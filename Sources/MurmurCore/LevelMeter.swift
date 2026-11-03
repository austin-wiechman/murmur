import Foundation

/// Turns the microphone's RMS at each pill tick into a 0...1 bar level that stays flat on room
/// noise and rises with speech.
///
/// The floor rises slower while input is above the gate so speech can't drag it up, and the span
/// decays from the speech peak so a quiet mic still fills the bars and a loud one doesn't pin
/// them. Constants were tuned at `tickRate` against recorded dictations and noise mixes.
public struct LevelMeter: Sendable {
    public static let tickRate: Double = 30

    static let floorRange: ClosedRange<Float> = -70 ... -30
    static let floorFall: Float = 0.25
    static let floorRisePerTick: Float = 3 / 30
    static let floorRiseDuringSpeechPerTick: Float = 0.5 / 30
    static let margin: Float = 6
    static let spanRange: ClosedRange<Float> = 14...24
    static let spanDecayPerTick: Float = 3 / 30
    static let attack: Float = 0.55
    static let release: Float = 0.25
    static let heardLevel: Float = 0.1
    static let heardTicks = 3

    public private(set) var level: Float = 0
    /// True once the input has stayed above the gate for a few consecutive ticks, which a click doesn't.
    public private(set) var heardSpeech = false
    public private(set) var noiseFloor: Float?
    private var lastDB: Float = -140
    private var span: Float = LevelMeter.spanRange.lowerBound
    private var ticksAbove = 0

    public init() {}

    /// Advances one tick. `rms` is nil when no audio arrived since the previous tick.
    @discardableResult
    public mutating func update(rms: Float?) -> Float {
        if let rms {
            lastDB = 20 * log10(max(rms, 1e-7))
        } else if noiseFloor == nil {
            return level
        }
        let db = lastDB

        var floor = noiseFloor ?? db
        if db < floor {
            floor += (db - floor) * Self.floorFall
        } else {
            let rise = db < floor + Self.margin ? Self.floorRisePerTick : Self.floorRiseDuringSpeechPerTick
            floor += min(db - floor, rise)
        }
        floor = min(max(floor, Self.floorRange.lowerBound), Self.floorRange.upperBound)
        noiseFloor = floor

        let above = db - floor - Self.margin
        span = min(max(max(above, span - Self.spanDecayPerTick), Self.spanRange.lowerBound), Self.spanRange.upperBound)
        let target = min(max(above / span, 0), 1)
        level += (target - level) * (target > level ? Self.attack : Self.release)

        ticksAbove = target > Self.heardLevel ? ticksAbove + 1 : 0
        if ticksAbove >= Self.heardTicks { heardSpeech = true }
        return level
    }
}
