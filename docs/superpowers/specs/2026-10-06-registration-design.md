# Registration — Design

**Date:** 2026-10-06
**Status:** Draft for review
**Builds on:** `2026-10-03-event-race-setup-design.md` (events, races, Setup screen)

## 1. Goal

Officials manage who is racing from a **Registration** tab: import pre-registrations
from an external source (BikeReg first), add walk-ups on the day, give out bibs and
check riders in.

**Done when:** in a browser test an admin imports a BikeReg export, maps its
categories to races (one skipped as merchandise, one creating a new race) and assigns
bibs; a chief adds a walk-up and checks a rider in, and the counts and "needs bib"
flags update.

## 2. BikeReg export format

A promoter's BikeReg export is a CSV whose columns the promoter chooses, so names and
order vary between events. A real export (header row only, from
`github.com/Coletrane/bikeva.com-race-utils`, `data/creature-2019/in/bikereg.csv`):

> Bib, City, First Name, USAC License Status, Last Name, State, Team, USAC License,
> Age on Event Day, Email, Phone, Category Date, Category Entered / Merchandise
> Ordered, Gender, USAC Category DH, USAC Category XC, Quantity

Consequences:
- Columns are matched by name, with BikeReg names recognised automatically, and the
  official can correct the mapping.
- "Category Entered / Merchandise Ordered" mixes race entries with merchandise rows.
- Age arrives as "Age on Event Day", not a birth date.
- The Bib column is often empty; numbers are handed out at check-in.
- Email and phone are present but are **not imported or stored**: timing doesn't need them.

## 3. Data model

### Rider (a person, shared across events)
| Field | Change |
|---|---|
| first_name, last_name, gender, birth_date, team, license_number | unchanged |
| city, state | **new**, optional |
| ability_level | **removed** (unused since race categories are free text) |

### Registration (a rider in a race at one event)
| Field | Notes |
|---|---|
| bib | now **optional**; still unique within the event when present |
| age | **new**, optional: age for this event as reported by the source ("Age on Event Day") |
| source | **new**: `import` or `manual` |
| external_category | **new**, optional: the category text from the imported file |
| checked_in_at_ms | **new**, optional: when the rider was checked in; null = not checked in |

### Bib ranges
- Race: optional `bib_from`, `bib_to` (positive integers, from ≤ to).
- Event: optional `bib_from`, `bib_to`, used by races without their own range.
- Ranges within one event must not overlap (race vs race, race vs event range). Refused
  with both names, e.g. "Bib range 100–199 overlaps Masters 50+ Men (150–249)".

### Category mappings (per event)
`(event, external_category) → race | skip`. Saved by each import and pre-selected on
the next.

### Eligibility (still warnings only)
Age is the event age from `birth_date` when known, otherwise the registration's `age`.
The gender rule is unchanged.

## 4. Behaviour

### 4.1 Import
1. **Analyze:** parse the CSV, auto-match columns, and list each distinct category
   value with its row count and a suggested target. The suggestion is the saved
   mapping, else a race whose name matches case-insensitively, else none.
   - Recognised headers per field, case-insensitive:
     - first name: `First Name`, `first_name`
     - last name: `Last Name`, `last_name`
     - gender: `Gender`, `gender`
     - team: `Team`, `team`
     - license: `USAC License`, `License`, `license_number`
     - age: `Age on Event Day`, `Age`, `age`
     - birth date: `Birth Date`, `birth_date`
     - city: `City`, `city`
     - state: `State`, `state`
     - bib: `Bib`, `bib`
     - category: `Category Entered / Merchandise Ordered`, `Category Entered`, `Race Category`, `Category`, `race`
2. **Map categories:** each category is mapped to a race, to **skip**, or to a new race.
   A new race is created first through Setup's `createRace`, with its name pre-filled
   from the category and gender and scheduled start confirmed. The mapping then points
   at the new race.
