# Bike Race Timing — Hub MVP Design

**Date:** 2026-10-01
**Status:** Draft for review
**Scope:** Spec 1 of 4 (Hub MVP). Specs 2–4 are outlined in §11 for context only.

---

## 1. Purpose and context

We are building a system for timing bike races. Races frequently happen where there
is no internet, so timing must work fully offline at the venue and sync to a central
system later. Lapped races (criterium, cyclocross, MTB XC/XCC) are the most common
format and are the first priority; mass-start road races are supported as the
single-lap case.

Times will eventually come from chip timing (RFID mats/transponders) with manual
entry as backup. **This spec builds manual capture only**, but the data model treats
the capture source as a first-class attribute so chip reads slot in later without
schema changes.

### Success criteria for this spec

A simulated 45-minute CX start group — 3 races released at 30-second offsets, lap
count set mid-race, timed on 2 tablets — where one tablet loses Wi-Fi for 2 minutes
and another has its browser tab killed mid-sprint, results in:

1. Every tap that the capture UI confirmed reaches the hub (zero loss).
2. A deliberately skipped crossing triggers a "suspected missed crossing" suggestion.
3. Published standings for all 3 races match a golden file.

---

## 2. System architecture (whole system)

| Component | Runs on | Storage | Role |
|---|---|---|---|
| **Cloud app** (Rails, `cloud` mode) | Server | Postgres | Event setup, registrations, archive, public results, sync target. *Spec 2.* |
| **Hub app** (Rails, `hub` mode) | Venue laptop | SQLite | Owns one event offline; computes live results; serves capture and ops apps on the LAN. |
| **Capture app** (React/TS PWA) | Crew-owned tablets/phones | IndexedDB append-only log | Bib/time entry; keeps recording through hub disconnects. |
| **Ops console** (React/TS) | Browser on the hub laptop (or LAN) | none (talks to hub) | Start control, rulings, review queue, publishing. |

### Key decisions

- **Modular monolith, not microservices.** One Rails codebase. The hub must run the
  complete timing and results logic offline; splitting it into services would mean
  shipping and orchestrating several services on every venue laptop. Cloud-only
  services (notifications, payments, public results scaling) may be extracted later.
- **One codebase, two modes.** `TIMING_MODE=hub|cloud` selects database adapter and
  enabled modules. Results logic exists exactly once, so hub and cloud compute
  identical results from the same log.
- **Single writer per event.** While an event is checked out to a hub, the hub is the
  only place its race data can be changed. Hub→cloud sync is therefore log
  replication, not conflict resolution. (Check-out mechanics are Spec 2; in this spec
  the hub creates events locally.)
- **Append-only race log.** Raw captures are never edited. Official decisions are
  separate immutable `Ruling` records that reference captures. Results are a pure
  function of the log.

### Rails modules (engines/packs)

- `events` — event, start groups, races, categories, riders, registrations.
- `timing` — captures, rulings, devices, clock offsets.
- `results` — pure-Ruby results engine and anomaly detection (no Rails, no DB access).
- `sync` — versioned sync protocol endpoints (device→hub in this spec).
- `api` — GraphQL schema (graphql-ruby) and subscriptions (ActionCable / Solid Cable).
- `access` — device pairing, official PINs and roles.

Module boundaries are enforced (packwerk or equivalent): `results` depends on nothing;
`api` depends on the others; others do not depend on `api`.

---

## 3. Data model

All primary keys are **UUIDv7** (globally unique, time-ordered) so records created on
different machines never collide and can be merged into the cloud later. Timestamps
are stored as integer milliseconds since epoch (UTC) to avoid SQLite/Postgres
datetime differences.

### 3.1 Setup data

**`Event`** — `id`, `name`, `date`, `venue`, `timezone`, `age_rule`
(`racing_age_dec31` default; `age_on_event_date` alternative).

**`Category`** — eligibility definition, reusable across events.
- `name` (e.g. "Cat 3 Masters 35+")
- `ability_levels` — set of strings, may be empty (e.g. `["Cat 3"]`, `["Cat 1","Cat 2"]`)
- `age_min`, `age_max` — nullable integers
- `gender` — required

**`StartGroup`** — races that share one start gun and one finish.
- `event_id`, `name`, `scheduled_at`
- `finish_rule` — one of:
  - `{type: "fixed_laps", laps: N}` (road race = 1)
  - `{type: "timed", target_duration_ms: D}` (lap count unknown at start; set by
    ruling during the race)

