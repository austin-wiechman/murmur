import AppKit
import AVFoundation
import MurmurCore
import MurmurEngine
import Observation

/// Runs one dictation at a time: key-down starts the mic and warms the cleaner, key-up (or the
/// second tap) finishes transcription, cleans up within the user's time limit, and pastes.
@MainActor @Observable
final class DictationController: AppActions {
    let preferences: Preferences
    let history: HistoryStore
    let meter = PillMeter()
    let pillStore = PillStore()
    let statusStore = StatusStore()
    private(set) var status: EngineStatus = .preparingSpeechModel { didSet { publishStatus() } }
    private enum ModelState { case loading, loaded, failed(String) }
    private var model = ModelState.loading { didSet { updateStatus() } }
    private var hotkeysRunning = false { didSet { updateStatus() } }

    var onOpenSettings: ((SettingsSection) -> Void)?
    var onCheckForUpdates: (() -> Void)?

    private let audio = AudioCapture()
    private let transcriber = Transcriber()
    private let inserter = TextInserter()
    private let network = NetworkMonitor()
    private let hotkeys = HotkeyMonitor()
    private var machine = HotkeyMachine()

    private var take: Take?
    private var busy = false
    private var holdTimer: Task<Void, Never>?
    private var meterTimer: Timer?
    @ObservationIgnored private var levelMeter = LevelMeter()
    private var pillTimer: Task<Void, Never>?
    private var undoRaw: String?
    private enum ClaudeLookup: Equatable { case pending, missing, found(URL) }
    @ObservationIgnored private var claudeLookup = ClaudeLookup.pending { didSet { publishStatus() } }
    @ObservationIgnored private var findingClaude = false
    private var claudeExecutable: URL? {
        if case .found(let url) = claudeLookup { url } else { nil }
    }

    private struct Take {
        var started = Date()
        var targetApp: NSRunningApplication?
        var audioInput: AsyncStream<AVAudioPCMBuffer>.Continuation
        var cleanup: CleanupSession?
        var engine: CleanupEngine
        var heard = false
    }

    init(preferences: Preferences, history: HistoryStore) {
        self.preferences = preferences
        self.history = history
        statusStore.setup = Setup(confirmed: preferences.setupConfirmed)
    }

    // MARK: - Lifecycle

    func start() {
        applyPreferences()
        hotkeys.onEvent = { [weak self] event, time in self?.handle(event, at: time) }
        watchPermissions()
        startHotkeys()
        refreshCleanupEngines()
        Task {
            do {
                let store = statusStore
                try await transcriber.load { progress in
                    Task { @MainActor in store.modelProgress = progress }
                }
                model = .loaded
            } catch {
                model = .failed(error.localizedDescription)
            }
        }
    }

    private func updateStatus() {
        status = switch (model, hotkeysRunning) {
        case (.failed(let why), _): .needsPermission("Speech model failed to load: \(why)")
        case (_, false): .needsPermission("Accessibility")
        case (.loading, true): .preparingSpeechModel
        case (.loaded, true): .ready
        }
        statusStore.setup.speechModelReady = modelLoaded
    }

    private var modelLoaded: Bool {
        if case .loaded = model { true } else { false }
    }

    private func publishStatus() {
        statusStore.engine = status
        statusStore.claudeInstalled = claudeLookup != .missing
    }

    /// Re-runs whenever a preference it reads changes.
    func applyPreferences() {
        withObservationTracking { applyPreferencesOnce() } onChange: { [weak self] in
            Task { @MainActor in self?.applyPreferences() }
        }
    }

    private func applyPreferencesOnce() {
        publishStatus()
        hotkeys.hotkeys = preferences.hotkeys
        machine.holdThreshold = preferences.holdToTalk ? 0.25 : .infinity
        audio.keepWarm = preferences.keepMicWarmSeconds
        if preferences.hotkeys.contains(.globe) { GlobeKeyGuard.engage() } else { GlobeKeyGuard.release() }
    }

    func shutdown() {
        hotkeys.stop()
        audio.shutdown()
        GlobeKeyGuard.release()
    }

