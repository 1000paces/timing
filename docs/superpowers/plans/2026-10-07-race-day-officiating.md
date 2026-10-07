# Race-Day Officiating (part 1) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Chiefs fix a racer's race from a racer panel (void, move, insert, pull, flag finish, undo), everyone sees a read-only lap summary with per-lap positions, and History lists and undoes every ruling.

**Architecture:** The results engine exposes, per racer, every crossing it saw with what it counted as, per-lap positions, and the pull and finish markers. The API adds a `racer` query, named fix mutations writing rulings, and readable History. The console adds a racer panel on Results and a History view on Problems.

**Tech Stack:** unchanged (Rails 8.1 packs, pure-Ruby engine, graphql-ruby, React 19 + MUI 9 + Apollo 4, Playwright).

**Spec:** `docs/superpowers/specs/2026-10-07-race-day-officiating-design.md`

**Granularity note:** the author is also the inline executor, so tasks give exact behaviour, interfaces and test cases rather than verbatim code. Each step is test-first.

## Global Constraints

- Crossing kinds: `lap`, `finish`, `duplicate`, `before_start`, `after_finish`, `after_pull`.
- Lap positions: for lap N, racers in the same race with ≥ N counted crossings, ranked by the time of their N-th crossing; ties broken by crossing ref.
- Fix mutations need chief or above; `racer` and History are readable by any signed-in official.
- Refusal messages, verbatim:
  - "Bib X is not registered in this event"
  - "That crossing isn't part of this event"
  - "That crossing isn't one of bib X's" (flag finish)
  - "A crossing can't be inserted before the race started"
  - "That fix is already undone"
  - "An undo can't be undone"
- Voiding an inserted crossing = reverting its `insert_capture` ruling. Moving is captures only.
- History descriptions use the event's `timezone` for times (HH:MM:SS).
- The racer panel's `?racer=<bib>` is kept in the address. The standings row ⋮ is removed (its actions move to the panel header).

## Review Focus

1. **Undo of a fix that later fixes depend on** (e.g. undo a move after the racer was flagged finished on that crossing). The engine just recomputes; the flag on a crossing the racer no longer has is ignored (existing rule). Pin it with an engine test. (Task 1)
2. **Inserting a crossing at exactly the time of an existing tap** (within the debounce). The insert or the tap shows as `duplicate`, not two laps. (Task 1)
3. **Pulling at a time between crossings.** Crossings after the pull are `after_pull`, and positions only cover counted laps. (Task 1)
4. **Two chiefs undoing the same ruling at once.** The second gets "That fix is already undone", not a revert-of-revert. Checked under the event lock, as acceptSuggestion does. (Task 2)
5. **A racer panel for a bib not registered (or removed) in the event.** The panel shows "No racer with bib X in this event", not a crash. (Tasks 2 and 4)

---

### Task 1: Engine — crossings, lap positions, markers

**Files:**
- `packs/results/lib/results/resolver.rb`: `Resolved` gains `dropped` (bib → crossings dropped by the debounce, each with `kept_ref`).
- `packs/results/lib/results/types.rb`: `CrossingView(ref, at_ms, inserted, kind, lap, lap_ms)`; `RacerResult` + `crossings`, `lap_positions`, `pull_at_ms`, `finish_ref`.
- `packs/results/lib/results/cohort_scorer.rb` / `standings.rb`: build the views and positions.
- Tests: new `packs/results/test/racer_detail_test.rb`. Golden files must stay unchanged; if the golden comparison includes `RacerResult` fields, update the comparer to ignore the new ones.

**Interfaces (produces):**
- `RacerResult#crossings -> [CrossingView]`, in time order. It includes pre-start crossings for the bib, debounced duplicates, and after-finish / after-pull crossings.
- `RacerResult#lap_positions -> [Integer]`, one per counted crossing.
- `RacerResult#pull_at_ms -> Integer?` and `RacerResult#finish_ref -> String?`.

- [ ] Failing tests (fixture YAML helpers, as `standings_test.rb`):
  - kinds for a racer with a tap before the start, three laps, a duplicate 3 s after lap 2, a finish, and a tap after the finish;
  - lap times on `lap` / `finish` rows;
  - lap positions for three racers, including a racer with fewer laps and a tie broken by ref;
  - a pulled racer: crossings after the pull are `after_pull`, and `pull_at_ms` is set;
  - a flagged finish: `finish_ref` and the following `after_finish`;
  - Review Focus 1: a flag on a crossing moved away is ignored;
  - Review Focus 2: an insert within the debounce of a tap shows one `duplicate`;
  - Review Focus 3: a pull between crossings.
- [ ] Implement. Run `bundle exec bin/test-results` (all golden pass unchanged) and `bin/rails test`. Commit.

### Task 2: API — racer query and fix mutations

