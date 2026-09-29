import Foundation
import SQLite3
import InputStatsCore

public enum StorageError: Error, LocalizedError {
    case sqlite(String)
    case invalidDelta
    public var errorDescription: String? {
        switch self {
        case .sqlite(let message): return "统计数据读写失败：\(message)"
        case .invalidDelta: return "拒绝写入负数统计增量"
        }
    }
}

/// One serialized SQLite connection. Batch writes are atomic and errors reach the caller.
public final class StatsDatabase {
    private var db: OpaquePointer?
    private let queue = DispatchQueue(label: "mactoys.database", qos: .utility)

    public init(url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard sqlite3_open_v2(url.path, &db, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK else {
            let message = db.map { String(cString: sqlite3_errmsg($0)) } ?? "无法打开文件"
            sqlite3_close(db); db = nil
            throw StorageError.sqlite(message)
        }
        do {
            sqlite3_busy_timeout(db, 1500)
            try exec("PRAGMA journal_mode=WAL;")
            try exec("PRAGMA synchronous=FULL;")
            try exec("CREATE TABLE IF NOT EXISTS recovered_batches (id TEXT PRIMARY KEY);")
            try exec("CREATE TABLE IF NOT EXISTS minute_stats (bucket_start INTEGER PRIMARY KEY, keyboard_chars INTEGER NOT NULL DEFAULT 0, keyboard_words INTEGER NOT NULL DEFAULT 0, voice_chars INTEGER NOT NULL DEFAULT 0, voice_words INTEGER NOT NULL DEFAULT 0);")
            var columns = Set<String>()
            let stmt = try prepare("PRAGMA table_info(minute_stats);")
            defer { sqlite3_finalize(stmt) }
            while sqlite3_step(stmt) == SQLITE_ROW {
                columns.insert(String(cString: sqlite3_column_text(stmt, 1)))
            }
            for name in ["keyboard_words", "voice_words"] where !columns.contains(name) {
                try exec("ALTER TABLE minute_stats ADD COLUMN \(name) INTEGER NOT NULL DEFAULT 0;")
            }
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        } catch {
            sqlite3_close(db); db = nil
            throw error
        }
    }

    deinit { sqlite3_close(db) }
    private func fail() -> StorageError { .sqlite(String(cString: sqlite3_errmsg(db))) }
    private func exec(_ sql: String) throws {
        guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else { throw fail() }
    }
    private func prepare(_ sql: String) throws -> OpaquePointer {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else { throw fail() }
        return stmt
    }

    public func add(_ buckets: [MinuteBucket], recoveryID: String? = nil) throws {
        guard buckets.allSatisfy({ $0.keyboardChars >= 0 && $0.keyboardWords >= 0 && $0.voiceChars >= 0 && $0.voiceWords >= 0 }) else { throw StorageError.invalidDelta }
        guard !buckets.isEmpty else { return }
        try queue.sync {
            try exec("BEGIN IMMEDIATE;")
            do {
                if let recoveryID {
                    let marker = try prepare("INSERT OR IGNORE INTO recovered_batches (id) VALUES (?);")
                    defer { sqlite3_finalize(marker) }
                    let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
                    sqlite3_bind_text(marker, 1, recoveryID, -1, transient)
                    guard sqlite3_step(marker) == SQLITE_DONE else { throw fail() }
                    if sqlite3_changes(db) == 0 { try exec("COMMIT;"); return }
                }
                let stmt = try prepare("""
                INSERT INTO minute_stats (bucket_start, keyboard_chars, keyboard_words, voice_chars, voice_words)
                VALUES (?, ?, ?, ?, ?) ON CONFLICT(bucket_start) DO UPDATE SET
                keyboard_chars = keyboard_chars + excluded.keyboard_chars,
                keyboard_words = keyboard_words + excluded.keyboard_words,
                voice_chars = voice_chars + excluded.voice_chars,
                voice_words = voice_words + excluded.voice_words;
                """)
                defer { sqlite3_finalize(stmt) }
                for b in buckets {
                    sqlite3_reset(stmt)
                    for (i, n) in [b.start, b.keyboardChars, b.keyboardWords, b.voiceChars, b.voiceWords].enumerated() {
                        sqlite3_bind_int64(stmt, Int32(i + 1), sqlite3_int64(n))
                    }
                    guard sqlite3_step(stmt) == SQLITE_DONE else { throw fail() }
                }
                try exec("COMMIT;")
            } catch {
                try? exec("ROLLBACK;")
                throw error
            }
        }
    }

    public func buckets(from: Int = 0, to: Int = Int.max) throws -> [MinuteBucket] {
        try queue.sync {
            let stmt = try prepare("SELECT bucket_start, keyboard_chars, keyboard_words, voice_chars, voice_words FROM minute_stats WHERE bucket_start >= ? AND bucket_start < ? ORDER BY bucket_start;")
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_int64(stmt, 1, sqlite3_int64(from)); sqlite3_bind_int64(stmt, 2, sqlite3_int64(to))
            var rows: [MinuteBucket] = []
            var status = sqlite3_step(stmt)
            while status == SQLITE_ROW {
                rows.append(MinuteBucket(start: Int(sqlite3_column_int64(stmt, 0)),
                    keyboardChars: Int(sqlite3_column_int64(stmt, 1)), keyboardWords: Int(sqlite3_column_int64(stmt, 2)),
                    voiceChars: Int(sqlite3_column_int64(stmt, 3)), voiceWords: Int(sqlite3_column_int64(stmt, 4))))
                status = sqlite3_step(stmt)
            }
            guard status == SQLITE_DONE else { throw fail() }
            return rows
        }
    }

    public func clearAll() throws { try queue.sync { try exec("DELETE FROM minute_stats;") } }
}
