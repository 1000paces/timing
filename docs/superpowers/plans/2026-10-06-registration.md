# Registration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A Registration tab where officials import BikeReg (and similar) exports with category mapping, add walk-ups, assign bibs from ranges, and check riders in.

**Architecture:** The events pack owns the registration rules: data, import analyze/run, bib assignment and check-in. The API exposes them with role checks; the capture-dependent removal guard lives in the API because the events pack can't see captures. The console adds a Registration tab, an import dialog, and bib-range fields on Setup.

**Tech Stack:** unchanged (Rails 8.1, graphql-ruby, React 19 + MUI 9 + Apollo 4, Playwright).

**Spec:** `docs/superpowers/specs/2026-10-06-registration-design.md`

**Granularity note:** as in the setup plan, the author is also the inline executor, so tasks give exact behaviour, interfaces and test cases rather than verbatim code. Each step is still test-first.

## Global Constraints

- Email and phone are never imported or stored.
- Bib is optional and unique within the event when present. Import never clears an existing bib with a blank.
- Re-import never removes registrations. Riders absent from the file are only reported as "not in file".
- Assign bibs never changes an existing bib, so running it twice assigns nothing.
- Bib ranges: positive integers, from ≤ to, no overlap within an event. The error names both owners, e.g. "Bib range 100–199 overlaps Masters 50+ Men (150–249)".
- Gender values `M`/`F`/`X`/`Male`/`Female` (any case) normalise to M/F/X.
- Roles:
  - admin: `analyzeImport`, `importRegistrations`, bib ranges.
  - chief: `registerRider`, `updateRegistration`, `setCheckedIn`, `removeRegistration`, `assignBibs`.
  - timer: read-only. Birth date, license and warnings stay hidden from timers.
- Event tabs: Setup | Registration | Starts | Capture | Results. The Registration route is `/console/event/<id>/registration`.

## Review Focus

1. **Re-importing a file where a rider's license is blank this time but was present before.** They should still match by name, not be duplicated. (Task 2)
2. **Two rows in one file for the same rider** (e.g. a race entry and a merchandise row, or two races). The merchandise row is skipped; two race rows give the second as a row error ("already registered in this event"), not a silent overwrite. (Task 2)
3. **Assign bibs when a range contains bibs typed by hand that belong to another race.** Those numbers count as used and are skipped. (Task 3)
4. **Moving a registration to another race with `updateRegistration`.** Eligibility warnings are recomputed, and the bib is kept. (Task 4)
5. **A CSV with Windows line endings, a BOM and quoted headers** (the real BikeReg export has all three). It must parse with the headers recognised. (Task 2 fixture)

---

### Task 1: Data model

**Files:**
- Migration: `db/migrate/20261006000001_registration.rb`.
- Models in `packs/events/app/models/`: `rider.rb`, `registration.rb`, `race.rb`, `event.rb`, `eligibility.rb`, plus a new `bib_range.rb` (shared validation) and a new `category_mapping.rb`.
- `test/support/build_helpers.rb`; model tests: a new `test/models/registration_model_test.rb`, and `rider_registrar_test.rb` / `event_race_setup_test.rb` updated to drop `ability_level`.

**Interfaces:**
- `Rider`: city and state added; `ability_level` removed.
- `Registration`:
  - `bib` is nullable; `age` (integer, nullable); `source` (`"import"` or `"manual"`, default `"manual"`); `external_category`; `checked_in_at_ms`.
  - `#checked_in?`.
  - `#effective_age` = the event age from the rider's birth date, else `age`.
- `Race#bib_from` / `#bib_to` and `Event#bib_from` / `#bib_to`, with the overlap validation from Global Constraints.
- `CategoryMapping(event_id, external_category, race_id nullable, skip boolean)`: unique per (event, external_category), and either a race or skip.
- `Eligibility.warnings` uses `registration.effective_age`. Its signature changes to `warnings(registration:)`, and all callers are updated.

- [ ] Failing tests:
  - bib nil allowed, but a duplicate non-nil bib in the event is refused;
  - age, source and check-in fields;
  - race range overlapping another race, or the event range, is refused with the exact message;
  - from > to refused;
  - a race without a range uses the event range (helper `Race#bib_range` → `Range` or nil);
  - category mapping uniqueness and race-or-skip;
  - eligibility age falls back to the registration's age;
  - `ability_level` is gone.
