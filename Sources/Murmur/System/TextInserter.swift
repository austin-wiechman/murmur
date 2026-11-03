import AppKit
import Carbon.HIToolbox

/// Pastes text at the cursor of the frontmost app by writing the pasteboard and posting ⌘V. Unless
/// `keepOnClipboard` is set, the user's clipboard is restored once the target has read it.
@MainActor
final class TextInserter {
    enum Failure: Error { case notTrusted, noKeyCode }

    private let settleBeforePaste: Duration = .milliseconds(60)
    /// Long enough for Electron apps, terminals and browsers to read the pasteboard.
    private let restoreDelay: Duration = .milliseconds(450)
    private var lastUndoable: (text: String, app: pid_t)?

    func insert(_ text: String, keepOnClipboard: Bool = false) async throws {
        guard AXIsProcessTrusted() else {
            put(text)
            throw Failure.notTrusted
        }
        guard let v = Self.keyCode(for: "v") else {
            put(text)
            throw Failure.noKeyCode
        }
        let pasteboard = NSPasteboard.general
        let snapshot = keepOnClipboard ? nil : Self.snapshot(pasteboard)
        put(text)
        let written = pasteboard.changeCount
        try? await Task.sleep(for: settleBeforePaste)
        post(v, flags: .maskCommand)
        lastUndoable = (text, NSWorkspace.shared.frontmostApplication?.processIdentifier ?? 0)
        guard let snapshot else { return }
        try? await Task.sleep(for: restoreDelay)
        // Leave the clipboard alone if the user copied something meanwhile.
        if pasteboard.changeCount == written { Self.restore(snapshot, to: pasteboard) }
    }

    /// Replaces the text just pasted with `replacement`. Backspaces rather than a selection, because
    /// Shift+Left selects nothing in a terminal. Only valid while the same app is frontmost.
    func replaceLast(with replacement: String) async throws {
        guard let last = lastUndoable, last.text.count <= 2000,
              NSWorkspace.shared.frontmostApplication?.processIdentifier == last.app else { return }
        lastUndoable = nil
        for _ in 0..<last.text.count { post(CGKeyCode(kVK_Delete), flags: []) }
        try await insert(replacement)
    }

    var canReplaceLast: Bool { (lastUndoable?.text.count ?? .max) <= 2000 }

    func clearUndo() { lastUndoable = nil }

    func put(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    private func post(_ key: CGKeyCode, flags: CGEventFlags) {
        let source = CGEventSource(stateID: .combinedSessionState)
        let down = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: true)
        let up = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: false)
        down?.flags = flags
        up?.flags = flags
        down?.post(tap: .cgSessionEventTap)
        up?.post(tap: .cgSessionEventTap)
    }

    static func keyCode(for character: String) -> CGKeyCode? {
        let current = TISCopyCurrentKeyboardInputSource().takeRetainedValue()
        if TISGetInputSourceProperty(current, kTISPropertyUnicodeKeyLayoutData) != nil {
            return keyCode(for: character, in: current)
        }
        return keyCode(for: character, in: TISCopyCurrentASCIICapableKeyboardLayoutInputSource().takeRetainedValue())
    }

    /// Translates with Command held, since layouts like "Dvorak – QWERTY ⌘" remap under Command.
    static func keyCode(for character: String, in layout: TISInputSource) -> CGKeyCode? {
        let command = UInt32((cmdKey >> 8) & 0xFF)
        return (0..<CGKeyCode(128)).first { KeyboardLayout.character(for: $0, modifiers: command, in: layout) == character }
    }

    private static func snapshot(_ pasteboard: NSPasteboard) -> [[NSPasteboard.PasteboardType: Data]] {
        (pasteboard.pasteboardItems ?? []).map { item in
            Dictionary(uniqueKeysWithValues: item.types.compactMap { type in item.data(forType: type).map { (type, $0) } })
        }
    }

    private static func restore(_ items: [[NSPasteboard.PasteboardType: Data]], to pasteboard: NSPasteboard) {
        pasteboard.clearContents()
        guard !items.isEmpty else { return }
        pasteboard.writeObjects(items.map { entry in
            let item = NSPasteboardItem()
            for (type, data) in entry { item.setData(data, forType: type) }
            return item
        })
    }
}
