import Foundation
import Testing
@testable import TimingCapture

// Final review #2: the bib belongs to the tap that was pressed, read at that moment.
@MainActor @Suite struct AppModelTests {
    func model() async throws -> (AppModel, CaptureStore) {
        let store = try await pairedStore()
        return (AppModel(store: store), store)
    }

    @Test func doubleEnterRecordsBibOnce() async throws {
        let (model, store) = try await model()
        model.bib = "12"
        let first = model.enter(atMs: 1)
        let second = model.enter(atMs: 2) // the next racer, no bib
        await first.value
        await second.value
        #expect(try await store.allEntries().map(\.bib) == [String?]([ "12", nil ]))
    }

    @Test func digitsTypedDuringTheWriteStay() async throws {
        let (model, store) = try await model()
        model.bib = "12"
        let tap = model.enter(atMs: 1)
        model.typeDigit("3")
        await tap.value
        #expect(model.bib == "3")
        #expect(try await store.allEntries().map(\.bib) == [String?]([ "12" ]))
    }

    @Test func failedWriteGivesTheBibBack() async throws {
        let store = try CaptureStore(path: tempStoreURL()) // not paired: the write fails
        let model = AppModel(store: store)
        model.bib = "12"
        await model.enter(atMs: 1).value
        #expect(model.bib == "12")
        #expect(model.error?.hasPrefix("Not recorded") == true)
    }

    // Device report (build 192): offline, taps stopped registering. Each tap waited for the
    // previous tap's push, which waits out the network timeout when the hub is unreachable.
    @Test func tapsAreWrittenWithoutWaitingForTheHub() async throws {
        let (model, store) = try await model()
        let hub = FakeHub()
        var held: [CheckedContinuation<Void, Never>] = []
        hub.beforePushAnswers = { await withCheckedContinuation { held.append($0) } } // a hub that never answers
        model.sync = Sync(store: store, api: hub, now: { 0 }, sleep: { _ in throw CancellationError() })
        model.enter(atMs: 1)
        model.enter(atMs: 2)
        await eventually { held.count >= 1 }
        var written = 0
        for _ in 0..<250 {
            written = try await store.allEntries().count
            if written == 2 { break }
            try await Task.sleep(nanoseconds: 2_000_000)
        }
        #expect(written == 2)
        while !held.isEmpty { held.removeFirst().resume() }
    }
}
