import Foundation
import Observation

struct SyncState: Equatable {
    var pending = 0 // entries the hub hasn't stored yet
    var online = true { // the last request reached the hub
        didSet { if online { contacted = true } }
    }
    var contacted = false // the hub has answered at least once since the app started
    var stopped = false // the hub refused our chain: export and see an official
    var revoked = false // the hub refused this phone's credential: export and re-pair
    var ackSeq = 0 // the hub has stored entries up to here
    var clockSynced = false
    var offsetMs: Int? = nil // hub time - phone time
    var lastSyncAtMs: Int? = nil
    var location: Location? = nil // where this phone is on the course
    var roster: Roster? = nil
    var status: Status? = nil
    var error: String? = nil
}

func syncLabel(_ s: SyncState) -> String {
    if s.revoked { return "Revoked" }
    if s.stopped { return "Sync stopped" }
    if !s.online { return s.pending > 0 ? "Offline · \(s.pending) to send" : "Offline" }
    if s.pending > 0 { return "\(s.pending) to send" }
    return s.contacted ? "Synced" : "Connecting…" // never claim Synced before the hub has answered
}

// Pushes the phone's log to the hub, keeps the clock offset, and pulls the
// roster and the status of this phone's crossings. Never deletes entries.
// A port of frontend/capture/src/sync.ts.
@MainActor @Observable final class Sync {
    static let batch = 500
    static let pushEveryMs = 5_000
    static let clockEveryMs = 60_000
    static let statusEveryMs = 10_000
    static let rosterEveryMs = 60_000

    private(set) var state = SyncState()

    @ObservationIgnored private let store: CaptureStore
    @ObservationIgnored private let api: HubAPI
    @ObservationIgnored private let now: () -> Int
    @ObservationIgnored private let sleep: (Int) async throws -> Void
    @ObservationIgnored private let onOffset: (Int?) -> Void
    @ObservationIgnored private var ackSeq = 0
    @ObservationIgnored private var backoffMs = 0
    @ObservationIgnored private var due = (clock: 0, status: 0, roster: 0, push: 0)
    @ObservationIgnored private var loopTask: Task<Void, Never>?
    @ObservationIgnored private var retryTask: Task<Void, Never>?
    @ObservationIgnored private var pushing: Task<Void, Never>?
    // stop() was called: nothing that was in flight may write to the store any more
    // (the phone may have re-paired since). start() clears it.
    @ObservationIgnored private var halted = false

    init(store: CaptureStore, api: HubAPI, now: @escaping () -> Int = { Int(Date().timeIntervalSince1970 * 1000) },
         sleep: @escaping (Int) async throws -> Void = { try await Task.sleep(nanoseconds: UInt64($0) * 1_000_000) },
         onOffset: @escaping (Int?) -> Void = { _ in }) {
        self.store = store
        self.api = api
        self.now = now
        self.sleep = sleep
        self.onOffset = onOffset // the clock offset changed (the hub client sends it with every request)
    }

    func load() async {
        do {
            ackSeq = try await store.get("ackSeq", as: Int.self) ?? 0
            state.stopped = try await store.get("stopped", as: Bool.self) ?? false
            state.offsetMs = try await store.get("offsetMs", as: Int.self)
            state.clockSynced = state.offsetMs != nil
            onOffset(state.offsetMs)
            state.lastSyncAtMs = try await store.get("lastSyncAtMs", as: Int.self)
            state.location = try await store.get("location", as: Location.self)
            state.roster = try await store.get("roster", as: Roster.self)
            state.status = try await store.get("status", as: Status.self)
            try await countPending()
        } catch {
            state.error = error.localizedDescription
        }
    }

    // One push at a time; a tap during a push is picked up by a follow-up push.
    // The task clears `pushing` itself before it finishes: if the caller cleared it after
    // `await task.value`, a second caller could wake first, find the finished task still
    // there, and spin on the main actor (awaiting a finished task doesn't suspend).
    func pushNow() async {
        while let current = pushing { await current.value }
        let task = Task {
            await self.pushOnce()
            self.pushing = nil
        }
        pushing = task
        await task.value
    }

    func syncClock() async {
        var samples: [ClockSample] = []
        do {
            for _ in 0..<5 {
                let t0 = now()
                let (t1, t2) = try await api.clock(t0: t0)
                if halted { return }
                samples.append(ClockSample(t0: t0, t1: t1, t2: t2, t3: now()))
            }
            let offset = pickOffset(samples).offsetMs
            try await store.put("offsetMs", offset)
            state.offsetMs = offset
            onOffset(offset)
            state.clockSynced = true
            state.online = true
        } catch {
            failed(error)
        }
    }

