# Event & Race Setup Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans (chosen: inline) to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Races carry their own category, age group, gender, schedule and lap expectations; "finish with leader" is an event default each race can override; admins create and edit events and races in a console Setup screen.

**Architecture:** Start groups and categories go away. The engine's input becomes a flat list of races (`scheduled_at_ms`, effective `finish_with_leader`, `expected_laps`); it forms cohorts itself (finish-with-leader races with the same scheduled start; everyone else alone) and runs the existing finish logic per cohort. Rails models, API and console follow. Dev/test databases are reset (no production data).

**Tech Stack:** unchanged (Rails 8.1, graphql-ruby, React 19 + MUI 9 + Apollo 4, Playwright).

**Spec:** `docs/superpowers/specs/2026-10-03-event-race-setup-design.md`

**Granularity note:** the plan's author is also its (inline) executor, so tasks give exact behavior, interfaces and test cases rather than verbatim code; each step is still test-first.

## Global Constraints

- Disciplines: `cyclocross`, `mountain_bike` (`xco`, `xcc`, `xc_marathon`, `enduro`, `downhill`), `road` (`road_race`, `criterium`, `time_trial`, `hill_climb`), `gravel`, `run`. finish_with_leader default: on for cyclocross, mountain_bike/xcc, road/criterium; off otherwise.
- Race gender: `men` | `women` | `open` (labels Men / Women / Open). Default name = `[category, age_group, gender label]` non-blank, joined by spaces; `name_override` wins when present. Names unique per event.
- Cohort = effective-finish-with-leader races sharing `scheduled_at_ms`; all others are cohorts of one.
- Cohort lap count = latest active `set_lap_count` (`{race_id, laps}`) for any race in the cohort; else agreed `expected_laps`; else nil.
- A race's start = its latest active `set_race_start`; there is no group gun any more.
- All setup mutations admin; `setRaceStart`, `setLapCount`, `startRaces`, `unstartRace` chief.
- Keep the review-queue, standings, publishing and sync behavior unchanged.

## Review Focus

1. **Two finish-with-leader races at 6 pm and one non-finish-with-leader race at 6 pm** — the first two finish together, the third finishes on its own leader. (Task 1 engine test, Task 4 e2e.)
2. **Renaming a race to a name another race already has** — refused with a clear error. (Task 2.)
3. **Changing a sub-discipline the discipline doesn't allow** (e.g. road + xcc) — refused. (Task 2.)
4. **Deleting a race that has registrations or has started** — refused. (Task 3.)
5. **Setting the lap count on one race of a cohort** — every race in that cohort shows the new count. (Task 3.)

---

### Task 1: Engine — races instead of start groups; cohorts

**Files:** `packs/results/lib/results/{types,engine,group_scorer→cohort_scorer,ruling_shape}.rb`, `packs/results/test/support/{fixture,helpers}.rb`, all `packs/results/test/fixtures/races/*.yml`, `packs/results/test/*_test.rb`.

**Interfaces:**
- `Results::RaceDef(id, scheduled_at_ms, finish_with_leader, expected_laps)`; `Input(races:, entrants:, captures:, bib_assignments: [], rulings: [], now_ms: 0, config:)` (no `start_groups`).
- `Results::CohortScorer.new(input, races, resolved).call -> Scored(races, lap_count, finish_open_at, riders, race_results)` (replaces GroupScorer).
- `RulingShape`: no `set_group_start`; `set_lap_count` keys `race_id`, `laps`.
- Fixture YAML: `races: [{id, scheduled (s, default 0), fwl (default true), laps (optional), start (s, optional → set_race_start ruling "start-<id>")}]`; no `start_groups`. Helper `setup_yaml(bibs:, laps: 3, start: 0, fwl: true)`.

- [ ] Rewrite fixture loader + helper + all fixtures/tests to the new format (mechanical: `finish_rule fixed_laps N` → `laps: N`; timed → no laps; `gun` → `start`; `set_lap_count start_group_id: g1` → `race_id: r1`; waves fixture → three races, same scheduled, starts 1000/1030/1060).
- [ ] New failing tests (`standings_test.rb`):
  - two fwl races at the same scheduled time + one non-fwl race at that time: the non-fwl race's finish opens on its own leader (its riders aren't finished by the other races' leader).
  - fwl races with different scheduled times are separate cohorts.
  - cohort lap count from agreed `expected_laps`; disagreeing `expected_laps` → `lap_count` nil; `set_lap_count` on one race of a cohort applies to all of them.
- [ ] Implement; run `bundle exec bin/test-results` (all golden + property tests green).
- [ ] Commit.

### Task 2: Rails data model

**Files:** migration `db/migrate/20261003000002_event_race_setup.rb`; `packs/events/app/models/{event,race,registration,eligibility,registration_import,disciplines}.rb`; delete `start_group.rb`, `category.rb`; `packs/timing/app/models/{ruling,results_snapshot}.rb`; `lib/race_simulator*.rb`; `test/support/build_helpers.rb`; model tests.

