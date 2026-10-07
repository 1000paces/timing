# To Do — examine later

Items deliberately deferred. Each has enough context to pick up cold.

## Results engine

### Compare early laps against the field, not just the rider's own laps
- **Idea:** use the field's lap times as the comparison point for anomaly
  detection (missed crossing / short lap), especially early in a race.
- **Why:** with only 1–2 laps of their own, a rider's "typical lap" is easily
  distorted by a single missed crossing. (We already fixed the worst symptom: a
  `short` suggestion is no longer raised next to an abnormally long lap.)
- **Proposed shape:** use the field **median** (not average — one missed lap
  skews an average) of that lap index until the rider has ≥ 2 other laps of
  their own; then switch to the rider's own median. Riders' paces differ by
  30–40% across a field, so own-pace stays the better reference once available.
- **Catch:** in small fields the field median is fragile — in the 3-rider
  `missed-crossings.yml` golden race, one rider's missed lap skews the median and
  rider 3's genuine missed crossing would stop being flagged. Likely needs a
  minimum field size (e.g. ≥ 5 other riders with that lap) before trusting it.
- **Where:** `packs/results/lib/results/anomalies.rb` (`RaceLaps#typical`),
  spec §4.4 "Reference lap time".
- **Raised:** 2026-10-01.

### Pace-scaled field fallback for early laps (known false positive today)
- **Problem:** when a rider has no other laps ≥ 2 of their own, lap 2 is compared
  with the *field's* lap-2 median. A slow but steady rider (e.g. 180 s laps in a
  ~100 s field) gets a "suspected missed crossing" suggestion at lap 2. If an
  official accepted it, the rider would gain a phantom lap. It disappears at lap
  3, but stays in the queue for riders who stop after 2 laps (flagged, pulled).
- **Pinned as known** in `packs/results/test/fixtures/races/flag-finish-and-pulls.yml`
  (`missed:2:c-2-1:c-2-2`).
- **Proposed fix:** scale the field fallback by the rider's own pace:
  field lap-i median × (rider's lap 1 ÷ field lap-1 median). For the pinned
  case that gives ~142 s → ratio 1.27 → no suggestion.
- Closely related to the entry above; decide both together.
- **Raised:** 2026-10-01 (final review of plan 1).

### Suggest "no finish crossing" for riders who never cross after the finish opens
- **Problem:** a missed finish tap (the most common bunch-sprint error) is never
  flagged: the rider stays `racing` with N−1 laps and no suggestion appears.
- **Proposed:** once the finish is open and `now` is past the rider's last
  crossing + ~1.5× their reference lap, emit a `no_finish` suggestion — insert at
  the projected time, or assign a nearby unassigned capture.
- **Where:** `packs/results/lib/results/anomalies.rb`, spec §4.4.
- **Raised:** 2026-10-01 (final review of plan 1).

## Events & eligibility

### Cyclocross racing age: January–February events
- **Done (2026-10-06):** events have "Age as of next year (cross season)", on by
  default for cyclocross; racing age is then as of Dec 31 of the following year.
- **Left:** a CX event in Jan–Feb belongs to the season that started the autumn
  before, so its age should be as of Dec 31 of the event's own year — today the
  official has to untick the setting for those. Could default it from the event
  date (Sep–Dec → next year; Jan–Aug → this year).

## Hub operations & hardening

### Run the venue hub in production mode (not development)
- **Problem:** `bin/hub` starts Rails in the development environment, so at a venue
  any device on the LAN that hits an error sees full debug pages (backtraces,
  source), code reloads, and the development database is used.
- **Why not a one-liner:** `config/environments/production.rb` has `force_ssl` /
  `assume_ssl` (would redirect the plain-HTTP onboarding page that tablets need
  before they trust the CA), needs `secret_key_base`, and uses separate
  cache/queue/cable databases.
- **Options:** a dedicated `hub` Rails environment, or production with
  `config.ssl_options = { redirect: { exclude: ->(r) { r.path.start_with?("/onboarding", "/up") } } }`,
  generated `secret_key_base` stored under `storage/`, and `bin/hub` setting `RAILS_ENV`.
- **Raised:** 2026-10-02 (review of plan 2, task 9).

### Constrain the hub's root CA
- Add `pathlen:0` and critical `nameConstraints` (private IP ranges, `.local`,
  `localhost`) so a stolen hub key can't mint certificates for real websites on
  crew tablets. Caveat: the raw machine hostname (e.g. `laptop.lan`) must be
  permitted or dropped from the server certificate.
- **Raised:** 2026-10-02.

## Carry into upcoming plans

### Ops console / API plan
- **Expose crossing ids per rider** (`crossings { ref atMs inserted counted }` on
  standings rows, or a crossings query). Without them the console can't void a
  bad tap, reassign a counted crossing, or flag-finish a specific crossing — and
  "about to be lapped" fixes can't be completed. First API task of the plan.
- **Guard against a second GO:** `fireStart` on an already-started group should
  refuse unless `restart: true` (console confirm dialog). Today a second GO
  silently moves the gun and shifts every elapsed time.
- **Sessions:** expire after 12–24 h; `updateOfficial(id, active, role, pin)`
  (admin); invalidate existing sessions on deactivation or PIN change (check in
  `CurrentOfficial` and the cable connection). Today a copied cookie keeps
  working after sign-out and there's no way to deactivate an official via the API.
- **Pairing QR URL** must use the hub's LAN address (`LocalCa.lan_ips` +
  `HUB_TLS_PORT`) or a configured hub URL — not the admin's request host
  (`localhost` QR codes are unreachable from tablets).