    func refreshStatus() async {
        do {
            let status = try await api.status()
            if halted { return }
            try await store.put("status", status)
            state.status = status
            state.online = true
        } catch {
            failed(error)
        }
    }

    func refreshRoster() async {
        do {
            let fetched = try await api.roster(version: state.roster?.version)
            if halted { return }
            if let roster = fetched {
                try await store.put("roster", roster)
                state.roster = roster
                if shouldAdopt(state.location, roster.device), let setAt = roster.device.checkpoint_set_at_ms {
                    await setLocation(roster.device.checkpoint_id, hubAtMs: setAt)
                }
            }
            state.online = true
        } catch {
            failed(error)
        }
    }

    // The volunteer (or, via the roster, an official) moved this phone.
    func setLocation(_ checkpointId: String?, hubAtMs: Int? = nil) async {
        let offset = state.offsetMs ?? 0
        let at = hubAtMs ?? now() + offset
        do {
            _ = try await store.appendLocation(checkpointId: checkpointId, atMs: Double(at - offset), offsetMs: state.offsetMs)
            let location = Location(checkpointId: checkpointId, changedAtMs: at)
            try await store.put("location", location)
            state.location = location
            try await countPending()
        } catch {
            state.error = error.localizedDescription
        }
    }

    // After a tap: count it, and push straight away (status follows).
    func kick() async {
        try? await countPending()
        await pushNow()
        await refreshStatus()
    }

    // Back online: retry everything now instead of waiting out the backoff.
    func online() {
        backoffMs = 0
        due = (0, 0, 0, 0)
    }

    func start() {
        loopTask?.cancel()
        halted = false
        loopTask = Task { [weak self] in
            await self?.load()
            while !Task.isCancelled {
                guard let self else { return }
                await self.step()
                do { try await self.sleep(1000) } catch { return }
            }
        }
    }

    func stop() {
        halted = true
        loopTask?.cancel()
        loopTask = nil
        retryTask?.cancel()
        retryTask = nil
    }

    // MARK: private

    private func countPending() async throws {
        let last = try await store.lastSeq()
        state.pending = max(0, last - ackSeq)
        state.ackSeq = ackSeq
    }

    // A revoked phone can never sync again: say so, and stop trying.
    @discardableResult private func failed(_ error: Error) -> Bool {
        if case HubError.revoked = error {
            state.revoked = true
            state.online = true
            state.error = error.localizedDescription
            return true
        }
        state.online = false
        state.error = error.localizedDescription
        return false
    }

    private func pushOnce() async {
        do {
            try await countPending()
            if state.stopped || state.revoked { return }
            while true {
                let batch = try await store.unsent(after: ackSeq, limit: Self.batch)
                if batch.isEmpty { break }
                let result: PushResult
                do {
                    result = try await api.push(batch)
                    if halted { return } // stopped mid-push (maybe re-paired): the answer is for a log that may be gone
                } catch {
                    if failed(error) || halted { return }
                    backoffMs = nextBackoff(backoffMs)
                    scheduleRetry(after: backoffMs)
                    return
                }
                backoffMs = 0
                if result.conflict {
                    try await store.put("stopped", true)
                    state.stopped = true
                    state.online = true
                    return
                }
                let advanced = result.ackSeq > ackSeq
                ackSeq = result.ackSeq
                try await store.put("ackSeq", ackSeq)
                let at = now()
                try await store.put("lastSyncAtMs", at)
                state.online = true
                state.error = nil
                state.lastSyncAtMs = at
                try await countPending()
                if !advanced { break }
            }
            try await countPending()
        } catch {
            state.error = error.localizedDescription
        }
    }

    private func scheduleRetry(after ms: Int) {
        retryTask?.cancel()
        retryTask = Task { [weak self] in
            do { try await self?.sleep(ms) } catch { return }
            guard !Task.isCancelled else { return }
            await self?.pushNow()
        }
    }

    // One pass of the loop. Whatever happens in it (a storage error, say), the
    // next pass is scheduled — unless stop() was called.
    private func step() async {
        if state.revoked { return }
        let t = now()
        // The roster first: a freshly paired phone needs names before anything else.
        if t >= due.roster {
            due.roster = t + Self.rosterEveryMs
            await refreshRoster()
        }
        if t >= due.clock {
            due.clock = t + Self.clockEveryMs
            await syncClock()
        }
        do { try await countPending() } catch { state.error = error.localizedDescription }
        if state.pending > 0 && t >= due.push {
            due.push = t + Self.pushEveryMs
            await pushNow()
        }
        if t >= due.status {
            due.status = t + Self.statusEveryMs
            await refreshStatus()
        }
    }
}
