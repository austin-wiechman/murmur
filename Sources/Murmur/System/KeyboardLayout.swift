import Carbon.HIToolbox

enum KeyboardLayout {
    /// What `keyCode` types on `layout`, ignoring dead-key composition. `modifiers` are Carbon
    /// modifier bits shifted right by 8, as `UCKeyTranslate` takes them.
    static func character(for keyCode: UInt16, modifiers: UInt32 = 0, action: Int = kUCKeyActionDown,
                          in layout: TISInputSource) -> String? {
        guard let raw = TISGetInputSourceProperty(layout, kTISPropertyUnicodeKeyLayoutData) else { return nil }
        let data = Unmanaged<CFData>.fromOpaque(raw).takeUnretainedValue() as Data
        return data.withUnsafeBytes { bytes -> String? in
            guard let keyLayout = bytes.baseAddress?.assumingMemoryBound(to: UCKeyboardLayout.self) else { return nil }
            var deadKeyState: UInt32 = 0
            var chars = [UniChar](repeating: 0, count: 4)
            var length = 0
            let status = UCKeyTranslate(keyLayout, keyCode, UInt16(action), modifiers, UInt32(LMGetKbdType()),
                                        OptionBits(kUCKeyTranslateNoDeadKeysMask), &deadKeyState, chars.count, &length, &chars)
            return status == noErr ? String(utf16CodeUnits: chars, count: length) : nil
        }
    }
}
