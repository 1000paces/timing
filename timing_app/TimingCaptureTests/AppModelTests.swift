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
}
