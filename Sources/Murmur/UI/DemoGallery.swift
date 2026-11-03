import AppKit
import SwiftUI
import MurmurCore
import MurmurEngine
import Carbon.HIToolbox

/// `Murmur --demo-gallery <dir>` renders every pill state over light and dark backdrops, plus the
/// menu and each Settings section, and writes PNGs. Used to review the UI without a live session.
@MainActor
enum DemoGallery {
    private static var windows: [NSWindow] = []
    private static let actions = DemoActions()

    static func run(outDir: String) {
        let out = URL(fileURLWithPath: outDir)
        try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        // No Dock icon and no activation: the windows render behind whatever the user is doing.
        NSApp.setActivationPolicy(.accessory)

        let prefs = Preferences(defaults: UserDefaults(suiteName: "murmur.demo.\(UUID().uuidString)")!)
        prefs.hotkeys = Hotkey.defaults + [Hotkey(keyCode: UInt16(kVK_Space), modifiers: CGEventFlags.maskAlternate.rawValue,
                                                  isModifierOnly: false)]
        let history = HistoryStore(url: FileManager.default.temporaryDirectory
            .appendingPathComponent("murmur-demo-\(UUID().uuidString).sqlite"))
        seed(history)
        let status = StatusStore()
        status.setup.accessibility = true
        status.setup.microphone = true
        status.setup.updatesAnswered = true
        status.setup.speechModelReady = true
        let missing = StatusStore()
        missing.accessibility = false
        missing.microphone = .notDetermined
        let settingUp = StatusStore()
        settingUp.microphone = .notDetermined
        settingUp.setup = Setup(confirmed: false)
        settingUp.setup.accessibility = true
        settingUp.modelProgress = .downloading(0.42)

        let states = galleryStates
        let half = (states.count + 1) / 2
        let settings = SettingsSection.allCases.map { section in
            ("settings-\(section.rawValue)", SettingsWindow.make(
                SettingsView(prefs: prefs, history: history, status: status, actions: actions, section: section)))
        } + [("settings-missing", SettingsWindow.make(
                SettingsView(prefs: prefs, history: history, status: missing, actions: actions, section: .general)))]
        let pages: [(String, AnyView, CGSize)] = [
            ("pills-1", AnyView(PillGrid(items: Array(states[..<half]))), CGSize(width: 1136, height: CGFloat(half) * 104 + 24)),
            ("pills-2", AnyView(PillGrid(items: Array(states[half...]))), CGSize(width: 1136, height: CGFloat(states.count - half) * 104 + 24)),
            ("menu", AnyView(MenuBackdrop { MenuContent(prefs: prefs, history: history, status: status, actions: actions) }),
             CGSize(width: 380, height: 520)),
            ("setup", AnyView(MenuBackdrop { MenuContent(prefs: prefs, history: history, status: settingUp, actions: actions) }),
             CGSize(width: 380, height: 420)),
            ("readme-pill", AnyView(ReadmePill()), CGSize(width: 640, height: 320)),
            ("readme-menu", AnyView(MenuBackdrop { MenuContent(prefs: prefs, history: history, status: status, actions: actions) }
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))), CGSize(width: 380, height: 472)),
        ]

        for (index, page) in pages.enumerated() {
            // README images have no title bar; their views round their own corners.
            let readme = page.0.hasPrefix("readme")
            let window = NSWindow(contentRect: CGRect(x: 40 + index * 30, y: 80, width: Int(page.2.width), height: Int(page.2.height)),
                                  styleMask: readme ? [.borderless] : [.titled, .closable, .fullSizeContentView],
                                  backing: .buffered, defer: false)
            if readme {
                window.isOpaque = false
                window.backgroundColor = .clear
            }
            window.title = page.0
            window.titlebarAppearsTransparent = page.0.hasPrefix("pills") || page.0 == "menu"
            window.contentView = NSHostingView(rootView: page.1.frame(width: page.2.width, height: page.2.height))
            window.isReleasedWhenClosed = false
            windows.append(window)
        }
        for (name, window) in settings {
            window.title = name
            windows.append(window)
        }
        let names = pages.map(\.0) + settings.map(\.0)
        let host = largestOtherWindow()
        for window in windows {
            if let host {
                window.setFrameOrigin(CGPoint(x: host.midX - window.frame.width / 2, y: host.midY - window.frame.height / 2))
            }
            window.orderBack(nil)
        }

        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2.5))
            var report: [String] = []
            for (window, name) in zip(windows, names) {
                let file = out.appendingPathComponent("\(name).png")
                if capture(window: window, to: file) {
                    report.append("ok screencapture \(file.path)")
                } else if fallback(window: window, to: file) {
                    report.append("fallback cacheDisplay (no glass) \(file.path)")
                } else {
                    report.append("failed \(name)")
                }
            }
            print(report.joined(separator: "\n"))
            NSApp.terminate(nil)
        }
    }

    /// The frame of another app's largest window, in AppKit coordinates. Windows centered inside it
    /// stay on screen, which `screencapture -l` needs, but out of sight.
    private static func largestOtherWindow() -> CGRect? {
        let me = ProcessInfo.processInfo.processIdentifier
        let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
            as? [[String: Any]] ?? []
        let frames = list.compactMap { info -> CGRect? in
            guard info[kCGWindowLayer as String] as? Int == 0,
                  info[kCGWindowOwnerPID as String] as? pid_t != me,
                  let bounds = info[kCGWindowBounds as String] as? NSDictionary else { return nil }
            return CGRect(dictionaryRepresentation: bounds)
        }
        guard let largest = frames.max(by: { $0.width * $0.height < $1.width * $1.height }),
              let primary = NSScreen.screens.first else { return nil }
        // The window server measures from the top of the primary screen, AppKit from the bottom.
        return CGRect(x: largest.minX, y: primary.frame.maxY - largest.maxY, width: largest.width, height: largest.height)
    }

    /// Window-server capture, which includes Liquid Glass. Needs Screen Recording for the
    /// launching process; returns false when it is blocked.
    private static func capture(window: NSWindow, to file: URL) -> Bool {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        p.arguments = ["-x", "-o", "-l", String(window.windowNumber), file.path]
        do { try p.run() } catch { return false }
        p.waitUntilExit()
        guard p.terminationStatus == 0,
              let attrs = try? FileManager.default.attributesOfItem(atPath: file.path),
              (attrs[.size] as? Int ?? 0) > 10_000 else { return false }
        return true
    }

    private static func fallback(window: NSWindow, to file: URL) -> Bool {
        guard let view = window.contentView, let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
            return false
        }
        view.cacheDisplay(in: view.bounds, to: rep)
        guard let data = rep.representation(using: .png, properties: [:]) else { return false }
        return (try? data.write(to: file)) != nil
    }

    private static func seed(_ history: HistoryStore) {
        let now = Date()
        history.add(HistoryEntry(id: 0, createdAt: now.addingTimeInterval(-3600),
                                 raw: "thanks for the notes I'll send the updated draft on Friday",
                                 text: "Thanks for the notes. I'll send the updated draft on Friday.",
                                 app: "Mail", audioSeconds: 5, cleanupEngine: "onDevice", cleanupNote: nil, transcribeMs: 60, cleanupMs: 900))
        history.add(HistoryEntry(id: 0, createdAt: now.addingTimeInterval(-1800),
                                 raw: "running about ten minutes late go ahead and start without me",
                                 text: "Running about ten minutes late. Go ahead and start without me.",
                                 app: "Messages", audioSeconds: 4, cleanupEngine: "onDevice", cleanupNote: nil, transcribeMs: 50, cleanupMs: 800))
        history.add(HistoryEntry(id: 0, createdAt: now.addingTimeInterval(-60),
                                 raw: "add to the grocery list oat milk coffee filters and um two lemons",
                                 text: "Add to the grocery list:\n- Oat milk\n- Coffee filters\n- Two lemons",
                                 app: "Notes", audioSeconds: 6, cleanupEngine: "onDevice", cleanupNote: nil, transcribeMs: 60, cleanupMs: 1000))
    }

    struct Item: Identifiable {
        let id = UUID()
        var name: String
        var state: PillState
        var liveWords = ""
    }

    static var galleryStates: [Item] {
        [
            Item(name: "Listening", state: .listening(heard: true)),
            Item(name: "Quiet", state: .listening(heard: false)),
            Item(name: "Hands-free", state: .locked(heard: true)),
            Item(name: "Live words", state: .listening(heard: true),
                 liveWords: "Ask Sam to check the order. Five, I agree, the button should say"),
            Item(name: "Transcribing", state: .transcribing),
            Item(name: "Cleaning up", state: .cleaning(.claude)),
            Item(name: "Inserted", state: .inserted(app: "Ghostty", canUndoCleanup: true)),
            Item(name: "Inserted, raw", state: .inserted(app: "Ghostty", canUndoCleanup: false)),
            Item(name: "No audio", state: .failure(.noAudio(device: nil))),
            Item(name: "Couldn't paste", state: .failure(.pasteBlocked)),
            Item(name: "Model loading", state: .failure(.modelLoading)),
            Item(name: "Mic denied", state: .failure(.microphoneDenied)),
        ]
    }
}

