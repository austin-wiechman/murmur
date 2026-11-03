import Foundation
import Testing
@testable import MurmurCore

// Globe actions in System Settings: 0 Do Nothing, 1 Change Input Source, 2 Show Emoji & Symbols, 3 Start Dictation.
private final class FakeFnUsage: FnUsageSetting {
    private let systemDefault: Int32
    private var explicit: Int32?

    init(systemDefault: Int32 = 2, explicit: Int32?) {
        self.systemDefault = systemDefault
        self.explicit = explicit
    }

    var value: Int32 { explicit ?? systemDefault }
    func update(_ value: Int32) { explicit = value }
    var isExplicitlySet: Bool { explicit != nil }
    func clearExplicitValue() { explicit = nil }
}

private final class MemorySlot: PersistentSlot {
    struct WriteFailed: Error {}
    var data: Data?
    var failsWrites = false

    func load() -> Data? { data }
    func save(_ data: Data) throws {
        if failsWrites { throw WriteFailed() }
        self.data = data
    }
    func clear() { data = nil }
}

struct GlobeActionGuardTests {
    @Test func holdsGlobeAtDoNothingWhileEngagedAndRestoresTheUsersAction() {
        let setting = FakeFnUsage(explicit: 1)
        let guard_ = GlobeActionGuard(setting: setting, slot: MemorySlot())
        guard_.engage()
        #expect(setting.value == 0)
        guard_.engage()
        guard_.release()
        #expect(setting.value == 1)
        #expect(setting.isExplicitlySet)
    }

    @Test func restoresTheSystemDefaultWhenTheUserHadNeverChosenAnAction() {
        let setting = FakeFnUsage(systemDefault: 2, explicit: nil)
        let guard_ = GlobeActionGuard(setting: setting, slot: MemorySlot())
        guard_.engage()
        #expect(setting.value == 0)
        guard_.release()
        #expect(setting.value == 2)
        #expect(!setting.isExplicitlySet)
    }

    @Test func keepsAnActionTheUserPickedWhileEngaged() {
        let setting = FakeFnUsage(explicit: 1)
        let guard_ = GlobeActionGuard(setting: setting, slot: MemorySlot())
        guard_.engage()
        setting.update(3)
        guard_.release()
        #expect(setting.value == 3)
    }

    @Test func relaunchAfterACrashStillRestoresTheOriginalAction() {
        let setting = FakeFnUsage(explicit: 1)
        let slot = MemorySlot()
        GlobeActionGuard(setting: setting, slot: slot).engage()

        let relaunched = GlobeActionGuard(setting: setting, slot: slot)
        relaunched.engage()
        #expect(setting.value == 0)
        relaunched.release()
        #expect(setting.value == 1)
    }

    @Test func relaunchAfterACrashPrefersAnActionTheUserPickedSince() {
        let setting = FakeFnUsage(explicit: 1)
        let slot = MemorySlot()
        GlobeActionGuard(setting: setting, slot: slot).engage()
        setting.update(3)

        let relaunched = GlobeActionGuard(setting: setting, slot: slot)
        relaunched.engage()
        #expect(setting.value == 0)
        relaunched.release()
        #expect(setting.value == 3)
    }

    @Test func relaunchAfterACrashRestoresTheActionEvenWithGlobeNoLongerTheHotkey() {
        let setting = FakeFnUsage(explicit: 1)
        let slot = MemorySlot()
        GlobeActionGuard(setting: setting, slot: slot).engage()

        GlobeActionGuard(setting: setting, slot: slot).release()
        #expect(setting.value == 1)
    }

    @Test func leavesTheActionAloneWhenTheOriginalCannotBeSaved() {
        let setting = FakeFnUsage(explicit: 1)
        let slot = MemorySlot()
        slot.failsWrites = true
        GlobeActionGuard(setting: setting, slot: slot).engage()
        #expect(setting.value == 1)
    }
}
