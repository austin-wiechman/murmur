import SwiftUI
import Carbon.HIToolbox
import MurmurCore
import MurmurEngine

/// The Settings window: a Liquid Glass sidebar over its sections.
struct SettingsView: View {
    @Bindable var prefs: Preferences
    var history: HistoryStore
    var status: StatusStore
    weak var actions: AppActions?
    @State var section: SettingsSection = .general

    var body: some View {
        NavigationSplitView {
            List(SettingsSection.allCases, selection: $section) { item in
                Label(item.title, systemImage: item.symbol).tag(item)
            }
            .navigationSplitViewColumnWidth(min: 170, ideal: 180, max: 220)
        } detail: {
            Group {
                switch section {
                case .general: GeneralSettings(prefs: prefs, status: status, actions: actions)
                case .speech: SpeechSettings(status: status)
                case .cleanup: CleanupSettings(prefs: prefs, status: status)
                case .history: HistoryView(history: history, actions: actions)
                }
            }
            .navigationTitle(section.title)
        }
        .frame(minWidth: 720, minHeight: 520)
    }
}

// MARK: - General

struct GeneralSettings: View {
    @Bindable var prefs: Preferences
    var status: StatusStore
    weak var actions: AppActions?

    var body: some View {
        Form {
            if !status.missingPermissions.isEmpty {
                Section("Permissions") { PermissionRows(status: status, actions: actions) }
            }
            Section("Dictation") {
                LabeledContent {
                    HotkeyList(hotkeys: $prefs.hotkeys, actions: actions)
                } label: {
                    Text("Shortcuts")
                    Text("Any of these starts and stops dictation, in every app")
                }
                Toggle(isOn: $prefs.holdToTalk) {
                    Text("Hold to talk")
                    Text("Tap a key to lock hands-free instead; Esc cancels")
                }
                Picker(selection: $prefs.keepMicWarmSeconds) {
                    Text("Off").tag(0.0)
                    Text("10 seconds").tag(10.0)
                    Text("1 minute").tag(60.0)
                    Text("15 minutes").tag(900.0)
                } label: {
                    Text("Keep microphone ready")
                    Text("The next dictation starts instantly; the mic indicator stays on")
                }
                Toggle(isOn: $prefs.showLiveWords) {
                    Text("Show live words")
                    Text("One line of what is heard, next to the pill")
                }
            }
            Section("System") {
                Toggle(isOn: $prefs.startSound) {
                    Text("Start sound")
                    Text("A soft tick when the mic opens")
                }
                Toggle("Open at login", isOn: Binding(
                    get: { status.launchAtLogin },
                    set: { status.setLaunchAtLogin($0) }))
                Toggle("Check for updates automatically", isOn: Binding(
                    get: { status.automaticUpdates },
                    set: { status.setAutomaticUpdates($0) }))
            }
            if status.missingPermissions.isEmpty {
                Section("Permissions") { PermissionRows(status: status, actions: actions) }
            }
        }
        .formStyle(.grouped)
    }
}

struct HotkeyList: View {
    @Binding var hotkeys: [Hotkey]
    weak var actions: AppActions?
    @State private var recorder = HotkeyRecorder()

    var body: some View {
        VStack(alignment: .trailing, spacing: 6) {
            FlowLayout(spacing: 6) {
                ForEach(hotkeys) { key in
                    HotkeyChip(hotkey: key, removable: hotkeys.count > 1) { remove(key) }
                }
                recordChip
            }
            if let message = recorder.message {
                Text(message).font(.system(size: 11.5)).foregroundStyle(.secondary)
            }
        }
        .onDisappear { recorder.stop() }
    }

    private var recordChip: some View {
        Button {
            if recorder.isRecording { recorder.stop() } else { record() }
        } label: {
            Text(recorder.isRecording ? "Press a key or combo… Esc to cancel" : "Record shortcut…")
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(recorder.isRecording ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.primary))
                .padding(.horizontal, 10).frame(height: 26)
                .overlay {
                    Capsule().strokeBorder(recorder.isRecording ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.tertiary),
                                           style: StrokeStyle(lineWidth: 1, dash: recorder.isRecording ? [] : [3, 2]))
                }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private func record() {
        actions?.setRecordingShortcut(true)
        recorder.start(existing: hotkeys, add: { hotkeys.append($0) }, finished: { actions?.setRecordingShortcut(false) })
    }

    private func remove(_ hotkey: Hotkey) {
        guard hotkeys.count > 1 else { return }
        hotkeys.removeAll { $0 == hotkey }
    }
}

