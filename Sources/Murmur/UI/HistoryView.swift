import MurmurCore
import SwiftUI

struct HistoryView: View {
    var history: HistoryStore
    weak var actions: AppActions?
    @State private var query = ""
    @State private var showChanges = true

    var body: some View {
        let results = history.search(query)
        Group {
            if history.entries.isEmpty {
                ContentUnavailableView("No dictations yet", systemImage: "waveform",
                                       description: Text("Hold your shortcut and speak. Everything you dictate is kept here."))
            } else if results.isEmpty {
                ContentUnavailableView.search(text: query)
            } else {
                List(results) { entry in
                    HistoryRow(entry: entry, showChanges: showChanges, actions: actions) {
                        history.delete(entry.id)
                    }
                    .listRowSeparator(.visible)
                }
                .listStyle(.inset)
                .scrollContentBackground(.hidden)
            }
        }
        // In the content, not the toolbar: toolbar items on one section change the title bar height.
        .safeAreaInset(edge: .top, spacing: 0) {
            HStack(spacing: 12) {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Search \(history.entries.count) dictations", text: $query).textFieldStyle(.plain)
                }
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(.quaternary.opacity(0.6), in: Capsule())
                Toggle("Show changes", isOn: $showChanges).toggleStyle(.switch).controlSize(.small)
                    .font(.system(size: 12)).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 20).padding(.vertical, 10)
        }
    }
}

private struct HistoryRow: View {
    var entry: HistoryEntry
    var showChanges: Bool
    weak var actions: AppActions?
    var delete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if showChanges && entry.wasCleaned {
                Text(diffText).font(.system(size: 13.5)).textSelection(.enabled)
            } else {
                Text(entry.text).font(.system(size: 13.5)).textSelection(.enabled)
            }
            HStack(spacing: 12) {
                if let app = entry.app { Text(app) }
                Text(entry.createdAt.formatted(date: .abbreviated, time: .shortened))
                Text(Duration.seconds(entry.audioSeconds).formatted(.units(allowed: [.minutes, .seconds], width: .narrow)))
                if let note = entry.cleanupNote, !note.isEmpty {
                    Label("Raw words pasted", systemImage: "arrow.uturn.backward").help(note)
                }
                Spacer()
                Button("Copy") { actions?.copy(entry) }
                Button("Paste again") { actions?.repaste(entry) }
                Button(role: .destructive, action: delete) { Image(systemName: "trash") }
                    .accessibilityLabel("Delete")
            }
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
            .buttonStyle(.borderless)
        }
        .padding(.vertical, 6)
    }

    private var diffText: AttributedString {
        var out = AttributedString()
        var previous = ""
        for piece in WordDiff.diff(entry.raw, entry.text) {
            let text: String
            switch piece { case .same(let s), .removed(let s), .added(let s): text = s }
            if WordDiff.needsSpace(previous, text) { out += AttributedString(" ") }
            previous = text
            switch piece {
            case .same(let s):
                out += AttributedString(s)
            case .removed(let s):
                var a = AttributedString(s)
                a.strikethroughStyle = .single
                a.foregroundColor = Color(nsColor: .systemRed)
                out += a
            case .added(let s):
                var a = AttributedString(s)
                a.backgroundColor = Theme.accent.opacity(0.22)
                out += a
            }
        }
        return out
    }
}
