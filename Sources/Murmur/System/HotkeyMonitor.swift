import AppKit
import Carbon.HIToolbox

/// Watches the dictation key system-wide with a CGEventTap.
///
/// An active (not listen-only) tap is used so Esc can be swallowed while recording; otherwise it
/// would also reach the focused app, and in a terminal running Claude Code, Esc interrupts it.
/// Every keystroke on the system waits for an active tap's callback, so the tap runs on its own
/// thread and hands events to the main thread; a busy main thread can't delay typing elsewhere.
final class HotkeyMonitor: @unchecked Sendable {
    enum Event {
        case down, up, otherKey, escape, pasteLast, undoCleanup
    }

    /// What the tap reads to decide each event, shared with the main thread under `lock`.
    private struct State {
        var hotkeys: [Hotkey] = Hotkey.defaults
        var paused = false
        var isRecording = false
        /// The hotkey holding the current press, so releasing a different one doesn't end it.
        var active: Hotkey?
    }

    private let lock = NSLock()
    private var state = State()

    var hotkeys: [Hotkey] {
        get { lock.withLock { state.hotkeys } }
        set { lock.withLock { state.hotkeys = newValue } }
    }
    /// Set while Settings records a new shortcut, so pressing it doesn't start dictation.
    var paused: Bool {
        get { lock.withLock { state.paused } }
        set { lock.withLock { state.paused = newValue } }
    }
    /// Read synchronously from the tap to decide whether Esc is ours.
    var isRecording: Bool {
        get { lock.withLock { state.isRecording } }
        set { lock.withLock { state.isRecording = newValue } }
    }
    /// Called on the main thread with each event and when it happened, in `systemUptime` seconds;
    /// the main thread may handle a key-up well after it happened.
    @MainActor var onEvent: ((Event, TimeInterval) -> Void)?

    private var tap: CFMachPort?

    /// Fails without Accessibility permission.
    @MainActor @discardableResult
    func start() -> Bool {
        guard tap == nil else { return true }
        let mask = (1 << CGEventType.flagsChanged.rawValue) | (1 << CGEventType.keyDown.rawValue)
            | (1 << CGEventType.keyUp.rawValue)
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
            eventsOfInterest: CGEventMask(mask),
            callback: { _, type, event, refcon in
                guard let refcon else { return Unmanaged.passUnretained(event) }
                let monitor = Unmanaged<HotkeyMonitor>.fromOpaque(refcon).takeUnretainedValue()
                return monitor.handle(type, event)
            },
            userInfo: refcon)
        else { return false }
        self.tap = tap
        // The thread below is the only code that uses the port from here on.
        nonisolated(unsafe) let port = tap
        let thread = Thread {
            let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0)
            CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
            CGEvent.tapEnable(tap: port, enable: true)
            CFRunLoopRun()
        }
        thread.name = "Murmur hotkeys"
        thread.qualityOfService = .userInteractive
        thread.start()
        return true
    }

    /// Invalidating the port removes its run loop source, which ends the tap's thread.
    @MainActor
    func stop() {
        guard let tap else { return }
        CGEvent.tapEnable(tap: tap, enable: false)
        CFMachPortInvalidate(tap)
        self.tap = nil
    }

    /// Runs on the tap's thread.
    private func handle(_ type: CGEventType, _ event: CGEvent) -> Unmanaged<CGEvent>? {
        let pass = Unmanaged.passUnretained(event)
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return pass
        }
        let time = ProcessInfo.processInfo.systemUptime
        var sent: Event?
        let swallow = lock.withLock {
            let swallow = decide(type, event, &sent)
            // So an Esc right after the key is swallowed before the main thread catches up; the
            // main thread clears it again if the key doesn't start a dictation.
            if sent == .down { state.isRecording = true }
            return swallow
        }
        if let sent {
            DispatchQueue.main.async { MainActor.assumeIsolated { self.onEvent?(sent, time) } }
        }
        return swallow ? nil : pass
    }

    /// Whether to swallow `event`, setting `sent` to what it means for dictation. Called with `lock` held.
    private func decide(_ type: CGEventType, _ event: CGEvent, _ sent: inout Event?) -> Bool {
        guard !state.paused else { return false }
        let keyCode = Int(event.getIntegerValueField(.keyboardEventKeycode))
        let flags = event.flags
        let hotkeys = state.hotkeys

        switch type {
        case .flagsChanged:
            if let lone = hotkeys.first(where: { $0.isModifierOnly && Int($0.keyCode) == keyCode }) {
                let pressed = Hotkey.modifierIsDown(keyCode, flags: flags)
                if pressed, state.active == nil {
                    state.active = lone
                    sent = .down
                } else if !pressed, state.active == lone {
                    state.active = nil
                    sent = .up
                }
            } else if state.active?.isModifierOnly == true {
                sent = .otherKey
            }
            return false
        case .keyDown:
            if Hotkey.pasteLast.matchesKeyDown(keyCode: keyCode, flags: flags) { sent = .pasteLast; return true }
            if Hotkey.undoCleanup.matchesKeyDown(keyCode: keyCode, flags: flags) { sent = .undoCleanup; return true }
            if keyCode == kVK_Escape, state.isRecording {
                sent = .escape
                return true
            }
            if let combo = state.active, !combo.isModifierOnly, Int(combo.keyCode) == keyCode {
                return true
            }
            if let combo = hotkeys.first(where: { $0.matchesKeyDown(keyCode: keyCode, flags: flags) }) {
                if state.active == nil, event.getIntegerValueField(.keyboardEventAutorepeat) == 0 {
                    state.active = combo
                    sent = .down
                }
                return true
            }
            if state.active?.isModifierOnly == true { sent = .otherKey }
            return false
        case .keyUp:
            if let combo = state.active, !combo.isModifierOnly, Int(combo.keyCode) == keyCode {
                state.active = nil
                sent = .up
                return true
            }
            if hotkeys.contains(where: { !$0.isModifierOnly && Int($0.keyCode) == keyCode }) { return true }
            if keyCode == kVK_Escape, state.isRecording { return true }
            return false
        default:
            return false
        }
    }
}