**Interfaces:**
- `Disciplines::TABLE` (discipline → sub-disciplines), `Disciplines.default_finish_with_leader(discipline, sub)`, `Disciplines.valid?(discipline, sub)`.
- `Event`: `location`, `discipline`, `sub_discipline`, `finish_with_leader` (defaulted on create from Disciplines when not given), `has_many :races`.
- `Race`: `category`, `age_group`, `age_min`, `age_max`, `gender`, `name_override`, `scheduled_at_ms`, `expected_duration_ms`, `expected_laps`, `finish_with_leader` (nullable); `#name`, `#default_name`, `#effective_finish_with_leader`, `#cohort` (races of the event in its cohort, including itself).
- `Eligibility.warnings(rider:, race:, event:)` (gender + age only).
- `RegistrationImport`: `race` column matched against race names.
- `Ruling::KINDS`: no `set_group_start`; `set_lap_count` → `race_id laps`.
- `ResultsSnapshot.for` emits the new `RaceDef`.
- Simulator: `RaceSimulator.specs_for(races)`; `Writer#start_races(races, at_ms:)`, `Writer#set_lap_count(race, laps)`; `Demo.create!` makes a cyclocross event with three races scheduled together.
- Build helpers: `create_event(**)`, `create_race(event:, **)` (defaults: category "Cat 3", gender men, scheduled now-ish fixed time).

- [ ] Failing model tests: discipline/sub-discipline validation; finish_with_leader defaults per table; default name and override; name uniqueness within an event (case-insensitive); effective finish_with_leader; cohort membership; eligibility gender/age; CSV import by race name.
- [ ] Migration: rename `events.venue`→`location`; add discipline (default `cyclocross` for existing rows), sub_discipline, finish_with_leader; races add new columns, drop `start_group_id`/`category_id`; drop `start_groups`, `categories`. Reset dev DB (`bin/rails db:reset`) — test DB rebuilt from schema.
- [ ] Implement models, snapshot, ruling kinds, simulator, helpers; update all Rails tests (API tests may be left failing until Task 3 only if they exercise removed types — fix them in Task 3).
- [ ] `bin/rails test test/models test/lib`, engine suite, packwerk, zeitwerk green. Commit.

### Task 3: API

**Files:** `packs/api/app/graphql/types/{event,race,discipline}_type.rb`, `query_type.rb`, `mutation_type.rb`; mutations `create_event`, `update_event`, `create_race`, `update_race`, `delete_race`, `set_lap_count`, `set_race_start`; delete `start_group_type`, `category_type`, `create_category`, `create_start_group`, `update_start_group`, `fire_start`; API integration tests.

**Interfaces:**
- `Event { id name date location discipline subDiscipline finishWithLeader races registrations }`, `Race { id name nameOverride defaultName category ageGroup ageMin ageMax gender scheduledAtMs expectedDurationMs expectedLaps finishWithLeader finishWithLeaderOverride }`, `disciplines { id label subDisciplines { id label finishWithLeader } finishWithLeader }`.
- `createEvent(name, date, location, discipline, subDiscipline, finishWithLeader)`, `updateEvent(id, …)`; `createRace(eventId, category, ageGroup, ageMin, ageMax, gender, nameOverride, scheduledAtMs, expectedDurationMs, expectedLaps, finishWithLeader)`, `updateRace(id, …)` (explicit `null` clears optional fields), `deleteRace(id)` (refused with registrations or a start); `setLapCount(raceId, laps)` → one ruling per race in the cohort, returns `rulings`; `setRaceStart(raceId, atMs)`.
- [ ] Failing integration tests for each mutation, permissions (admin vs chief), deleteRace refusals, cohort lap count, disciplines query; update existing API tests (race_day, start_races, standings, rulings, privacy, import) to the new setup.
- [ ] Implement; full Rails suite green on SQLite and Postgres (`PARALLEL_WORKERS=1`). Commit.

### Task 4: Console

**Files:** `frontend/src/queries.ts`, `route.ts` (+ `setupHref`, `setup` view), `views/{EventNav,StartScreen,RaceScreen,Events,SetupScreen,EventDialog,RaceDialog}.tsx`, `frontend/e2e/{seed.rb,simulate.rb,race.spec.ts,setup.spec.ts}`.

- [ ] Failing unit tests: route parse/href for `/console/event/<id>/setup`; `defaultRaceName(category, ageGroup, gender)` mirrors the Rails rule; `cohortLapWarnings(races)` lists fwl races sharing a schedule with different expected laps.
- [ ] Failing e2e `setup.spec.ts`: admin creates a CX event from the Events list (finish with leader pre-checked), adds "Cat 3 / Masters 35+ / men" (default name shown), "Women Open" via override, and "Novice / open" with finish with leader Off, all at the same time; a same-name save is refused with the API's message; Start all; set laps 2 on the Race screen; simulate; the Novice race finishes on its own leader.
- [ ] Implement Setup screen, dialogs, tab (admin-only), Start/Race screen updates (no start groups; lap count per race, shown per race header). Update `race.spec.ts`, seed, simulate.
- [ ] `npm test`, typecheck, e2e green; full Rails/engine suites green. Commit.
