# Course events: point to point and single loop, with checkpoints

## Goal

Time races that ride a course once (point to point or a single loop) instead of laps,
with timing points along the way. Checkpoints serve two jobs:

- **Splits** in the results: each racer's time at each checkpoint.
- **Tracking** on race day: who has passed where, who is overdue, who skipped a
  checkpoint, who missed a cutoff.

Laps events (cyclocross, crits, XCC) work exactly as today.

## Decisions

- **Format is per event.** `events.format` is `laps` (default) or `course`. Every race in
  a course event rides the same course; races differ only in start time.
- **Single loop and point to point are the same format.** For timing both are start →
  checkpoints → finish; whether the finish sits next to the start only matters for where
  devices go. The Event screen labels the format "Point to point / single loop".
- **Each checkpoint is passed once.** No out-and-back or repeated spots, so a checkpoint
  is both a physical spot (where a device sits) and a position on the course.
- **Checkpoints are optional.** A course event with no checkpoints is start → finish.
- **Cutoffs are optional, per checkpoint, stored as a clock time.** The official enters
  either a clock time ("2:30 pm") or elapsed from the start ("6:30"); elapsed is converted
  from the earliest race start in the event and shown back as a clock time. Events with
  cutoffs start everyone together, so there is no per-race allowance.
- **Device location is set either way.** A pairing token can carry a checkpoint; the
  phone can change it; an official can change it on the Devices screen.

## Data model

| Table / column | Notes |
|---|---|
| `events.format` | `laps` \| `course`, default from the discipline: gravel, road race, run, XC marathon → `course`; everything else → `laps`. Editable on the Event screen. |
| `checkpoints` | `id`, `event_id`, `position` (1…n, unique per event), `name` ("Aid 1", "Mile 37"), `distance_km` (optional), `cutoff_at_ms` (optional). The finish is **not** a row: it is implicit and always last. |
| `devices.checkpoint_id` | Optional; null means the finish line. |
| `pairing_tokens.checkpoint_id` | Optional; copied to the device on redeem. |
| `device_entries.checkpoint_id` | Captures only; null means the finish. |

Checkpoints can be added, renamed, reordered and deleted from the Event screen until a
capture references one; after that a referenced checkpoint can be renamed or have its
distance or cutoff edited, but not deleted, and referenced checkpoints keep their order
among themselves (unreferenced ones can still be added, deleted or moved around them).

## Capture and sync

- **Phone:** the capture screen header shows the current location ("Aid 2" / "Finish").
  Tapping it opens a picker listing the event's checkpoints plus Finish. The choice is
  stored on the phone and stamped on each capture as `checkpoint_id`.
- **Hash compatibility:** `DeviceHash` omits null fields, so finish captures (no
  `checkpoint_id`) hash exactly as today; older phones and logs stay valid.
- **Location changes are logged** as a new device log entry `kind: "location"`
  (`checkpoint_id`, nullable), so the audit trail shows when a phone moved. Ingest accepts
  it; the engine ignores it (each capture already carries its own location).
- **Official changes:** `setDeviceCheckpoint(deviceId, checkpointId)` (chief). The sync
  pull response includes the device's assigned checkpoint and the event's checkpoint
  list; when the hub's assignment changed since the phone last saw it, the phone adopts it
  and logs a `location` entry. A change on the phone is pushed through the log and updates
  `devices.checkpoint_id`, so the last change from either side wins.
- **Ingest validation:** a capture's `checkpoint_id` must belong to the device's event,
  else the batch is rejected (as with any malformed entry today).

## Engine

Input gains the event's checkpoints and a format:

- `RaceDef.course`: nil for laps races; for course races an ordered list of
  `Checkpoint(id, position, distance_km, cutoff_at_ms)`.
- `Capture.checkpoint_id` (nil = finish).

A new scorer, `CourseScorer`, handles course races; `CohortScorer` keeps laps races.
Shared pieces (debounce, bib assignment, voids, statuses, pulls, inserts) are reused.

**Crossings.** A racer's effective crossings (after bib fixes, voids, inserts, debounce
per checkpoint) are grouped by checkpoint. At each checkpoint the **first** crossing at or
after the race start counts; later ones are duplicates. Crossings before the start are
`before_start`. The first finish crossing finishes the racer; crossings anywhere after it
are `after_finish`.

**Results.**