**`Race`** — one category at one event, scored independently.
- `event_id`, `category_id`, `start_group_id`
- `start_offset_ms` — offset from the start group's gun (0, 30000, 60000, …)

All races in a start group race the **same number of laps**.

**`Rider`** — `id`, `first_name`, `last_name`, `gender`, `birth_date`,
`ability_level`, `license_number` (nullable), `team` (nullable).

**`Registration`** — `rider_id`, `race_id`, `bib` (unique within event).
Eligibility against the category is checked at registration and produces a
**warning, not a block** (officials may allow riders to race up).

### 3.2 Race log (append-only, immutable)

**`Device`** — `id`, `event_id`, `name`, `paired_at`, `revoked_at`, `credential_digest`.

**`Capture`** — a line crossing.
- `id` (UUIDv7, generated on device)
- `device_id`, `device_seq` (strictly increasing per device, starting at 1)
- `captured_at_ms` — device clock at the moment of the tap
- `clock_offset_ms` — device-vs-hub offset measured at last clock sync (nullable =
  "unsynced clock")
- `bib` — nullable ("rider crossed, bib unknown")
- `source` — `manual` (this spec) | `chip` (Spec 4)
- `prev_hash`, `entry_hash` — per-device hash chain (§5.3; `hash` is reserved in Ruby)
- `received_at_ms` — set by hub on receipt (not part of the hash)

Effective crossing time = `captured_at_ms + clock_offset_ms`.

The tap timestamp is taken at the moment of the tap; a bib may be added afterwards on
the device ("tap now, bib later"). Adding a bib on the device before sync produces a
**new device log entry** (`bib_assignment` referencing the capture id), never a
mutation — see §5.1.

Captures and bib assignments share one per-device sequence, so both are stored in a
single `device_entries` table (STI: `Capture`, `BibAssignment`) with a unique index
on `(device_id, device_seq)`.

**`Ruling`** — an official decision.
- `id`, `event_id`, `kind`, `payload` (JSON), `official_id`, `reason` (nullable),
  `created_at_ms`
- Kinds:

| Kind | Payload | Effect |
|---|---|---|
| `set_group_start` | `start_group_id`, `at_ms` | Gun time for the start group |
| `set_race_start` | `race_id`, `at_ms` | Overrides one race's start (held/delayed wave) |
| `set_lap_count` | `start_group_id`, `laps` | Lap count; latest wins |
| `assign_bib` | `capture_id`, `bib` | Sets/overrides a capture's bib |
| `void_capture` | `capture_id` | Capture ignored for results |
| `insert_capture` | `bib`, `at_ms` | Synthetic crossing for a missed rider |
| `flag_finish` | `bib`, `capture_id` | This crossing is the rider's finish (early checkered flag) |
| `pull` | `bib`, `at_ms` | Rider pulled from course |
| `dnf` / `dns` / `dsq` | `bib` | Status |
| `dismiss_suggestion` | `suggestion_key` | Suppresses an anomaly suggestion |
| `publish_results` | `race_id`, `result_digest` | Marks this race's results official as of these standings |
| `revert` | `ruling_id` | Cancels a prior ruling |

Rulings are created only on the hub (requires connection to the hub).

### 3.3 Derived data

Lap crossings, standings and suggestions are **computed**, never authoritative. The
hub may cache them (in-memory or a cache table) and invalidates on any log append.

---

## 4. Results engine (`results` module)

Pure Ruby. Input: a snapshot of setup data + captures + rulings. Output: per-race
standings and a list of suggestions. Deterministic and independent of record arrival
order.

### 4.1 Resolving crossings

1. Apply `revert` rulings (remove reverted rulings).
2. For each capture: bib = latest `assign_bib` ruling, else latest device
   `bib_assignment`, else capture's own `bib`. Drop voided captures.
3. Add `insert_capture` crossings.
4. Map bib → registration → race. Captures with no bib or unknown bib go to the
   **unassigned** list (shown in the review queue, never discarded).
5. Effective start for each race = `set_race_start` if present, else
   `set_group_start.at_ms + race.start_offset_ms`. Crossings before the race's
   effective start are ignored for laps (kept visible in review).