**Files:**
- `packs/api/app/graphql/types/`: new `racer_detail_type.rb` and `racer_crossing_type.rb`; `query_type.rb` (`racer`).
- `packs/api/app/graphql/mutations/`: new `void_crossing.rb`, `move_crossing.rb`, `insert_crossing.rb`, `pull_racer.rb`, `flag_finish.rb`; `revert_ruling.rb` (guards).
- `mutation_type.rb`.
- New `packs/api/app/graphql/ruling_describer.rb` (shared with Task 3; here only for the racer's `rulings`).
- Tests: new `test/integration/api/racer_detail_test.rb` and `racer_fixes_test.rb`.

**Interfaces:**
- `racer(eventId, bib) -> RacerDetail { bib name race { id name } status place laps elapsedMs gapLapsDown gapMs startAtMs pullAtMs finishRef crossings { ref atMs inserted kind lap lapMs source } lapPositions rulings { id kind description officialName createdAtMs undone undoneBy undoneAtMs } }`.
  - It's null with error "No racer with bib X in this event" when the bib isn't registered (Review Focus 5).
  - `source` is the device name, or "inserted by <official>".
- Mutations (each returns `{ ruling { id } errors }`):
  - `voidCrossing(eventId, ref)`;
  - `moveCrossing(eventId, captureId, bib)`;
  - `insertCrossing(eventId, bib, atMs)`;
  - `pullRacer(eventId, bib, atMs)`;
  - `flagFinish(eventId, bib, ref)`.
- `revertRuling(rulingId)` refuses an undone ruling and a revert, under `event.with_lock` (Review Focus 4).
- `RulingDescriber.describe(ruling, event:, names:) -> String`, using the Global Constraints formats.

- [ ] Failing tests:
  - `racer` returns crossings with kinds, source and positions, and is readable by a timer;
  - an unknown bib gives the error;
  - each mutation: a timer is refused; the success path writes the expected ruling kind and payload; each refusal message from Global Constraints;
  - voiding an inserted crossing writes a `revert` of its insert;
  - a revert of an undone ruling, and of a revert, is refused;
  - the racer's `rulings` include `undone` / `undoneBy`.
- [ ] Implement. Rails suite on SQLite and Postgres, packwerk, zeitwerk. Commit.

### Task 3: API — History

**Files:** `packs/api/app/graphql/types/ruling_type.rb` (description, bib, undone, undoneBy, undoneAtMs), `query_type.rb` (`rulings(eventId, search, limit, offset)`), `ruling_describer.rb`. Test: new `test/integration/api/history_test.rb`.

- [ ] Failing tests:
  - the descriptions for each kind, in the event's time zone ("Void crossing 10:42:09 (bib 101)", "Insert crossing 10:48:11 for bib 101", "Pull bib 205 at 10:51:00", "Lap count 3 for Masters 35+ Men", "Start Women Open at 10:00:30", "Bib 101 → 102 for crossing 10:42:05", "Finish bib 101 at 10:54:20", "DNF bib 101", "Undo: <description>");
  - search by bib and by racer name;
  - limit / offset;
  - `undone` with `undoneBy` name and time.
- [ ] Implement. Rails suite passes. Commit.

### Task 4: Console — racer panel on Results

**Files:**
- `frontend/src/queries.ts` (RACER, fix mutations);
- new `frontend/src/views/RacerPanel.tsx`, `CrossingMenu.tsx`, `BibPickerDialog.tsx` (Move), `TimeDialog.tsx` (Insert at / Pull at);
- `RaceScreen.tsx` / `Standings.tsx` (row click opens the panel; `?racer=`; remove the row ⋮);
- `RacerStatusMenu.tsx` (reused in the panel header);
- new `frontend/src/racerPanel.ts` (pure helpers: `midpoint(a, b)`, `kindLabel(kind)`, `positionLabel(n)` → "3rd") with tests.
- e2e: new `frontend/e2e/officiating.spec.ts`.

- [ ] Failing unit tests for the helpers.
- [ ] Failing e2e (on the E2E CX race after `simulate.rb`, or a dedicated seed):
  - a chief clicks a racer row and the panel shows laps with positions;
  - **Void** a duplicate (seed one: a second tap 3 s after a lap) — it stays greyed "duplicate", or disappears once voided;
  - **Insert missed crossing before** a lap — the lap count +1, positions update;
  - **Pull here** on one racer — status Pulled; **Finish here** on another — status Finished;
  - **Undo** the insert in the panel — laps back;
  - a timer opens the same racer — no ⋮, Insert, Pull or Undo;
  - `?racer=` survives a reload;
  - Review Focus 5: `?racer=999` shows "No racer with bib 999 in this event".
- [ ] Implement the panel per spec §4.1 (Drawer anchored right; full width under 600 px). Unit, typecheck and e2e pass. Commit.

### Task 5: Console — History on Problems

**Files:** `frontend/src/queries.ts` (RULINGS), `views/ProblemsScreen.tsx` (view switch Open problems | History), new `views/HistoryList.tsx`, e2e additions in `officiating.spec.ts`.

- [ ] Failing e2e:
  - History lists the earlier fixes with descriptions and who made them;
  - search by bib narrows it;
  - **Undo** the pull from History (confirm) — the entry is struck through with "undone by", and the racer is back to Racing on Results;
  - clicking a racer in History opens the racer panel on Results.
- [ ] Implement per spec §4.2 (50 at a time, Show more). Unit, typecheck, all e2e, Rails and engine suites pass. Commit. Add spec §5 out-of-scope items to `docs/TODO.md` (except part 2, which is the next slice).
