import Foundation
import Testing
@testable import TimingCapture

// Shared with the hub's DeviceHash test and frontend/capture/src/hash.test.ts:
// all three must agree byte for byte.
struct HashVector: Decodable {
    struct Item: Decodable {
        let entry: [String: JSONValue]
        let canonical: String
        let hash: String
    }
    let device_id: String
    let genesis: String
    let entries: [Item]
}

func repoFile(_ relative: String) -> URL {
    URL(fileURLWithPath: #filePath).deletingLastPathComponent() // TimingCaptureTests
        .deletingLastPathComponent() // timing_app
        .deletingLastPathComponent() // repo root
        .appendingPathComponent(relative)
}

@Suite struct DeviceHashTests {
    @Test func sortsKeysAndOmitsNulls() {
        #expect(canonicalJSON(["b": .int(1), "a": .null, "c": .string("x")]) == #"{"b":1,"c":"x"}"#)
    }

    @Test func reproducesHubVector() throws {
        let data = try Data(contentsOf: repoFile("test/fixtures/files/device_hash_vector.json"))
        let vector = try JSONDecoder().decode(HashVector.self, from: data)
        #expect(DeviceHash.genesis(vector.device_id) == vector.genesis)
        #expect(vector.entries.count == 3)
        for item in vector.entries {
            #expect(canonicalJSON(item.entry) == item.canonical)
            #expect(DeviceHash.digest(item.entry) == item.hash)
        }
    }

    // Pinned literally, as in hash.test.ts: a finish capture, with or without a
    // null checkpoint_id, hashes exactly as old phones hash it.
    @Test func finishCaptureHashesAsAlways() {
        var finish: [String: JSONValue] = [
            "id": .string("e1"), "kind": .string("capture"), "device_seq": .int(1), "captured_at_ms": .int(1000),
            "clock_offset_ms": .int(-25), "bib": .string("101"),
            "prev_hash": .string("0388fb626ca89a127847443989334b8c29e17567bc03a7a2ed13effca701a4a1"),
        ]
        let golden = "4b12d73ab756f7c1d5f7892cd87da2b3d29b95827e5d1a95e3527878ceaefb4e"
        #expect(DeviceHash.digest(finish) == golden)
        finish["checkpoint_id"] = .null
        #expect(DeviceHash.digest(finish) == golden)
    }

    @Test func excludesOwnHash() {
        let fields: [String: JSONValue] = ["a": .int(1)]
        #expect(DeviceHash.digest(fields.merging(["hash": .string("x")]) { $1 }) == DeviceHash.digest(fields))
    }

    @Test func escapesLikeJavaScript() {
        #expect(canonicalJSON(["s": .string("a\"b\\c/d\né\u{01}\t")]) == #"{"s":"a\"b\\c/d\né\u0001\t"}"#)
    }

    @Test func leadingZeroBibStaysString() {
        #expect(canonicalJSON(["bib": .string("007")]) == #"{"bib":"007"}"#)
    }

    @Test func uuidv7Layout() throws {
        let id = DeviceHash.uuidv7(nowMs: 0x0123_4567_89ab)
        #expect(id.hasPrefix("01234567-89ab-7"))
        let pattern = try Regex("^[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$")
        #expect(id.wholeMatch(of: pattern) != nil)
        #expect(DeviceHash.uuidv7() != DeviceHash.uuidv7())
    }
}
