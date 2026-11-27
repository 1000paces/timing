# To Do — examine later

Items deliberately deferred. Each has enough context to pick up cold.

## Priorities for a real (manual, no-chip) race — 2026-10-07

1. **Race-day officiating** (in progress on `officiating`): rider detail with
   crossings (void / move / insert), pull and flag finish, ruling history with
   Undo, Publish, results CSV export and printable results.
2. **Hardening:** run the hub in production mode, back up `storage/` during the
   event, session expiry (see below).
3. **Engine:** "no finish crossing" suggestion; fewer early-lap false alarms
   (field comparison / pace-scaled fallback — see Results engine).
4. **Registration on Starts:** "N of M checked in" per race; DNS suggestions.
5. Operational: dedicated router (fixed hub IP), power, phones paired and
   certificates installed the day before, console built before leaving, a paper
   backup at the line, a dry run.

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

### Course events (checkpoints on a point-to-point course)
- **Done (2026-10-10):** an event can be a course event with checkpoints (name, distance,
  optional cutoff), a finish distance and cutoff; phones are paired to a checkpoint;
  Results shows splits, the Course view shows who has passed where, and problems flag
  missed checkpoints, overdue riders and missed cutoffs. A registered rider never seen
  after the start gets one overdue problem offering DNS (no cutoff problem).
- **Left:**
  - splits within laps (checkpoints on a laps course);
  - out-and-back / repeated checkpoints;
  - individual-start time trials;
  - fixed-time races (most laps in N hours);
  - per-race courses (short and long course in one event);
  - clock-time cutoffs resolve on the event's date, so a race past midnight needs the elapsed (+h:mm) form;
  - `bin/replay-race --check/--fit` don't apply to course datasets.
- **Raised:** 2026-10-07.

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

### Concerns from the flag-out / replay review (2026-10-07)
Done (2026-10-07, branch flag-out-hardening): the leader exemption skips DNF/DNS/DSQ and
pulled riders and is shown on the flag chip; an "Overdue — mark DNF?" problem once the
finish is open; the Capture flag is stamped when Flag out was first pressed.

Later:
- The lap count's finish can still be opened by a DNF/DSQ rider's crossing (only the
  flag-out leader skips riders out of the race).
- "Current wave" can pick wrong: overlapping waves (newer wins), races that finish on their
  own count as waves of one, and it groups by scheduled time while the engine also splits
  off races that started after the finish opened.
- A timer can flag out a whole wave; only a chief can undo it.
- No sanity checks on flag times (in the future, before the wave started, typos in "Flag out at…").
- Waves are still "same scheduled time": a mistyped time silently moves a race out of its
  wave (lap count, flag). The user asked for a foreign key; deferred.
- Flag out on a race header flags the whole wave; the History line names one race.
- Wave view groups races that finish on their own (Running Race) into the scheduled wave.
- Timers can flag out on Capture but don't see the button on Results.
- Replay checks are partly circular: flag times, start offsets and arming delays are fitted
  from the results they're checked against.
- Replays are too clean: one device, perfect hundredths, in order, historic timestamps (live
  "now" behaviour never runs). Nothing tests whether a person can tap a bunch sprint.
- The replay check ignores lap positions, gaps, other statuses; one rider's error (386)
  shows as 10 lines.
- Fitter edge cases (one-rider waves, ties like 330/402, crash laps); no test for
  script/results-pdf-to-csv (sample PDFs aren't committed).
- Cascade Locks 1's date (2026-09-27) is a guess; replays pile up events in dev with no cleanup.
- Flag out lacks tests with a finish flag or a pull on the same rider.
- Split big branches into reviewable PRs; get an independent review of the Flag out engine change.

### Real-race replay (after the clean replay, 2026-10-07)
- A messy replay for officiating rehearsal: missed taps, wrong bibs, no-bib taps, a phone
  offline for 10 minutes, on top of the real anomalies (46, 422, 386, 70).
- Several phones and bursty sync, to load-test the console, Results and Problems.
- An "officiate" option that pulls the riders who stopped before the finish, so the
  check compares statuses too.
- **Chip timing:** start-line reads as a wave rolls off (gun to arming, 1–2 min), and a
  per-race "ignore reads for N seconds after the start" rule. Without it, moving a start
  back to the gun turns every start-line read into a ~20 s lap 1.

### Officiating follow-ups (after part 1, 2026-10-07)
- Open the racer panel from Problems and Capture rows (today: Results and History only).
- Redo (undoing an undo). Today an undo can't be undone; re-apply the fix instead.
- Voiding an inserted crossing should use the already-undone guard (two chiefs → two "Undo: Insert…" lines).
- Hide "Finish here" / "Pull here" on ignored crossings (before start, after pull/finish), or refuse them on the hub; today they record a fix that does nothing.
- Racer panel fix list: show when an undo happened ("undone by X at T").
- History: "Show more" appears at exactly 50 entries; debounce the search box.
- Keyboard access to Results rows (open the racer panel with Enter), since DNF/DNS/DSQ now live in the panel.
- "Pull now" uses the console's clock, not hub time; "Insert missed crossing before" a pre-start crossing pre-fills a time the hub refuses.

### Ops console / API plan
- **Sessions:** expire after 12–24 h; `updateOfficial(id, active, role, pin)`
  (admin); invalidate existing sessions on deactivation or PIN change (check in
  `CurrentOfficial` and the cable connection). Today a copied cookie keeps
  working after sign-out and there's no way to deactivate an official via the API.
- **Pairing QR URL** (partly done): it uses the address the console is open on;
  the dialog and runbook say to open the console on the hub's LAN address. Could
  instead build it from `LocalCa.lan_ips` + `HUB_TLS_PORT` so it can't be wrong.
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
- Suggestion `fix` hashes are *templates*: `flag_finish` lacks `capture_id`,
  unassigned-capture fixes have `bib: nil`. The console must complete them before
  creating a ruling.

### Sync + capture plan
- **Before any tablet/venue test:** run the hub in production mode (see "Run the
  venue hub in production mode") and constrain the root CA (nameConstraints).
- Bound device name length (pairing).
- Consider storing each raw device entry so hash chains can be re-verified later.

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
- Mobile capture review minors (2026-10-07):
  - `pushNow` follow-up pushes can overlap (harmless: the hub is idempotent); chain them and never lower the local ack.
  - Correcting or deleting on the phone has no error message if the write itself fails.
  - A remembered Results filter for a since-deleted race shows an empty page with no chip; drop unknown race ids.
  - Phone rows show times with the current clock offset rather than each entry's own.
  - Console devices ("Console – name") are listed in the Phones panel; hide them or label them.
  - A phone's own delete (capture_void) can't be undone from the console's ruling history.
