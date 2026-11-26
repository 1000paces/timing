import Foundation
import Testing
@testable import TimingCapture

let testPairing = Pairing(hubURL: URL(string: "https://hub.local:3443")!, deviceId: "dev-1", credential: "c", eventId: "e", name: "Phone")

func tempStoreURL() -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent("store-\(UUID().uuidString).sqlite3")
}

func pairedStore(_ url: URL = tempStoreURL()) async throws -> CaptureStore {
    let store = try CaptureStore(path: url)
    try await store.startNewPairing(testPairing)
    return store
}

@Suite struct StoreTests {
    @Test func numbersAndChainsFromGenesis() async throws {
        let store = try await pairedStore()
        let a = try await store.appendCapture(atMs: 1000, offsetMs: 0, bib: "1", checkpointId: nil)
        let b = try await store.appendCapture(atMs: 2000, offsetMs: 0, bib: "", checkpointId: nil)
        #expect([a.device_seq, b.device_seq] == [Int]([1, 2]))
        #expect(a.prev_hash == DeviceHash.genesis("dev-1"))
        #expect(b.prev_hash == a.hash)
        for e in [a, b] { #expect(e.hash == DeviceHash.digest(e.fields)) }
        #expect(try await store.allEntries() == [a, b])
    }

    @Test func stampsCheckpointAndLogsLocation() async throws {
        let store = try await pairedStore()
        let capture = try await store.appendCapture(atMs: 1, offsetMs: nil, bib: "5", checkpointId: "a1")
        #expect(capture.checkpoint_id == "a1")
        let moved = try await store.appendLocation(checkpointId: nil, atMs: 2, offsetMs: 10)
        #expect(moved.kind == .location)
        #expect(moved.fields["checkpoint_id"] == nil)
        #expect(moved.captured_at_ms == 2)
    }

    @Test func correctionsAndVoids() async throws {
        let store = try await pairedStore()
        let capture = try await store.appendCapture(atMs: 1, offsetMs: nil, bib: "5", checkpointId: nil)
        let fix = try await store.appendBibAssignment(captureId: capture.id, bib: " 6 ")
        let void = try await store.appendVoid(captureId: capture.id)
        #expect([fix.kind, void.kind] == [Entry.Kind]([.bib_assignment, .capture_void]))
        #expect(fix.bib == "6")
        #expect(void.capture_id == capture.id)
    }

    @Test func concurrentTapsFormOneChain() async throws {
        let store = try await pairedStore()
        await withThrowingTaskGroup(of: Void.self) { group in
            for i in 0..<20 {
                group.addTask { _ = try await store.appendCapture(atMs: Double(i), offsetMs: nil, bib: "\(i)", checkpointId: nil) }
            }
        }
        let entries = try await store.allEntries()
        #expect(entries.map(\.device_seq) == Array(1...20))
        for (prev, next) in zip(entries, entries.dropFirst()) { #expect(next.prev_hash == prev.hash) }
    }

    @Test func unsentAndUnpair() async throws {
        let store = try await pairedStore()
        for bib in ["1", "2", "3"] { _ = try await store.appendCapture(atMs: 1, offsetMs: 0, bib: bib, checkpointId: nil) }
        #expect(try await store.unsent(after: 1, limit: 500).map(\.device_seq) == [2, 3])
        #expect(try await store.unsent(after: 0, limit: 2).map(\.device_seq) == [1, 2])
        #expect(try await store.lastSeq() == 3)
        #expect(!canUnpair(lastSeq: 3, ackSeq: 2))
        #expect(canUnpair(lastSeq: 3, ackSeq: 3))
    }

    @Test func repairArchives() async throws {
        let store = try await pairedStore()
        for bib in ["1", "2"] { _ = try await store.appendCapture(atMs: 1, offsetMs: 0, bib: bib, checkpointId: nil) }
        try await store.put("ackSeq", 2)
        var other = testPairing
        other.deviceId = "dev-2"
        try await store.startNewPairing(other)
        #expect(try await store.allEntries().isEmpty)
        #expect(try await store.get("ackSeq", as: Int.self) == nil)
        #expect(try await store.pairing() == other)
        let archives = try await store.archives()
        #expect(archives.count == 1)
        #expect(archives.first?.entries.count == 2)
        #expect(archives.first?.pairing == testPairing)
        let fresh = try await store.appendCapture(atMs: 1, offsetMs: nil, bib: "9", checkpointId: nil)
        #expect(fresh.device_seq == 1)
        #expect(fresh.prev_hash == DeviceHash.genesis("dev-2"))
    }

    @Test func captureWithoutOffsetOmitsKey() async throws {
        let store = try await pairedStore()
        let e = try await store.appendCapture(atMs: 1000.4, offsetMs: nil, bib: " ", checkpointId: nil)
        #expect(e.fields.keys.sorted() == ["captured_at_ms", "device_seq", "hash", "id", "kind", "prev_hash"])
        #expect(e.captured_at_ms == 1000)
        let encoded = try JSONSerialization.jsonObject(with: JSONEncoder().encode(e)) as! [String: Any]
        #expect(encoded.keys.sorted() == ["captured_at_ms", "device_seq", "hash", "id", "kind", "prev_hash"])
    }

    @Test func reopenContinuesChain() async throws {
        let url = tempStoreURL()
        var store: CaptureStore? = try await pairedStore(url)
        _ = try await store!.appendCapture(atMs: 1, offsetMs: nil, bib: "1", checkpointId: nil)
        let second = try await store!.appendCapture(atMs: 2, offsetMs: nil, bib: "2", checkpointId: nil)
        store = nil
        let reopened = try CaptureStore(path: url)
        #expect(try await reopened.pairing() == testPairing)
        let third = try await reopened.appendCapture(atMs: 3, offsetMs: nil, bib: "3", checkpointId: nil)
        #expect(third.device_seq == 3)
        #expect(third.prev_hash == second.hash)
    }

    @Test func stateRoundTrips() async throws {
        let store = try await pairedStore()
        struct Spot: Codable, Equatable { var name: String; var at: Int }
        try await store.put("spot", Spot(name: "a1", at: 5))
        #expect(try await store.get("spot", as: Spot.self) == Spot(name: "a1", at: 5))
        try await store.put("spot", Optional<Spot>.none)
        #expect(try await store.get("spot", as: Spot.self) == nil)
        try await store.put("flag", true)
        #expect(try await store.get("flag", as: Bool.self) == true)
    }

    @Test func appendWhenUnpairedThrows() async throws {
        let store = try CaptureStore(path: tempStoreURL())
        await #expect(throws: CaptureError.notPaired) {
            _ = try await store.appendCapture(atMs: 1, offsetMs: nil, bib: "1", checkpointId: nil)
        }
        try await store.startNewPairing(testPairing)
        try await store.clearPairing()
        #expect(try await store.pairing() == nil)
    }
}
