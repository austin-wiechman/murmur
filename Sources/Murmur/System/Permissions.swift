import AppKit
import AVFoundation

enum Permissions {
    static var accessibility: Bool { AXIsProcessTrusted() }

    /// Shows macOS's Accessibility alert, which also adds Murmur to the list in System Settings.
    /// It first clears Murmur's own record: a record left by a build with another signature shows as
    /// switched on yet never grants trust, and nothing can tell it apart from a missing one.
    /// If the record can't be cleared, it opens the list in System Settings instead.
    static func requestAccessibility() {
        guard !accessibility else { return }
        if clearAccessibilityRecord() {
            AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary)
        } else {
            openSettings(for: .accessibility)
        }
    }

    private static func clearAccessibilityRecord() -> Bool {
        // Without a bundle ID, tccutil would reset Accessibility for every app on the Mac.
        guard let id = Bundle.main.bundleIdentifier, !id.isEmpty else { return false }
        let reset = Process()
        reset.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
        reset.arguments = ["reset", "Accessibility", id]
        guard (try? reset.run()) != nil else { return false }
        reset.waitUntilExit()
        return reset.terminationStatus == 0
    }

    static var microphone: AVAuthorizationStatus { AVCaptureDevice.authorizationStatus(for: .audio) }

    static func requestMicrophone() async -> Bool {
        await AVCaptureDevice.requestAccess(for: .audio)
    }

    static func openSettings(for permission: Permission) {
        let anchor = permission == .accessibility ? "Privacy_Accessibility" : "Privacy_Microphone"
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)")!)
    }
}
