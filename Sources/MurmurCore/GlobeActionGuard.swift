import Foundation

/// Holds the system's Globe action at "Do Nothing" while engaged, so pressing Globe for dictation
/// doesn't also open the emoji picker or switch input source. The user's action is recorded in
/// `slot` before it is changed, so a relaunch after a crash can still put it back.
public final class GlobeActionGuard {
    private struct Original: Codable {
        var value: Int32
        /// False when the user never chose an action, so release must leave it unset again.
        var explicit: Bool
    }

    private let setting: FnUsageSetting
    private let slot: PersistentSlot

    public init(setting: FnUsageSetting, slot: PersistentSlot) {
        self.setting = setting
        self.slot = slot
    }

    public func engage() {
        let current = setting.value
        if saved() != nil {
            if current == 0 { return }
            // The user picked an action since the record was written; that is the one to restore.
            slot.clear()
        }
        guard current != 0 else { return }
        let original = Original(value: current, explicit: setting.isExplicitlySet)
        guard let data = try? JSONEncoder().encode(original), (try? slot.save(data)) != nil else { return }
        setting.update(0)
    }

    public func release() {
        guard let original = saved() else { return }
        if setting.value == 0 {
            // Updating applies immediately; clearing the stored value alone would wait for next login.
            setting.update(original.value)
            if !original.explicit { setting.clearExplicitValue() }
        }
        slot.clear()
    }

    private func saved() -> Original? {
        slot.load().flatMap { try? JSONDecoder().decode(Original.self, from: $0) }
    }
}
