import Foundation
import Observation
import SQLite3

struct HistoryEntry: Identifiable, Equatable {
    var id: Int64
    var createdAt: Date
    var raw: String
    /// What was pasted: the cleaned text, or `raw` when cleanup was off or fell back.
    var text: String
    var app: String?
    var audioSeconds: Double
    var cleanupEngine: String?
    var cleanupNote: String?
    var transcribeMs: Int
    var cleanupMs: Int

    var wasCleaned: Bool { text != raw }
}

@MainActor @Observable
final class HistoryStore {
    private(set) var entries: [HistoryEntry] = []
    private var db: OpaquePointer?
    /// Negative, so it never collides with a SQLite row ID.
    private var unsavedID: Int64 = -1

    init(url: URL = HistoryStore.defaultURL) {
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard sqlite3_open(url.path, &db) == SQLITE_OK else {
            NSLog("Murmur: can't open history at \(url.path): \(String(cString: sqlite3_errmsg(db)))")
            return
        }
        exec("""
        PRAGMA journal_mode=WAL;
        CREATE TABLE IF NOT EXISTS dictations (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          created_at REAL NOT NULL,
          raw TEXT NOT NULL,
          text TEXT NOT NULL,
          app TEXT,
          audio_seconds REAL NOT NULL DEFAULT 0,
          cleanup_engine TEXT,
          cleanup_note TEXT,
          transcribe_ms INTEGER NOT NULL DEFAULT 0,
          cleanup_ms INTEGER NOT NULL DEFAULT 0
        );
        """)
        reload()
    }

    nonisolated static var defaultURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Murmur/history.sqlite")
    }

    var last: HistoryEntry? { entries.first }

    /// Shows the entry even when the database can't store it, so "Paste last" still finds it.
    func add(_ entry: HistoryEntry) {
        var saved = entry
        if let id = insert(entry) {
            saved.id = id
        } else {
            NSLog("Murmur: history write failed: \(String(cString: sqlite3_errmsg(db)))")
            saved.id = unsavedID
            unsavedID -= 1
        }
        entries.insert(saved, at: 0)
    }

    private func insert(_ entry: HistoryEntry) -> Int64? {
        var stmt: OpaquePointer?
        let sql = """
        INSERT INTO dictations (created_at, raw, text, app, audio_seconds, cleanup_engine, cleanup_note,
          transcribe_ms, cleanup_ms) VALUES (?,?,?,?,?,?,?,?,?)
        """
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_double(stmt, 1, entry.createdAt.timeIntervalSince1970)
        bind(stmt, 2, entry.raw)
        bind(stmt, 3, entry.text)
        bind(stmt, 4, entry.app)
        sqlite3_bind_double(stmt, 5, entry.audioSeconds)
        bind(stmt, 6, entry.cleanupEngine)
        bind(stmt, 7, entry.cleanupNote)
        sqlite3_bind_int64(stmt, 8, Int64(entry.transcribeMs))
        sqlite3_bind_int64(stmt, 9, Int64(entry.cleanupMs))
        guard sqlite3_step(stmt) == SQLITE_DONE else { return nil }
        return sqlite3_last_insert_rowid(db)
    }

    func delete(_ id: Int64) {
        exec("DELETE FROM dictations WHERE id = \(id)")
        entries.removeAll { $0.id == id }
    }

    func search(_ query: String) -> [HistoryEntry] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return entries }
        return entries.filter { $0.text.localizedCaseInsensitiveContains(q) || $0.raw.localizedCaseInsensitiveContains(q) }
    }

    private func reload() {
        var stmt: OpaquePointer?
        let sql = """
        SELECT id, created_at, raw, text, app, audio_seconds, cleanup_engine, cleanup_note, transcribe_ms, cleanup_ms
        FROM dictations ORDER BY id DESC LIMIT 2000
        """
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }
        var rows: [HistoryEntry] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            rows.append(HistoryEntry(
                id: sqlite3_column_int64(stmt, 0),
                createdAt: Date(timeIntervalSince1970: sqlite3_column_double(stmt, 1)),
                raw: column(stmt, 2) ?? "", text: column(stmt, 3) ?? "", app: column(stmt, 4),
                audioSeconds: sqlite3_column_double(stmt, 5), cleanupEngine: column(stmt, 6),
                cleanupNote: column(stmt, 7), transcribeMs: Int(sqlite3_column_int64(stmt, 8)),
                cleanupMs: Int(sqlite3_column_int64(stmt, 9))))
        }
        entries = rows
    }

    private func exec(_ sql: String) {
        sqlite3_exec(db, sql, nil, nil, nil)
    }

    private func bind(_ stmt: OpaquePointer?, _ index: Int32, _ value: String?) {
        guard let value else {
            sqlite3_bind_null(stmt, index)
            return
        }
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        sqlite3_bind_text(stmt, index, value, -1, transient)
    }

    private func column(_ stmt: OpaquePointer?, _ index: Int32) -> String? {
        guard let text = sqlite3_column_text(stmt, index) else { return nil }
        return String(cString: text)
    }
}