private struct HotkeyChip: View {
    var hotkey: Hotkey
    var removable: Bool
    var remove: () -> Void

    var body: some View {
        let label = hotkey.label
        HStack(spacing: 5) {
            if hotkey == .globe { Image(systemName: "globe") }
            Text(label)
            Button(action: remove) { Image(systemName: "xmark").font(.system(size: 9, weight: .bold)) }
                .buttonStyle(.plain)
                .disabled(!removable)
                .opacity(removable ? 0.85 : 0.35)
                .help(removable ? "Remove \(label)" : "Keep at least one shortcut")
                .accessibilityLabel("Remove \(label)")
        }
        .font(.system(size: 12.5, weight: .medium))
        .foregroundStyle(.white)
        .padding(.leading, 10).padding(.trailing, 8).frame(height: 26)
        .background(Color.accentColor, in: Capsule())
    }
}

/// Captures one shortcut from the Settings window: the first key or combo, or a lone modifier
/// pressed and released with nothing else in between.
@MainActor @Observable
final class HotkeyRecorder {
    private(set) var isRecording = false
    private(set) var message: String?

    @ObservationIgnored private var monitor: Any?
    @ObservationIgnored private var resignObserver: Any?
    /// The one modifier currently down, while it is still a candidate for a lone-modifier hotkey.
    @ObservationIgnored private var lone: UInt16?
    /// A second modifier or a rejected key joined this press, so its release is not a hotkey.
    @ObservationIgnored private var spoiled = false
    @ObservationIgnored private var existing: [Hotkey] = []
    @ObservationIgnored private var add: (Hotkey) -> Void = { _ in }
    @ObservationIgnored private var finished: () -> Void = {}

    /// Keys that may be a hotkey without a modifier, because they never type text.
    private static let bareKeys: Set<Int> = [
        kVK_F1, kVK_F2, kVK_F3, kVK_F4, kVK_F5, kVK_F6, kVK_F7, kVK_F8, kVK_F9, kVK_F10, kVK_F11, kVK_F12,
        kVK_F13, kVK_F14, kVK_F15, kVK_F16, kVK_F17, kVK_F18, kVK_F19, kVK_F20,
        kVK_Home, kVK_End, kVK_PageUp, kVK_PageDown, kVK_Help,
    ]
    private static let reserved: [Hotkey: String] = [
        .pasteLast: "⌃⌘V is Paste last dictation",
        .undoCleanup: "⌃⌘Z is Undo cleanup",
    ]

    func start(existing: [Hotkey], add: @escaping (Hotkey) -> Void, finished: @escaping () -> Void) {
        stop()
        self.existing = existing
        self.add = add
        self.finished = finished
        isRecording = true
        message = nil
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] event in
            guard let self else { return event }
            return MainActor.assumeIsolated { self.handle(event) } ? nil : event
        }
        resignObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification, object: NSApp.keyWindow, queue: .main
        ) { [weak self] _ in MainActor.assumeIsolated { self?.stop() } }
    }

    func stop() {
        guard isRecording else { return }
        isRecording = false
        if let monitor { NSEvent.removeMonitor(monitor) }
        if let resignObserver { NotificationCenter.default.removeObserver(resignObserver) }
        monitor = nil
        resignObserver = nil
        lone = nil
        spoiled = false
        finished()
    }

    /// Returns true when the event was consumed.
    private func handle(_ event: NSEvent) -> Bool {
        let flags = CGEventFlags(rawValue: UInt64(event.modifierFlags.rawValue))
        let held = flags.intersection(Hotkey.modifierMask)
        if event.type == .keyDown {
            lone = nil
            if Int(event.keyCode) == kVK_Escape, held.isEmpty { stop(); return true }
            let hotkey = Hotkey(recording: event)
            if held.isEmpty, !Self.bareKeys.contains(Int(event.keyCode)) {
                message = "Add ⌘, ⌥, ⌃ or ⇧ to \(hotkey.label) so it still types normally"
                return true
            }
            accept(hotkey)
            return true
        }
        guard Hotkey.isModifierKey(Int(event.keyCode)) else { return false }
        if Hotkey.modifierIsDown(Int(event.keyCode), flags: flags) {
            if lone == nil, !spoiled { lone = event.keyCode } else { lone = nil; spoiled = true }
        } else if lone == event.keyCode {
            accept(Hotkey(keyCode: event.keyCode, modifiers: 0, isModifierOnly: true))
        }
        if held.isEmpty, !flags.contains(.maskSecondaryFn) { lone = nil; spoiled = false }
        return true
    }

    private func accept(_ hotkey: Hotkey) {
        if let reason = Self.reserved[hotkey] {
            message = "\(reason); pick another"
        } else if existing.contains(hotkey) {
            message = "\(hotkey.label) is already a shortcut"
            stop()
        } else {
            message = nil
            add(hotkey)
            stop()
        }
    }
}

