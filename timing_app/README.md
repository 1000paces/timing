# Timing Capture (iPhone + iPad)

A native SwiftUI version of the phone capture app (`frontend/capture/`). It does
the same things: pair from the console, record crossings with the bib keypad,
keep an append-only, hash-chained log on the phone, sync with the hub
(`/sync/v1`), correct and delete crossings, pick a checkpoint on course events,
export the log, unpair and re-pair. It needs no hub changes; the PWA still works
alongside it.

Design: `docs/superpowers/specs/2026-11-26-native-capture-app-design.md`.

## Build and test

Needs Xcode 26+ and [XcodeGen](https://github.com/yonaskolb/XcodeGen)
(`brew install xcodegen`). The Xcode project is generated, not committed.

```bash
cd timing_app
bin/test                     # unit tests on the first available iPhone simulator
bin/test StoreTests SyncTests
xcodegen && open TimingCapture.xcodeproj
```

`Core/` has the logic with no UI (log, checksum, store, sync, rows), ported
module by module from `frontend/capture/src/`. Keep the two in step: the
checksum tests read the hub's shared vector
(`test/fixtures/files/device_hash_vector.json`).

## On a phone or iPad

1. Open the project in Xcode, choose your team under Signing, and run on the device.
2. Trust the hub's certificate once (as for the PWA): on the device, open
   `http://<hub address>:3000/onboarding`, install the profile, then turn on full
   trust in Settings → General → About → Certificate Trust Settings. Compare the
   fingerprint with the one `bin/rails hub:certs` printed.
3. On the console: Capture (or Event) → Phones → Pair a phone. In the app, tap
   **Scan QR code** (or type the hub address, e.g. `192.168.1.10`, and the code).

Debug builds also accept a plain `http://` hub (a dev hub on `localhost:3000`);
release builds need https.

## End-to-end check (Simulator, against a dev hub)

`bin/e2e [TestName]` drives the app against `bin/rails server` on :3000: it
reinstalls the app, issues a pairing code for the newest event (or `EVENT=<id>`)
and runs the live-hub UI tests. `KEEP=1` keeps the installed app and its pairing;
`SIM="iPad Pro 11-inch (M5)"` picks the simulator. Screenshots are in the printed
`.xcresult`.

The spec's check, in order:

```bash
bin/e2e testPairAndCapture                       # pairs, records bib 101, Synced
# stop the hub (Ctrl-C bin/rails server)
KEEP=1 bin/e2e testOfflineRecord                 # 3 crossings, a correction, a delete: "Offline · 5 to send"; re-pair warns
# start the hub again
KEEP=1 bin/e2e testBackOnline                    # Synced
# resolve the no-bib crossing on the console (review queue) as a chief, then:
RESOLVED_BIB=<bib> KEEP=1 bin/e2e testResolvedBibShows   # the phone shows it, locked
KEEP=1 bin/e2e testCorrectDeleteFilter
KEEP=1 bin/e2e testHardwareKeyboard
KEEP=1 bin/e2e testLayouts                       # also with SIM="iPad …"
# a course event (bin/replay-race --dataset gravel_demo):
EVENT=<id> bin/e2e testLocationPick              # then move the phone on the console
KEEP=1 bin/e2e testLocationAdoptsHubMove
KEEP=1 bin/e2e testExportAndUnpair
```

Check by hand: scanning the console QR on a real device, and a hardware keyboard's
Return and Delete keys (XCUITest's synthesized Return/Delete never reach the app,
so `testHardwareKeyboard` checks digits only).
