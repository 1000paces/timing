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

## Decisions needed

### Can officials change the lap count of a fixed-lap race mid-race?
- **Today:** `set_lap_count` only applies to `timed` start groups; on a
  `fixed_laps` group it is silently ignored.
- **Real-world need:** crits get shortened mid-race (crash, schedule).
- **Options:** (a) latest `set_lap_count` overrides any finish rule (one-line
  engine change + spec §4.2 amendment); (b) the ops console rejects it for fixed
  groups with a clear message, and shortening means editing setup.
- Either way it must not be silent. The ops console plan must handle this.
- **Raised:** 2026-10-01 (final review of plan 1).

## Carry into upcoming plans

### Ops console / API plan
- Clients must never set `Ruling#created_at_ms` ("latest wins" ordering depends
  on hub time) — the API sets it.
- Suggestion `fix` hashes are *templates*: `flag_finish` lacks `capture_id`,
  unassigned-capture fixes have `bib: nil`. The console must complete them before
  creating a ruling.
- Show last good standings with an error banner if computing results fails (spec §9).

### Sync + capture plan
- Device entries must take their `event_id` from the authenticated device, never
  from the payload (and add a model check that it matches `device.event_id`).
- Consider storing each raw device entry so hash chains can be re-verified later.
- Normalize empty-string bibs to nil on captures.
