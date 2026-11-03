import AppKit
import ServiceManagement
import Sparkle
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate, NSWindowDelegate {
    private var controller: DictationController!
    private let updater = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: nil,
                                                       userDriverDelegate: nil)
    private var pillPanel: PillPanel!
    private var statusItem: NSStatusItem!
    private let popover = NSPopover()
    private var settingsWindow: NSWindow?
    private var updaterStarted = false
    /// Timestamp of the event that started the popover's close animation, while it plays.
    private var closingSince: TimeInterval?
    private var reopenAfterClose = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        let preferences = Preferences()
        controller = DictationController(preferences: preferences, history: HistoryStore())
        controller.onOpenSettings = { [weak self] in self?.showSettings($0) }
        controller.onCheckForUpdates = { [weak self] in
            NSApp.activate()
            self?.updater.checkForUpdates(nil)
        }

        let status = controller.statusStore
        status.launchAtLogin = SMAppService.mainApp.status == .enabled
        status.setLaunchAtLogin = { enabled in
            do {
                if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            } catch {
                NSLog("Murmur: launch at login failed: \(error)")
            }
            status.launchAtLogin = SMAppService.mainApp.status == .enabled
        }
        // Sparkle writes this key once the question is answered, by setup or by Sparkle itself.
        status.setup.updatesAnswered = UserDefaults.standard.object(forKey: "SUEnableAutomaticChecks") != nil
        status.automaticUpdates = updater.updater.automaticallyChecksForUpdates
        status.setAutomaticUpdates = { [weak self] enabled in
            self?.updater.updater.automaticallyChecksForUpdates = enabled
            status.automaticUpdates = enabled
            status.setup.updatesAnswered = true
            self?.startUpdater()
        }

        NSApp.mainMenu = MainMenu.make(openSettings: #selector(openGeneralSettings), target: self)
        pillPanel = PillPanel(state: controller.pillStore, meter: controller.meter, actions: controller)

        popover.behavior = .transient
        popover.delegate = self
        let menu = NSHostingController(rootView: MenuContent(
            prefs: preferences, history: controller.history, status: status, actions: controller))
        menu.sizingOptions = .preferredContentSize
        popover.contentViewController = menu
        // Builds the SwiftUI menu now, so the first click doesn't wait for it.
        menu.view.layoutSubtreeIfNeeded()

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.target = self
        statusItem.button?.action = #selector(togglePopover)
        statusItem.button?.sendAction(on: [.leftMouseDown])
        updateStatusIcon()

        controller.start()
        if status.setup.updatesAnswered { startUpdater() }
        // Setup lives in the menu, so open it for anyone with a step left to do.
        if status.setup.nextStep != nil { showPopover() }
    }

    /// Waits for setup to answer the updates question, so Sparkle never asks it in a window of its own.
    private func startUpdater() {
        // `swift run` and development builds have no update feed.
        guard !updaterStarted, Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") != nil else { return }
        updaterStarted = true
        updater.startUpdater()
    }

    private func updateStatusIcon() {
        let attention = withObservationTracking {
            controller.statusStore.setup.needsAttention
        } onChange: { [weak self] in
            Task { @MainActor in self?.updateStatusIcon() }
        }
        statusItem.button?.image = attention ? Self.attentionIcon : Self.icon
    }

    private static let icon = NSImage(systemSymbolName: "waveform", accessibilityDescription: "Murmur")!

    /// The waveform with a coral dot cut into its corner. Drawn per appearance, since a colored dot
    /// can't be part of a template image.
    private static let attentionIcon: NSImage = {
        let base = icon.withSymbolConfiguration(.init(paletteColors: [.labelColor]))!
        let image = NSImage(size: base.size, flipped: false) { rect in
            base.draw(in: rect)
            let diameter: CGFloat = 6
            let dot = NSRect(x: rect.maxX - diameter, y: rect.maxY - diameter, width: diameter, height: diameter)
            NSGraphicsContext.current?.compositingOperation = .clear
            NSBezierPath(ovalIn: dot.insetBy(dx: -1.5, dy: -1.5)).fill()
            NSGraphicsContext.current?.compositingOperation = .sourceOver
            NSColor(Theme.coral).setFill()
            NSBezierPath(ovalIn: dot).fill()
            return true
        }
        image.accessibilityDescription = "Murmur needs setup"
        return image
    }()

    func applicationWillTerminate(_ notification: Notification) {
        controller?.shutdown()
    }

    /// `isShown` stays true through the close animation, so it can't tell a reopen from a close.
    @objc private func togglePopover() {
        if let closingSince {
            // A transient popover closes on any outside press, the icon included. If this press
            // started the close, it was the close; a press during an earlier close is a reopen.
            if closingSince != NSApp.currentEvent?.timestamp { reopenAfterClose = true }
            return
        }
        if popover.isShown { popover.performClose(nil) } else { showPopover() }
    }

    private func showPopover() {
        guard let button = statusItem.button else { return }
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
        controller.statusStore.menuOpen = true
    }

    func popoverWillClose(_ notification: Notification) {
        closingSince = NSApp.currentEvent?.timestamp ?? -1
    }

    func popoverDidClose(_ notification: Notification) {
        closingSince = nil
        controller.statusStore.menuOpen = false
        if reopenAfterClose {
            reopenAfterClose = false
            showPopover()
        }
    }

    private func showSettings(_ section: SettingsSection) {
        popover.performClose(nil)
        let view = SettingsView(prefs: controller.preferences, history: controller.history,
                                status: controller.statusStore, actions: controller, section: section)
        if let window = settingsWindow {
            window.contentViewController = NSHostingController(rootView: view)
        } else {
            let window = SettingsWindow.make(view)
            window.delegate = self
            settingsWindow = window
        }
        // A Dock icon while Settings is open gives a backgrounded window a way back.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    @objc private func openGeneralSettings() { showSettings(.general) }

    func windowWillClose(_ notification: Notification) {
        guard notification.object as? NSWindow === settingsWindow else { return }
        NSApp.setActivationPolicy(.accessory)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if let settingsWindow { settingsWindow.makeKeyAndOrderFront(nil) }
        return true
    }
}
