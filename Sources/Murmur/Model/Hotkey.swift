import AppKit
import Carbon.HIToolbox

/// A dictation key: either a lone modifier (Globe, Right ⌥) or a key with optional modifiers
/// (F13, ⌥Space). Lone modifiers are matched by physical side, so Right ⌘ leaves Left ⌘ alone.
struct Hotkey: Codable, Hashable, Identifiable {
    var keyCode: UInt16
    /// For key hotkeys: the exact ⌘⌥⌃⇧ set that must be held. Unused for lone modifiers.
    var modifiers: UInt64
    var isModifierOnly: Bool

    var id: String { "\(keyCode):\(modifiers):\(isModifierOnly)" }

    static let globe = Hotkey(keyCode: UInt16(kVK_Function), modifiers: 0, isModifierOnly: true)
    static let f13 = Hotkey(keyCode: UInt16(kVK_F13), modifiers: 0, isModifierOnly: false)
    static let defaults: [Hotkey] = [.f13, .globe]
    static let pasteLast = Hotkey(keyCode: UInt16(kVK_ANSI_V), modifiers: controlCommand, isModifierOnly: false)
    static let undoCleanup = Hotkey(keyCode: UInt16(kVK_ANSI_Z), modifiers: controlCommand, isModifierOnly: false)
    private static let controlCommand = CGEventFlags([.maskControl, .maskCommand]).rawValue

    static let modifierMask: CGEventFlags = [.maskCommand, .maskAlternate, .maskControl, .maskShift]

    /// Device-dependent bits (IOLLEvent.h) that say which side of a modifier is down.
    private static let sideBits: [Int: (family: CGEventFlags, bit: UInt64)] = [
        kVK_Command: (.maskCommand, 0x08), kVK_RightCommand: (.maskCommand, 0x10),
        kVK_Shift: (.maskShift, 0x02), kVK_RightShift: (.maskShift, 0x04),
        kVK_Option: (.maskAlternate, 0x20), kVK_RightOption: (.maskAlternate, 0x40),
        kVK_Control: (.maskControl, 0x01), kVK_RightControl: (.maskControl, 0x2000),
        kVK_Function: (.maskSecondaryFn, 0),
    ]

    static func isModifierKey(_ keyCode: Int) -> Bool { sideBits[keyCode] != nil }

    /// Whether the lone modifier `keyCode` is down according to a flagsChanged event's flags.
    static func modifierIsDown(_ keyCode: Int, flags: CGEventFlags) -> Bool {
        guard let side = sideBits[keyCode], flags.contains(side.family) else { return false }
        return side.bit == 0 || flags.rawValue & side.bit != 0
    }

    func matchesKeyDown(keyCode: Int, flags: CGEventFlags) -> Bool {
        !isModifierOnly && Int(self.keyCode) == keyCode
            && flags.intersection(Self.modifierMask).rawValue == modifiers
    }

    init(keyCode: UInt16, modifiers: UInt64, isModifierOnly: Bool) {
        self.keyCode = keyCode
        self.modifiers = isModifierOnly ? 0 : modifiers & Self.modifierMask.rawValue
        self.isModifierOnly = isModifierOnly
    }

    init(recording event: NSEvent) {
        let isModifier = event.type == .flagsChanged && Self.isModifierKey(Int(event.keyCode))
        let flags = CGEventFlags(rawValue: UInt64(event.modifierFlags.rawValue))
        self.init(keyCode: event.keyCode, modifiers: flags.rawValue, isModifierOnly: isModifier)
    }

    var label: String {
        if isModifierOnly { return Self.modifierNames[Int(keyCode)] ?? "Key \(keyCode)" }
        let flags = CGEventFlags(rawValue: modifiers)
        var text = ""
        if flags.contains(.maskControl) { text += "⌃" }
        if flags.contains(.maskAlternate) { text += "⌥" }
        if flags.contains(.maskShift) { text += "⇧" }
        if flags.contains(.maskCommand) { text += "⌘" }
        return text + Self.keyName(Int(keyCode))
    }

    private static let modifierNames: [Int: String] = [
        kVK_Function: "Globe", kVK_Command: "Left ⌘", kVK_RightCommand: "Right ⌘",
        kVK_Option: "Left ⌥", kVK_RightOption: "Right ⌥", kVK_Shift: "Left ⇧", kVK_RightShift: "Right ⇧",
        kVK_Control: "Left ⌃", kVK_RightControl: "Right ⌃",
    ]

    private static let specialKeys: [Int: String] = [
        kVK_Space: "Space", kVK_Return: "Return", kVK_Tab: "Tab", kVK_Delete: "Delete", kVK_Escape: "Esc",
        kVK_ForwardDelete: "Fwd Delete", kVK_Home: "Home", kVK_End: "End", kVK_PageUp: "Page Up",
        kVK_PageDown: "Page Down", kVK_LeftArrow: "←", kVK_RightArrow: "→", kVK_UpArrow: "↑", kVK_DownArrow: "↓",
        kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5", kVK_F6: "F6", kVK_F7: "F7",
        kVK_F8: "F8", kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12", kVK_F13: "F13",
        kVK_F14: "F14", kVK_F15: "F15", kVK_F16: "F16", kVK_F17: "F17", kVK_F18: "F18", kVK_F19: "F19",
        kVK_F20: "F20",
    ]

    private static func keyName(_ keyCode: Int) -> String {
        if let name = specialKeys[keyCode] { return name }
        let text = TISCopyCurrentKeyboardLayoutInputSource().flatMap {
            KeyboardLayout.character(for: UInt16(keyCode), action: kUCKeyActionDisplay, in: $0.takeRetainedValue())
        }?.uppercased() ?? ""
        return text.isEmpty ? "Key \(keyCode)" : text
    }
}