6. Sort each rider's crossings by effective time. Collapse crossings within a
   **debounce window** (default 10 s, configurable per event) into one (keep the
   earliest) — protects against double taps from two devices.

### 4.2 Finish logic (per start group)

- **Lap count** = `fixed_laps.laps`, or latest `set_lap_count` for `timed` groups. If
  a timed group has no lap count yet, standings are "in progress" with laps completed
  only.
- **Group leader** = first rider from any race in the group to complete the lap count.
- **Finish opens** at the group leader's finishing crossing.
- **A rider's finish** = their first crossing at or after the finish opens, **or** a
  crossing marked by `flag_finish` (which may precede the finish opening). Laps
  completed is counted up to and including that crossing. Crossings after a rider's
  finish are ignored.
- Riders lapped any number of times finish on their first crossing after the finish
  opens, with their actual laps completed (e.g. N−3).

### 4.3 Standings (per race)

Ranking order:
1. **Finishers and riders still racing**, ranked together: laps completed descending,
   then latest counted crossing time ascending (for finishers, that is the finish
   crossing). Ranking them together keeps live standings correct mid-race.
2. **Pulled**: laps completed descending, then pull time ascending (pull order). Pulled
   riders always rank below every rider still racing or finished.
3. **DNF**, then **DNS**, then **DSQ**.

Exact ties (same laps, same millisecond) are broken by crossing id so results are
deterministic.

Displayed times are **elapsed from the race's effective start**, so later waves are
not penalized. Per-rider output: place, bib, name, laps, elapsed time, gap to race
leader (time if same laps, otherwise "−N laps"), lap times, status.

Standings are **provisional** until a `publish_results` ruling exists for the race
whose `result_digest` matches the race's current standings digest (SHA-256 of lap
count + rows). If the race's standings change after publishing — from new captures,
rulings, or setup edits — the UI shows "changed since published". Changes in other
races don't affect it.

### 4.4 Anomaly detection (suggestions)

Computed on every recompute. Suggestions never modify data; an official accepts
(creates the corresponding ruling) or dismisses (`dismiss_suggestion`). Each
suggestion has a stable `suggestion_key` (kind + bib + crossing ids) so dismissals
stick.

Reference lap time for lap *i* of a rider:
- *i* ≥ 2: median of the rider's other laps (index ≥ 2, excluding the lap under test);
  if the rider has none, the median of other riders' lap *i* in the same race.
- *i* = 1 (the start lap, often a different length): the rider's own reference ×
  the race's **start factor** (median over riders of lap 1 ÷ their own reference). If
  either is unknown, lap 1 is not checked.
- Neighbor laps are checked against a reference that also excludes the suspect lap.

| Suggestion | Trigger | Proposed fix |
|---|---|---|
| **Suspected missed crossing** | Lap time between 1.7× and 2.3× reference, and neighboring laps (if any) within 0.7×–1.3× | `insert_capture` at the midpoint; **or** `assign_bib` of an unassigned capture within ±15% of a lap of the midpoint, if one exists (preferred) |
| **Suspected duplicate / wrong bib** | Lap time < 0.5× reference (after debounce), and no adjacent lap is itself ≥ 1.7× its reference (a long neighbour means a missed crossing is distorting the reference) | `void_capture`, or reassign bib |
| **About to be lapped** (live) | Projecting both riders forward at their typical pace, the group leader gains another whole lap on the rider before the rider's next crossing (live, only while the finish is not open) | Prompt to `flag_finish` on final lap |
| **Unsynced clock** | Capture with null `clock_offset_ms` | Review; ranked provisionally |
| **Unassigned capture** | No/unknown bib | `assign_bib` |

Thresholds are constants in one config object, tunable later.

---

## 5. Capture app and device→hub sync

### 5.1 Device log

- IndexedDB, one object store per event, append-only. Entry types: `capture`,
  `bib_assignment` (references capture id; for "tap now, bib later").
- Each entry: `id` (UUIDv7), `device_seq`, payload, `prev_hash`, `hash`.
- **A tap is confirmed only after the IndexedDB transaction commits.** The beep/flash
  happens on commit, not on touch. The tap timestamp is taken with
  `performance.timeOrigin + performance.now()` at the pointer-down event, before the
  write.
- On first launch the app calls `navigator.storage.persist()` and shows a warning if
  persistence is denied.
