# Mobile Capture — Design

**Date:** 2026-10-06
**Status:** Draft for review
**Builds on:** `2026-10-01-hub-mvp-design.md` §5 (capture app and device→hub sync),
the console Capture tab (resolved bibs, corrections, lap chips).

## 1. Goal

A timer records crossings on a phone at the line, **with or without a connection to the
hub**. Every tap is safe on the phone the moment it's confirmed, and reaches the hub when
the venue Wi-Fi allows. The phone shows most of what the console's Capture tab shows.

**Done when:** in a browser test on a phone-sized screen:
1. A phone is paired from the console's QR link.
2. It goes **offline** and records three crossings, one bib correction and one delete, and
   shows "3 to send".
3. It comes back online and shows **Synced**.
4. The console's Results and review queue reflect those entries.
5. A chief resolves a no-bib crossing in the review queue, and the phone shows the resolved
   bib after its next sync.

## 2. Decisions

- **A web app served by the hub** over the venue network, installable to the home screen and
  working offline. No app store, and no cloud server (venues often have no internet).
- **The phone is a paired device**, not a signed-in official. A QR code from the console is
  traded once for a device credential. The phone is tied to one event and can be revoked from
  the console.
- **A second entry point in `frontend/`**, at `/capture-app/`, built into
  `public/capture-app`.
  - It shares the theme, the time formatting and the lap/chip wording with the console.
  - It has no Apollo, GraphQL or sign-in. It talks to plain JSON `/sync/v1` endpoints with its
    device credential.
- **What carries over from /capture:**

