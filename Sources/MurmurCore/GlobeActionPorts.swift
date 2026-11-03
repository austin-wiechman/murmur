import Foundation

/// The system's Globe-key action preference (`AppleFnUsageType` in `com.apple.HIToolbox`).
public protocol FnUsageSetting: AnyObject {
    /// The action macOS runs when Globe is pressed. 0 is "Do Nothing".
    var value: Int32 { get }
    func update(_ value: Int32)
    /// Whether the user's preferences hold an explicit value, rather than the system default.
    var isExplicitlySet: Bool { get }
    func clearExplicitValue()
}

/// Storage that survives a crash or force quit of the app.
public protocol PersistentSlot: AnyObject {
    func load() -> Data?
    func save(_ data: Data) throws
    func clear()
}
