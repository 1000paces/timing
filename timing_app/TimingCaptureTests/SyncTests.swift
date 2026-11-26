import Foundation
import SQLite3
import Testing
@testable import TimingCapture

// A hub that stores whatever continues the chain.
final class FakeHub: HubAPI, @unchecked Sendable {
    var stored: [Entry] = []
    var fail = false
    var conflict = false
    var calls: [String] = []
    var pushError: Error?
    var rosterResult: () throws -> Roster? = { nil }

    func pair(token: String, name: String) async throws -> Paired { throw HubError.failed("unused") }

    func clock(t0: Int) async throws -> (t1: Int, t2: Int) {
        calls.append("clock")
        return (t0 + 50, t0 + 50)
    }

    func push(_ entries: [Entry]) async throws -> PushResult {
        calls.append("push")
        if let pushError { throw pushError }
        if fail { throw HubError.failed("offline") }
        if conflict { return PushResult(conflict: true, ackSeq: stored.count) }
        for e in entries where e.device_seq == stored.count + 1 { stored.append(e) }
        return PushResult(conflict: false, ackSeq: stored.count)
    }

    func roster(version: String?) async throws -> Roster? {
        calls.append("roster")
        return try rosterResult()
    }

    func status() async throws -> Status {
        calls.append("status")
        return Status(captures: [])
    }
}

// Sleeps until the test wakes it (or the sleeping task is cancelled).
@MainActor final class ManualSleeper {
    private var waiting: [CheckedContinuation<Void, Error>] = []
    private(set) var calls = 0
    var active: Int { waiting.count }

    func sleep(_ ms: Int) async throws {
        calls += 1
        let id = calls
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, Error>) in
                if Task.isCancelled { c.resume(throwing: CancellationError()) } else { waiting.append(c); ids.append(id) }
            }
        } onCancel: {
            Task { @MainActor in self.cancel(id) }
        }
    }

    private var ids: [Int] = []

    private func cancel(_ id: Int) {
        guard let i = ids.firstIndex(of: id) else { return }
        ids.remove(at: i)
        waiting.remove(at: i).resume(throwing: CancellationError())
    }

    func wakeAll() {
        let all = waiting
        waiting = []
        ids = []
        all.forEach { $0.resume() }
    }
}

@MainActor func eventually(_ condition: () -> Bool) async {
    for _ in 0..<500 where !condition() { try? await Task.sleep(nanoseconds: 2_000_000) }
}

@MainActor @Suite struct SyncTests {
    // Timers never fire unless a test says so (like the TS tests' setTimer: () => 0).
    func sync(_ store: CaptureStore, _ hub: FakeHub, sleep: @escaping (Int) async throws -> Void = { _ in throw CancellationError() }) -> Sync {
        Sync(store: store, api: hub, now: { 0 }, sleep: sleep)
    }

    func capture(_ store: CaptureStore, _ bib: String) async throws {
        _ = try await store.appendCapture(atMs: 1, offsetMs: 0, bib: bib, checkpointId: nil)
    }

    @Test func pushesUnsentAndRemembersAck() async throws {
        let store = try await pairedStore()
        for bib in ["1", "2", "3"] { try await capture(store, bib) }
        let hub = FakeHub()
        let s = sync(store, hub)
        await s.pushNow()
        #expect(hub.stored.map(\.device_seq) == [1, 2, 3])
        #expect(s.state.pending == 0)
        #expect(try await store.get("ackSeq", as: Int.self) == 3)
    }

    // Review Focus: a restart picks up from the stored ack.
    @Test func restartResumesFromStoredAck() async throws {
        let store = try await pairedStore()
        for bib in ["1", "2"] { try await capture(store, bib) }
        let hub = FakeHub()
        await sync(store, hub).pushNow()
        try await capture(store, "3")
        let restarted = sync(store, hub)
        await restarted.load()
        #expect(restarted.state.pending == 1)
        await restarted.pushNow()
        #expect(hub.stored.map(\.device_seq) == [1, 2, 3])
    }

    @Test func unreachableLeavesPendingOffline() async throws {
        let store = try await pairedStore()
        try await capture(store, "1")
        let hub = FakeHub()
        hub.fail = true
        let s = sync(store, hub)
        await s.pushNow()
        #expect(s.state.pending == 1)
        #expect(!s.state.online)
        #expect(!s.state.stopped)
    }

    @Test func failedPushRetriesWithBackoff() async throws {
        let store = try await pairedStore()
        try await capture(store, "1")
        let hub = FakeHub()
        hub.fail = true
        var slept: [Int] = []
        let s = sync(store, hub) { ms in slept.append(ms); throw CancellationError() }
        await s.pushNow()
        await eventually { slept.count >= 1 }
        #expect(slept.first == 1000)
        s.stop()
    }

    @Test func chainMismatchStops() async throws {
        let store = try await pairedStore()
        try await capture(store, "1")
        let hub = FakeHub()
        hub.conflict = true
        let s = sync(store, hub)
        await s.pushNow()
        #expect(s.state.stopped)
        #expect(try await store.get("stopped", as: Bool.self) == true)
    }

    @Test func clockStoresOffset() async throws {
        let store = try await pairedStore()
        let s = sync(store, FakeHub())
        await s.syncClock()
        #expect(s.state.clockSynced)
        #expect(s.state.offsetMs == 50)
        #expect(try await store.get("offsetMs", as: Int.self) == 50)
    }

