# Race-Day Officiating (part 1: fixing what happened) — Design

**Date:** 2026-10-07
**Status:** Draft for review
**Builds on:** the results engine (rulings, cohorts), the Results and Problems
tabs, mobile capture.
**Part 2 (next slice):** Publish, CSV export, printable results.

## 1. Goal

Chiefs and admins can fix anything about a racer's race from the console:
- see every crossing;
- void, move or insert crossings;
- pull or flag the finish;
- undo any fix.

Everyone (timers included) can open a read-only summary of a racer's race.

**Done when:** in a browser test, a chief opens a racer from Results and:
- voids a duplicate tap;
- inserts a missed crossing (laps and per-lap positions update);
- pulls one racer and flags another's finish;
- undoes one fix in the racer panel and another from History.

A timer sees the same panel with no editing controls.

## 2. Engine (results)

Each racer's result (`RacerResult`) gains:
- **`crossings`**: every crossing the engine saw for the racer, in time order.
  Each is `{ref, at_ms, inserted, kind, lap, lap_ms}`. `kind` is one of:
  - `lap` — counted, with `lap` = 1..n and `lap_ms` since the previous counted
    crossing (or the start);
  - `finish` — the counted crossing that is the racer's finish;
  - `duplicate` — dropped by the debounce (within `debounce_ms` of the
    previous kept tap);
  - `before_start` — before the racer's race start (or the race has no start);
  - `after_finish` — after the finish crossing;
  - `after_pull` — after the racer's pull time.
- **`lap_positions`** — the racer's position in their race at the end of each
  counted lap. For lap N: racers in the race with at least N counted crossings,
  ranked by the time of their N-th crossing. Ties are broken by crossing ref, as
  in standings.
- **`pull_at_ms`** and **`finish_ref`** (null when not pulled / not finished).

The resolver keeps the crossings it drops as duplicates (time and ref), so they
can be shown. Today it keeps only an alias map.

## 3. API

### 3.1 `racer(eventId, bib)` query
Returns:
- the race (id, name), start time, status, place, laps, elapsed, gap;
- `pullAtMs`, `finishRef`;
- `crossings`: the engine's crossings plus `source`. The source is the capture's
  device name, or "inserted by <official>" for inserted crossings.
- `lapPositions`;
- `rulings`: the rulings affecting this bib (described as in §3.3).

Readable by any signed-in official. Privacy is as elsewhere (no birth date or
license for timers).

### 3.2 Fix mutations (chief and above)
Each records one ruling through `RulingWriter` and returns `{ruling, errors}`.

| Mutation | Ruling | Checks |
|---|---|---|
| `voidCrossing(eventId, ref)` | `void_capture` for a capture; for an inserted crossing, `revert` of its `insert_capture` | the ref belongs to the event |
| `moveCrossing(eventId, captureId, bib)` | `assign_bib` | bib registered in the event ("Bib X is not registered in this event"); captures only (an inserted crossing is undone and re-inserted instead) |
| `insertCrossing(eventId, bib, atMs)` | `insert_capture` | bib registered; atMs not before the race start ("before the race started") |
| `pullRacer(eventId, bib, atMs)` | `pull` | bib registered |
| `flagFinish(eventId, bib, ref)` | `flag_finish` (capture_id = ref) | the ref is one of the racer's crossings |
| `revertRuling(rulingId)` (exists) | `revert` | refuse an already-undone ruling ("already undone"), and refuse reverting a revert (no redo) |

### 3.3 History
`rulings(eventId)` (exists, newest first) gains:
- `officialName`;
- `description`: one readable line, e.g. "Void crossing 10:42:09 (bib 101)",
  "Insert crossing 10:48:11 for bib 101", "Pull bib 205 at 10:51:00",
  "Lap count 3 for Masters 35+ Men", "Start Women Open at 10:00:30",
  "Bib 101 → 102 for crossing 10:42:05". Times are in the event's time zone.
- `bib` (when the ruling concerns one racer);
- `undone` and `undoneBy` / `undoneAtMs`.

It takes optional `search` (bib or racer name) and `limit` / `offset`.

## 4. Console

### 4.1 Racer panel (Results)
- Clicking a racer's row on Results opens a right-hand panel (about 480 px; full
  width on narrow screens). `?racer=<bib>` keeps it open across refreshes; ✕ or
  Escape closes it. It updates live.
- **Header:** bib, name, race, status chip, place; then start time · laps · total
  time · gap. The header ⋮ (chief+) holds Mark DNF / DNS / DSQ / Clear. These
  move here from the standings row menu, which is removed.
- **Laps table**, one row per crossing: lap (or Finish, or —), crossed at, lap
  time, position, source.
  - Ignored crossings are greyed, with their reason chip.
  - ⋮ per crossing (chief+): Void · Move to bib… (bib box showing who the bib is)
    · Pull here · Finish here · Insert missed crossing before this one
    (pre-filled with the midpoint time, editable).
- **Below the table** (chief+): Insert crossing at… · Pull now.
- **This racer's fixes:** one line each (description · who · when) with Undo
  (confirm). Undone entries are struck through with "undone by X at T".
- Timers see the panel with no ⋮, insert, pull or Undo.

### 4.2 History (Problems tab)
- The Problems tab gets a view switch: **Open problems | History**.
- History lists every ruling, newest first: time · who · description · racer
  (opens the racer panel on Results), with Undo (chief+, confirm).
- Undone entries are struck through.
- There's a search box (bib or name) and "Show more" (50 at a time).

## 5. Out of scope
- Publish, CSV export and printable results (part 2).
- Opening the racer panel from Problems or Capture rows.
- Intermediate timing.
- Redo (undoing an undo).

## 6. Testing
- **Engine:**
  - crossing kinds (lap, finish, duplicate, before start, after finish, after
    pull);
  - lap positions, including ties and a racer with fewer laps;
  - `pull_at_ms` and `finish_ref`;
  - existing golden files unchanged.
- **API:**
  - the `racer` query;
  - each fix mutation's role and checks (registered bib, ref belongs to the
    event and racer, insert before start refused, already undone, revert of a
    revert);
  - voiding an inserted crossing reverts its insert;
  - History descriptions, `undone`, and search.
- **Browser:** the "done when" flow in §1, and a timer's read-only panel.
