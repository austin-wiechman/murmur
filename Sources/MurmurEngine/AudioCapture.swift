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
    /// format, and tapping with it fails, so engines get replaced. Only touched on `engineQueue`.
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
    /// Replaced engines. Freeing one while AVFAudio still delivers a device change to it
    /// segfaults, so they live as long as the process. Only touched on `engineQueue`.
    private var retiredEngines: [AVAudioEngine] = []

    public var keepWarm: TimeInterval = 60
    /// Apple's voice processing: cancels what the speakers play and suppresses background noise.
    /// It can only change while the engine is stopped, so a change takes effect now, or at the next
    /// `start` if a take is running.
    public var voiceProcessing = false {
        didSet {
            guard voiceProcessing != oldValue else { return }
            let voiceProcessing = voiceProcessing
            engineQueue.async { [self] in
                engineState.settingChanged()
                guard lock.withLock({ sink == nil }) else { return }
                stopEngine()
                prepareStoppedEngine(voiceProcessing: voiceProcessing)
            }
        }
    }
    /// The mode the running engine was asked for. Only touched on `engineQueue`.
    private var startedWithVoiceProcessing = false
    /// Only touched on `engineQueue`.
    private var engineState = MicEngineState()
    /// When the engine went live for the current take; a slow start doesn't count as a silent take.
    /// Only touched on `engineQueue`.
    private var liveSince: Date?

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
            liveSince = nil
            let route = Self.currentRoute()
            guard route.input != kAudioObjectUnknown else {
                stopEngine()
                started(CaptureError.noInputDevice)
                return
            }
            let voiceProcessing = wanted && engineState.allowsVoiceProcessing(on: route)
            retireIfRouteChanged(route)
            if engine.isRunning, startedWithVoiceProcessing != voiceProcessing { stopEngine() }
            do {
                if !engine.isRunning { try startEngineReplacingIfStale(voiceProcessing: voiceProcessing) }
                liveSince = Date()
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
        let route = Self.currentRoute()
        let voiceProcessing = wanted && engineState.allowsVoiceProcessing(on: route)
        guard !engine.isRunning, route.input != kAudioObjectUnknown,
              AVCaptureDevice.authorizationStatus(for: .audio) == .authorized else { return }
        retireIfRouteChanged(route)
        setVoiceProcessing(voiceProcessing)
    }

    /// With voice processing the node's format no longer follows the hardware, so a tap on an
    /// engine left on old devices can succeed and deliver nothing; a changed route gets a new one.
    private func retireIfRouteChanged(_ route: AudioRoute) {
        guard engineState.needsNewEngine(on: route, engineRunning: engine.isRunning) else { return }
        retireEngine()
    }

    private func retireEngine() {
        stopEngine()
        // Retired engines live as long as the process, so none keeps a voice processing unit.
        if engineState.voiceProcessing { try? ObjCExceptionCatcher.setVoiceProcessing(on: engine, enabled: false) }
        retiredEngines.append(engine)
        engine = AVAudioEngine()
        engineState.replaced()
    }

    private static func currentRoute() -> AudioRoute {
        let system = AudioObjectID(kAudioObjectSystemObject), unknown = AudioObjectID(kAudioObjectUnknown)
        let input = property(kAudioHardwarePropertyDefaultInputDevice, of: system, initial: unknown)
        return AudioRoute(input: input, inputRate: property(kAudioDevicePropertyNominalSampleRate, of: input, initial: 0),
                          output: property(kAudioHardwarePropertyDefaultOutputDevice, of: system, initial: unknown))
    }

    /// `initial` is what the caller sees when the read fails.
    private static func property<Value: BitwiseCopyable>(_ selector: AudioObjectPropertySelector, of object: AudioObjectID,
                                        initial: Value) -> Value {
        var address = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var value = initial
        var size = UInt32(MemoryLayout<Value>.size)
        AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value)
        return value
    }

    /// Stops recording and returns how many frames were captured since `start`.
    @discardableResult
    public func stop() -> Int {
        let captured = lock.withLock {
            sink = nil
            return framesCaptured
        }
        let stopped = Date()
        let keepWarm = keepWarm
        engineQueue.async { [self] in
            let live = liveSince.map { max(0, stopped.timeIntervalSince($0)) } ?? 0
            liveSince = nil
            engineState.takeEnded(frames: captured, seconds: live)
            scheduleShutdown(after: keepWarm)
        }
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
    private func startEngineReplacingIfStale(voiceProcessing: Bool) throws {
        do {
            try startEngine(voiceProcessing: voiceProcessing)
        } catch {
            retireEngine()
            do {
                try startEngine(voiceProcessing: voiceProcessing)
            } catch let error where voiceProcessing && error as? CaptureError != .noInputDevice {
                // Only a route where voice processing actually came on is blamed for the failure.
                let failedRoute = engineState.voiceProcessing ? engineState.route : nil
                retireEngine()
                try startEngine(voiceProcessing: false)
                guard let failedRoute else { return }
                engineState.voiceProcessingFailed(on: failedRoute)
                NSLog("Murmur: the mic only starts without voice processing; using the plain mic on these devices: \(error)")
            }
        }
    }

    private func startEngine(voiceProcessing: Bool) throws {
        engineState.usedInput(on: Self.currentRoute())
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
        // Returning here keeps the off path from touching `inputNode`, which would create the node.
        guard enabled != engineState.voiceProcessing else { return }
        // Read before the switch, which binds the node and takes about a second.
        let route = Self.currentRoute()
        do {
            // AVFAudio raises instead of throwing for some device states, and this runs at launch.
            try ObjCExceptionCatcher.setVoiceProcessing(on: engine, enabled: enabled)
        } catch {
            NSLog("Murmur: couldn't turn voice processing \(enabled ? "on" : "off"): \(error)")
        }
        // A failure can come after the switch, such as in the ducking setter, so ask the node.
        let isEnabled = ObjCExceptionCatcher.isVoiceProcessingEnabled(on: engine)
        engineState.voiceProcessingChanged(to: isEnabled, on: route)
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
