# Native Capture App (iPhone + iPad) — Design

**Date:** 2026-11-26
**Status:** Draft for review
**Builds on:** `2026-10-06-mobile-capture-design.md` (the PWA at `/capture-app/`, the
`/sync/v1` API, the device log and its hash chain).

## 1. Intent

A native SwiftUI app that does everything the capture PWA (`frontend/capture/`) does, for
the advantages a browser can't give:

- **Storage that is guaranteed to stay.** No "this browser hasn't promised to keep the
  crossings" warning, no home-screen dance; the log lives in the app's own SQLite file.
- **No insecure-page dead end.** The PWA refuses to capture when the page isn't a secure
  context. A native app's storage doesn't depend on that.
- **Real haptics** on every recorded tap.
- **A more precise tap time**, taken at touch-down from the system's monotonic clock.

The PWA stays. Both talk to the same hub API, and a phone can use either.

**Done when** (in the iOS Simulator against a dev hub, mirroring the PWA's own check):
1. The app is paired from the console's pairing code (typed hub address + code; the QR
   scan is checked on a real device).
2. It goes offline (hub stopped) and records three crossings, one bib correction and one
   delete, and shows "5 to send" (the correction and delete are entries too).
3. The hub comes back and the app shows **Synced**.
4. The console's Results and review queue reflect those entries.
5. A chief resolves a no-bib crossing on the console; the app shows the resolved bib after
   its next sync.
6. On a course event, choosing a checkpoint in the app shows on the console, and an
   official moving the phone on the console moves it in the app.

## 2. Goals, non-goals, anti-goals

**Goals — feature parity with the PWA:**

| Feature | PWA source |
|---|---|
| Pair: scan the console QR (hub address + code) or type both; name the phone | `App.tsx` PairScreen |
| Re-pair warning when unsent crossings exist; Export / Pair anyway; old log archived, never deleted | `App.tsx`, `log.ts` startNewPairing |
| Bib keypad (digits, ⌫, Enter), max 6 digits, Enter with no bib = no-bib crossing; hardware keyboard too | `Keypad.tsx`, `App.tsx` |
| Green flash + haptic only after the tap is on disk; "Not recorded: …" otherwise | `App.tsx` record |
| Append-only hash-chained log: capture, bib_assignment, capture_void, location | `log.ts`, `hash.ts` |
| Sync loop: roster (ETag), clock (5 samples, fastest RTT), push (batches of 500, backoff 1 s → 30 s), status; conflict → stopped; 401 → revoked | `sync.ts`, `api.ts`, `clock.ts` |
| Crossing log, newest first, 20 at a time + Show more: time (hub-corrected), bib, "entered: …" note, name, race, No bib / Unknown bib chips, Lap N, lap flag chip | `rows.ts`, `App.tsx` |
| Filter to one bib; correct bib (keypad sheet with racer lookup, locked when an official ruled); delete with confirmation | `App.tsx` BibSheet |
| Location chip + picker (Finish + checkpoints) on course events; adopt the hub's move when newer | `location.ts`, `sync.ts` setLocation |
| Sync pill (Connecting…, Synced, N to send, Offline · N to send, Sync stopped, Revoked) + clock indicator | `SyncPill.tsx` |
| Menu: phone name, last sync, clock offset, Export log, Unpair (refused while unsent) | `App.tsx` |
| Stopped / revoked banners | `App.tsx` |
| Portrait: keypad over log. Landscape (and iPad): keypad left, log right | `App.tsx` |

**Non-goals (this version):** App Store release (dev install / TestFlight only); background
sync while the app is closed; universal links (the system camera opening the app); keeping
the screen awake; any hub change; iPad multi-window.

**Anti-goals:** a tap confirmed but not on disk; a checksum that differs from the hub's
(the hub would stop the phone); ever deleting log entries, on unpair or re-pair.

## 3. Constraints (from the hub, unchanged)