// MARK: - Speech

struct SpeechSettings: View {
    var status: StatusStore

    var body: some View {
        Form {
            Section("Speech model") {
                LabeledContent {
                    statusBadge
                } label: {
                    Text("Parakeet Unified 0.6B, English")
                    Text("Runs on the Neural Engine. Audio never leaves this Mac.")
                }
                LabeledContent("Transcription", value: "Streams while you speak")
            }
        }
        .formStyle(.grouped)
    }

    @ViewBuilder private var statusBadge: some View {
        switch status.engine {
        case .preparingSpeechModel:
            HStack(spacing: 6) { ProgressView().controlSize(.small); Text("Preparing") }
                .foregroundStyle(.secondary)
        case .needsPermission(let what):
            Label("Needs \(what)", systemImage: "exclamationmark.triangle").foregroundStyle(Theme.coral)
        case .ready:
            Label("Ready", systemImage: "circle.fill").labelStyle(DotLabelStyle()).foregroundStyle(Theme.accent)
        }
    }
}

private struct DotLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 6) {
            configuration.icon.font(.system(size: 7))
            configuration.title
        }
    }
}

// MARK: - Cleanup

struct CleanupSettings: View {
    @Bindable var prefs: Preferences
    var status: StatusStore

    var body: some View {
        Form {
            Section {
                LabeledContent {
                    EnginePicker(engine: $prefs.cleanupEngine, status: status).frame(width: 260)
                } label: {
                    Text("Clean up with")
                    Text(engineDetail)
                }
                if prefs.cleanupEngine == .claude {
                    Picker("Claude model", selection: $prefs.claudeModel) {
                        ForEach(ClaudeModel.allCases) { Text($0.label).tag($0) }
                    }
                }
                if prefs.cleanupEngine != .off {
                    LabeledContent {
                        Stepper(value: $prefs.cleanupTimeout, in: 1...10, step: 1) {
                            Text("\(Int(prefs.cleanupTimeout)) s").monospacedDigit()
                        }
                    } label: {
                        Text("Give up after")
                        Text("Your raw words are pasted if cleanup takes longer; long dictations get about a second more per 100 words")
                    }
                }
            }
            Section {
                TextEditor(text: Binding(
                    get: { prefs.customInstructions.isEmpty ? CleanupPrompt.defaultInstructions : prefs.customInstructions },
                    set: { prefs.customInstructions = $0 == CleanupPrompt.defaultInstructions ? "" : $0 }))
                    .font(.system(size: 12.5))
                    .frame(minHeight: 150)
                    .scrollContentBackground(.hidden)
            } header: {
                HStack {
                    Text("Instructions")
                    Spacer()
                    Button("Reset to default") { prefs.customInstructions = "" }
                        .disabled(prefs.customInstructions.isEmpty)
                }
            } footer: {
                Text(prefs.customInstructions.isEmpty ? "Default instructions, used by both engines." : "Edited. Used by both engines.")
            }
        }
        .formStyle(.grouped)
    }

    private var engineDetail: String {
        let shown = prefs.cleanupEngine.resolved(
            claudeInstalled: status.claudeInstalled, onDeviceAvailable: status.onDeviceAvailable, online: true)
        return switch shown {
        case .off where prefs.cleanupEngine != .off:
            "Cleanup needs Apple Intelligence or Claude Code. Murmur pastes exactly what was heard."
        case .off: "Paste exactly what was heard"
        case .onDevice where !status.claudeInstalled:
            "Apple's on-device model. Nothing leaves this Mac. To use Claude, install Claude Code and sign in."
        case .onDevice: "Apple's on-device model. Nothing leaves this Mac."
        case .claude: "Runs your Claude Code CLI on your Claude subscription. Transcripts go to Anthropic."
        }
    }
}

struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 400
        var x: CGFloat = 0, y: CGFloat = 0, row: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width { x = 0; y += row + spacing; row = 0 }
            x += size.width + spacing
            row = max(row, size.height)
        }
        return CGSize(width: width, height: y + row)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, row: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX { x = bounds.minX; y += row + spacing; row = 0 }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            row = max(row, size.height)
        }
    }
}
