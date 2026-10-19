import Foundation
import SQLite3

/// SQLite owns all durable state. Each user action is committed atomically before the UI advances.
public final class Database {
    private var handle: OpaquePointer?
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private var savedState: AppState?
    public let url: URL

    public init(url: URL, excludeFromBackup: Bool = true) throws {
        self.url = url
        let parent = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        if excludeFromBackup {
            var directory = parent
            var values = URLResourceValues(); values.isExcludedFromBackup = true
            try directory.setResourceValues(values)
        }
        guard sqlite3_open(url.path, &handle) == SQLITE_OK else {
            let error = failure(); sqlite3_close(handle); handle = nil; throw error
        }
        do {
            try execute("PRAGMA foreign_keys = ON")
            try execute("PRAGMA journal_mode = DELETE")
            try execute("PRAGMA synchronous = FULL")
            try execute("CREATE TABLE IF NOT EXISTS metadata (key TEXT PRIMARY KEY, value TEXT NOT NULL)")
            try execute("CREATE TABLE IF NOT EXISTS words (id TEXT PRIMARY KEY, payload TEXT NOT NULL)")
            try execute("CREATE TABLE IF NOT EXISTS progress (id TEXT PRIMARY KEY, word_id TEXT NOT NULL REFERENCES words(id) ON DELETE CASCADE, payload TEXT NOT NULL)")
            try execute("CREATE TABLE IF NOT EXISTS settings (id TEXT PRIMARY KEY, payload TEXT NOT NULL)")
            try execute("CREATE TABLE IF NOT EXISTS reviews (id TEXT PRIMARY KEY, word_id TEXT NOT NULL REFERENCES words(id) ON DELETE CASCADE, payload TEXT NOT NULL)")
            try execute("INSERT OR IGNORE INTO metadata VALUES ('schema_version', '1')")
            if excludeFromBackup {
                var file = url; var values = URLResourceValues(); values.isExcludedFromBackup = true
                try file.setResourceValues(values)
                #if os(iOS)
                try FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: url.path)
                #endif
            }
        } catch { sqlite3_close(handle); handle = nil; throw error }
    }
    deinit { sqlite3_close(handle) }

    public func load() throws -> AppState {
        var state = AppState()
        state.words = try read("words", as: WordPair.self).sorted { $0.createdAt < $1.createdAt }
        let progress = try read("progress", as: Progress.self)
        state.progress = Dictionary(uniqueKeysWithValues: progress.map { ($0.key, $0) })
        for (id, data) in try rows("SELECT id, payload FROM settings") {
            state.settings[id] = try decoder.decode(PoolSettings.self, from: data)
        }
        state.reviews = try read("reviews", as: Review.self).sorted { $0.date < $1.date }
        savedState = state
        return state
    }

    public func save(_ state: AppState) throws {
        let old = try savedState ?? load()
        let oldWords = Dictionary(uniqueKeysWithValues: old.words.map { ($0.id, $0) })
        let newWords = Dictionary(uniqueKeysWithValues: state.words.map { ($0.id, $0) })
        let oldReviews = Dictionary(uniqueKeysWithValues: old.reviews.map { ($0.id, $0) })
        let newReviews = Dictionary(uniqueKeysWithValues: state.reviews.map { ($0.id, $0) })
        try execute("BEGIN IMMEDIATE")
        do {
            for id in oldReviews.keys where newReviews[id] == nil { try delete("reviews", id: id.uuidString) }
            for key in old.progress.keys where state.progress[key] == nil { try delete("progress", id: key) }
            for id in oldWords.keys where newWords[id] == nil { try delete("words", id: id.uuidString) }
            for id in old.settings.keys where state.settings[id] == nil { try delete("settings", id: id) }
            for word in state.words where oldWords[word.id] != word { try insert("words", id: word.id.uuidString, value: word) }
            for p in state.progress.values where old.progress[p.key] != p { try insert("progress", id: p.key, wordID: p.wordID, value: p) }
            for (id, config) in state.settings where old.settings[id] != config { try insert("settings", id: id, value: config) }
            for event in state.reviews where oldReviews[event.id] != event { try insert("reviews", id: event.id.uuidString, wordID: event.wordID, value: event) }
            // Defaults are virtual on an empty database; materialize all exercise configurations.
            if old.words.isEmpty && old.reviews.isEmpty {
                for (id, config) in state.settings { try insert("settings", id: id, value: config) }
            }
            try execute("COMMIT")
            savedState = state
        } catch { try? execute("ROLLBACK"); throw error }
    }

    private func delete(_ table: String, id: String) throws {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(handle, "DELETE FROM \(table) WHERE id = ?", -1, &stmt, nil) == SQLITE_OK else { throw failure() }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, id, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        guard sqlite3_step(stmt) == SQLITE_DONE else { throw failure() }
    }

    private func failure() -> Error { SprechenError.message("Couldn’t save or read your local data: \(handle.map { String(cString: sqlite3_errmsg($0)) } ?? "SQLite unavailable")") }
    private func execute(_ sql: String) throws {
        guard sqlite3_exec(handle, sql, nil, nil, nil) == SQLITE_OK else { throw failure() }
    }
    private func insert<T: Encodable>(_ table: String, id: String, wordID: UUID? = nil, value: T) throws {
        let json = String(decoding: try encoder.encode(value), as: UTF8.self)
        let sql = wordID == nil ? "INSERT INTO \(table) (id, payload) VALUES (?, ?) ON CONFLICT(id) DO UPDATE SET payload = excluded.payload" : "INSERT INTO \(table) (id, payload, word_id) VALUES (?, ?, ?) ON CONFLICT(id) DO UPDATE SET payload = excluded.payload, word_id = excluded.word_id"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &stmt, nil) == SQLITE_OK else { throw failure() }
        defer { sqlite3_finalize(stmt) }
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        sqlite3_bind_text(stmt, 1, id, -1, transient)
        sqlite3_bind_text(stmt, 2, json, -1, transient)
        if let wordID { sqlite3_bind_text(stmt, 3, wordID.uuidString, -1, transient) }
        guard sqlite3_step(stmt) == SQLITE_DONE else { throw failure() }
    }
    private func rows(_ sql: String) throws -> [(String, Data)] {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &stmt, nil) == SQLITE_OK else { throw failure() }
        defer { sqlite3_finalize(stmt) }
        var result: [(String, Data)] = []
        while true {
            let code = sqlite3_step(stmt)
            if code == SQLITE_DONE { return result }
            guard code == SQLITE_ROW, let id = sqlite3_column_text(stmt, 0), let json = sqlite3_column_text(stmt, 1) else { throw failure() }
            result.append((String(cString: id), Data(String(cString: json).utf8)))
        }
    }
    private func read<T: Decodable>(_ table: String, as type: T.Type) throws -> [T] {
        try rows("SELECT id, payload FROM \(table)").map { try decoder.decode(type, from: $0.1) }
    }
}
