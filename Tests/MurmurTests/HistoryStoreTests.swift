import Foundation
import Testing
@testable import Murmur

@MainActor
struct HistoryStoreTests {
    /// ⌃⌘V pastes `history.last`; a database that can't be opened or written must not make it paste nothing.
    @Test func pasteLastSeesADictationTheDatabaseCouldNotStore() {
        let store = HistoryStore(url: URL(fileURLWithPath: "/dev/null/Murmur/history.sqlite"))
        store.add(HistoryEntry(
            id: 0, createdAt: Date(), raw: "send it by friday", text: "Send it by Friday.", app: nil,
            audioSeconds: 1, cleanupEngine: nil, cleanupNote: nil, transcribeMs: 0, cleanupMs: 0))
        #expect(store.last?.text == "Send it by Friday.")
    }
}
