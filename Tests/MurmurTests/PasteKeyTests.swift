import Carbon.HIToolbox
import Testing
@testable import Murmur

@MainActor
struct PasteKeyTests {
    /// Dvorak types "v" from the key QWERTY labels ".". "Dvorak – QWERTY ⌘" switches to QWERTY while
    /// Command is held, so ⌘V is back on the QWERTY "v" key.
    @Test(arguments: [
        ("com.apple.keylayout.US", kVK_ANSI_V),
        ("com.apple.keylayout.Dvorak", kVK_ANSI_Period),
        ("com.apple.keylayout.DVORAK-QWERTYCMD", kVK_ANSI_V),
    ])
    func findsThePasteKeyForTheLayoutWithCommandHeld(layoutID: String, expected: Int) throws {
        let layout = try #require(installedLayout(layoutID))
        #expect(TextInserter.keyCode(for: "v", in: layout) == CGKeyCode(expected))
    }

    private func installedLayout(_ id: String) -> TISInputSource? {
        let filter = [kTISPropertyInputSourceID as String: id] as CFDictionary
        let sources = TISCreateInputSourceList(filter, true)?.takeRetainedValue() as? [TISInputSource]
        return sources?.first
    }
}
