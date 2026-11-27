import Foundation
import Testing
@testable import TimingCapture

@Suite struct ExportTests {
    @Test func exportOmitsCredential() async throws {
        let store = try await pairedStore()
        _ = try await store.appendCapture(atMs: 1, offsetMs: nil, bib: "1", checkpointId: nil)
        var next = testPairing
        next.deviceId = "dev-2"
        next.credential = "second-secret"
        try await store.startNewPairing(next)
        _ = try await store.appendCapture(atMs: 2, offsetMs: nil, bib: "2", checkpointId: nil)
        let data = try exportJSON(pairing: try await store.pairing(), entries: try await store.allEntries(), archives: try await store.archives())
        let text = String(decoding: data, as: UTF8.self)
        #expect(!text.contains("credential"))
        #expect(!text.contains("second-secret"))
        let body = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect((body["pairing"] as? [String: Any])?["deviceId"] as? String == "dev-2")
        #expect((body["entries"] as? [Any])?.count == 1)
        let archive = try #require((body["archive"] as? [[String: Any]])?.first)
        #expect((archive["pairing"] as? [String: Any])?["deviceId"] as? String == "dev-1")
        #expect((archive["entries"] as? [Any])?.count == 1)
    }

    @Test func exportFileNameSanitises() {
        let at = Date(timeIntervalSince1970: 1_795_687_200) // 2026-11-26T10:00:00Z
        #expect(exportFileName(phoneName: "Finish line phone 2", at: at) == "capture-log-Finish-line-phone-2-2026-11-26T10:00:00.json")
        #expect(exportFileName(phoneName: nil, at: at) == "capture-log-phone-2026-11-26T10:00:00.json")
    }
}