- [ ] Migration:
  - riders: add city and state; remove ability_level;
  - registrations: `bib` null allowed; add age, source (default "manual", not null), external_category, checked_in_at_ms (bigint); the unique index on (event_id, bib) stays (NULLs don't collide on SQLite or Postgres);
  - races and events: add bib_from and bib_to;
  - create category_mappings.
  - Run `bin/rails db:migrate` and `bin/rails db:schema:dump`.
- [ ] Implement; update every caller of the removed field and of the `Eligibility` signature (registration import, simulator demo if needed, API types in Task 4 — keep the API compiling by removing `ability_level` from `RiderType` and `RiderInput` here).
- [ ] `bin/rails test`, packwerk and zeitwerk all green. Commit.

### Task 2: Import — analyze and run

**Files:**
- `packs/events/app/models/registration_import.rb` (rework) and `rider_registrar.rb`.
- Fixture `test/fixtures/files/bikereg_export.csv`: the exact 17 headers from spec §2, with a BOM, CRLF line endings, quoted headers and made-up riders.
- `test/models/registration_import_test.rb` (rewrite) and `rider_registrar_test.rb`.

**Interfaces:**
- `RegistrationImport.analyze(event:, csv:)` → `Analysis(headers:, mapping:, categories:)`.
  - `mapping` is a field → header Hash, auto-matched by the spec §4.1 list.
  - `categories` is `[CategoryRow(value:, count:, race_id:, skip:)]`. The suggestion is the saved `CategoryMapping`, else a race whose name matches (case-insensitive), else nil.
- `RegistrationImport.call(event:, csv:, mapping:, categories:, dry_run: false)` → `Result(created:, updated:, skipped:, errors:, warnings:, not_in_file:)`.
  - `categories` is `{ value => { "race_id" => id } | { "skip" => true } }`.
  - errors and warnings are `[RowMessage(row:, message:)]`; `not_in_file` is `[String]` ("First Last (bib 101 / Race)").
  - A dry run executes inside a transaction that is always rolled back.
  - Saves the category mappings when not a dry run.
- `RiderRegistrar.upsert(event:, race:, attrs:, source:)` → Registration, where `attrs` holds the rider fields plus bib, age and external_category.
  - Matches an existing registration in the event by license, else by first and last name (case-insensitive).
  - Updates race, team, age, city, state and external_category. Sets the bib only when non-blank.
  - Creates a new registration otherwise.
  - Returns a Registration with errors on failure. `RiderRegistrar.register` (walk-ups) stays, adding source "manual".

- [ ] Failing tests:
  - the fixture's headers auto-match every field;
  - categories are listed with counts and suggestions (saved mapping beats name match);
  - merchandise mapped to skip is counted in `skipped`, not errors;
  - unmapped category → row error "category X is not mapped";
  - gender normalisation;
  - re-import updates team and race and keeps a console-set bib when the file's bib is blank (Review Focus 1: license blank the second time still matches by name);
  - Review Focus 2: duplicate rider rows;
  - `not_in_file` lists earlier-imported registrations (source "import") whose rider isn't in the new file. Walk-ups (source "manual") are never listed, because they were never in a file;
  - a dry run returns the same counts and leaves the database unchanged;
  - a bad row doesn't stop the rest;
  - an unreadable CSV raises `CSV::MalformedCSVError` (the API turns it into one error).
- [ ] Implement. Commit.

### Task 3: Bib assignment and day-of rules

**Files:**
- New `packs/events/app/models/bib_assigner.rb`.
- `registration.rb` (check-in helpers).
- New test `test/models/bib_assigner_test.rb`.

**Interfaces:**
- `BibAssigner.call(event)` → `Result(assigned: [[registration, bib]], unfilled: [String])`.
  - Registrations without a bib are taken in race scheduled order, then last and first name.
  - Each gets the lowest unused number in its race's range, or the event range when the race has none.
  - "Used" = every bib in the event that parses as an integer.
  - One transaction.
  - `unfilled` messages: "Masters 50+ Men: 3 riders still need a bib — range 200–209 is full", or "…— no bib range".
- `Registration#check_in!(at_ms)` and `#undo_check_in!`.

- [ ] Failing tests:
  - race range, and event range for races without one;
  - a second run assigns nothing;
  - full range → the unfilled message;
  - no range → the unfilled message;
  - Review Focus 3: a hand-typed bib from another race inside the range is skipped;
  - ordering by name.
- [ ] Implement. Commit.

### Task 4: API

**Files:**
- `packs/api/app/graphql/types/`:
  - `registration_type.rb`, `rider_type.rb`, `rider_input.rb`, `event_type.rb`, `race_type.rb`;
  - new `import_analysis_type.rb`, `import_category_type.rb`, `import_result` fields, `registration_counts_type.rb`, `bib_assignment_type.rb`.
- `packs/api/app/graphql/mutations/`:
  - `import_registrations.rb` (rework), `register_rider.rb` (chief, optional bib, age);
  - new `analyze_import.rb`, `update_registration.rb`, `set_checked_in.rb`, `remove_registration.rb`, `assign_bibs.rb`;
  - `race_fields.rb` and `update_event.rb` / `create_event.rb` (bib ranges).
- `mutation_type.rb`.
- Tests: `test/integration/api/import_registrations_test.rb` (rewrite), new `registration_mutations_test.rb`, `rider_privacy_test.rb` (timer read-only).

**Interfaces** (GraphQL, as spec §5):
- `analyzeImport(eventId, csv) { headers mapping categories { value count raceId skip } errors }`.
- `importRegistrations(eventId, csv, mapping, categories, dryRun) { created updated skipped rowErrors warnings notInFile errors }`.
- `registerRider(raceId, bib, age, rider) { registration warnings errors }`.
- `updateRegistration(id, raceId, bib, age, rider) { registration warnings errors }`.
  - An explicit null clears the bib or age; omitted means unchanged.
  - Rider fields update the shared rider.
- `setCheckedIn(registrationId, checkedIn) { registration errors }`, at hub time.
- `removeRegistration(id) { errors }`, refused with "Bib X has captures and can't be removed" when the event has a Capture with that bib.
- `assignBibs(eventId) { assigned { bib name raceName } unfilled errors }`.
- `Event.registrationCounts { registered checkedIn needsBib }`; `Event.bibFrom` / `bibTo`; `Race.bibFrom` / `bibTo`.
- `RegistrationType`: bib, age, source, externalCategory, checkedInAtMs, race { id name }.
- `RiderType`: city and state.

- [ ] Failing tests:
  - each mutation's role (timer refused for writes; chief allowed for day-of; admin required for import and ranges);
  - analyze returns the fixture's mapping and categories;
  - the dry run matches the real counts and writes nothing;
  - a malformed CSV gives one error;
  - check-in and undo;
  - removal refused with captures, allowed without;
  - assign bibs output;
  - counts;
  - Review Focus 4: a race move keeps the bib and recomputes warnings;
  - a duplicate bib on update → the error.
- [ ] Implement. Full Rails suite green on SQLite and Postgres (`PARALLEL_WORKERS=1`). Commit.

### Task 5: Console

**Files:**
- `frontend/src/route.ts` (+ `registrationHref`, `registration` view) and `route.test.ts`.
- `queries.ts`.
- `views/EventNav.tsx` (the new tab).
- New `views/RegistrationScreen.tsx`, `views/RiderDialog.tsx` (add/edit) and `views/ImportDialog.tsx`.
- `views/EventFields.tsx` and `views/RaceDialog.tsx` (bib range fields).
- `App.tsx`.
- New `src/registration.ts` (pure helpers: `filterRegistrations`, `countsLabel`), with tests.
- e2e: `frontend/e2e/registration.spec.ts` and a copy of the fixture at `frontend/e2e/fixtures/bikereg_export.csv`.

**Interfaces:**
- `filterRegistrations(rows, { search, raceId, needsBib, notCheckedIn })`: search matches name, bib, team or license, case-insensitive.
- `countsLabel({ registered, checkedIn, needsBib })` → "168 registered · 142 checked in · 6 need a bib" ("1 needs a bib" when singular).

- [ ] Failing unit tests: route parse and href; `filterRegistrations`; `countsLabel`.
- [ ] Failing e2e `registration.spec.ts`:
  - an admin opens Registration → Import → picks the fixture;
  - columns are auto-matched;
  - categories: two mapped to existing races, the merchandise value set to Skip, and one set to "Create race" (confirm gender and scheduled start);
  - the preview shows the counts, then Import;
  - the summary appears and the table lists riders, with "needs bib" flags;
  - Assign bibs → bibs filled, needs-bib count 0;
  - then sign in as chief: Add rider (walk-up) with no bib → appears flagged and checked in; tick Checked in on an imported rider → the count updates; type a bib inline for the walk-up → the flag clears.
- [ ] Implement:
  - the tab and screen with toolbar (search, race filter, two filters, counts, buttons by role), the table (inline bib edit with Enter, check-in box, ⚠ with tooltip, Edit, Remove with confirm);
  - RiderDialog;
  - ImportDialog steps (file → columns → categories → preview → import → summary);
  - bib range fields on Setup;
  - live refresh via `useEventChanges`.
- [ ] `npm test`, typecheck, e2e green; full Rails and engine suites green. Commit.
- [ ] Add the spec §7 out-of-scope items to `docs/TODO.md`. Commit.
