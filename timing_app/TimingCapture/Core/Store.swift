import Foundation
import SQLite3

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

// The phone's own storage: its pairing, its append-only log (by device_seq),
// sync state (ack, clock, roster, status) and logs from earlier pairings.
// One actor, so appends run one at a time and concurrent taps form one chain.
// Every write is committed with synchronous=FULL before the call returns.
actor CaptureStore {
    private var db: OpaquePointer?
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(path: URL) throws {
        try FileManager.default.createDirectory(at: path.deletingLastPathComponent(), withIntermediateDirectories: true)
        var handle: OpaquePointer?
        guard sqlite3_open_v2(path.path, &handle, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK else {
            let message = handle.map { String(cString: sqlite3_errmsg($0)) } ?? "can't open storage"
            sqlite3_close(handle)
            throw CaptureError.storage(message)
        }
        db = handle
        try Self.exec(handle, """
            PRAGMA journal_mode=WAL;
            PRAGMA synchronous=FULL;
            CREATE TABLE IF NOT EXISTS pairing (k TEXT PRIMARY KEY, v BLOB NOT NULL);
            CREATE TABLE IF NOT EXISTS entries (device_seq INTEGER PRIMARY KEY, v BLOB NOT NULL);
            CREATE TABLE IF NOT EXISTS state (k TEXT PRIMARY KEY, v BLOB NOT NULL);
            CREATE TABLE IF NOT EXISTS archive (id INTEGER PRIMARY KEY AUTOINCREMENT, v BLOB NOT NULL);
            """)
    }

    deinit { sqlite3_close(db) }

    static func defaultURL() -> URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("capture.sqlite3")
    }

    // MARK: pairing and state

    func pairing() throws -> Pairing? { try value(table: "pairing", key: "pairing", as: Pairing.self) }

    func clearPairing() throws { try run("DELETE FROM pairing") }

    func get<T: Decodable>(_ key: String, as type: T.Type) throws -> T? { try value(table: "state", key: key, as: type) }

    // nil deletes the key.
    func put<T: Encodable>(_ key: String, _ value: T?) throws {
        if let value {
            try run("INSERT OR REPLACE INTO state (k, v) VALUES (?, ?)", .text(key), .blob(try encoder.encode(value)))
        } else {
            try run("DELETE FROM state WHERE k = ?", .text(key))
        }
    }

    // MARK: the log

    // checkpointId: where the phone is (nil: the finish, and the entry hashes exactly as before).
    func appendCapture(atMs: Double, offsetMs: Int?, bib: String, checkpointId: String?) throws -> Entry {
        let trimmed = bib.trimmingCharacters(in: .whitespaces)
        return try append(.capture, captured_at_ms: Int(atMs.rounded()), clock_offset_ms: offsetMs,
                          bib: trimmed.isEmpty ? nil : trimmed, checkpoint_id: checkpointId)
    }

    // The phone moved (nil: to the finish). atMs is phone time, like a capture's.
    func appendLocation(checkpointId: String?, atMs: Double, offsetMs: Int?) throws -> Entry {
        try append(.location, captured_at_ms: Int(atMs.rounded()), clock_offset_ms: offsetMs, checkpoint_id: checkpointId)
    }

    func appendBibAssignment(captureId: String, bib: String) throws -> Entry {
        try append(.bib_assignment, bib: bib.trimmingCharacters(in: .whitespaces), capture_id: captureId)
    }

    func appendVoid(captureId: String) throws -> Entry { try append(.capture_void, capture_id: captureId) }

    func allEntries() throws -> [Entry] { try entries("SELECT v FROM entries ORDER BY device_seq") }

    func unsent(after ackSeq: Int, limit: Int) throws -> [Entry] {
        try entries("SELECT v FROM entries WHERE device_seq > ? ORDER BY device_seq LIMIT ?", .int(ackSeq), .int(limit))
    }

    func lastSeq() throws -> Int { try lastEntry()?.device_seq ?? 0 }

    // Re-pairing (a new event, or after a revoke) never deletes the old log: it is
    // archived on the phone, then a fresh log and sync state begin.
    func startNewPairing(_ next: Pairing) throws {
        try transaction {
            let previous = try pairing()
            let old = try allEntries()
            if previous != nil || !old.isEmpty {
                let log = ArchivedLog(pairing: previous, entries: old, archivedAtMs: Int(Date().timeIntervalSince1970 * 1000))
                try run("INSERT INTO archive (v) VALUES (?)", .blob(try encoder.encode(log)))
            }
            try run("DELETE FROM entries")
            try run("DELETE FROM state")
            try run("INSERT OR REPLACE INTO pairing (k, v) VALUES ('pairing', ?)", .blob(try encoder.encode(next)))
        }
    }

    func archives() throws -> [ArchivedLog] {
        try query("SELECT v FROM archive ORDER BY id").map { try decoder.decode(ArchivedLog.self, from: $0) }
    }

    // MARK: private

    private func append(_ kind: Entry.Kind, captured_at_ms: Int? = nil, clock_offset_ms: Int? = nil, bib: String? = nil,
                        capture_id: String? = nil, checkpoint_id: String? = nil) throws -> Entry {
        guard let pairing = try pairing() else { throw CaptureError.notPaired }
        let last = try lastEntry()
        var entry = Entry(id: DeviceHash.uuidv7(), kind: kind, device_seq: (last?.device_seq ?? 0) + 1,
                          prev_hash: last?.hash ?? DeviceHash.genesis(pairing.deviceId), hash: "",
                          captured_at_ms: captured_at_ms, clock_offset_ms: clock_offset_ms, bib: bib,
                          capture_id: capture_id, checkpoint_id: checkpoint_id)
        entry.hash = DeviceHash.digest(entry.fields)
        // INSERT (never replace): a second writer for the same seq fails instead of overwriting.
        try run("INSERT INTO entries (device_seq, v) VALUES (?, ?)", .int(entry.device_seq), .blob(try encoder.encode(entry)))
        return entry
    }

    private func lastEntry() throws -> Entry? {
        try entries("SELECT v FROM entries ORDER BY device_seq DESC LIMIT 1").first
    }

    private func entries(_ sql: String, _ params: Param...) throws -> [Entry] {
        try query(sql, params).map { try decoder.decode(Entry.self, from: $0) }
    }

    private func value<T: Decodable>(table: String, key: String, as type: T.Type) throws -> T? {
        try query("SELECT v FROM \(table) WHERE k = ?", [.text(key)]).first.map { try decoder.decode(T.self, from: $0) }
    }

    private func transaction(_ body: () throws -> Void) throws {
        try run("BEGIN IMMEDIATE")
        do {
            try body()
            try run("COMMIT")
        } catch {
            try? run("ROLLBACK")
            throw error
        }
    }

    private enum Param {
        case text(String), int(Int), blob(Data)
    }

    private func prepare(_ sql: String, _ params: [Param]) throws -> OpaquePointer? {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { throw failure() }
        for (i, param) in params.enumerated() {
            let index = Int32(i + 1)
            switch param {
            case .text(let s): sqlite3_bind_text(stmt, index, s, -1, SQLITE_TRANSIENT)
            case .int(let n): sqlite3_bind_int64(stmt, index, Int64(n))
            case .blob(let d): _ = d.withUnsafeBytes { sqlite3_bind_blob(stmt, index, $0.baseAddress, Int32(d.count), SQLITE_TRANSIENT) }
            }
        }
        return stmt
    }

    private func run(_ sql: String, _ params: Param...) throws {
        let stmt = try prepare(sql, params)
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_step(stmt) == SQLITE_DONE else { throw failure() }
    }

    private func query(_ sql: String, _ params: [Param] = []) throws -> [Data] {
        let stmt = try prepare(sql, params)
        defer { sqlite3_finalize(stmt) }
        var rows: [Data] = []
        while true {
            let rc = sqlite3_step(stmt)
            if rc == SQLITE_DONE { break }
            guard rc == SQLITE_ROW else { throw failure() }
            let count = Int(sqlite3_column_bytes(stmt, 0))
            rows.append(count == 0 ? Data() : Data(bytes: sqlite3_column_blob(stmt, 0), count: count))
        }
        return rows
    }

    private func failure() -> CaptureError { .storage(String(cString: sqlite3_errmsg(db))) }

    private static func exec(_ db: OpaquePointer?, _ sql: String) throws {
        guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else { throw CaptureError.storage(String(cString: sqlite3_errmsg(db))) }
    }
}