- Finished racers are placed by elapsed time (finish − race start), from the gun.
- Racers still out are listed after the finishers, ordered by furthest checkpoint
  reached, then earliest time there. Status `racing`.
- DNF / DNS / DSQ / pull behave as today. A pull `at_ms` stops counting crossings after it.
- Finish-with-leader, lap count and Flag out do not apply; the API returns null for them
  and the console hides those controls for course events.

**Splits.** `RacerResult.splits`: one entry per checkpoint plus the finish —
`Split(checkpoint_id, at_ms, elapsed_ms, segment_ms, ref, inserted)` with nils where the
racer has no crossing. `segment_ms` is from the previous checkpoint the racer was seen at
(or the start).

**`insert_capture`** gains an optional `checkpoint_id` (absent = finish), so a missed
checkpoint can be filled in by an official.

## Problems (suggestions)

All use the existing suggestion → fix → ruling flow and the Problems screen.

| Kind | Raised when | Fix offered |
|---|---|---|
| `missed_checkpoint` | A racer has a crossing at a later checkpoint or the finish but none at an earlier checkpoint. | `insert_capture` at that checkpoint, time interpolated between the neighbouring crossings by distance (or the midpoint without distances). The chief can dismiss (missed tap) or rule DSQ by hand. |
| `overdue` (course) | A racer is still out and `now` is more than 1.5× their expected segment time past their last crossing. | `dnf`; or `dns` for a racer with no crossings at all (never started), who gets no `cutoff` problem. |
| `cutoff` | A checkpoint's cutoff has passed and a racer still out has no crossing there, or a racer (still out or finished) crossed it after the cutoff. | `pull` at the cutoff time. |

**Expected segment time** to the next checkpoint: the racer's own pace (time per km over
their crossings so far) × the segment distance when distances are set; otherwise the
median of other racers' times on that segment in the same race (falling back to the whole
event), once at least 3 have ridden it. With neither, no overdue suggestion is raised.

Keys follow the existing pattern: `missed_checkpoint:#{bib}:#{checkpoint_id}`,
`overdue:#{bib}:#{last.ref}`, `cutoff:#{bib}:#{checkpoint_id}`.

## Console

- **Event screen:** a Format select (Laps / Point to point or single loop). For course
  events, a Checkpoints list: name, distance, cutoff (clock or elapsed entry), add,
  reorder, delete. Finish is shown last, fixed.
- **Devices screen:** each device's location, with a select to change it; the pairing
  dialog has an optional location.
- **Race screen (course events):**
  - **Results view:** place, bib, name, one column per checkpoint plus Finish (clock time;
    segment and elapsed on hover/expand), total time. Missing splits show "—".
  - **Course view** (the where-is-everyone board), beside Results: per checkpoint, how many
    riders have passed and how many are still to come, with the cutoff; below, the riders
    still out with last checkpoint, time there, next checkpoint and ETA. Overdue and
    cutoff riders are highlighted.
- **Racer panel:** the list of checkpoints with time, segment and elapsed, inserted ones
  marked.
- **Capture screen (console):** shows the device location as on the phone.

## Testing

- **Engine** (`packs/results/test`): matching per checkpoint, duplicates, before start and
  after finish, placing, ordering racers still out, splits and segments, inserts at a
  checkpoint, each of the three problems including the no-distance and too-few-riders
  cases, pulls at a cutoff.
- **API**: checkpoints CRUD and the lock once referenced, `setDeviceCheckpoint`, pairing
  with a checkpoint, splits and course fields in standings, cutoff entry as elapsed.
- **Sync**: captures with and without `checkpoint_id` hash and ingest; `location` entries;
  a foreign `checkpoint_id` rejects the batch; hub assignment reaches the phone.
- **Replay:** a synthetic course dataset in `lib/race_simulator/data/` (a gravel event,
  three checkpoints with distances, one cutoff) replayed through `bin/replay-race`, with a
  missed tap, an overdue rider and a cutoff miss, checked for places, splits and the
  expected problems.
- **E2E (Playwright):** set up a course event, pair a device at a checkpoint, capture
  there and at the finish, and see the splits and the Course view.

## Out of scope (to TODO)

- Splits within laps (checkpoints on a laps course).
- Out-and-back / repeated checkpoints.
- Individual-start time trials.
- Fixed-time races (most laps in N hours).
- Per-race courses (short and long course in one event).