| Feature | Offline |
|---|---|
| Bib + Enter, blank + Enter (time at the Enter press, on the phone's clock corrected by clock sync) | ✅ |
| Recent crossings (time, bib) | ✅ |
| Racer name and race; No bib / Unknown bib chips (from a cached roster) | ✅ as of the last roster |
| Correct or add a bib (tap the bib) — a bib correction entry | ✅ |
| Delete a crossing (confirm) — a **void** entry (new) | ✅ |
| Lap number and lap-warning chips (supplied by the hub) | after a sync |
| Fixes from the review queue (resolved bib, "entered: …") | after a sync |
| Sync indicator and clock status | ✅ |
| Export the log as JSON | ✅ |

  Not on the phone: Results, the review queue, Registration, starting races.

## 3. Hub side

### 3.1 Pairing (console)
- The console's **Capture** tab gets a **Phones** panel, for chief and above.
  - A **Pair a phone** button shows a QR code for
    `https://<hub>/capture-app/?pair=<token>`. The token is one-time and expires after
    10 minutes.
  - The panel lists the event's devices: name, paired at, last seen, last sync, clock
    offset, and a "sync stopped" flag. Each has a **Revoke** button.
- `createPairingToken` moves from admin to **chief** (pairing is race-day work). Its
  `pairingUrl` becomes the address above.
- `POST /devices/pair` exists (token + device name → `{device_id, credential, event_id}`).
- New `Device` columns:
  - `last_seen_at_ms`, `last_sync_at_ms`, `clock_offset_ms`;
  - `sync_stopped_at_ms`, set on a chain mismatch and cleared by re-pairing.

### 3.2 Sync API (`/sync/v1`, JSON, not GraphQL)
Every request carries `Authorization: Device <device_id>:<credential>`. An unknown or
revoked device gets `401`. The event is always the device's, never taken from the request.
Each request updates `last_seen_at_ms`.

| Endpoint | Request → response |
|---|---|
| `POST /sync/v1/clock` | `{t0}` → `{t1, t2}` (hub ms on receipt and on reply). The phone computes offset = ((t1−t0)+(t2−t3))/2 and keeps the one with the lowest round trip of 5. It reports the offset it adopted in `X-Clock-Offset-Ms` on later requests, which is stored for the console. |
| `POST /sync/v1/push` | `{entries: [...]}` in `device_seq` order, at most 500 → `{ack_seq}`, the highest contiguous `device_seq` stored. Idempotent by entry `id`: already-stored entries are skipped. A gap or a `prev_hash`/`hash` that doesn't verify → `409 {error: "chain_mismatch", ack_seq}`, the batch is not applied, and the device is flagged `sync_stopped`. |
| `GET /sync/v1/roster` | `{event: {name, races: [{id, name}]}, racers: [{bib, name, race_id}], version}` — racers with a bib only, no other fields. With `If-None-Match: <version>` → `304`. |
| `GET /sync/v1/status` | `{captures: [{id, bib, entered_bib, bib_source, lap, lap_ms, typical_lap_ms, lap_flag, voided}]}` for this device's captures, from the same calculator as the console (`CaptureLaps`). |

### 3.3 Device log entries
Entry kinds (the `device_entries` table):
- `capture`: `captured_at_ms` (phone clock), `clock_offset_ms` (null if not yet synced),
  `bib` (nullable).
- `bib_assignment`: `capture_id`, `bib`.
- **`capture_void`** (new): `capture_id`. The device takes back one of its own taps.
  - Treated like an official's delete: the results input gets a void for that capture,
    and `CaptureLaps` excludes it.
  - The capture must belong to the same device.

Pushed entry shape: `{id, kind, device_seq, prev_hash, hash, captured_at_ms?,
clock_offset_ms?, bib?, capture_id?}`.

### 3.4 Checksums (one rule)
- `hash = SHA-256(canonical JSON of the entry without hash)`.
  - Canonical JSON: keys sorted, no whitespace, null fields omitted.
  - `prev_hash` of the first entry = SHA-256(device_id).
- The hub verifies pushed entries with this rule. Its own console entries
  (`DeviceEntry.append!`) switch to the same rule.
- Only development data exists, so nothing is migrated.

## 4. Phone side

### 4.1 Storage (IndexedDB, via `idb`)
- **pairing:** device id, credential, event id, device name.
- **entries:** the append-only log, keyed by `device_seq`.
- **state:**
  - `ack_seq`;
  - the clock offset, its round trip and when it was measured;
  - the roster and its version;
  - the last status and when it was fetched;
  - `sync_stopped`.
- On first launch the app calls `navigator.storage.persist()`. If that's refused, a banner
  stays up.

### 4.2 A tap
- The time is `performance.timeOrigin + performance.now()` at the Enter press.
- The entry carries the current clock offset, or null.
- It's written in one IndexedDB transaction. **Only after the commit** does the phone
  confirm: a flash, a short vibration where supported, and the field clears.
- If the write fails, the phone shows an error and keeps the bib.

### 4.3 Sync loop
- **Push:** right after each committed entry, and every 5 s while unsent entries remain.
  - On failure, retry with backoff 1 s, 2 s, 4 s … up to 30 s. Retry immediately on the
    browser's `online` event.
  - A 409 stops pushing and shows "Sync stopped — export the log and see an official".
- **Clock:** on connect and every 60 s. Taps before the first clock sync carry a null
  offset. The hub already raises those as "Clock not synced" in the review queue.
- **Status:** every 10 s while connected. **Roster:** at start and every 60 s (only if
  changed).
- The phone never deletes its log. Unpair is refused while `ack_seq` is below the last
  entry. Export downloads the whole log as JSON.

### 4.4 Offline app shell
A service worker caches the app's files, so it opens with no connection once loaded from
the hub. Offline storage, the service worker and `crypto.subtle` all need HTTPS: the hub's
local certificate, installed once per phone from `/onboarding`. `localhost` counts as
secure, for development and tests.

## 5. Screen (phone, portrait)
- **Top bar:**
  - event name;
  - a sync pill: green "Synced", amber "N to send", red "Offline · N to send" or
    "Sync stopped";
  - a clock indicator, ⏱ synced or not synced.
- **Bib display:** large digits.
- **On-screen keypad:**
  - 0–9 and ⌫, plus a wide green **ENTER** (blank = no-bib crossing);
  - large keys for gloves and cold hands;
  - a hardware keyboard works too. Our own keypad is used so the phone's never covers
    the screen.
- **Recent crossings**, newest first: the last 20, then "Show more".
  - time; the bib (**tap it** to correct with the same keypad in a sheet); "entered: …"
    when the hub resolved a different bib;
  - racer name and race on two lines;
  - chips: No bib / Unknown bib (from the roster); Lap N and the lap-warning chips (from
    status) or "—" before a sync;
  - a trash can with a confirm (writes a void).
- **Menu (⋮):** phone name and event, last sync, clock offset, Export log, Unpair.
- **Unpaired:** "Scan the pairing code on the console's Capture tab". `?pair=` is redeemed
  (with a device name prompt), stored, and removed from the address (`history.replaceState`).

## 6. Out of scope (to `docs/TODO.md`)
- Installing the certificate beyond linking to `/onboarding`.
- Several events on one phone.
- "Who's holding the phone".
- Device check-in after the event.
- Chip timing.
- Running the hub in production mode for venue tests (already in TODO).

## 7. Testing
- **Engine / Rails:**
  - sync auth (unknown, revoked, event from the device);
  - push: good, idempotent re-send, gap, bad hash → 409 and flag, at most 500;
  - `ack_seq`;
  - clock;
  - roster: fields, version, 304;
  - status: laps, resolved bibs, voids;
  - `capture_void` voids in results and `CaptureLaps` and must be the device's own capture;
  - console entries use the canonical hash;
  - `createPairingToken` for chief.
- **Unit (Vitest + fake-indexeddb):**
  - canonical JSON and hash, with a vector shared with a Rails test;
  - log append and chaining;
  - clock offset selection;
  - retry timing;
  - row view from roster and status;
  - unpair refused with unsent entries.
- **Browser (Playwright, phone viewport):** the "done when" flow in §1, using
  `context.setOffline`.
