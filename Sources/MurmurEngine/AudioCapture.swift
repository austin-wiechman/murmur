import AVFoundation
import Accelerate
import CoreAudio
import MurmurCore
import ObjCExceptionCatcher

/// Microphone capture converted to 16 kHz mono Float32, the format Parakeet expects.
///
/// The engine can stay running between takes (`keepWarm`) because a cold input start can take
/// hundreds of milliseconds and clip the first word; while idle, buffers are dropped.
public final class AudioCapture: @unchecked Sendable {
    public static let sampleRate: Double = 16_000

    /// After the default input switches to a device with another sample rate, an engine can keep reporting the old
    /// format, and tapping with it fails; a start that fails retries once on a new engine. Only touched on `engineQueue`.
    private var engine = AVAudioEngine()
    private let target = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: AudioCapture.sampleRate,
                                       channels: 1, interleaved: false)!
    private let lock = NSLock()
    /// Starting or stopping the engine can block for hundreds of milliseconds, so it happens here,
    /// in order, instead of on the caller's thread. `cooldown` is only touched on this queue.
    private let engineQueue = DispatchQueue(label: "murmur.audio-engine", qos: .userInitiated)
    private var converter: AVAudioConverter?
    private var sink: ((AVAudioPCMBuffer) -> Void)?
    private var framesCaptured = 0
    private var squaresSinceRead: Float = 0
    private var framesSinceRead = 0
    private var cooldown: DispatchWorkItem?
    /// Reading `engine.inputNode` asks macOS for the microphone, so stopping never touches it
    /// unless a start already did. Only touched on `engineQueue`.
    private var inputTapped = false
    /// Engines replaced after a failed start. Freeing one while AVFAudio still delivers a device change to it
    /// segfaults, so they live as long as the process. Only touched on `engineQueue`.
    private var retiredEngines: [AVAudioEngine] = []

    public var keepWarm: TimeInterval = 60
    /// Apple's voice processing: cancels what the speakers play and suppresses background noise.
    /// It can only change while the engine is stopped, so a change stops and prepares an idle
    /// engine now and switches a warm one at the next `start`.
    public var voiceProcessing = false {
        didSet {
            guard voiceProcessing != oldValue else { return }
            let voiceProcessing = voiceProcessing
            engineQueue.async { [self] in
                guard lock.withLock({ sink == nil }) else { return }
                stopEngine()
                prepareStoppedEngine(voiceProcessing: voiceProcessing)
            }
        }
    }
    /// The mode the running engine was asked for. Only touched on `engineQueue`.
    private var startedWithVoiceProcessing = false
    /// Whether the current engine's input node has voice processing on, so the off path can skip
    /// `inputNode`, which would create the node. Only touched on `engineQueue`.
    private var voiceProcessingOnEngine = false
    /// The devices the current engine was set up on; nil until its input node is first used.
    /// Only touched on `engineQueue`.
    private var engineRoute: AudioRoute?
    /// Set when the mic started only without voice processing; the rest of the session records
    /// plain. Only touched on `engineQueue`.
    private var voiceProcessingUnavailable = false

    public init() {}

    /// Starts delivering converted buffers to `sink`.
    /// The engine starts on `engineQueue`, then `started` reports how it went, on that queue. The
    /// start is queued before this returns, so a `stop()` made right after still runs after it.
    public func start(sink: @escaping (AVAudioPCMBuffer) -> Void, started: @escaping (Error?) -> Void) {
        lock.withLock {
            self.sink = sink
            framesCaptured = 0
            squaresSinceRead = 0
            framesSinceRead = 0
        }
        let wanted = voiceProcessing
        engineQueue.async { [self] in
            cooldown?.cancel()
            let voiceProcessing = wanted && !voiceProcessingUnavailable
            retireIfRouteChanged(Self.currentRoute())
            if engine.isRunning, startedWithVoiceProcessing != voiceProcessing { stopEngine() }
            do {
                if !engine.isRunning { try startEngineReplacingIfStale(voiceProcessing: voiceProcessing) }
                started(nil)
            } catch {
                stopEngine()
                started(error)
            }
        }
    }

    /// Switches voice processing on a stopped engine ahead of the first `start`, which would
    /// otherwise wait about a second for it. The mic stays off, and without mic access this does
    /// nothing, so it never prompts.
    public func prepare() {
        guard voiceProcessing else { return }
        engineQueue.async { [self] in prepareStoppedEngine(voiceProcessing: true) }
    }

    private func prepareStoppedEngine(voiceProcessing wanted: Bool) {
        let voiceProcessing = wanted && !voiceProcessingUnavailable
        let route = Self.currentRoute()
        guard !engine.isRunning, route.input != kAudioObjectUnknown,
              AVCaptureDevice.authorizationStatus(for: .audio) == .authorized else { return }
        retireIfRouteChanged(route)
        setVoiceProcessing(voiceProcessing)
    }

    /// With voice processing the node's format no longer follows the hardware, so a tap on an
    /// engine left on old devices can succeed and deliver nothing; a changed route gets a new one.
    private func retireIfRouteChanged(_ route: AudioRoute) {
        guard let engineRoute, route.needsNewEngine(builtOn: engineRoute, voiceProcessing: voiceProcessingOnEngine)
        else { return }
        retireEngine()
    }

    private func retireEngine() {
        stopEngine()
        retiredEngines.append(engine)
        engine = AVAudioEngine()
        voiceProcessingOnEngine = false
        engineRoute = nil
    }

    private static func currentRoute() -> AudioRoute {
        AudioRoute(input: defaultDevice(kAudioHardwarePropertyDefaultInputDevice),
                   output: defaultDevice(kAudioHardwarePropertyDefaultOutputDevice))
    }

    private static func defaultDevice(_ selector: AudioObjectPropertySelector) -> AudioObjectID {
        var address = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var device = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device)
        return device
    }

    /// Stops recording and returns how many frames were captured since `start`.
    @discardableResult
    public func stop() -> Int {
        let captured = lock.withLock {
            sink = nil
            return framesCaptured
        }
        let keepWarm = keepWarm
        engineQueue.async { [self] in scheduleShutdown(after: keepWarm) }
        return captured
    }

    /// RMS of the audio since the last call, or nil if no buffer arrived in between.
    public func readRMS() -> Float? {
        lock.withLock {
            defer {
                squaresSinceRead = 0
                framesSinceRead = 0
            }
            return framesSinceRead > 0 ? (squaresSinceRead / Float(framesSinceRead)).squareRoot() : nil
        }
    }

    /// Stops the engine now, waiting for it; for quitting.
    public func shutdown() {
        engineQueue.sync { stopEngine() }
    }

    private func stopEngine() {
        cooldown?.cancel()
        guard inputTapped else { return }
        engine.inputNode.removeTap(onBus: 0)
        inputTapped = false
        engine.stop()
        converter = nil
    }

    /// A replacement engine hasn't been prepared, so its start pays the voice processing enable.
    /// If voice processing turns on but the engine won't start twice, a plain start is tried.
    private func startEngineReplacingIfStale(voiceProcessing: Bool) throws {
        do {
            try startEngine(voiceProcessing: voiceProcessing)
        } catch {
            retireEngine()
            do {
                try startEngine(voiceProcessing: voiceProcessing)
            } catch where voiceProcessing {
                retireEngine()
                try startEngine(voiceProcessing: false)
                voiceProcessingUnavailable = true
                NSLog("Murmur: the mic only starts without voice processing, so this session records without it: \(error)")
            }
        }
    }

    private func startEngine(voiceProcessing: Bool) throws {
        if engineRoute == nil { engineRoute = Self.currentRoute() }
        setVoiceProcessing(voiceProcessing)
        startedWithVoiceProcessing = voiceProcessing
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            throw CaptureError.noInputDevice
        }
        converter = AVAudioConverter(from: format, to: target)
        // Voice processing delivers four identical discrete channels, which the converter's
        // default mapping turns into silence. Plain stereo input already maps channel 0.
        converter?.channelMap = [0]
        input.removeTap(onBus: 0)
        // AVFAudio raises instead of throwing when the format no longer matches the device.
        try ObjCExceptionCatcher.installTap(on: input, bus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            self?.handle(buffer)
        }
        inputTapped = true
        engine.prepare()
        try engine.start()
    }

    /// The first enable takes about a second; the node keeps it across stops, so later starts skip
    /// that. If it can't be enabled, capture carries on with the plain mic.
    private func setVoiceProcessing(_ enabled: Bool) {
        guard enabled != voiceProcessingOnEngine else { return }
        let input = engine.inputNode
        var thrown: Error?
        do {
            // AVFAudio raises instead of throwing for some device states, and this runs at launch.
            try ObjCExceptionCatcher.catchException {
                do {
                    try input.setVoiceProcessingEnabled(enabled)
                    guard enabled else { return }
                    input.voiceProcessingOtherAudioDuckingConfiguration =
                        AVAudioVoiceProcessingOtherAudioDuckingConfiguration(enableAdvancedDucking: false, duckingLevel: .min)
                } catch {
                    thrown = error
                }
            }
        } catch {
            thrown = error
        }
        if let thrown {
            NSLog("Murmur: couldn't turn voice processing \(enabled ? "on" : "off"): \(thrown)")
            return
        }
        voiceProcessingOnEngine = enabled
        if enabled { engineRoute = Self.currentRoute() }
    }

    private func handle(_ buffer: AVAudioPCMBuffer) {
        guard lock.withLock({ sink != nil }), let converter else { return }
        let ratio = target.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 32
        guard let out = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: capacity) else { return }
        var supplied = false
        var error: NSError?
        converter.convert(to: out, error: &error) { _, status in
            if supplied {
                status.pointee = .noDataNow
                return nil
            }
            supplied = true
            status.pointee = .haveData
            return buffer
        }
        guard error == nil, out.frameLength > 0, let channel = out.floatChannelData?[0] else { return }
        let count = Int(out.frameLength)
        var squares: Float = 0
        vDSP_svesq(channel, 1, &squares, vDSP_Length(count))
        let deliver: ((AVAudioPCMBuffer) -> Void)? = lock.withLock {
            framesCaptured += count
            squaresSinceRead += squares
            framesSinceRead += count
            return sink
        }
        deliver?(out)
    }

    private func scheduleShutdown(after keepWarm: TimeInterval) {
        cooldown?.cancel()
        guard keepWarm > 0 else {
            stopEngine()
            return
        }
        let item = DispatchWorkItem { [weak self] in self?.stopEngine() }
        cooldown = item
        engineQueue.asyncAfter(deadline: .now() + keepWarm, execute: item)
    }

    public enum CaptureError: Error, CustomStringConvertible {
        case noInputDevice
        public var description: String { "No microphone is available" }
    }
}