- **API:** `POST /devices/pair {token, name}` → `{device_id, credential, event_id}`;
  `/sync/v1/clock|push|roster|status` with `Authorization: Device <id>:<credential>` and
  `X-Clock-Offset-Ms`. 409 on push = chain conflict; 401 = revoked; 304 on roster = unchanged.
  `SameOrigin` allows requests with no `Origin` header, so the native client needs nothing
  new.
- **Hub address:** the console's pairing QR encodes
  `https://<hub>:3443/capture-app/?pair=<CODE>`. The app takes the scheme+host+port as the
  hub address and `pair` as the code, and stores the address with the pairing.
- **TLS:** the hub's own CA (`LocalCa`), trusted once per device via `/onboarding` (install
  profile, then enable full trust). URLSession honours that trust; the server cert's SANs
  cover the hostname, `<host>.local` and LAN IPs. No pinning or custom trust code.
- **Checksum:** byte-identical to `hash.ts` / `device_hash.rb`: SHA-256 of canonical JSON
  (keys sorted, no whitespace, nulls omitted, own `hash` excluded); genesis =
  SHA-256(device id). Values are strings and integers only — no floats.
- **IDs:** UUIDv7 like `hash.ts` uuidv7.
- **iOS local network:** the hub is on the LAN, so the app needs
  `NSLocalNetworkUsageDescription`; camera needs `NSCameraUsageDescription`.

## 4. Approaches

- **A. Native SwiftUI, logic ported module by module (chosen).** Each TS module becomes a
  Swift file with the same rules; tests mirror the TS tests and share the hub's checksum
  vector. Costs a second copy of the capture logic; the shared vector and API tests contain
  the drift.
- **B. Native shell around the PWA (WKWebView + bridge).** Reuses the UI, but timing-critical
  code stays in JS and WKWebView handles the hub's own CA awkwardly — keeps only half the
  advantages.
- **C. Native with SwiftData.** Less code, but weaker control over when a write is durable and
  no add-don't-overwrite guarantee on the log. Dropped for a timing log.

The user picked A.

## 5. Design

### 5.1 Layout in the repo

```
timing_app/
  project.yml                 # XcodeGen (as in ../LiftLog); the .xcodeproj is generated, not committed
  README.md                   # generate, build, test, install, onboarding a device
  TimingCapture/
    App/                      # TimingCaptureApp, AppModel (pairing state, routing)
    Core/                     # no UI: Hash, UUIDv7, CanonicalJSON, Clock, Location, Rows, Log, Store, HubAPI, Sync
    UI/                       # PairView, QRScannerView, CaptureView, Keypad, CrossingRow, BibSheet, SyncPill, LocationPicker
  TimingCaptureTests/         # one test file per Core module, mirroring frontend/capture/src/*.test.ts
```

- iOS 17+, `TARGETED_DEVICE_FAMILY = "1,2"`, all orientations.
- Bundle id prefix and team from LiftLog (`com.ronmiles`, team `Q3KYUZGC72`); id
  `com.ronmiles.timingcapture`, display name "Timing Capture". *(Builder's call — easy to
  change.)*
- No third-party dependencies.

### 5.2 Core (ported logic)

- **CanonicalJSON / Hash:** entries are modelled as an ordered `[String: JSONValue]` where
  `JSONValue` is `.string` / `.int`; canonical JSON is written by hand (sorted keys, the
  same string escaping as `JSON.stringify` for the characters that can occur), hashed with
  CryptoKit. Tests: `test/fixtures/files/device_hash_vector.json` (read from the repo path
  at test time, as the TS test does) plus the pinned "finish capture" golden.