private struct PillGrid: View {
    var items: [DemoGallery.Item]
    var body: some View {
        VStack(spacing: 8) {
            ForEach(items) { item in
                HStack(spacing: 8) {
                    ForEach(Tone.allCases, id: \.self) { Tile(item: item, tone: $0) }
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color(red: 0.106, green: 0.11, blue: 0.125))
    }

    struct Tile: View {
        var item: DemoGallery.Item
        var tone: Tone
        @State private var store = PillStore()
        @State private var meter = PillMeter()

        var body: some View {
            ZStack(alignment: .topLeading) {
                Backdrop(tone: tone)
                Text(item.name).font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(tone == .dark ? .white.opacity(0.6) : .black.opacity(0.55))
                    .padding(8)
                PillView(store: store, meter: meter, actions: nil)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(width: 362, height: 96)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .onAppear {
                store.state = item.state
                meter.levels = [0.15, 0.3, 0.5, 0.42, 0.7, 0.55, 0.85, 0.6, 0.95, 0.72, 0.9]
                meter.liveWords = item.liveWords
            }
        }
    }

    enum Tone: CaseIterable { case dark, grey, white }

    struct Backdrop: View {
        var tone: Tone
        var body: some View {
            if tone != .dark {
                ZStack(alignment: .topLeading) {
                    tone == .white ? Color.white : Color(white: 0x88 / 255)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Weeknight tomato soup").font(.system(size: 14, weight: .bold))
                        Text("Simmer the tomatoes with garlic and basil for twenty minutes, then blend until smooth. Season with salt, finish with a little cream, and serve with toasted bread. Serves four.")
                            .font(.system(size: 12))
                    }
                    .foregroundStyle(.black.opacity(0.85))
                    .padding(.horizontal, 16).padding(.top, 24)
                }
            } else {
                ZStack(alignment: .topLeading) {
                    LinearGradient(colors: [Color(red: 0.25, green: 0.12, blue: 0.35), Color(red: 0.05, green: 0.08, blue: 0.2),
                                            Color(red: 0.4, green: 0.18, blue: 0.1)], startPoint: .topLeading, endPoint: .bottomTrailing)
                    Text("● Q4 Should the export include archived notes?\n  Q5 What should the export button say?\n> Waiting for your answers")
                        .font(.system(size: 11.5, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.75))
                        .padding(.horizontal, 16).padding(.top, 26)
                }
            }
        }
    }
}

/// The README's main image: a note being dictated, with the pill listening.
private struct ReadmePill: View {
    @State private var store = PillStore()
    @State private var meter = PillMeter()

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.white
            VStack(alignment: .leading, spacing: 10) {
                Text("Trip planning").font(.system(size: 22, weight: .bold))
                Text("Book the cabin for the second weekend of June. Check whether the trail to the lake is open by then, and pack the camp stove.")
                    .font(.system(size: 15))
                Text("Ask Jamie about borrowing the canoe.")
                    .font(.system(size: 15))
                Spacer()
            }
            .foregroundStyle(.black.opacity(0.85))
            .padding(.horizontal, 36).padding(.top, 36)
            .frame(maxWidth: .infinity, alignment: .leading)
            PillView(store: store, meter: meter, actions: nil)
                .padding(.bottom, 28)
        }
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .onAppear {
            store.state = .listening(heard: true)
            meter.levels = [0.2, 0.35, 0.55, 0.45, 0.75, 0.6, 0.9, 0.65, 0.95, 0.7, 0.85]
        }
    }
}

private struct MenuBackdrop<Content: View>: View {
    @ViewBuilder var content: () -> Content
    var body: some View {
        ZStack(alignment: .top) {
            LinearGradient(colors: [Color(red: 0.1, green: 0.16, blue: 0.35), Color(red: 0.3, green: 0.15, blue: 0.45)],
                           startPoint: .top, endPoint: .bottom)
            content()
                .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .padding(.top, 36)
        }
    }
}

@MainActor
private final class DemoActions: AppActions {
    func stopLocked() {}
    func cancelDictation() {}
    func pasteLast() {}
    func copy(_ entry: HistoryEntry) {}
    func repaste(_ entry: HistoryEntry) {}
    func openSettings(section: SettingsSection) {}
    func takeSetupConfirmation() -> Bool { false }
    func grant(_ permission: Permission) {}
    func setRecordingShortcut(_ recording: Bool) {}
    func checkForUpdates() {}
    func refreshCleanupEngines() {}
    func quit() {}
}
