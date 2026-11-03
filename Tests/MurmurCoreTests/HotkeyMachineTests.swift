import Testing
@testable import MurmurCore

struct HotkeyMachineTests {
    /// The hold timer can lose the race to key-up, so release time alone must also decide a hold.
    @Test func holdPastThresholdInsertsOnRelease() {
        var m = HotkeyMachine(holdThreshold: 0.25)
        #expect(m.keyDown(at: 0) == .start)
        #expect(m.keyUp(at: 1.2) == .finish)
        #expect(m.keyDown(at: 2) == .start)
        m.holdTimerFired()
        #expect(m.keyUp(at: 3) == .finish)
        #expect(m.phase == .idle)
    }

    @Test func quickTapLocksAndNextPressInserts() {
        var m = HotkeyMachine(holdThreshold: 0.25)
        #expect(m.keyDown(at: 0) == .start)
        #expect(m.keyUp(at: 0.1) == .lock)
        #expect(m.keyDown(at: 5) == .finish)
        #expect(m.keyUp(at: 5.1) == nil)
        #expect(m.phase == .idle)
    }

    @Test func globeShortcutDuringShortHoldCancels() {
        var m = HotkeyMachine()
        _ = m.keyDown(at: 0)
        #expect(m.otherKeyDown() == .cancel)
        #expect(m.keyUp(at: 0.1) == nil)
    }

    @Test func typingWhileHoldingPastThresholdKeepsRecording() {
        var m = HotkeyMachine()
        _ = m.keyDown(at: 0)
        m.holdTimerFired()
        #expect(m.otherKeyDown() == nil)
        #expect(m.isRecording)
    }

    @Test func escapeCancelsLockedSession() {
        var m = HotkeyMachine()
        _ = m.keyDown(at: 0)
        _ = m.keyUp(at: 0.1)
        #expect(m.escape() == .cancel)
        #expect(m.keyDown(at: 1) == .start)
    }
}
