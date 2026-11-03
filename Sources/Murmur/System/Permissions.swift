import AppKit
import AVFoundation

enum Permissions {
    static var accessibility: Bool { AXIsProcessTrusted() }

    /// Shows macOS's Accessibility alert, which also adds Murmur to the list in System Settings.
    /// It first clears Murmur's own record: a record left by a build with another signature shows as
    /// switched on yet never grants trust, and nothing can tell it apart from a missing one.
    static func requestAccessibility() {
        guard !accessibility else { return }
        let reset = Process()
        reset.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
        reset.arguments = ["reset", "Accessibility", Bundle.main.bundleIdentifier ?? ""]
        if (try? reset.run()) != nil { reset.waitUntilExit() }
        AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary)
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
