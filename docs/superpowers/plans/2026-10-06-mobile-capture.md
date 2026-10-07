# Mobile Capture Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A phone web app, paired to an event, that records crossings offline and syncs its append-only log to the hub, showing most of what the console's Capture tab shows.

**Architecture:** The hub gains a canonical device-entry checksum, a `capture_void` entry, and plain JSON `/sync/v1` endpoints (clock, push, roster, status) authenticated by device credential. The console gets a Phones panel to pair by QR and revoke. A second Vite entry in `frontend/` (`/capture-app/`) holds the phone app: an IndexedDB log, a sync loop, a service worker, and a keypad screen.

**Tech Stack:** Rails 8.1 (packs: timing, access, api), React 19 + MUI 9, Vite 8 (second config), `idb`, `vite-plugin-pwa`, `qrcode` (console), Vitest + `fake-indexeddb`, Playwright (phone viewport).

**Spec:** `docs/superpowers/specs/2026-10-06-mobile-capture-design.md`

**Granularity note:** the plan's author is also its inline executor (as for the setup and registration plans), so tasks give exact behaviour, interfaces and test cases rather than verbatim code. Each step is still test-first.

## Global Constraints

- Sync endpoints live under `/sync/v1/` and use JSON, not GraphQL. Auth header: `Authorization: Device <device_id>:<credential>`. An unknown or revoked device gets 401. The event is always the device's.
- `POST /sync/v1/push`:
  - at most 500 entries, in `device_seq` order;
  - idempotent by `id`;
  - replies `{ack_seq}`, the highest contiguous stored seq;
  - a gap or a bad hash → `409 {error: "chain_mismatch", ack_seq}`, nothing applied, and the device gets `sync_stopped_at_ms`.
- Checksum: `hash = SHA-256(canonical JSON of the entry without "hash")`.
  - Canonical JSON: keys sorted, no whitespace, null fields omitted.
  - First `prev_hash` = SHA-256(device_id), lowercase hex.
- Entry kinds: `capture` {captured_at_ms, clock_offset_ms?, bib?}, `bib_assignment` {capture_id, bib}, `capture_void` {capture_id}.
  - A void or bib assignment must reference a capture of the same device.
- Roster: `{event: {name, races: [{id, name}]}, racers: [{bib, name, race_id}], version}`. It holds no other racer fields, and `If-None-Match` → 304.
- Status: `{captures: [{id, bib, entered_bib, bib_source, lap, lap_ms, typical_lap_ms, lap_flag, voided}]}`.
- `createPairingToken` requires the chief role. `pairingUrl` = `<base>/capture-app/?pair=<token>`.
- Phone:
  - a tap is confirmed only after the IndexedDB commit;
  - the time is `performance.timeOrigin + performance.now()` at the Enter press;
  - the phone never deletes its log, and Unpair is refused while unsent entries remain;
  - push retry backoff is 1 s doubling to a 30 s cap, immediately on `online`;
  - clock every 60 s, keeping the lowest-RTT of 5 exchanges;
  - status every 10 s, roster every 60 s.
- Sync pill text: "Synced", "N to send", "Offline · N to send", "Sync stopped".

## Review Focus

1. **A push whose first entry repeats one the hub already has, followed by new ones** (the phone resending after a lost ack). Stored entries are skipped, new ones appended, and the right `ack_seq` returned. (Task 2)
2. **Two pushes racing from the same phone** (the timer fires one per tap). They must not double-insert or break the chain check, so the device row is locked. (Task 2)
3. **A tap while a clock sync is in flight, or before any.** The entry carries the offset known at that moment, or null, and the hub raises "Clock not synced" for null offsets. (Task 4)
4. **The phone reloaded mid-sync** (the app is killed). On start it resumes from the stored `ack_seq`; entries the hub has but the phone hasn't acked are re-sent and skipped. (Task 4)
5. **A void for a capture that isn't this device's, or that doesn't exist.** The push gets a 409 or a refusal, not a silent apply. (Task 2)

---

### Task 1: Hub — canonical checksum, capture_void, device sync columns

**Files:**
- Models in `packs/timing/app/models/`: new `device_hash.rb`, `device_entry.rb` (`append!` uses DeviceHash), new `capture_void.rb`, `capture.rb`, `bib_assignment.rb` (`record!` hash parts → canonical), `capture_laps.rb` (device voids), `results_snapshot.rb` (device voids → void rulings).
- Migration `db/migrate/20261006000004_device_sync.rb`: devices gain `last_seen_at_ms`, `last_sync_at_ms`, `clock_offset_ms`, `sync_stopped_at_ms` (bigint).
- Shared vector: `test/fixtures/files/device_hash_vector.json`.
- Tests: `test/models/device_hash_test.rb`, `capture_record_test.rb`, `capture_laps_test.rb`, `results_snapshot_test.rb`.