- Entries are retained on the device until the event is checked in (Spec 2); in this
  spec, until an official clears the device from the ops console after publishing.
- **Export**: the device can download its full log as a JSON file at any time.

### 5.2 Sync protocol (v1)

Plain JSON over HTTPS, versioned under `/sync/v1/`. Not GraphQL. Reused hub→cloud in
Spec 2.

- `POST /sync/v1/clock` — NTP-style exchange: device sends `t0`; hub returns `t1`,
  `t2`; device records `t3`; offset = ((t1−t0)+(t2−t3))/2. Device runs 5 exchanges and
  keeps the offset from the lowest round-trip. Done on connect and every 60 s.
- `POST /sync/v1/push` — body: `{device_id, entries: [...]}` in `device_seq` order,
  max 500 per batch. Hub:
  - authenticates the device credential;
  - verifies the hash chain continues from the last stored entry;
  - inserts idempotently by `id` (duplicates ignored);
  - responds `{ack_seq}` = highest contiguous `device_seq` stored.
- Device pushes immediately after each committed tap (when connected) and retries
  with exponential backoff (1 s → 30 s cap) when not. Sends everything after
  `ack_seq`.
- Hash-chain mismatch → hub rejects the batch with `409 chain_mismatch`; the device
  is flagged in the ops console for manual investigation (export both sides). Entries
  already accepted are unaffected.

### 5.3 Hash chain

`hash = SHA-256(canonical_json(entry without hash/received_at) )`, where the entry
includes `prev_hash` (genesis `prev_hash` = SHA-256 of `device_id`). Canonical JSON =
sorted keys, no whitespace. Provides tamper evidence and a cheap checksum for
(later) check-in.

### 5.4 Capture UI

- Large numeric bib keypad; Enter records the crossing **with the time taken at the
  moment the first digit was pressed**, *or* a dedicated "LINE" button records the
  time immediately with no bib.
- **Tap-now, bib-later list**: recent bib-less taps appear in a list; tapping one lets
  the timer enter its bib (creates `bib_assignment`).
- "Bib unknown" is simply a tap with no bib that is never assigned on the device.
- Persistent sync indicator: green (synced), amber (pending N, connected), red
  (disconnected, N pending), plus clock status.
- Shows bib → rider name/race lookup for confirmation (from a minimal roster pulled
  from the hub: bib, name, race name only).

---

## 6. Ops console

- **Event setup**: create event, categories, start groups (finish rule, scheduled
  time), races (category + offset). CSV registration import with column mapping and
  eligibility warnings.
- **Devices**: pairing QR code, device list with last-seen, pending count, clock
  offset; revoke.
- **Start control**: GO button per start group (`set_group_start`), per-race start
  override, set lap count (with display of leader's lap times and projected finish vs.
  target duration).
- **Finish line view** per start group: leader, laps to go, recent crossings, "about
  to be lapped" warnings, quick actions (flag finish, pull, DNF).
- **Review queue**: unassigned captures and anomaly suggestions; accept/dismiss.
- **Standings** per race: provisional/published, publish button, "changed since
  published" indicator, CSV export.
- **Ruling history**: full audit list with author, reason, revert action.

---

## 7. API

- **GraphQL** (graphql-ruby, Apollo Client) for ops console and capture-app roster
  queries. Schema is mode-agnostic; cloud-only fields return a typed
  `NOT_AVAILABLE_IN_MODE` error in hub mode.
- **Subscriptions** via ActionCable using **Solid Cable** (no Redis on the hub):
  `standingsUpdated(raceId)`, `crossingRecorded(startGroupId)`,
  `reviewQueueChanged(eventId)`, `deviceStatusChanged(eventId)`.
- Mutations map 1:1 to ruling kinds plus setup CRUD.
- TypeScript types generated with GraphQL Code Generator into `packages/graphql`.

---

## 8. Security and durability

### Durability
- Capture: commit-before-confirm (§5.1), persistent storage request, log export.
- Hub: SQLite with `journal_mode=WAL`, `synchronous=FULL`.
- Devices retain their logs, acting as a distributed backup of raw captures.
- *(Automatic snapshots to a second location: Spec 3.)*

