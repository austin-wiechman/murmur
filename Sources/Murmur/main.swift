import AppKit

let app = NSApplication.shared
if let flag = CommandLine.arguments.firstIndex(of: "--demo-gallery"), flag + 1 < CommandLine.arguments.count {
    MainActor.assumeIsolated { DemoGallery.run(outDir: CommandLine.arguments[flag + 1]) }
} else {
    app.setActivationPolicy(.accessory)
}
let delegate = MainActor.assumeIsolated { AppDelegate() }
if !CommandLine.arguments.contains("--demo-gallery") { app.delegate = delegate }
app.run()