    /// Starting the keyboard tap without Accessibility makes macOS show its own prompt on top of
    /// Murmur's permissions window, so wait for the grant first.
    private func startHotkeys() {
        if Permissions.accessibility, hotkeys.start() {
            hotkeysRunning = true
            return
        }
        Task {
            while !(Permissions.accessibility && hotkeys.start()) { try? await Task.sleep(for: .seconds(2)) }
            hotkeysRunning = true
        }
    }

    // MARK: - Hotkey events

    private func handle(_ event: HotkeyMonitor.Event, at now: TimeInterval) {
        // On every exit, so a flag left set while the machine is idle can't keep swallowing Esc.
        defer { hotkeys.isRecording = machine.isRecording }
        let command: HotkeyMachine.Command?
        switch event {
        case .down:
            if busy && !machine.isRecording {
                flash(.failure(.other("Still finishing the last dictation")))
                return
            }
            command = machine.keyDown(at: now)
        case .up: command = machine.keyUp(at: now)
        case .otherKey: command = machine.otherKeyDown()
        case .escape: command = machine.escape()
        case .pasteLast:
            pasteLast()
            return
        case .undoCleanup:
            undoCleanup()
            return
        }
        guard let command else { return }
        switch command {
        case .start: begin()
        case .lock: pillStore.state = .locked(heard: take?.heard ?? false)
        case .finish: finish()
        case .cancel: cancel()
        }
    }

    // MARK: - Pipeline

    private func begin() {
        guard modelLoaded else {
            machine.reset()
            flash(.failure(.modelLoading))
            return
        }
        if Permissions.microphone == .denied {
            machine.reset()
            flash(.failure(.microphoneDenied))
            return
        }
        statusStore.setup.dictated()
        preferences.setupConfirmed = statusStore.setup.confirmed
        pillTimer?.cancel()
        undoRaw = nil
        inserter.clearUndo()

        let (stream, input) = AsyncStream.makeStream(of: AVAudioPCMBuffer.self)
        let target = NSWorkspace.shared.frontmostApplication
        var cleanup: CleanupSession?
        let engine = preferences.cleanupEngine.resolved(
            claudeInstalled: claudeExecutable != nil, onDeviceAvailable: FoundationModelsCleaner.availability == nil,
            online: network.isOnline)
        if let cleaner = cleaner(for: engine) {
            let instructions = CleanupPrompt(transcript: "", template: preferences.instructions,
                                             targetApp: target?.localizedName).instructions
            cleanup = cleaner.prepare(instructions: instructions)
        }
        // Picks up a Claude Code install or removal for the next dictation.
        if preferences.cleanupEngine == .claude { findClaude() }
        let started = Date()
        take = Take(started: started, targetApp: target, audioInput: input, cleanup: cleanup, engine: engine)
        busy = true
        audio.start(sink: { buffer in input.yield(buffer) }) { [weak self] error in
            Task { @MainActor in self?.micStarted(error: error, take: started) }
        }

        meter.liveWords = ""
        let meter = meter
        var onPartial: (@Sendable (String) -> Void)?
        if preferences.showLiveWords {
            onPartial = { partial in
                let tail = String(partial.suffix(60))
                DispatchQueue.main.async { MainActor.assumeIsolated { meter.liveWords = tail } }
            }
        }
        Task {
            do {
                try await transcriber.begin(stream, onPartial: onPartial)
            } catch {
                self.cancelDictation()
                self.flash(.failure(.other("Couldn't start transcription")), for: 3)
            }
        }
        pillStore.state = .listening(heard: false)
        startMeter()
        holdTimer?.cancel()
        let threshold = machine.holdThreshold
        if threshold.isFinite {
            holdTimer = Task { [weak self] in
                try? await Task.sleep(for: .seconds(threshold))
                self?.machine.holdTimerFired()
            }
        }
    }

    private func micStarted(error: Error?, take started: Date) {
        guard take?.started == started else { return }
        if error != nil {
            cancelDictation()
            flash(.failure(.noAudio(device: nil)))
        } else if preferences.startSound {
            // The sound is the cue to talk, so it waits for a live mic.
            NSSound(named: "Tink")?.play()
        }
    }