### Security
- **PII minimization**: capture devices receive only bib, name, race name.
- **Device pairing**: ops console shows a QR code with hub LAN URL + one-time pairing
  token (expires in 10 min, single use). Device exchanges it for a long-lived
  device credential scoped to the event; stored digest-only on the hub; revocable.
- **Officials**: PIN login at the hub. Roles: `timer` (capture only), `chief`
  (rulings, start control, publishing), `admin` (setup, devices, officials). Every
  ruling records `official_id`.
- **LAN HTTPS — local CA (decided: option A)**: on first run the hub generates a
  local root CA and a server certificate for its LAN IP(s) and mDNS hostname. Each
  crew-owned tablet installs and trusts the root CA once (manual install or MDM
  profile). The hub serves the root CA download at an HTTP-only onboarding page with
  platform-specific instructions. The server cert is reissued automatically when the
  LAN IP changes.
- *(SQLCipher at-rest encryption with OS keychain key: Spec 3.)*

---

## 9. Error handling

| Situation | Behavior |
|---|---|
| Device offline from hub | Keeps capturing; queue grows; red indicator; backoff retry |
| Duplicate push / retry | Idempotent by id; no effect |
| Unknown or missing bib | Stored; appears in review queue as unassigned |
| Device clock never synced | Stored with null offset; ranked provisionally; review queue |
| Hash chain mismatch | Batch rejected (409); device flagged; prior entries kept |
| Revoked device pushes | 401; device shows "revoked — contact chief official"; local log retained and exportable |
| Timed group with no lap count | Standings show laps completed, "lap count not set" banner |
| Log changes after publish | "Changed since published" flag; republish required |
| Results engine exception | Last good standings remain displayed with an error banner; error logged; captures unaffected |

---

## 10. Testing

- **Results engine golden files** (`results/spec/fixtures/*.yml`): log in → standings
  and suggestions out. Required scenarios: single-lap road race; fixed-lap crit;
  timed CX with lap count set mid-race and changed once; three waves at 30 s offsets;
  riders lapped 1×, 2×, 3×; early `flag_finish`; pulls; DNF/DNS/DSQ; missed crossing
  (with and without a matching unassigned capture); duplicate taps from two devices;
  `revert`.
- **Property tests**: shuffling arrival order and duplicating records produces
  identical standings and suggestions.
- **Dual database CI**: full Rails suite on SQLite and Postgres.
- **Sync harness**: simulated devices over a fault-injecting transport (drop,
  duplicate, reorder, truncate mid-batch). Invariant: hub log for each device equals
  the device log prefix up to `ack_seq`, and eventually the full log.
- **Capture app**: Vitest for log/hash/sync logic; Playwright for offline capture,
  tab kill between pointer-down and commit and after commit (confirmed taps survive;
  unconfirmed ones may not), reconnect and drain.
- **Race simulator** (`bin/simulate-race`): generates a realistic start group (lap
  time distributions per rider, bunch finishes, skipped taps) and drives capture
  devices against a running hub. Used for the success-criteria test (§1) and for
  dry runs with real tablets.

---

## 11. Repository layout and later specs

```
/                       Rails app (modes: hub | cloud)
  app/ packs/ (events, timing, results, sync, api, access)
/frontend               pnpm workspace
  apps/capture          PWA
  apps/ops              Ops console
  packages/ui
  packages/graphql      generated types
  packages/sync-client  sync protocol v1 client
/docs/superpowers/specs
```

The Rails app serves the built `capture` and `ops` bundles as static assets in hub
mode.

**Later specs (not in scope here):**
- **Spec 2 — Cloud mode & sync**: Postgres deployment, `apps/admin`, event
  check-out/check-in with leases, hub→cloud log replication via sync protocol,
  late-registration pull, lease revocation, live results upload.
- **Spec 3 — Packaging & hardening**: Tauri desktop shell with bundled Ruby,
  SQLCipher, automatic snapshots, guided tablet CA install.
- **Spec 4 — Chip timing & public results**: reader adapters writing
  `source: chip` captures; `apps/results`.

### Built now to avoid rework later
UUIDv7 ids, integer-ms timestamps, hash-chained device logs, sync protocol v1, and
Postgres in CI.

---

## 12. Out of scope for this spec

Cloud deployment, multi-event administration, online registration/payments, chip
timing, time trials, stage races/series points, public results site, at-rest
encryption, desktop packaging, native mobile apps.
