import AVFoundation
import Accelerate

/// Microphone capture converted to 16 kHz mono Float32, the format Parakeet expects.
///
/// The engine can stay running between takes (`keepWarm`) because a cold input start can take
/// hundreds of milliseconds and clip the first word; while idle, buffers are dropped.
public final class AudioCapture: @unchecked Sendable {
    public static let sampleRate: Double = 16_000

    private let engine = AVAudioEngine()
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

    public var keepWarm: TimeInterval = 60

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
        engineQueue.async { [self] in
            cooldown?.cancel()
            do {
                if !engine.isRunning { try startEngine() }
                started(nil)
            } catch {
                started(error)
            }
        }
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

    private func startEngine() throws {
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            throw CaptureError.noInputDevice
        }
        converter = AVAudioConverter(from: format, to: target)
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            self?.handle(buffer)
        }
        inputTapped = true
        engine.prepare()
        try engine.start()
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
