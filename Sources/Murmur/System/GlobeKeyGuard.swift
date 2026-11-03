import Foundation
import MurmurCore

/// Keeps macOS's own Globe action from firing while Globe is the dictation key.
enum GlobeKeyGuard {
    private static let shared = CarbonFnUsage().map { GlobeActionGuard(setting: $0, slot: DefaultsSlot()) }

    static func engage() { shared?.engage() }
    static func release() { shared?.release() }
}

/// The Globe action via Carbon's private TIS calls, which System Settings uses and which apply
/// immediately; writing `AppleFnUsageType` directly only takes effect at next login.
private final class CarbonFnUsage: FnUsageSetting {
    private typealias Get = @convention(c) () -> Int32
    private typealias Update = @convention(c) (Int32) -> Void

    private static let domain = "com.apple.HIToolbox" as CFString
    private static let key = "AppleFnUsageType" as CFString

    private let read: Get
    private let write: Update

    init?() {
        guard let carbon = dlopen("/System/Library/Frameworks/Carbon.framework/Carbon", RTLD_LAZY),
              let get = dlsym(carbon, "TISGetFnUsageType"),
              let set = dlsym(carbon, "TISUpdateFnUsageType") else { return nil }
        self.read = unsafeBitCast(get, to: Get.self)
        self.write = unsafeBitCast(set, to: Update.self)
    }

    var value: Int32 { read() }

    func update(_ value: Int32) { write(value) }

    // CFPreferences caches a foreign domain for the life of the process, hence the synchronizes.
    var isExplicitlySet: Bool {
        CFPreferencesSynchronize(Self.domain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
        return CFPreferencesCopyValue(Self.key, Self.domain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost) != nil
    }

    func clearExplicitValue() {
        CFPreferencesSynchronize(Self.domain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
        CFPreferencesSetValue(Self.key, nil, Self.domain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
        CFPreferencesSynchronize(Self.domain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
    }
}

private final class DefaultsSlot: PersistentSlot {
    private let key = "globeActionBeforeEngage"

    func load() -> Data? { UserDefaults.standard.data(forKey: key) }
    func save(_ data: Data) throws { UserDefaults.standard.set(data, forKey: key) }
    func clear() { UserDefaults.standard.removeObject(forKey: key) }
}