3. **Preview** (dry run), then **import**. Output: new, updated, skipped (rows whose
   category maps to skip), errors (by row), warnings (eligibility), and **not in file**
   (registrations in the event from an earlier import whose rider isn't in this file).
   Not-in-file riders are listed, never removed.

Rules:
- **Matching** an existing registration in the event: by license number when the row
  has one, otherwise by first and last name (case-insensitive). A match is updated
  (race, team, age, city, state, external category); otherwise a new registration is
  created.
- A **blank bib** in the file never clears an existing bib. A non-blank bib that
  differs from the existing one updates it, and is refused if taken.
- Gender values `M`, `F`, `X`, `Male`, `Female` (any case) are normalised to M/F/X.
- Rows are independent: a bad row is reported and the rest import. A file that can't be
  parsed gives one error.

### 4.2 Assign bibs
For each registration **without a bib**, in race scheduled order, then last and first
name: assign the lowest unused number in the race's range, or the event's range when
the race has none. Existing bibs are never changed, so a second run assigns nothing.
Riders who can't be given a bib (no range, or the range is full) stay blank and are
reported, e.g. "Masters 50+ Men: 3 riders still need a bib — range 200–209 is full".
Runs in one transaction.

### 4.3 Day-of
- **Walk-up:** add a rider to a race. Bib is optional. Fields: first and last name,
  gender, race, birth date or age, team, license, city, state. Source is `manual`, and
  the rider is checked in on creation.
- **Edit:** any registration or rider field, including moving the rider to another
  race and setting or changing the bib (unique within the event).
- **Check in / undo:** sets or clears `checked_in_at_ms` (hub time).
- **Remove:** refused once the rider's bib has captures in the event.

## 5. API

- `event.registrations` gains `bib` (nullable), `age`, `source`, `externalCategory`,
  `checkedInAtMs`, and `rider.city` / `rider.state`. `rider.abilityLevel` is removed.
  The privacy rules are unchanged: timers don't see birth date, license or warnings.
- `event.registrationCounts { registered checkedIn needsBib }`.
- `Event` and `Race` gain `bibFrom` / `bibTo`, set through `updateEvent`, `createRace`
  and `updateRace` (admin).
- Mutations:

| Mutation | Role |
|---|---|
| `analyzeImport(eventId, csv)` → `{ headers, mapping, categories { value count raceId skip } }` | admin |
| `importRegistrations(eventId, csv, mapping, categories, dryRun)` → `{ created updated skipped rowErrors warnings notInFile }` | admin |
| `registerRider(raceId, bib?, rider, age?)` (walk-up) | chief |
| `updateRegistration(id, raceId?, bib?, age?, rider fields?)` | chief |
| `setCheckedIn(registrationId, checkedIn)` | chief |
| `removeRegistration(id)` | chief |
| `assignBibs(eventId)` → `{ assigned { bib name raceName } unfilled }` | chief |

`registerRider` moves from admin to chief because walk-ups are day-of work.

## 6. Console

- Event tabs: **Setup | Registration | Starts | Capture | Results**, at
  `/console/event/<id>/registration`, visible to every role.
  - Import and bib ranges: admin.
  - Walk-ups, edits, bibs, check-in and assign bibs: chief and above.
  - Timers: read-only.
- **Toolbar:**
  - search by name, bib, team or license; race filter; filters "needs bib" and
    "not checked in";
  - counts ("168 registered · 142 checked in · 6 need a bib");
  - buttons **Add rider**, **Import**, **Assign bibs**.
- **Table:**
  - columns: bib (editable inline; Enter saves, error shown in the row), name, gender,
    age, team, race, checked in (tick box), and ⚠ for "needs bib" or eligibility
    warnings;
  - per-row **Edit** dialog and **Remove** with confirm.
- **Import dialog:** file → columns → categories (race / skip / create race) → preview
  → import → summary, including "not in file".
- **Setup:** bib range fields in the event form and the race dialog.

## 7. Out of scope (to `docs/TODO.md`)

- A check-in count on the Starts tab.
- DNS suggestions for riders who never checked in and have no captures.
- Assigning bibs only to checked-in riders.
- The public "Who's Registered" list format.
- Registration export.
- Other sources' presets (USAC and others beyond the recognised header names).
- Chip or tag numbers.

## 8. Testing

- **Model:**
  - Header auto-match using a fixture with the exact 17 BikeReg headers and made-up
    riders.
  - Merchandise rows skipped.
  - Re-import updates, adds and lists not-in-file riders, and never clears a bib.
  - Gender normalisation.
  - Assign bibs: race range, event range, a second run assigns nothing, full range,
    no range.
  - Overlapping ranges refused.
  - Eligibility from age when there's no birth date.
  - Removal refused with captures.
- **API:**
  - Each mutation's role, with timers read-only.
  - The dry run reports the same counts as the real import and changes nothing.
  - Check-in and undo.
  - Counts.
- **Browser:** the "done when" flow in §1.