- **Coalesce broadcasts** during CSV import (one "changed" at the end, not one
  per row); broadcast device pair/revoke so the device list is live.
- **Simulator virtual clock:** taps are stamped ahead of the wall clock
  (gun + race time), which confuses live features (about-to-be-lapped, `now`).
- **Live updates across processes in development:** the dev cable adapter is
  in-process (`async`), so `bin/simulate-race` won't push to an open console.
  Use Solid Cable for hub mode, and align `config.action_cable.allowed_request_origins`
  with `TIMING_ALLOWED_ORIGINS` (Vite dev server).
- Smaller: strip `license_number` in `RiderRegistrar`; guard duplicate category
  names per event; `revokeDevice` shouldn't overwrite the first revocation time;
  CSV import row cap and per-row error resilience; runbook notes (restart
  `bin/hub` after a network change; delete `storage/certs/server.*` if corrupt).
- Clients must never set `Ruling#created_at_ms` ("latest wins" ordering depends
  on hub time) — the API sets it.
- Suggestion `fix` hashes are *templates*: `flag_finish` lacks `capture_id`,
  unassigned-capture fixes have `bib: nil`. The console must complete them before
  creating a ruling.
- Lap-count changes: the console must let officials set the lap count on ANY start
  group (fixed or timed) — decided 2026-10-01: a `set_lap_count` ruling overrides
  the finish rule.
- Show last good standings with an error banner if computing results fails (spec §9).

### Sync + capture plan
- **Before any tablet/venue test:** run the hub in production mode (see "Run the
  venue hub in production mode") and constrain the root CA (nameConstraints).
- Strip the pairing token from the capture app URL after reading it
  (`history.replaceState`); bound device name length.
- Device entries must take their `event_id` from the authenticated device, never
  from the payload (and add a model check that it matches `device.event_id`).
- Consider storing each raw device entry so hash chains can be re-verified later.
- Normalize empty-string bibs to nil on captures.

### Event & race setup (review minors, 2026-10-02)
- Warn in Setup when moving a race into a cohort (new scheduled start or finish
  with leader switched on) changes that cohort's lap count — the newest
  `set_lap_count` in the cohort wins.
- `deleteRace` should refuse when standings are stale, as `startRaces` /
  `unstartRace` do.
- A blank or unknown discipline should give its own error, not "Sub discipline
  is not part of …".
- `unstart_race.rb` still says "whole start group" in an unreachable branch.
- New event dialog pre-fills the UTC date (tomorrow on US evenings); use the local date.
- Honour `TIMING_SIGN_IN_LIMIT` only in the test environment (or cap it).
- Non-admins who type a `/setup` URL see the form (saves are refused); show a notice.
- Date/time fields use the browser's time zone, not the event's `timezone`.
- Browser test for "a finish-with-leader-off race finishes on its own leader"
  (engine tests cover it; the e2e only checks lap counts per cohort).

### Registration (out of scope for the first slice, 2026-10-06)
- Starts tab: show "N of M checked in" per race before starting a wave.
- Suggest DNS in the review queue for riders who never checked in and have no captures.
- Assign bibs only to checked-in riders (option).
- Import BikeReg's public "Who's Registered" list format.
- Registration export (CSV).
- Presets for other registration sources (USAC, RaceRoster, …) beyond the recognised header names.
- Chip / tag numbers on registrations (for chip timing).
- Registration review minors (2026-10-06):
  - show "not in file" in the import preview, not only after importing;
  - a returning rider's first import into a new event keeps last event's team/city/state (applied on the next re-import);
  - a row with no category says "category  is not mapped" — say "no category";
  - "License number has already been taken" should name the rider who holds it;
  - the import dialog's file analysis has no error handling for network/sign-out errors.

### Mobile capture (out of scope for the first slice, 2026-10-07)
- Help installing the hub certificate on phones beyond linking to /onboarding.
- Several events on one phone at once (today: one pairing; re-pair after syncing).
- "Who's holding the phone" recorded with each tap.
- Device check-in after the event (verify and archive each phone's full log).
- Chip timing.
- Run the hub in production mode before any venue test (see "Run the venue hub in production mode").