    // A revoked phone says so and stops retrying.
    @Test func revokedStopsRetrying() async throws {
        let store = try await pairedStore()
        try await capture(store, "1")
        let hub = FakeHub()
        hub.pushError = HubError.revoked
        var slept: [Int] = []
        let s = sync(store, hub) { ms in slept.append(ms); throw CancellationError() }
        await s.pushNow()
        try await Task.sleep(nanoseconds: 20_000_000)
        #expect(s.state.revoked)
        #expect(slept.isEmpty)
    }

    // The loop survives a failing step, and stops for good when stopped.
    @Test func loopSurvivesErrorAndStops() async throws {
        let url = tempStoreURL()
        let store = try await pairedStore(url)
        let hub = FakeHub()
        let sleeper = ManualSleeper()
        let s = Sync(store: store, api: hub, now: { 0 }, sleep: { try await sleeper.sleep($0) })
        s.start()
        await eventually { sleeper.active == 1 }
        // Break the storage underneath: every log read now fails.
        var raw: OpaquePointer?
        sqlite3_open(url.path, &raw)
        sqlite3_exec(raw, "DROP TABLE entries", nil, nil, nil)
        sqlite3_close(raw)
        sleeper.wakeAll()
        await eventually { sleeper.calls >= 2 && sleeper.active == 1 }
        #expect(sleeper.calls == 2) // rescheduled despite the error
        #expect(s.state.error != nil)
        s.stop()
        await eventually { sleeper.active == 0 }
        let callsAtStop = hub.calls.count
        try await Task.sleep(nanoseconds: 20_000_000)
        #expect(sleeper.calls == 2)
        #expect(hub.calls.count == callsAtStop)
    }

    @Test func startTwiceRunsOneLoop() async throws {
        let store = try await pairedStore()
        let sleeper = ManualSleeper()
        let s = Sync(store: store, api: FakeHub(), now: { 0 }, sleep: { try await sleeper.sleep($0) })
        s.start()
        s.start()
        await eventually { sleeper.active >= 1 }
        try await Task.sleep(nanoseconds: 20_000_000)
        #expect(sleeper.active == 1)
        s.stop()
    }

    @Test func rosterBeforeClockAndContacted() async throws {
        let store = try await pairedStore()
        let hub = FakeHub()
        hub.rosterResult = { makeRoster() }
        let sleeper = ManualSleeper()
        let s = Sync(store: store, api: hub, now: { 0 }, sleep: { try await sleeper.sleep($0) })
        #expect(!s.state.contacted)
        s.start()
        await eventually { sleeper.active == 1 }
        #expect(hub.calls.first == "roster")
        #expect(hub.calls.contains("clock"))
        #expect(s.state.contacted)
        #expect(s.state.roster == makeRoster())
        s.stop()
    }

    @Test func adoptsNewerHubMove() async throws {
        let store = try await pairedStore()
        try await store.put("location", Location(checkpointId: nil, changedAtMs: 1_000))
        let hub = FakeHub()
        hub.rosterResult = { makeRoster(checkpoints: [.init(id: "a1", name: "Aid 1")], device: .init(checkpoint_id: "a1", checkpoint_set_at_ms: 2_000)) }
        let s = sync(store, hub)
        await s.load()
        await s.refreshRoster()
        #expect(s.state.location == Location(checkpointId: "a1", changedAtMs: 2_000))
        let entry = try #require(try await store.allEntries().first)
        #expect(entry.kind == .location)
        #expect(entry.checkpoint_id == "a1")
        #expect(entry.captured_at_ms == 2_000)
    }

    @Test func keepsNewerLocalChoice() async throws {
        let store = try await pairedStore()
        try await store.put("location", Location(checkpointId: nil, changedAtMs: 3_000))
        let hub = FakeHub()
        hub.rosterResult = { makeRoster(checkpoints: [.init(id: "a1", name: "Aid 1")], device: .init(checkpoint_id: "a1", checkpoint_set_at_ms: 2_000)) }
        let s = sync(store, hub)
        await s.load()
        await s.refreshRoster()
        #expect(s.state.location == Location(checkpointId: nil, changedAtMs: 3_000))
        #expect(try await store.allEntries().isEmpty)
    }

    @Test func setLocationLogsAndRemembers() async throws {
        let store = try await pairedStore()
        let s = sync(store, FakeHub())
        await s.load()
        await s.setLocation("a1")
        #expect(s.state.location?.checkpointId == "a1")
        #expect(try await store.allEntries().map(\.kind) == [Entry.Kind.location])
        #expect(try await store.get("location", as: Location.self)?.checkpointId == "a1")
        #expect(s.state.pending == 1)
    }

    @Test func loadRestoresState() async throws {
        let store = try await pairedStore()
        try await store.put("offsetMs", 12)
        try await store.put("stopped", true)
        let s = sync(store, FakeHub())
        await s.load()
        #expect(s.state.offsetMs == 12)
        #expect(s.state.clockSynced)
        #expect(s.state.stopped)
    }

    @Test func syncLabelWording() {
        var base = SyncState()
        #expect(syncLabel(base) == "Connecting…")
        base.contacted = true
        #expect(syncLabel(base) == "Synced")
        var pending = SyncState()
        pending.pending = 2
        #expect(syncLabel(pending) == "2 to send")
        pending.online = false
        #expect(syncLabel(pending) == "Offline · 2 to send")
        var offline = SyncState()
        offline.online = false
        #expect(syncLabel(offline) == "Offline")
        var stopped = SyncState()
        stopped.stopped = true
        #expect(syncLabel(stopped) == "Sync stopped")
        stopped.revoked = true
        #expect(syncLabel(stopped) == "Revoked")
    }
}
