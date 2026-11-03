import SwiftUI
import MurmurEngine

/// The menu bar dropdown, shown in an `NSPopover`.
struct MenuContent: View {
    @Bindable var prefs: Preferences
    var history: HistoryStore
    var status: StatusStore
    weak var actions: AppActions?

    @State private var copiedID: Int64?
    @State private var finishing: Finishing?

    /// The last step's check lands, then the confirmation plays, then the normal menu takes over.
    private enum Finishing { case checking, confirming }

    var body: some View {
        Group {
            if status.setup.showsSetupMenu || finishing != nil {
                SetupMenu(prefs: prefs, status: status, actions: actions, confirming: finishing == .confirming)
                    .transition(.opacity)
            } else {
                menu.transition(.opacity)
            }
        }
        .frame(width: 300)
        .onAppear { actions?.refreshCleanupEngines() }
        .onChange(of: status.menuOpen && status.setup.isComplete, initial: true) { _, ready in
            if ready, actions?.takeSetupConfirmation() == true { finish() }
        }
    }

    private func finish() {
        finishing = .checking
        Task {
            try? await Task.sleep(for: .milliseconds(450))
            withAnimation(.easeInOut(duration: 0.25)) { finishing = .confirming }
            try? await Task.sleep(for: .seconds(2))
            withAnimation(.easeInOut(duration: 0.3)) { finishing = nil }
        }
    }

    private var menu: some View {
        VStack(alignment: .leading, spacing: 0) {
            header.padding(.horizontal, 14).padding(.top, 14).padding(.bottom, 12)
            Divider().padding(.horizontal, 12)
            recent
            Divider().padding(.horizontal, 12)
            cleanup.padding(.horizontal, 14).padding(.vertical, 12)
            Divider().padding(.horizontal, 12)
            VStack(spacing: 2) {
                MenuRow(title: "Paste last dictation", shortcut: "⌃⌘V", disabled: history.last == nil) {
                    actions?.pasteLast()
                }
                MenuRow(title: "Settings…", shortcut: "⌘,") { actions?.openSettings(section: .general) }
                MenuRow(title: "Check for Updates…", shortcut: "") { actions?.checkForUpdates() }
            }
            .padding(6)
            Divider().padding(.horizontal, 12)
            MenuRow(title: "Quit Murmur", shortcut: "⌘Q") { actions?.quit() }.padding(6)
        }
    }

    private var header: some View {
        HStack(spacing: 11) {
            HStack(spacing: 2.5) {
                ForEach([5, 9, 13, 9, 5], id: \.self) { Capsule().frame(width: 2.5, height: CGFloat($0)) }
            }
            .frame(width: 34, height: 22)
            .background(.quaternary, in: Capsule())
            VStack(alignment: .leading, spacing: 1) {
                Text(statusTitle).font(.system(size: 13, weight: .semibold))
                Text(statusDetail).font(.system(size: 12)).foregroundStyle(.secondary)
            }
        }
    }

    private var statusTitle: String {
        switch status.engine {
        case .ready: "Ready"
        case .preparingSpeechModel: "Getting ready"
        case .needsPermission: "Needs permission"
        }
    }

    private var statusDetail: String {
        switch status.engine {
        case .ready:
            prefs.shortcutHint
        case .preparingSpeechModel: "Preparing the speech model, about 30 seconds"
        case .needsPermission(let what): "Allow \(what) in System Settings"
        }
    }

    private var recent: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Recent").font(.system(size: 11.5, weight: .medium)).foregroundStyle(.secondary)
                .padding(.horizontal, 8).padding(.bottom, 2)
            if history.entries.isEmpty {
                Text("Your dictations appear here.").font(.system(size: 13)).foregroundStyle(.secondary)
                    .padding(.horizontal, 8).padding(.vertical, 6)
            }
            ForEach(history.entries.prefix(3)) { entry in
                RecentRow(entry: entry, copied: copiedID == entry.id) {
                    actions?.copy(entry)
                    copiedID = entry.id
                } repaste: {
                    actions?.repaste(entry)
                }
            }
        }
        .padding(.horizontal, 6).padding(.vertical, 10)
    }

    private var cleanup: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Clean up with").font(.system(size: 11.5, weight: .medium)).foregroundStyle(.secondary)
            EnginePicker(engine: $prefs.cleanupEngine, status: status)
        }
    }
}

/// A segmented control drawn by hand: the system one renders its labels faintly on glass.
struct EnginePicker: View {
    @Binding var engine: CleanupEngine
    var status: StatusStore

    /// The engine dictation will use, so an option that can't run never looks selected.
    private var shown: CleanupEngine {
        engine.resolved(claudeInstalled: status.claudeInstalled, onDeviceAvailable: status.onDeviceAvailable, online: true)
    }

    var body: some View {
        HStack(spacing: 2) {
            segment(.off) { Text("Off") }
            segment(.onDevice) { Text("On device") }
                .disabled(!status.onDeviceAvailable)
                .help(status.onDeviceAvailable ? "" : "Turn on Apple Intelligence to clean up on device")
            segment(.claude) { Label("Claude", systemImage: "sparkle") }
                .disabled(!status.claudeInstalled)
                .help(status.claudeInstalled ? "" : "Install Claude Code to clean up with Claude")
        }
        .padding(2)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Clean up with")
    }

    private func segment(_ value: CleanupEngine, @ViewBuilder label: () -> some View) -> some View {
        let selected = shown == value
        return Button { engine = value } label: {
            label()
                .font(.system(size: 12.5, weight: selected ? .semibold : .regular))
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity).frame(height: 24)
                .background {
                    if selected {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(.background)
                            .shadow(color: .black.opacity(0.15), radius: 1.5, y: 0.5)
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

private struct RecentRow: View {
    var entry: HistoryEntry
    var copied: Bool
    var copy: () -> Void
    var repaste: () -> Void
    @State private var hovering = false

    /// One line, without Markdown list markers.
    private var preview: String {
        entry.text.split(separator: "\n")
            .map { $0.replacingOccurrences(of: #"^\s*(?:[-*]|\d+\.)\s+"#, with: "", options: .regularExpression) }
            .joined(separator: " ")
    }

    var body: some View {
        HStack(spacing: 8) {
            Button(action: copy) {
                HStack {
                    Text(preview)
                        .lineLimit(1).truncationMode(.tail)
                    Spacer(minLength: 8)
                    Text(copied ? "Copied" : entry.createdAt.formatted(date: .omitted, time: .shortened))
                        .font(.system(size: 12).monospacedDigit())
                        .foregroundStyle(copied ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(.secondary))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Copy")
            if hovering {
                Button(action: repaste) { Image(systemName: "arrow.uturn.down") }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .help("Paste again")
                    .accessibilityLabel("Paste again")
            }
        }
        .font(.system(size: 13))
        .padding(.horizontal, 8).frame(height: 28)
        .background(hovering ? AnyShapeStyle(.quaternary) : AnyShapeStyle(.clear),
                    in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .onHover { hovering = $0 }
    }
}

struct MenuRow: View {
    var title: String
    var shortcut: String
    var disabled = false
    var action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack {
                Text(title)
                Spacer()
                Text(shortcut).foregroundStyle(.secondary).font(.system(size: 12.5))
            }
            .font(.system(size: 13))
            .padding(.horizontal, 8).frame(height: 28)
            .contentShape(Rectangle())
            .background(hovering && !disabled ? AnyShapeStyle(.quaternary) : AnyShapeStyle(.clear),
                        in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.5 : 1)
        .onHover { hovering = $0 }
    }
}
