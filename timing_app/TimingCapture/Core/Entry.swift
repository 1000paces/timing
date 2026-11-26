import Foundation

// The phone's pairing with the hub. hubURL is where the hub was reached when
// pairing (scheme, host, port).
struct Pairing: Codable, Equatable, Sendable {
    var hubURL: URL
    var deviceId: String
    var credential: String
    var eventId: String
    var name: String
}

// One entry of the phone's append-only log, as the hub receives it
// (property names are the wire keys; absent fields are omitted).
struct Entry: Codable, Equatable, Sendable, Identifiable {
    enum Kind: String, Codable, Sendable {
        case capture, bib_assignment, capture_void, location
    }

    var id: String
    var kind: Kind
    var device_seq: Int
    var prev_hash: String
    var hash: String
    var captured_at_ms: Int?
    var clock_offset_ms: Int?
    var bib: String?
    var capture_id: String?
    var checkpoint_id: String?

    // Every present field, as the checksum sees it (including hash).
    var fields: [String: JSONValue] {
        var f: [String: JSONValue] = [
            "id": .string(id), "kind": .string(kind.rawValue), "device_seq": .int(device_seq),
            "prev_hash": .string(prev_hash), "hash": .string(hash),
        ]
        if let captured_at_ms { f["captured_at_ms"] = .int(captured_at_ms) }
        if let clock_offset_ms { f["clock_offset_ms"] = .int(clock_offset_ms) }
        if let bib { f["bib"] = .string(bib) }
        if let capture_id { f["capture_id"] = .string(capture_id) }
        if let checkpoint_id { f["checkpoint_id"] = .string(checkpoint_id) }
        return f
    }
}

// A log from an earlier pairing, kept on the phone rather than deleted.
struct ArchivedLog: Codable, Sendable {
    var pairing: Pairing?
    var entries: [Entry]
    var archivedAtMs: Int
}

enum CaptureError: Error, Equatable, LocalizedError {
    case notPaired
    case storage(String)

    var errorDescription: String? {
        switch self {
        case .notPaired: return "This phone isn't paired"
        case .storage(let message): return message
        }
    }
}

// The phone never drops entries the hub hasn't stored.
func canUnpair(lastSeq: Int, ackSeq: Int) -> Bool { ackSeq >= lastSeq }
