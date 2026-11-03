import AppKit
import SwiftUI

/// The Settings window, shared by the app and the demo gallery so screenshots match the real thing.
enum SettingsWindow {
    static let size = CGSize(width: 760, height: 560)

    static func make(_ view: SettingsView) -> NSWindow {
        let window = NSWindow(contentViewController: NSHostingController(rootView: view))
        window.title = "Murmur Settings"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        window.toolbarStyle = .unified
        window.setContentSize(size)
        window.isReleasedWhenClosed = false
        window.center()
        return window
    }
}