    private func finish() {
        guard let take else { return }
        self.take = nil
        stopMeter()
        let frames = audio.stop()
        take.audioInput.finish()
        let audioSeconds = Double(frames) / AudioCapture.sampleRate
        // Parakeet decodes silence as "Yeah." or "Okay.", so a take with no speech never reaches it.
        guard take.heard else {
            take.cleanup?.discard()
            Task { await transcriber.cancel() }
            fail(.noAudio(device: AVCaptureDevice.default(for: .audio)?.localizedName))
            return
        }
        pillStore.state = .transcribing

        Task {
            let t0 = Date()
            let raw: String
            do {
                raw = try await transcriber.finish()
            } catch {
                take.cleanup?.discard()
                fail(.other("Transcription failed"))
                return
            }
            let transcribeMs = Int(Date().timeIntervalSince(t0) * 1000)
            guard !raw.isEmpty else {
                take.cleanup?.discard()
                fail(.noAudio(device: AVCaptureDevice.default(for: .audio)?.localizedName))
                return
            }

            var text = raw
            var note: String?
            var cleanupMs = 0
            // A word or two has nothing to clean, and waiting on the model only delays the paste.
            let cleanup = raw.split(whereSeparator: \.isWhitespace).count < 3 ? nil : take.cleanup
            if cleanup == nil { take.cleanup?.discard() }
            if let session = cleanup {
                pillStore.state = .cleaning(take.engine)
                let outcome = await CleanupRunner.run(
                    session, prompt: CleanupPrompt(transcript: raw), raw: raw, timeout: .seconds(CleanupDeadline.seconds(limit: preferences.cleanupTimeout, transcript: raw)))
                text = outcome.text
                note = outcome.note
                cleanupMs = Int(outcome.seconds * 1000)
            }

            let appName = take.targetApp?.localizedName
            history.add(HistoryEntry(
                id: 0, createdAt: take.started, raw: raw, text: text, app: appName, audioSeconds: audioSeconds,
                cleanupEngine: cleanup == nil ? nil : take.engine.rawValue, cleanupNote: note,
                transcribeMs: transcribeMs, cleanupMs: cleanupMs))

            if let target = take.targetApp, target != NSWorkspace.shared.frontmostApplication {
                target.activate()
                try? await Task.sleep(for: .milliseconds(80))
            }
            do {
                try await inserter.insert(text, keepOnClipboard: true)
                let undoable = text != raw && inserter.canReplaceLast
                undoRaw = undoable ? raw : nil
                busy = false
                flash(.inserted(app: appName, canUndoCleanup: undoable), for: undoable ? 4 : 1.6)
            } catch {
                busy = false
                flash(.failure(.pasteBlocked), for: 4)
            }
        }
    }

    private func cancel() {
        guard let take else { return }
        self.take = nil
        stopMeter()
        audio.stop()
        take.audioInput.finish()
        take.cleanup?.discard()
        Task { await transcriber.cancel() }
        busy = false
        pillStore.state = .hidden
    }

    private func fail(_ failure: PillState.Failure) {
        busy = false
        machine.reset()
        hotkeys.isRecording = false
        flash(.failure(failure), for: 3)
    }

