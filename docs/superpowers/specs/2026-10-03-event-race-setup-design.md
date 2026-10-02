# Event & Race Setup — Design

**Date:** 2026-10-03
**Status:** Draft for review
**Parent spec:** `docs/superpowers/specs/2026-10-01-hub-mvp-design.md` (replaces its §3.1 setup model and the start-group parts of §4.2)
**Approach:** small slice — the data model change plus a Setup screen for events and races. Registrations UI comes later.

## 1. Goal

An admin can create and edit an event and its races from the console, and the
results engine works from that setup: races carry their own category, age group,
gender, schedule and lap expectations, and "finish with the leader" is an event
default each race can override.

**Done when:** in a browser test, an admin creates a CX event, adds races (one with a
manual name override), sees default names built from category + age group + gender,
and the Start and Race screens work for those races — including two
finish-with-leader races scheduled at the same time finishing together, while a
race with finish-with-leader off finishes on its own.

## 2. Data model

### Event
| Field | Notes |
|---|---|
| name | required |
| date | required |
| location | replaces `venue` |
| discipline | required: `cyclocross`, `mountain_bike`, `road`, `gravel`, `run` |
| sub_discipline | optional; allowed values depend on discipline (below) |
| finish_with_leader | boolean, required; pre-filled from discipline + sub-discipline when the event is created; editable |
| timezone, age_rule | unchanged |

| Discipline | Sub-disciplines | finish_with_leader default |
|---|---|---|
| cyclocross | — | on |
| mountain_bike | `xco`, `xcc`, `xc_marathon`, `enduro`, `downhill` | on for `xcc` only |
| road | `road_race`, `criterium`, `time_trial`, `hill_climb` | on for `criterium` only |
| gravel | — | off |
| run | — | off |

### Race
| Field | Notes |
|---|---|
| category | optional free text ("Cat 3", "Pro", "Novice") |
| age_group | optional free text label ("Masters 35+", "U23") |
| age_min, age_max | optional integers — the age group's range, used for eligibility warnings |
| gender | required: `men`, `women`, `open` |
| name_override | optional; when blank the name is `category + age_group + gender label` joined by spaces, skipping blanks (e.g. "Cat 3 Masters 35+ Men"; "Novice Women"; "Open Women") |
| scheduled_at_ms | required |
| expected_duration_ms | optional |
| expected_laps | optional, positive integer |
| finish_with_leader | optional boolean override; `null` = inherit from the event |
| start time | the actual start: set by the Start screen (`startRaces`) or typed in Setup (`setRaceStart`); both record a `set_race_start` ruling, so it can be undone |

Gender label for the default name: men → "Men", women → "Women", open → "Open".
Names must be unique within an event.

### Removed
`StartGroup` and `Category` records, `set_group_start` rulings, `fireStart`,
`createStartGroup`, `updateStartGroup`, `createCategory`. There is no production data;
existing development and test databases are reset.

### Eligibility (registration warnings, still never a block)
- Gender: race `open` accepts anyone; otherwise rider gender must match.
- Age: rider's age (by the event's `age_rule`) within `age_min`/`age_max` when set.
- No ability-level check (category is free text).

## 3. Finishing (results engine)

- A race's **effective finish-with-leader** = its override, else the event's setting.
- **Cohorts:** finish-with-leader races with the **same scheduled start** form one
  cohort; every other race is a cohort of one.
- Within a cohort the existing finish logic applies unchanged: the first rider in the
  cohort to complete the lap count opens the finish; everyone in the cohort finishes on
  their next crossing (or an early flag); standings are still per race, timed from each
  race's own start.
- **Lap count of a cohort:** the latest active `set_lap_count` for any race in the
  cohort; otherwise the races' `expected_laps` if they all agree; otherwise "not set".
  `set_lap_count` payload becomes `{race_id, laps}`; the console's lap-count control
  sets it for the race's whole cohort (one ruling per race in the cohort).
- Races in a cohort with different `expected_laps` show a warning in Setup.
- Expected duration is informational in this slice (shown in Setup and on the Race
  screen; no automatic lap-count suggestion yet).

## 4. API

- `Event` type: `location`, `discipline`, `subDiscipline`, `finishWithLeader`, `races`
  (ordered by scheduled start, then name). `startGroups` removed.
- `Race` type: `name` (effective), `nameOverride`, `category`, `ageGroup`, `ageMin`,
  `ageMax`, `gender`, `scheduledAtMs`, `expectedDurationMs`, `expectedLaps`,
  `finishWithLeader` (effective), `finishWithLeaderOverride`.
- Mutations (admin): `createEvent`, `updateEvent`, `createRace`, `updateRace`,
  `deleteRace` (refused once the race has registrations or a start). Chief:
  `setRaceStart(raceId, atMs)` (manual start time), `setLapCount(raceId, laps)`
  (applies to the cohort). `startRaces` / `unstartRace` unchanged.
- `disciplines` query: the discipline / sub-discipline table above with defaults, so
  the console doesn't hard-code it.
- CSV import: the `category` column becomes `race`, matched against race names
  (case-insensitive).

## 5. Console

- Event tabs become **Setup | Start | Race**; Setup is shown to admins only.
- **Events list:** "New event" button → dialog (name, date, location, discipline,
  sub-discipline, finish with leader pre-filled from the choice).
- **Setup screen** (`/console/event/<id>/setup`):
  - Event details form (same fields), Save.
  - Races table in scheduled order: name, scheduled, gender, laps / duration, finish
    with leader, start time; "Add race" and per-row Edit (dialog) and Delete.
  - Race dialog: category, age group (+ min/max age), gender, name (shows the default
    as placeholder; typing overrides it; clearing returns to the default), scheduled
    start, expected duration (minutes), expected laps, finish with leader (Inherit /
    On / Off), start time (manual entry, chief+).
  - Warning when finish-with-leader races sharing a scheduled start have different
    expected laps.
- **Race screen:** shows each race (no start-group tabs); lap count control per race,
  applied to its cohort.

## 6. Out of scope (later)

Registrations / CSV import UI, officials and devices screens, automatic lap-count
suggestions from expected duration, time trials (individual starts), copying an
event's races from a template.

## 7. Testing

- Engine: golden files rewritten for the new input (cohort by scheduled start + flag);
  new cases: finish-with-leader cohort across categories/genders, a non-finish-with-leader
  race at the same scheduled time finishing on its own, cohort lap count from
  `expected_laps` and from `set_lap_count`, disagreeing expected laps → not set.
- Rails: model validations (discipline/sub-discipline pairs, name uniqueness, default
  name), mutations and permissions, CSV import by race name, eligibility.
- Browser: the "done when" flow in §1; existing Start / Race / sign-in tests updated.
