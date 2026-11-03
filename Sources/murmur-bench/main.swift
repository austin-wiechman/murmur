import AVFoundation
import Foundation
import MurmurCore
import MurmurEngine

let usage = """
usage: murmur-bench cleanup <onDevice|claude> <transcripts.jsonl> [prompt.txt|default] [--warmup S] [--model M] [--limit S]
       murmur-bench transcribe <file.wav>
       murmur-bench meter <16k-mono.wav> [tapFrames]  (CSV of the pill level per 30 Hz tick)
Each JSONL line is {"raw": "..."}; cleanup prints one JSON result per line.

"""

let args = CommandLine.arguments
if args.count == 3, args[1] == "transcribe" {
    let file = try AVAudioFile(forReading: URL(fileURLWithPath: args[2]))
    let transcriber = Transcriber()
    let loadStart = Date()
    try await transcriber.load()
    print(String(format: "load %.2fs", Date().timeIntervalSince(loadStart)))
    let (stream, input) = AsyncStream.makeStream(of: AVAudioPCMBuffer.self)
    try await transcriber.begin(stream)
    let chunk = AVAudioFrameCount(file.processingFormat.sampleRate / 10)
    while file.framePosition < file.length {
        let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: chunk)!
        try file.read(into: buffer, frameCount: chunk)
        input.yield(buffer)
        try await Task.sleep(for: .milliseconds(10))
    }
    input.finish()
    let tailStart = Date()
    let text = try await transcriber.finish()
    print(String(format: "finish %.3fs", Date().timeIntervalSince(tailStart)))
    print(text)
    exit(0)
}
if args.count >= 3, args[1] == "meter" {
    let file = try AVAudioFile(forReading: URL(fileURLWithPath: args[2]))
    guard file.processingFormat.sampleRate == AudioCapture.sampleRate, file.processingFormat.channelCount == 1 else {
        FileHandle.standardError.write(Data("meter needs a 16 kHz mono WAV\n".utf8))
        exit(2)
    }
    let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length))!
    try file.read(into: buffer)
    let samples = UnsafeBufferPointer(start: buffer.floatChannelData![0], count: Int(buffer.frameLength))
    // Replays the tap: buffers of `tapFrames` land when complete and each tick reads what arrived.
    // 341 is the app's 1024-frame tap buffer at 48 kHz, resampled to 16 kHz.
    let tapFrames = args.count >= 4 ? Int(args[3])! : 341
    var meter = LevelMeter()
    var delivered = 0
    print("t,rms,level,floor,heard")
    let ticks = Int(Double(samples.count) / AudioCapture.sampleRate * LevelMeter.tickRate)
    for tick in stride(from: 1, through: ticks, by: 1) {
        let due = Int(Double(tick) / LevelMeter.tickRate * AudioCapture.sampleRate)
        var squares: Float = 0
        var frames = 0
        while delivered + tapFrames <= due {
            for s in samples[delivered..<delivered + tapFrames] { squares += s * s }
            frames += tapFrames
            delivered += tapFrames
        }
        let rms = frames > 0 ? (squares / Float(frames)).squareRoot() : nil
        let level = meter.update(rms: rms)
        print(String(format: "%.4f,%.6f,%.5f,%.3f,%d", Double(tick) / LevelMeter.tickRate, rms ?? -1, level,
                     meter.noiseFloor ?? .nan, meter.heardSpeech ? 1 : 0))
    }
    exit(0)
}
guard args.count >= 4, args[1] == "cleanup", let engine = CleanupEngine(rawValue: args[2]) else {
    FileHandle.standardError.write(Data(usage.utf8))
    exit(2)
}
let lines = try String(contentsOfFile: args[3], encoding: .utf8).split(separator: "\n")
var template = CleanupPrompt.defaultInstructions
if args.count >= 5, !args[4].hasPrefix("--"), args[4] != "default" { template = try String(contentsOfFile: args[4], encoding: .utf8) }
let limit = args.firstIndex(of: "--limit").flatMap { Double(args[$0 + 1]) } ?? 3
let warmup = args.firstIndex(of: "--warmup").flatMap { Double(args[$0 + 1]) } ?? 3

let model = args.firstIndex(of: "--model").map { args[$0 + 1] } ?? "haiku"
let cleaner: Cleaner = engine == .claude ? ClaudeCLICleaner(model: model) : FoundationModelsCleaner()
for line in lines {
    guard let obj = try JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
          let raw = obj["raw"] as? String else { continue }
    let prompt = CleanupPrompt(transcript: raw, template: template)
    let session = cleaner.prepare(instructions: prompt.instructions)
    try await Task.sleep(for: .seconds(warmup))
    let outcome = await CleanupRunner.run(session, prompt: prompt, raw: raw, timeout: .seconds(CleanupDeadline.seconds(limit: limit, transcript: raw)))
    let row: [String: Any] = [
        "raw": raw, "out": outcome.text, "source": outcome.source.rawValue,
        "note": outcome.note ?? "", "seconds": (outcome.seconds * 100).rounded() / 100,
    ]
    let data = try JSONSerialization.data(withJSONObject: row, options: [.sortedKeys, .withoutEscapingSlashes])
    print(String(decoding: data, as: UTF8.self))
}