**Interfaces:**
- Produces:
  - `DeviceHash.canonical_json(hash) -> String` and `DeviceHash.digest(entry_hash_without_hash) -> String` (lowercase hex);
  - `DeviceHash.genesis(device_id) -> String`;
  - `DeviceEntry#wire -> Hash`, the pushed shape `{id, kind, device_seq, prev_hash, captured_at_ms?, clock_offset_ms?, bib?, capture_id?}` without `hash`, kind from the STI class;
  - `DeviceEntry.append!(device:, **attrs)` computes `entry_hash = DeviceHash.digest(wire)`;
  - `CaptureVoid < DeviceEntry` (belongs_to :capture; same-device validation; `CaptureVoid.record!(capture:)`);
  - `CaptureLaps.voided_ids(event)` includes device voids.
- Vector file: `{device_id, entries: [{...wire, hash}]}`. Three entries (capture with bib, capture with null bib and null offset, capture_void), and Task 4's Vitest reads the same file.

- [ ] Failing tests:
  - the canonical JSON sorts keys and omits nulls (`{b:1,a:null,c:"x"}` → `{"b":1,"c":"x"}`);
  - the vector's hashes reproduce;
  - `append!` entries verify against `DeviceHash` and chain from genesis;
  - `CaptureVoid` for another device's capture is invalid;
  - a device void makes `CaptureLaps.voided_ids` include the capture and lap numbering skip it;
  - `ResultsSnapshot.for` emits a `void_capture` ruling (id `dv-<id>`) for each device void, so the engine excludes the capture.
- [ ] Implement, migrate both databases, and dump the schema. The Rails suite and packwerk pass. Commit.

### Task 2: Hub — sync API and pairing

**Files:**
- New `packs/timing/app/controllers/sync_controller.rb` (clock, push, roster, status), and `concerns/device_auth.rb` (or inline).
- `config/routes.rb` (`scope "sync/v1"`).
- New `packs/timing/app/models/device_log_ingest.rb` (verify and insert a batch).
- `packs/api/app/graphql/mutations/create_pairing_token.rb` (chief; new URL).
- Tests: new `test/integration/sync_test.rb`, updated pairing test.

**Interfaces:**
- `DeviceLogIngest.call(device:, entries:) -> Result(ack_seq:, error: nil | "chain_mismatch")`:
  - runs under `device.with_lock`;
  - skips ids already stored, after checking they match;
  - expects `device_seq == last+1`;
  - checks `prev_hash == last.entry_hash` (or genesis) and `hash == DeviceHash.digest(entry minus hash)`;
  - builds the STI record by `kind`, with `event` from the device;
  - on mismatch, rolls back the batch and sets `sync_stopped_at_ms`.
- Each request sets `last_seen_at_ms`. `X-Clock-Offset-Ms` updates `devices.clock_offset_ms`. A successful push sets `last_sync_at_ms`.