    private func flash(_ state: PillState, for seconds: Double = 2) {
        pillStore.state = state
        pillTimer?.cancel()
        pillTimer = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled, let self, self.pillStore.state == state else { return }
            self.pillStore.state = .hidden
        }
    }

    private func undoCleanup() {
        guard let raw = undoRaw else { return }
        undoRaw = nil
        Task {
            try? await inserter.replaceLast(with: raw)
            flash(.inserted(app: NSWorkspace.shared.frontmostApplication?.localizedName, canUndoCleanup: false), for: 1.2)
        }
    }

    // MARK: - Meter

    private func startMeter() {
        meter.levels = Array(repeating: 0, count: meter.levels.count)
        meterTimer?.invalidate()
        levelMeter = LevelMeter()
        meterTimer = Timer.scheduledTimer(withTimeInterval: 1 / LevelMeter.tickRate, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tickMeter() }
        }
    }

    private func tickMeter() {
        let level = levelMeter.update(rms: audio.readRMS())
        meter.levels.removeFirst()
        meter.levels.append(level)
        if levelMeter.heardSpeech, var current = take, !current.heard {
            current.heard = true
            take = current
            switch pillStore.state {
            case .listening: pillStore.state = .listening(heard: true)
            case .locked: pillStore.state = .locked(heard: true)
            default: break
            }
        }
    }

    private func stopMeter() {
        meterTimer?.invalidate()
        meterTimer = nil
        holdTimer?.cancel()
    }

    // MARK: - Cleanup

    private func cleaner(for engine: CleanupEngine) -> Cleaner? {
        switch engine {
        case .off: nil
        case .onDevice: FoundationModelsCleaner()
        case .claude: ClaudeCLICleaner(model: preferences.claudeModel.rawValue, executable: claudeExecutable)
        }
    }

    func refreshCleanupEngines() {
        statusStore.onDeviceAvailable = FoundationModelsCleaner.availability == nil
        findClaude()
    }

    private func findClaude() {
        guard !findingClaude else { return }
        if let url = claudeExecutable, FileManager.default.isExecutableFile(atPath: url.path) { return }
        findingClaude = true
        Task {
            // Off the main thread: `locate()` can fall back to running a login shell.
            let url = await Task.detached { ClaudeCLICleaner.locate() }.value
            findingClaude = false
            claudeLookup = url.map(ClaudeLookup.found) ?? .missing
        }
    }

    // MARK: - AppActions

    func stopLocked() {
        guard case .locked = pillStore.state else { return }
        machine.reset()
        hotkeys.isRecording = false
        finish()
    }

    func cancelDictation() {
        _ = machine.escape()
        hotkeys.isRecording = false
        cancel()
    }

    func pasteLast() {
        guard let last = history.last else { return }
        repaste(last)
    }

    func copy(_ entry: HistoryEntry) { inserter.put(entry.text) }

    func repaste(_ entry: HistoryEntry) {
        Task {
            do { try await inserter.insert(entry.text, keepOnClipboard: true) } catch { flash(.failure(.pasteBlocked), for: 4) }
        }
    }

    func openSettings(section: SettingsSection) { onOpenSettings?(section) }

    func takeSetupConfirmation() -> Bool {
        let play = statusStore.setup.takeConfirmation()
        preferences.setupConfirmed = statusStore.setup.confirmed
        return play
    }

    func checkForUpdates() { onCheckForUpdates?() }

    func grant(_ permission: Permission) {
        switch permission {
        case .accessibility where !statusStore.askedForAccessibility:
            statusStore.askedForAccessibility = true
            Permissions.requestAccessibility()
        case .accessibility:
            Permissions.openSettings(for: .accessibility)
        case .microphone where Permissions.microphone == .notDetermined:
            Task {
                _ = await Permissions.requestMicrophone()
                refreshPermissions()
            }
        case .microphone:
            Permissions.openSettings(for: .microphone)
        }
    }

    /// macOS posts nothing when a permission changes, so poll while one is missing.
    private func watchPermissions() {
        refreshPermissions()
        Task { [weak self] in
            while let self, !self.statusStore.missingPermissions.isEmpty {
                try? await Task.sleep(for: .seconds(1))
                self.refreshPermissions()
            }
        }
    }

    private func refreshPermissions() {
        if statusStore.accessibility != Permissions.accessibility { statusStore.accessibility = Permissions.accessibility }
        if statusStore.microphone != Permissions.microphone { statusStore.microphone = Permissions.microphone }
        statusStore.setup.accessibility = statusStore.accessibility
        statusStore.setup.microphone = statusStore.microphone == .authorized
    }

    func setRecordingShortcut(_ recording: Bool) { hotkeys.paused = recording }

    func quit() { NSApp.terminate(nil) }
}