- **Store:** SQLite via the system `sqlite3` library, a small wrapper, WAL with
  `synchronous=FULL`. Tables mirror the IndexedDB stores: `pairing` (one row, incl. hub
  URL), `entries` (`device_seq` primary key, JSON body — insert, never replace),
  `state` (key → JSON), `archive` (old pairings' logs). File in Application Support,
  excluded from nothing (it should be in device backups).
- **Log:** one serial actor appends entries, so concurrent taps form one chain; the append
  returns only after the SQLite commit. Same entry shapes and null-omission as `log.ts`.
- **Tap time:** captured on touch-down of Enter (or the hardware Return key) as wall-clock
  ms derived from a monotonic base: `bootWall + (CACurrentMediaTime() - bootMono)`, rebased
  when the app returns to the foreground. *(Builder's call on the exact method; it must be
  monotonic within a session and wall-clock aligned.)*
- **HubAPI:** URLSession, 10 s timeout per request, base URL from the pairing; a protocol
  so Sync can be tested with a fake, as `sync.test.ts` does.
- **Sync:** an actor with the same state, intervals and rules as `sync.ts` (roster first,
  clock 60 s, push 5 s when pending, status 10 s, 1 s tick, backoff, conflict → stopped
  persisted, 401 → revoked). `kick()` after every append. Network-path changes
  (`NWPathMonitor`) and app foregrounding call `online()`. The loop pauses in the
  background and restarts on foreground.
- **Rows / Location:** direct ports of `rows.ts` and `location.ts`, with their tests.

### 5.3 UI (SwiftUI)

- **Pair screen:** "Scan QR" (VisionKit `DataScannerViewController`; on a device without
  it, the typed fields) fills hub address and code; text fields for hub address, code
  (uppercased, letter-spaced), phone name. Re-pair warning with Export / Pair anyway.
  Shown when unpaired, or from the menu ("Pair again"). A typed hub address without a
  scheme gets `https://`, and without a port gets `:3443` *(builder's call)*.
- **Capture screen:** top bar — event name, location chip (course events only), sync pill,
  clock icon, menu. Banners for stopped / revoked / last error. Bib display + keypad; the
  crossing list. `ViewThatFits`/size classes give the portrait (stacked) and landscape/iPad
  (side by side) layouts. Big keys (≥ 56 pt) for gloves.
- **Feedback:** background flashes green for 150 ms and a `.success` haptic, only after the
  append succeeds.
- **Hardware keyboard:** digits, Delete, Return via `.onKeyPress`, ignored while a sheet is up.
- **Bib sheet:** keypad with Save; current bib dimmed until the first digit; racer lookup
  line ("Unknown bib" / "No roster yet"); "was N". Full screen on a landscape phone.
- **Export:** JSON of the same shape as the PWA's export (pairing without credential,
  entries, archive), handed to the share sheet (`ShareLink` with a temporary file).

### 5.4 Testing

- Unit tests per Core module, ported from the TS tests (hash vector, clock, location, rows,
  log chaining and archive-on-re-pair, sync with fake API and fake timers, sync labels).
- Run with `xcodebuild test` on an iOS Simulator; documented in `timing_app/README.md`.
- End-to-end: the §1 checklist, run by hand in the Simulator against `bin/rails server`.
  Debug builds allow plain `http://` hub addresses (for `localhost:3000`); release builds
  require https. *(Builder's call.)*

### 5.5 Build order

Each step ends runnable and tested, so it can stop at any point:
1. Project skeleton + Core: hash/canonical JSON/UUIDv7 (against the shared vector), store, log.
2. Pairing (typed) + keypad capture + push + clock + sync pill — usable at a finish line.
3. Roster + status: names, races, laps, chips; correct bib; delete; bib filter.
4. Location picker + hub adoption; menu (export, unpair, info); re-pair archive + warning.
5. QR scanning, landscape/iPad layout polish, hardware keyboard, README, the §1 check.

## 6. Left to the builder

Internal type names and file split within Core/UI; the SQLite wrapper's shape; exact
colours (follow the PWA: green synced, amber sending, red offline/stopped); app icon
(reuse `frontend/capture/public/icon.svg`); how Sync publishes state to SwiftUI
(`@Observable` model is expected).
