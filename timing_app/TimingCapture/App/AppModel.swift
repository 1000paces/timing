import Foundation
import Observation
import SwiftUI
import UIKit

// What the hub client sends with every request; written on the main actor,
// read from network tasks.
final class AuthBox: @unchecked Sendable {
    private let lock = NSLock()
    private var auth: DeviceAuth?

    var value: DeviceAuth? {
        get { lock.withLock { auth } }
        set { lock.withLock { auth = newValue } }
    }
}

@MainActor @Observable final class AppModel {
    let store: CaptureStore
    var loaded = false
    var pairing: Pairing?
    var pairingAgain = false // "Pair again" from the menu, while still paired
    var sync: Sync?
    var entries: [Entry] = []
    var bib = ""
    var flash = false
    var error: String?
    var pairBusy = false
    @ObservationIgnored var tapClock = TapClock()
    @ObservationIgnored private let auth = AuthBox()

    init(store: CaptureStore) {
        self.store = store
    }

    func load() async {
        do {
            pairing = try await store.pairing()
        } catch {
            self.error = error.localizedDescription
        }
        loaded = true
        if pairing != nil { startSync() }
        await reload()
    }

    func reload() async {
        do { entries = try await store.allEntries() } catch { self.error = error.localizedDescription }
    }

    // MARK: pairing

    func pair(address: String, code typedCode: String, name typedName: String) async {
        error = nil
        guard let parsed = HubAddress.parse(address) else {
            error = "Enter the hub address shown on the console"
            return
        }
        let code = typedCode.trimmingCharacters(in: .whitespaces).isEmpty ? (parsed.code ?? "") : typedCode.trimmingCharacters(in: .whitespaces)
        guard !code.isEmpty else {
            error = "Enter the pairing code shown on the console"
            return
        }
        let name = typedName.trimmingCharacters(in: .whitespaces).isEmpty ? "Phone" : typedName.trimmingCharacters(in: .whitespaces)
        pairBusy = true
        defer { pairBusy = false }
        do {
            let paired = try await HTTPHubAPI(base: parsed.base, auth: { nil }).pair(token: code, name: name)
            let next = Pairing(hubURL: parsed.base, deviceId: paired.device_id, credential: paired.credential, eventId: paired.event_id, name: name)
            try await store.startNewPairing(next) // the old log is archived on the phone, never deleted
            pairing = next
            pairingAgain = false
            startSync()
            await reload()
        } catch {
            self.error = error.localizedDescription
        }
    }

    // MARK: capture

    func typeDigit(_ digit: String) {
        guard bib.count < 6 else { return }
        bib += digit
    }

    func backspace() {
        if !bib.isEmpty { bib.removeLast() }
    }

    // Every tap is written to the phone first; only then do we confirm it.
    func tap(atMs: Double) async {
        let typed = bib
        do {
            _ = try await store.appendCapture(atMs: atMs, offsetMs: sync?.state.offsetMs, bib: typed,
                                              checkpointId: sync?.state.location?.checkpointId)
            bib = ""
            error = nil
            flash = true
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            Task {
                try? await Task.sleep(nanoseconds: 150_000_000)
                flash = false
            }
            await reload()
            await sync?.kick()
        } catch {
            self.error = "Not recorded: \(error.localizedDescription)"
            UINotificationFeedbackGenerator().notificationOccurred(.error)
        }
    }

    // A correction or a delete is an entry too: written first, then shown and sent.
    func correct(rowId: String, bib: String) async {
        await write { _ = try await self.store.appendBibAssignment(captureId: rowId, bib: bib) }
    }

    func remove(rowId: String) async {
        await write { _ = try await self.store.appendVoid(captureId: rowId) }
    }

    private func write(_ append: () async throws -> Void) async {
        do {
            try await append()
            await reload()
            await sync?.kick()
        } catch {
            self.error = "Not saved: \(error.localizedDescription)"
            UINotificationFeedbackGenerator().notificationOccurred(.error)
        }
    }

    // MARK: lifecycle

    func scenePhaseChanged(_ phase: ScenePhase) {
        switch phase {
        case .active:
            tapClock.rebase()
            guard let sync else { return }
            sync.online()
            sync.start()
        case .background:
            sync?.stop()
        default:
            break
        }
    }

    private func startSync() {
        sync?.stop()
        guard let pairing else { return }
        auth.value = DeviceAuth(deviceId: pairing.deviceId, credential: pairing.credential, offsetMs: nil)
        let box = auth
        let api = HTTPHubAPI(base: pairing.hubURL, auth: { box.value })
        let next = Sync(store: store, api: api, onOffset: { offset in box.value?.offsetMs = offset })
        sync = next
        next.start()
    }
}
