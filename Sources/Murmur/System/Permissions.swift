import AppKit
import AVFoundation

enum Permissions {
    static var accessibility: Bool { AXIsProcessTrusted() }

    /// Shows macOS's Accessibility alert, which also adds Murmur to the list in System Settings.
    static func requestAccessibility() {
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