- [ ] Failing tests:
  - 401 for a missing, wrong or revoked credential;
  - clock returns integers `t1 <= t2`;
  - push: good batch → `ack_seq`; the same batch again → same `ack_seq`, no duplicates; Review Focus 1, overlap plus new; a gap → 409 with the previous `ack_seq` and `sync_stopped`; a tampered hash → 409; 501 entries → 422; Review Focus 5, a void for another device's capture → 409;
  - Review Focus 2: two ingests of overlapping batches in threads leave one copy per id (or sequential calls under the lock, if threads aren't practical on SQLite in tests);
  - roster fields only (no birth date or license), and version/304;
  - status shows the resolved bib, lap and voided for this device's captures only;
  - `createPairingToken` works for chief and is refused for timer, and the URL has the new form;
  - a pushed capture appears in console standings (via `StandingsService`).
- [ ] Implement. Rails suite on SQLite and Postgres, packwerk and zeitwerk pass. Commit.

### Task 3: Console — Phones panel

**Files:**
- `packs/api/app/graphql/types/device_type.rb` (+ lastSeenAtMs, lastSyncAtMs, clockOffsetMs, syncStoppedAtMs, revokedAtMs, pendingHint omitted); `event_type.rb` (`devices`, chief+; check whether it exists).
- `frontend/src/queries.ts`; new `frontend/src/views/PhonesPanel.tsx` (QR via `qrcode`); `CaptureScreen.tsx` (renders the panel for chief+).
- `frontend/package.json` (`qrcode`, `@types/qrcode`).
- Test: `test/integration/api/devices_query_test.rb`, and an e2e step in `capture.spec.ts` (the chief sees Pair a phone and the QR link has `/capture-app/?pair=`).

- [ ] Failing tests: the devices query fields and chief-only; e2e: Pair a phone shows a QR `img` and a link containing `/capture-app/?pair=`, and Revoke marks the device revoked.
- [ ] Implement:
  - **Pair a phone** opens a dialog with the QR (data URL), the link text, and an expiry countdown;
  - the device list shows name, paired, last seen ("2 min ago"), last sync, clock offset, a red "Sync stopped" chip, and a Revoke button with a confirm.
- [ ] Unit, typecheck, e2e and Rails pass. Commit.

### Task 4: Phone app — log, hashing, sync engine (no UI)

**Files:**
- `frontend/capture/index.html`; `frontend/capture/src/{db.ts,hash.ts,log.ts,clock.ts,sync.ts,rows.ts,api.ts}` with `*.test.ts` alongside.
- New `frontend/vite.capture.config.ts` (base `/capture-app/`, outDir `../public/capture-app`, PWA plugin).
- `frontend/package.json` (`idb`, `vite-plugin-pwa`, `fake-indexeddb`; the `build` script builds both apps; Vitest includes `capture/src`).
- `frontend/tsconfig*.json` (include `capture/src`).

**Interfaces** (all in `frontend/capture/src`):
- `hash.ts`: `canonicalJson(obj)`, `digest(obj): Promise<string>`, `genesis(deviceId)`.
- `db.ts`: `openCaptureDb(name?)` with stores `pairing`, `entries` (key `device_seq`) and `state`.
- `log.ts`:
  - `appendCapture(db, {atMs, offsetMs, bib})`, `appendBibAssignment(db, captureId, bib)` and `appendVoid(db, captureId)`, each resolving only after commit with the entry;
  - `unsent(db, ackSeq, limit)` and `allEntries(db)`.
- `clock.ts`: `pickOffset(samples: {t0,t1,t2,t3}[]) -> {offsetMs, rttMs}`.
- `sync.ts`:
  - `createSync({db, api, now, schedule})` exposes `kick()`, `start()`, `stop()` and `subscribe(fn)`;
  - state: `{pending, online, stopped, clockSynced, offsetMs, lastSyncAtMs}`;
  - `nextBackoff(prevMs) -> min(prev*2 || 1000, 30000)`.
- `api.ts`: `pair(token, name)`, `clock`, `push`, `roster(version)`, `status`, all fetch with the Device auth header.
- `rows.ts`: `captureRows(entries, roster, status) -> Row[]`, newest first, voided removed, bib = status.bib ?? the latest local bib_assignment ?? entered. Each row carries `{name, race, chips: ["No bib" | "Unknown bib"], lap, lapFlag, enteredNote}`.

- [ ] Failing tests:
  - the hash vector from `test/fixtures/files/device_hash_vector.json` reproduces;
  - appends chain and number from 1;
  - `pickOffset` picks the lowest RTT;
  - `nextBackoff` sequence;
  - sync pushes unsent and advances `ack_seq`;
  - a 409 sets `stopped` and stops pushing;
  - Review Focus 4: a restart resumes from the stored `ack_seq`;
  - Review Focus 3: an entry made before the clock sync has a null offset;
  - `captureRows` with no status shows the local correction, "—" lap and the Unknown bib chip from the roster;
  - Unpair is refused with unsent entries (`canUnpair`).
- [ ] Implement, and wire the Vite capture config and build script. `npm test` and typecheck pass. Commit.

### Task 5: Phone app — screens and offline end-to-end

**Files:**
- `frontend/capture/src/{main.tsx,App.tsx,Keypad.tsx,CaptureList.tsx,BibSheet.tsx,SyncPill.tsx,Menu.tsx,PairScreen.tsx}`.
- `frontend/e2e/mobile-capture.spec.ts`; `frontend/e2e/seed.rb` (if needed).
- `docs/TODO.md` (spec §6 items).

- [ ] Failing e2e (phone viewport, e.g. `devices["Pixel 7"]`):
  1. A chief creates a pairing link on the console. The phone opens it, enters the name "Finish phone" and sees the keypad, and `?pair` is gone from the URL.
  2. `context.setOffline(true)`. The phone taps 101 ENTER, ENTER (blank), 999 ENTER. The pill shows "Offline · 3 to send". The phone taps the 999 bib → sheet → 102 → Save, and deletes the blank crossing (confirm).
  3. `setOffline(false)`. The pill shows "Synced". The console's Results / review queue shows 101 and 102 crossings, and no no-bib item (voided).
  4. The phone taps ENTER (blank) again and syncs. A chief accepts bib 103 for it in the review queue. Within a status cycle, the phone row shows 103 and "entered: no bib".
- [ ] Implement:
  - the screens per spec §5 (top bar, sync pill, clock indicator, bib display, keypad, ENTER, list with chips, bib sheet, void confirm, menu with Export/Unpair, unpaired screen, storage-persist banner);
  - a flash and vibrate on commit;
  - the service worker registered in production builds only (and in the e2e build).
- [ ] Add the spec §6 out-of-scope items to `docs/TODO.md`.
- [ ] Unit, typecheck and the full e2e suite pass; Rails and engine suites pass. Commit.
