# Course Events Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Time point-to-point / single-loop events with checkpoints along the course: splits in the results, and live tracking (where-is-everyone, overdue, missed checkpoint, cutoffs).

**Architecture:** An event gets `race_format` (`laps` | `course`) and an ordered list of `checkpoints`; the finish is implicit (its distance and cutoff live on the event). Devices and their captures carry a `checkpoint_id` (null = finish), set at pairing, on the phone, or by an official. The pure-Ruby engine routes course races to a new `CourseScorer` (laps races keep `CohortScorer`) and raises three new problems in `CourseAnomalies`; the console shows splits and a Course board.

**Tech Stack:** Rails 8.1 packs, pure-Ruby results engine (`packs/results/lib`), graphql-ruby, React 19 + MUI + Apollo 4 (console, `frontend/src`), the phone capture app (`frontend/capture/src`, IndexedDB, `/sync/v1`), Minitest, Vitest, Playwright.

**Spec:** `docs/superpowers/specs/2026-10-10-course-events-design.md`

## Global Constraints

- `bin/rubocop` must be clean (rails-omakase: `[ a, b ]` array spacing). Run it before every Ruby commit.
- Ruby tests: `bin/rails test` (Postgres: `PARALLEL_WORKERS=1 bin/rails test`); engine: `bin/rails test packs/results/test`.
- Frontend: `npm run typecheck` (never `tsc -b`; it emits `.js` next to sources), `npm test` (Vitest), `npm run build` before e2e (`npx playwright test`). Run from `frontend/`.
- Restart `bin/hub` after engine changes or new pack `app/` directories, or the console gets 500s.
- The engine (`packs/results/lib`) must not touch Rails or the database.
- Times run from the gun (the race's `set_race_start`), never from anything else.
- A capture with no `checkpoint_id` is a finish-line capture; older phones and logs must keep working unchanged (`DeviceHash` omits null fields).
- Laps events behave exactly as today: every existing test must still pass unchanged.
- The column is `race_format`, not `format` (an attribute named `format` would shadow `Kernel#format` inside models).
- Commit after each task only once its tests and `bin/rubocop` pass. Don't push or open a PR unless asked.
- Work on a new branch `course-events` from `flag-out-hardening` (it builds on that branch's Anomalies changes; PR #9 and that branch aren't merged yet). Rebase onto `main` once they are.

## Spec refinements made while planning

- The finish's distance and cutoff are event columns (`finish_distance_km`, `finish_cutoff_at_ms`), so overdue projection and cutoffs work on the last segment too. In the engine the course is a list of `Checkpoint`s ending with the finish (`id: nil`).
- Cutoff entry (clock or elapsed) is parsed in the console; the API stores and takes `cutoffAtMs` only.
- The console's own Capture screen always records at the finish (its device has no checkpoint); no location UI there.
- "Last change wins" between phone and official is decided by time: `devices.checkpoint_set_at_ms`.

## Review Focus

1. **A laps event that somehow gets checkpoint captures** (a phone left on "Aid 1" from another event): laps scoring must ignore non-finish crossings, not count them as laps. → test in Task 3.
2. **The same bib tapped at a checkpoint and at the finish within the 10 s debounce** (tiny courses, test events): debounce must be per checkpoint, so neither is dropped. → test in Task 3.
3. **A phone offline when the chief moves it, which then pushes an older location change**: the hub keeps the chief's (newer) choice. → test in Task 2.
4. **A cutoff entered as elapsed before any race has a scheduled start**: the editor must refuse with a message, not save a 1970 time. → test in Task 7.
5. **A racer pulled at a cutoff who later taps the finish**: stays pulled, the finish tap shows as after-pull, and no new problems are raised for them. → test in Task 4.

---

### Task 1: Event format and checkpoints (schema and models)

**Files:**
- Create: `db/migrate/20261010000001_course_events.rb`
- Create: `packs/events/app/models/checkpoint.rb`
- Modify: `packs/events/app/models/event.rb`
- Modify: `packs/events/app/models/disciplines.rb`
- Test: `test/models/course_setup_test.rb`

**Interfaces:**
- Produces: `Event#race_format` (`"laps"`|`"course"`), `Event#course?`, `Event#checkpoints` (ordered by position), `Event#finish_distance_km`, `Event#finish_cutoff_at_ms`; `Checkpoint(id, event_id, position, name, distance_km, cutoff_at_ms)`; `Disciplines.default_race_format(discipline, sub) -> "laps"|"course"`; columns `devices.checkpoint_id`, `devices.checkpoint_set_at_ms`, `pairing_tokens.checkpoint_id`, `device_entries.checkpoint_id`.

- [ ] **Step 1: Write the failing test**

```ruby
# test/models/course_setup_test.rb
require "test_helper"

class CourseSetupTest < ActiveSupport::TestCase
  test "the format defaults from the discipline and can be overridden" do
    assert_equal "laps", create_event(discipline: "cyclocross").race_format
    assert_equal "course", create_event(discipline: "gravel").race_format
    assert_equal "course", create_event(discipline: "road", sub_discipline: "road_race").race_format
    assert_equal "laps", create_event(discipline: "road", sub_discipline: "criterium").race_format
    assert_equal "course", create_event(discipline: "mountain_bike", sub_discipline: "xc_marathon").race_format
    assert_equal "laps", create_event(discipline: "gravel", race_format: "laps").race_format
    assert create_event(discipline: "gravel").course?
  end

  test "the format must be laps or course" do
    event = Event.new(name: "X", date: Date.new(2026, 10, 18), discipline: "gravel", race_format: "relay")
    assert_not event.valid?
    assert_includes event.errors[:race_format], "is not included in the list"
  end

  test "checkpoints come back in course order and need a name and a unique position" do
    event = create_event(discipline: "gravel")
    event.checkpoints.create!(position: 2, name: "Aid 2", distance_km: 62)
    event.checkpoints.create!(position: 1, name: "Aid 1", distance_km: 30.5)
    assert_equal [ "Aid 1", "Aid 2" ], event.reload.checkpoints.map(&:name)
    assert_not event.checkpoints.build(position: 1, name: "Dup").valid?
    assert_not event.checkpoints.build(position: 3, name: "").valid?
    assert_not event.checkpoints.build(position: 3, name: "Neg", distance_km: -1).valid?
  end

  test "deleting an event deletes its checkpoints" do
    event = create_event(discipline: "gravel")
    event.checkpoints.create!(position: 1, name: "Aid 1")
    event.destroy!
    assert_equal 0, Checkpoint.count
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bin/rails test test/models/course_setup_test.rb`
Expected: FAIL — `unknown attribute 'race_format'` / `uninitialized constant Checkpoint`.

- [ ] **Step 3: Write the migration**

```ruby
# db/migrate/20261010000001_course_events.rb
class CourseEvents < ActiveRecord::Migration[8.1]
  def change
    change_table :events, bulk: true do |t|
      t.string :race_format, null: false, default: "laps"
      t.decimal :finish_distance_km, precision: 8, scale: 3
      t.bigint :finish_cutoff_at_ms
    end

    create_table :checkpoints, id: :string do |t|
      t.references :event, type: :string, null: false, foreign_key: true
      t.integer :position, null: false
      t.string :name, null: false
      t.decimal :distance_km, precision: 8, scale: 3
      t.bigint :cutoff_at_ms
      t.index [ :event_id, :position ], unique: true
    end

    add_reference :devices, :checkpoint, type: :string, foreign_key: { on_delete: :nullify }
    add_column :devices, :checkpoint_set_at_ms, :bigint
    add_reference :pairing_tokens, :checkpoint, type: :string, foreign_key: { on_delete: :nullify }
    add_reference :device_entries, :checkpoint, type: :string, foreign_key: true
  end
end
```

Run: `bin/rails db:migrate && RAILS_ENV=test bin/rails db:migrate`
Expected: `db/schema.rb` gains the columns and the `checkpoints` table.

- [ ] **Step 4: Add the defaults to `Disciplines`**

In `packs/events/app/models/disciplines.rb`, give `Sub` and `Discipline` a `course` flag (default false) and set it for gravel, run, road race and XC marathon:

```ruby
  Sub = Data.define(:id, :label, :finish_with_leader, :course) do
    def initialize(course: false, **) = super
  end
  Discipline = Data.define(:id, :label, :finish_with_leader, :subs, :age_next_year, :course) do
    def initialize(age_next_year: false, course: false, **) = super
  end
```

Table changes (only these lines change):

```ruby
      Sub.new(id: "xc_marathon", label: "XC marathon", finish_with_leader: false, course: true),
      Sub.new(id: "road_race", label: "Road race", finish_with_leader: false, course: true),
    Discipline.new(id: "gravel", label: "Gravel", finish_with_leader: false, subs: [], course: true),
    Discipline.new(id: "run", label: "Run", finish_with_leader: false, subs: [], course: true)
```

Add the lookup next to `default_finish_with_leader`:

```ruby
  # "course" (point to point / single loop) or "laps".
  def default_race_format(discipline, sub)
    d = find(discipline) or return "laps"
    course = sub.present? ? d.subs.find { it.id == sub }&.course : d.course
    course ? "course" : "laps"
  end
```

Update the module comment's first line to: `# Event disciplines, their sub-disciplines, and their defaults: whether races finish with the leader, and whether they ride laps or a course.`

- [ ] **Step 5: Add the model and the event's side**

```ruby
# packs/events/app/models/checkpoint.rb
# A timing point on a course event's course (an aid station, "Mile 37"),
# passed once, in position order. The finish isn't one: it is always last,
# with its distance and cutoff on the event.
class Checkpoint < ApplicationRecord
  belongs_to :event

  validates :name, presence: true
  validates :position, numericality: { only_integer: true, greater_than: 0 }, uniqueness: { scope: :event_id }
  validates :distance_km, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true
end
```

In `packs/events/app/models/event.rb`:

```ruby
  RACE_FORMATS = %w[laps course].freeze
```

```ruby
  has_many :checkpoints, -> { order(:position) }, dependent: :destroy, inverse_of: :event
```

```ruby
  attribute :race_format, :string, default: nil
```

In the `before_validation` block add:

```ruby
    self.race_format = Disciplines.default_race_format(discipline, sub_discipline) if race_format.nil?
```

```ruby
  validates :race_format, inclusion: { in: RACE_FORMATS }
  validates :finish_distance_km, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true
```

```ruby
  # Point to point / single loop: start → checkpoints → finish, once.
  def course? = race_format == "course"
```

- [ ] **Step 6: Run the tests**

Run: `bin/rails test test/models/course_setup_test.rb test/models/events_test.rb test/models/event_race_setup_test.rb`
Expected: PASS.

- [ ] **Step 7: Rubocop and commit**

```bash
bin/rubocop
git add db/migrate/20261010000001_course_events.rb db/schema.rb packs/events/app/models/checkpoint.rb packs/events/app/models/event.rb packs/events/app/models/disciplines.rb test/models/course_setup_test.rb
git commit -m "Course events: an event's race format and its checkpoints"
```

---

### Task 2: Device locations in the log, pairing and sync

**Files:**
- Create: `packs/timing/app/models/device_location.rb`
- Modify: `packs/timing/app/models/device_entry.rb`
- Modify: `packs/timing/app/models/capture.rb`
- Modify: `packs/timing/app/models/device.rb`
- Modify: `packs/timing/app/models/device_log_ingest.rb`
- Modify: `packs/timing/app/controllers/sync_controller.rb`
- Modify: `packs/access/app/models/pairing_token.rb`
- Modify: `test/support/build_helpers.rb`
- Test: `test/integration/sync_test.rb`, `test/models/pairing_token_test.rb`

**Interfaces:**
- Consumes: `Checkpoint`, `devices.checkpoint_id/checkpoint_set_at_ms`, `pairing_tokens.checkpoint_id`, `device_entries.checkpoint_id` (Task 1).
- Produces:
  - Log entry `kind: "location"` with `checkpoint_id` (omitted = finish) and `captured_at_ms` (when it changed, phone time) plus `clock_offset_ms`.
  - Capture entries may carry `checkpoint_id`.
  - `Device#move_to!(checkpoint_id, at_ms:)` — sets the device's checkpoint if `at_ms >= checkpoint_set_at_ms`.
  - `Device.pair!(event:, name:, checkpoint_id: nil)`; `PairingToken.issue!(event:, official:, checkpoint_id: nil)`.
  - `Capture.record!(device:, at_ms:, bib:)` stamps `device.checkpoint_id`.
  - Roster JSON gains `checkpoints: [{id, name}]` (course order) and `device: {checkpoint_id, checkpoint_set_at_ms}`.
  - Test helper `record_capture(..., checkpoint: nil)`.

- [ ] **Step 1: Write the failing sync tests** (append to `test/integration/sync_test.rb`)

```ruby
  test "captures carry the checkpoint they were taken at; a capture without one is a finish capture" do
    aid = @event.checkpoints.create!(position: 1, name: "Aid 1")
    push(chain([ { captured_at_ms: 1_000, bib: "101", checkpoint_id: aid.id }, { captured_at_ms: 2_000, bib: "101" } ]))
    assert_response :ok
    assert_equal [ aid.id, nil ], Capture.where(device: @device).order(:device_seq).pluck(:checkpoint_id)
  end

  test "a checkpoint from another event rejects the whole batch" do
    other = create_event(name: "Other").checkpoints.create!(position: 1, name: "Aid 1")
    push(chain([ { captured_at_ms: 1_000, bib: "101", checkpoint_id: other.id } ]))
    assert_response :conflict
    assert_equal 0, Capture.where(device: @device).count
  end

  test "a location entry moves the device, unless an official moved it later" do
    aid1 = @event.checkpoints.create!(position: 1, name: "Aid 1")
    aid2 = @event.checkpoints.create!(position: 2, name: "Aid 2")
    push(chain([ { kind: "location", checkpoint_id: aid1.id, captured_at_ms: 1_000, clock_offset_ms: 0 } ]))
    assert_response :ok
    assert_equal [ aid1.id, 1_000 ], @device.reload.values_at(:checkpoint_id, :checkpoint_set_at_ms)

    @device.move_to!(aid2.id, at_ms: 5_000) # the chief, later
    entries = chain([ { kind: "location", captured_at_ms: 3_000, clock_offset_ms: 0 } ], from: 2,
                    prev: DeviceEntry.where(device: @device).order(:device_seq).last.entry_hash)
    push(entries) # the phone was offline: its move back to the finish happened before the chief's
    assert_response :ok
    assert_equal aid2.id, @device.reload.checkpoint_id
  end

  test "the roster lists the course's checkpoints and where the hub has this device" do
    aid = @event.checkpoints.create!(position: 1, name: "Aid 1")
    @device.move_to!(aid.id, at_ms: 7_000)
    get "/sync/v1/roster", headers: auth
    body = response.parsed_body
    assert_equal [ { "id" => aid.id, "name" => "Aid 1" } ], body["checkpoints"]
    assert_equal({ "checkpoint_id" => aid.id, "checkpoint_set_at_ms" => 7_000 }, body["device"])
  end
```

And in `test/models/pairing_token_test.rb`:

```ruby
  test "a pairing code can place the phone at a checkpoint" do
    event = create_event(discipline: "gravel")
    aid = event.checkpoints.create!(position: 1, name: "Aid 1")
    _, code = PairingToken.issue!(event:, official: create_official, checkpoint_id: aid.id)
    device, = PairingToken.redeem!(code, device_name: "Aid phone")
    assert_equal aid.id, device.checkpoint_id
    assert device.checkpoint_set_at_ms
  end
```

- [ ] **Step 2: Run to verify they fail**

Run: `bin/rails test test/integration/sync_test.rb test/models/pairing_token_test.rb`
Expected: FAIL — unknown kind `location` (409), `undefined method 'move_to!'`, unknown keyword `checkpoint_id`.

- [ ] **Step 3: Implement**

`packs/timing/app/models/device_location.rb`:

```ruby
# A phone moved to another timing point (null checkpoint: the finish). In the
# log so the audit trail shows when; each capture also carries its own.
class DeviceLocation < DeviceEntry
  validates :captured_at_ms, presence: true
end
```

`device_entry.rb`: add `"DeviceLocation" => "location"` to `KINDS`, and `"checkpoint_id" => checkpoint_id` to `wire` (before `.compact`).

`capture.rb`:

```ruby
  # Appends a crossing to a hub-side device's log (the console, the simulator), at the device's checkpoint.
  def self.record!(device:, at_ms:, bib:)
    bib = bib.to_s.strip.presence
    append!(device:, captured_at_ms: at_ms, clock_offset_ms: 0, bib:, checkpoint_id: device.checkpoint_id)
  end
```

`device.rb`:

```ruby
  belongs_to :checkpoint, optional: true

  # Returns [device, credential]; only the digest is stored.
  def self.pair!(event:, name:, checkpoint_id: nil)
    credential = SecureRandom.urlsafe_base64(32)
    device = create!(event:, name:, paired_at_ms: Clock.now_ms, credential_digest: digest(credential), checkpoint_id:,
                     checkpoint_set_at_ms: (Clock.now_ms if checkpoint_id))
    [ device, credential ]
  end

  # The phone or an official moved it (null: the finish). The latest move wins,
  # so a phone that was offline can't undo a later move by the chief.
  def move_to!(checkpoint_id, at_ms:)
    return false if checkpoint_set_at_ms && at_ms < checkpoint_set_at_ms
    update_columns(checkpoint_id:, checkpoint_set_at_ms: at_ms)
  end
```

`device_log_ingest.rb`: add `"location" => "DeviceLocation"` to `CLASSES`; in `build`:

```ruby
    when "capture"
      raise Mismatch unless entry["captured_at_ms"].is_a?(Integer)
      attrs.merge!(captured_at_ms: entry["captured_at_ms"], clock_offset_ms: entry["clock_offset_ms"], bib: entry["bib"].to_s.strip.presence,
                   checkpoint_id: checkpoint!(entry))
    when "location"
      raise Mismatch unless entry["captured_at_ms"].is_a?(Integer)
      attrs.merge!(captured_at_ms: entry["captured_at_ms"], clock_offset_ms: entry["clock_offset_ms"], checkpoint_id: checkpoint!(entry))
```

```ruby
  # A checkpoint must be one of the device's event's (absent: the finish).
  def checkpoint!(entry)
    id = entry["checkpoint_id"] or return nil
    raise Mismatch unless Checkpoint.exists?(id:, event_id: @device.event_id)
    id
  end
```

After the loop's `ack += 1`, apply moves (inside the transaction, so a rejected batch moves nothing):

```ruby
          if entry["kind"] == "location"
            @device.move_to!(entry["checkpoint_id"], at_ms: entry["captured_at_ms"] + entry["clock_offset_ms"].to_i)
          end
```

Update the class comment's "unknown kind" sentence to mention location entries: `Location entries move the device (see Device#move_to!).`

`pairing_token.rb`: `belongs_to :checkpoint, optional: true`; `issue!(event:, official:, checkpoint_id: nil)` passes `checkpoint_id:` to `create!`; `redeem!` calls `Device.pair!(event: token.event, name: device_name.presence || "Tablet", checkpoint_id: token.checkpoint_id)`.

`sync_controller.rb#roster`:

```ruby
    checkpoints = event.checkpoints.map { { id: it.id, name: it.name } }
    device = { checkpoint_id: @device.checkpoint_id, checkpoint_set_at_ms: @device.checkpoint_set_at_ms }
    body = { event: { name: event.name, races: races.map { { id: it.id, name: it.name } } }, racers:, checkpoints:, device: }
```

Update its comment: `# Bib, name and race only — nothing else about racers leaves the hub. Plus the course's checkpoints and where the hub has this phone.`

`test/support/build_helpers.rb`:

```ruby
  def record_capture(device:, seq:, at_ms:, bib: nil, offset_ms: 0, id: SecureRandom.uuid_v7, checkpoint: nil)
    Capture.create!(id:, event_id: device.event_id, device:, device_seq: seq, captured_at_ms: at_ms,
                    clock_offset_ms: offset_ms, bib:, checkpoint_id: checkpoint&.id, prev_hash: "p#{seq}", entry_hash: "h#{seq}")
  end
```

- [ ] **Step 4: Run the tests**

Run: `bin/rails test test/integration/sync_test.rb test/models/pairing_token_test.rb test/models/device_hash_test.rb test/integration/device_pairing_test.rb test/models/capture_record_test.rb`
Expected: PASS (the existing hash and sync tests still pass: no `checkpoint_id`, no change to the hash).

- [ ] **Step 5: Rubocop and commit**

```bash
bin/rubocop
git add packs/timing packs/access test/integration/sync_test.rb test/models/pairing_token_test.rb test/support/build_helpers.rb
git commit -m "Course events: devices and captures know their checkpoint"
```

---

### Task 3: Engine — scoring a course

**Files:**
- Modify: `packs/results/lib/results/types.rb`
- Modify: `packs/results/lib/results/resolver.rb`
- Modify: `packs/results/lib/results/cohort_scorer.rb`
- Modify: `packs/results/lib/results/engine.rb`
- Modify: `packs/results/lib/results.rb`
- Create: `packs/results/lib/results/course_scorer.rb`
- Create: `packs/results/lib/results/course_standings.rb`
- Modify: `packs/results/test/support/fixture.rb`
- Test: `packs/results/test/course_test.rb`, `packs/results/test/resolver_test.rb`

**Interfaces:**
- Consumes: nothing from earlier tasks (pure Ruby).
- Produces:
  - `Results::Checkpoint = Data.define(:id, :name, :position, :distance_km, :cutoff_at_ms)` — `id: nil` is the finish, always last.
  - `RaceDef#course` — `nil` for laps races, else `[Checkpoint]` ending with the finish. Default nil.
  - `Capture#checkpoint_id`, `Crossing#checkpoint_id` (nil = finish), both default nil.
  - `Split = Data.define(:checkpoint_id, :at_ms, :elapsed_ms, :segment_ms, :ref, :inserted)`.
  - `RacerResult#splits` (`[]` for laps races); `CrossingView#checkpoint_id`; crossing kind `:split` (a counted checkpoint pass).
  - `CourseScorer.new(input, race, resolved).call -> CourseScorer::Scored(race:, start_at:, racers:, race_result:)`; `CourseScorer::CourseRacer(entrant, race_start, passes, status, finish, pull_at, seen, dropped)` where `passes` is `{checkpoint_id => Crossing}` (first counted pass at each, finish under `nil`).
  - `insert_capture` payload may carry `checkpoint_id`.
  - Fixture YAML: race `course: [{id, name, km, cutoff}]` (finish appended automatically; `finish_km`, `finish_cutoff` on the race), crossings as `{at, cp}` hashes.

- [ ] **Step 1: Teach the fixture about courses**

In `packs/results/test/support/fixture.rb`, a crossing may be a number (finish) or `{at: 100, cp: a1}`:

```ruby
      (data["crossings"] || {}).each do |bib, times|
        times.each_with_index do |t, i|
          id = "c-#{bib}-#{i + 1}"
          devices[id] = "d1"
          at, checkpoint = t.is_a?(Hash) ? [ t["at"], t["cp"] ] : [ t, nil ]
          captures << Capture.new(id:, device_id: "d1", device_seq: next_seq.("d1"), captured_at_ms: ms.(at), clock_offset_ms: 0,
                                  bib: bib.to_s, checkpoint_id: checkpoint)
        end
      end
```

And for races:

```ruby
          RaceDef.new(id: it["id"], scheduled_at_ms: ms.(it.fetch("scheduled", 0)), finish_with_leader: it.fetch("fwl", true),
                      expected_laps: it["laps"], course: course(it, ms))
```

```ruby
    # A race's course: its checkpoints in order, then the finish (id nil).
    def course(race, ms)
      return nil unless race.key?("course")
      points = race["course"].each_with_index.map do |c, i|
        Checkpoint.new(id: c.fetch("id"), name: c.fetch("name", c["id"]), position: i + 1, distance_km: c["km"], cutoff_at_ms: ms.(c["cutoff"]))
      end
      points + [ Checkpoint.new(id: nil, name: "Finish", position: points.size + 1, distance_km: race["finish_km"], cutoff_at_ms: ms.(race["finish_cutoff"])) ]
    end
```

Also let `rulings` entries pass `cp` through as `checkpoint_id` (add `when "cp" then [ "checkpoint_id", v ]` to the payload `case`).

- [ ] **Step 2: Write the failing engine tests**

```ruby
# packs/results/test/course_test.rb
require "test_helper"

# Course races (point to point / single loop): start → checkpoints → finish, once.
class CourseTest < Minitest::Test
  include ResultsTestHelpers

  SETUP = <<~YAML
    races:
      - {id: r1, start: 0, course: [{id: a1, name: Aid 1, km: 30}, {id: a2, name: Aid 2, km: 60}], finish_km: 100}
    entrants:
      - {bib: 1, race: r1}
      - {bib: 2, race: r1}
      - {bib: 3, race: r1}
      - {bib: 4, race: r1}
  YAML

  def compute(yaml, now: 0) = Results.compute(input_from(SETUP + yaml + "now: #{now}\n"))
  def rows(out) = out.races.first.rows.map { [ it.place, it.bib, it.status.to_s, it.elapsed_ms&./(1000) ] }

  def test_finishers_place_by_time_from_the_gun_then_riders_still_out_by_how_far_they_got
    out = compute(<<~YAML)
      crossings:
        1: [{at: 900, cp: a1}, {at: 1800, cp: a2}, 3000]
        2: [{at: 800, cp: a1}, {at: 1700, cp: a2}, 2900]
        3: [{at: 1000, cp: a1}, {at: 2100, cp: a2}]
        4: [{at: 950, cp: a1}]
    YAML
    assert_equal [ [ 1, "2", "finished", 2900 ], [ 2, "1", "finished", 3000 ], [ 3, "3", "racing", 2100 ], [ 4, "4", "racing", 950 ] ], rows(out)
    assert_nil out.races.first.lap_count
  end

  def test_splits_give_clock_elapsed_and_segment_times_with_gaps_for_missed_checkpoints
    out = compute("crossings:\n  1: [{at: 900, cp: a1}, 3000]\n")
    splits = out.races.first.rows.find { it.bib == "1" }.splits
    assert_equal [ "a1", "a2", nil ], splits.map(&:checkpoint_id)
    assert_equal [ 900_000, nil, 3_000_000 ], splits.map(&:at_ms)
    assert_equal [ 900_000, nil, 2_100_000 ], splits.map(&:segment_ms) # from the last checkpoint they were seen at
  end

  def test_a_second_tap_at_a_checkpoint_is_a_duplicate_and_taps_before_the_start_or_after_the_finish_dont_count
    out = compute("crossings:\n  1: [{at: -5, cp: a1}, {at: 900, cp: a1}, {at: 960, cp: a1}, 3000, {at: 3100, cp: a2}]\n")
    row = out.races.first.rows.find { it.bib == "1" }
    assert_equal [ :before_start, :split, :duplicate, :finish, :after_finish ], row.crossings.map(&:kind)
    assert_equal [ "a1", "a1", "a1", nil, "a2" ], row.crossings.map(&:checkpoint_id)
  end

  def test_a_tap_at_a_checkpoint_and_the_finish_inside_the_debounce_window_both_count
    out = compute("crossings:\n  1: [{at: 100, cp: a1}, 105]\n")
    assert_equal [ 100_000, nil, 105_000 ], out.races.first.rows.find { it.bib == "1" }.splits.map(&:at_ms)
  end

  def test_pulls_and_statuses_work_as_on_laps
    out = compute(<<~YAML)
      crossings:
        1: [{at: 900, cp: a1}, {at: 1800, cp: a2}, 3000]
        2: [{at: 800, cp: a1}]
      rulings:
        - {kind: pull, bib: 1, at: 2000}
        - {kind: dnf, bib: 2}
    YAML
    by_bib = out.races.first.rows.to_h { [ it.bib, it ] }
    assert_equal :pulled, by_bib["1"].status
    assert_equal :after_pull, by_bib["1"].crossings.last.kind
    assert_equal :dnf, by_bib["2"].status
    assert_nil by_bib["2"].place
  end

  def test_an_inserted_crossing_fills_a_checkpoint
    out = compute("crossings:\n  1: [{at: 900, cp: a1}, 3000]\nrulings:\n  - {kind: insert_capture, bib: 1, at: 1900, cp: a2}\n")
    split = out.races.first.rows.first.splits[1]
    assert_equal [ 1_900_000, true ], [ split.at_ms, split.inserted ]
  end

  def test_not_started_and_in_progress_states
    assert_equal :not_started, Results.compute(input_from(SETUP.sub("start: 0, ", ""))).races.first.state
    assert_equal :in_progress, compute("crossings:\n  1: [{at: 900, cp: a1}]\n").races.first.state
    assert_equal :finish_open, compute("crossings:\n  1: [3000]\n").races.first.state
  end

  def test_a_laps_race_ignores_captures_taken_at_checkpoints
    yaml = setup_yaml(bibs: [ 1 ], laps: 3) + "crossings:\n  1: [100, {at: 150, cp: a1}, 200]\n"
    row = Results.compute(input_from(yaml)).races.first.rows.first
    assert_equal 2, row.laps
    assert_equal [], row.splits
  end
end
```

Add to `packs/results/test/resolver_test.rb`:

```ruby
  def test_debounce_is_per_checkpoint
    yaml = setup_yaml(bibs: [ 1 ]) + "crossings:\n  1: [{at: 100, cp: a1}, {at: 103, cp: a1}, 105]\n"
    resolved = Results::Resolver.new(input_from(yaml)).call
    assert_equal [ [ 100_000, "a1" ], [ 105_000, nil ] ], resolved.crossings_by_bib["1"].map { [ it.at_ms, it.checkpoint_id ] }
  end
```

- [ ] **Step 3: Run to verify they fail**

Run: `bin/rails test packs/results/test/course_test.rb packs/results/test/resolver_test.rb`
Expected: FAIL — `unknown keyword: :checkpoint_id` / `:course`.

- [ ] **Step 4: Types**

In `types.rb`:

```ruby
  # finish_with_leader: the race's effective setting (its own override, else the event's).
  # course: nil for a laps race; for a course race its checkpoints in order, ending with the finish (id nil).
  RaceDef = Data.define(:id, :scheduled_at_ms, :finish_with_leader, :expected_laps, :course) do
    def initialize(course: nil, **) = super
  end
  # A timing point on a course; id nil is the finish. cutoff_at_ms: a clock time, or nil.
  Checkpoint = Data.define(:id, :name, :position, :distance_km, :cutoff_at_ms)
```

```ruby
  # checkpoint_id: where it was taken; nil is the finish line.
  Capture = Data.define(:id, :device_id, :device_seq, :captured_at_ms, :clock_offset_ms, :bib, :checkpoint_id) do
    def initialize(checkpoint_id: nil, **) = super
  end
```

```ruby
  Crossing = Data.define(:bib, :at_ms, :ref, :inserted, :checkpoint_id) do # ref: capture id, or ruling id for inserted crossings
    def initialize(checkpoint_id: nil, **) = super
  end
```

```ruby
  # kind: :lap, :finish, :split (a counted checkpoint pass), :duplicate, :before_start, :after_finish, :after_pull;
  # lap / lap_ms only for counted laps.
  CrossingView = Data.define(:ref, :at_ms, :inserted, :kind, :lap, :lap_ms, :checkpoint_id) do
    def initialize(checkpoint_id: nil, **) = super
  end
  RacerResult = Data.define(:place, :bib, :name, :status, :laps, :elapsed_ms, :gap, :lap_times_ms,
                            :crossings, :lap_positions, :pull_at_ms, :finish_ref, :splits) do
    def initialize(splits: [], **) = super
  end
  # One checkpoint (or the finish, checkpoint_id nil) of a course racer's result; times nil when missed.
  Split = Data.define(:checkpoint_id, :at_ms, :elapsed_ms, :segment_ms, :ref, :inserted)
```

- [ ] **Step 5: Resolver — checkpoints on crossings, debounce per checkpoint**

In `resolver.rb`, pass `checkpoint_id: c.checkpoint_id` when building capture crossings and `checkpoint_id: r.payload["checkpoint_id"]` for inserts. Replace `debounce`:

```ruby
    # Collapses taps for the same bib at the same checkpoint that fall within the
    # debounce window of the last kept one, keeping the earliest. Returns
    # [by_bib (time order, every checkpoint), dropped_ref => kept_ref, bib => dropped crossings].
    def debounce(crossings)
      aliases = {}
      dropped = Hash.new { |h, k| h[k] = [] }
      kept_by_key = crossings.group_by { [ it.bib, it.checkpoint_id ] }.transform_values do |list|
        list.sort_by { [ it.at_ms, it.ref ] }.each_with_object([]) do |c, kept|
          if kept.any? && c.at_ms - kept.last.at_ms < @input.config.debounce_ms
            aliases[c.ref] = kept.last.ref
            dropped[c.bib] << c
          else
            kept << c
          end
        end
      end
      by_bib = kept_by_key.group_by { |(bib, _), _| bib }
                          .transform_values { |pairs| pairs.flat_map(&:last).sort_by { [ it.at_ms, it.ref ] } }
      [ by_bib, aliases, dropped.to_h ]
    end
```

- [ ] **Step 6: Laps scoring ignores checkpoint crossings**

In `cohort_scorer.rb`, `post_start` keeps only finish-line crossings:

```ruby
    # Finish-line crossings since the start (a laps race ignores checkpoint captures).
    def post_start(entrant, start)
      return [] unless start
      @resolved.crossings_by_bib.fetch(entrant.bib, []).select { it.at_ms >= start && it.checkpoint_id.nil? }
    end
```

and in `racer_state` pass `seen: @resolved.crossings_by_bib.fetch(entrant.bib, []).select { it.checkpoint_id.nil? }`.

- [ ] **Step 7: `CourseScorer` and `CourseStandings`**

```ruby
# packs/results/lib/results/course_scorer.rb
require "digest"
require "json"

module Results
  # Scores one course race (point to point / single loop): each racer's first
  # crossing at each checkpoint after the start counts, and their first finish
  # crossing finishes them. Finish-with-leader, lap counts and flags don't apply.
  class CourseScorer
    STATUS_KINDS = %w[dnf dns dsq].freeze

    # passes: checkpoint id (nil: the finish) => the counted crossing there.
    CourseRacer = Data.define(:entrant, :race_start, :passes, :status, :finish, :pull_at, :seen, :dropped)
    Scored = Data.define(:race, :start_at, :racers, :race_result)

    def initialize(input, race, resolved)
      @input = input
      @race = race
      @resolved = resolved
      rulings = resolved.rulings
      @start = rulings.latest_by("set_race_start") { it.payload["race_id"] }[race.id]&.payload&.fetch("at_ms")
      @pulls = rulings.latest_by("pull") { it.payload["bib"].to_s }
      @statuses = rulings.all.select { STATUS_KINDS.include?(it.kind) }.group_by { it.payload["bib"].to_s }.transform_values(&:last)
    end

    def call
      racers = @input.entrants.select { it.race_id == @race.id }.map { racer(it) }
      rows = CourseStandings.rows(racers, @race.course)
      state = if @start.nil? then :not_started
      elsif racers.any? { it.finish } then :finish_open
      else :in_progress
      end
      result = RaceResult.new(race_id: @race.id, state:, lap_count: nil, publication: :provisional, rows:, digest: digest(rows),
                              start_at_ms: @start, flag_out_at_ms: nil, flag_out_leader: nil)
      Scored.new(race: @race, start_at: @start, racers:, race_result: result)
    end

    private

    def digest(rows)
      Digest::SHA256.hexdigest(JSON.generate(rows.map { [ it.place, it.bib, it.status.to_s, it.elapsed_ms, it.splits.map(&:at_ms) ] }))
    end

    def racer(entrant)
      bib = entrant.bib
      seen = @resolved.crossings_by_bib.fetch(bib, [])
      known = @race.course.map(&:id).to_set
      after_start = @start ? seen.select { it.at_ms >= @start && known.include?(it.checkpoint_id) } : []
      finish = after_start.find { it.checkpoint_id.nil? }
      pull_at = @pulls[bib]&.payload&.fetch("at_ms")
      pull_at = nil if pull_at && finish && finish.at_ms <= pull_at # a pull at/after the finish does not undo it
      finish = nil if pull_at
      last_at = finish&.at_ms || pull_at
      in_play = last_at ? after_start.select { it.at_ms <= last_at } : after_start
      passes = in_play.group_by(&:checkpoint_id).transform_values(&:first)
      status = if (s = @statuses[bib]) then s.kind.to_sym
      elsif pull_at then :pulled
      elsif finish then :finished
      else :racing
      end
      CourseRacer.new(entrant:, race_start: @start, passes:, status:, finish: (finish if status == :finished), pull_at:,
                      seen:, dropped: @resolved.dropped.fetch(bib, []))
    end
  end
end
```

```ruby
# packs/results/lib/results/course_standings.rb
module Results
  # Ranking within one course race: finishers by time from the gun; then riders
  # still out (and pulled riders) by the furthest checkpoint reached, earliest there first.
  module CourseStandings
    UNPLACED = %i[dnf dns dsq].freeze

    module_function

    def rows(racers, course)
      position = course.to_h { [ it.id, it.position ] }
      reached = ->(r) { r.passes.keys.map { position[it] }.max || 0 }
      last_at = ->(r) { r.passes.values.map(&:at_ms).max || Float::INFINITY }
      finished = racers.select { it.status == :finished }.sort_by { [ it.finish.at_ms, it.finish.ref, it.entrant.bib ] }
      out = racers.select { %i[racing pulled].include?(it.status) }
                  .sort_by { [ it.status == :pulled ? 1 : 0, -reached.(it), last_at.(it), it.entrant.bib ] }
      unplaced = UNPLACED.flat_map { |s| racers.select { it.status == s }.sort_by { it.entrant.bib } }
      leader = finished.first
      (finished + out).each_with_index.map { |r, i| row(r, i + 1, leader, course) } + unplaced.map { row(it, nil, nil, course) }
    end

    def row(racer, place, leader, course)
      last = racer.finish || racer.passes.values.max_by(&:at_ms)
      elapsed = (last.at_ms - racer.race_start if place && last && racer.race_start)
      gap = (Gap.new(laps_down: 0, ms: elapsed - (leader.finish.at_ms - leader.race_start)) if racer.finish && leader && !leader.equal?(racer))
      RacerResult.new(place:, bib: racer.entrant.bib, name: racer.entrant.name, status: racer.status, laps: racer.passes.size,
                      elapsed_ms: elapsed, gap:, lap_times_ms: [], crossings: crossing_views(racer), lap_positions: [],
                      pull_at_ms: racer.pull_at, finish_ref: racer.finish&.ref, splits: splits(racer, course))
    end

    def splits(racer, course)
      previous = racer.race_start
      course.map do |point|
        c = racer.passes[point.id]
        split = Split.new(checkpoint_id: point.id, at_ms: c&.at_ms, elapsed_ms: c && racer.race_start && c.at_ms - racer.race_start,
                          segment_ms: c && previous && c.at_ms - previous, ref: c&.ref, inserted: c&.inserted || false)
        previous = c.at_ms if c
        split
      end
    end

    def crossing_views(racer)
      counted = racer.passes.values.to_h { [ it.ref, it ] }
      views = racer.seen.map do |c|
        kind = if counted.key?(c.ref) then c.checkpoint_id.nil? ? :finish : :split
        elsif racer.race_start.nil? || c.at_ms < racer.race_start then :before_start
        elsif racer.pull_at && c.at_ms > racer.pull_at then :after_pull
        elsif racer.finish && c.at_ms > racer.finish.at_ms then :after_finish
        else :duplicate
        end
        CrossingView.new(ref: c.ref, at_ms: c.at_ms, inserted: c.inserted, kind:, lap: nil, lap_ms: nil, checkpoint_id: c.checkpoint_id)
      end
      views += racer.dropped.map do
        CrossingView.new(ref: it.ref, at_ms: it.at_ms, inserted: it.inserted, kind: :duplicate, lap: nil, lap_ms: nil, checkpoint_id: it.checkpoint_id)
      end
      views.sort_by { [ it.at_ms, it.ref ] }
    end
  end
end
```

Require both in `packs/results/lib/results.rb` after `cohort_scorer` (`course_standings` first, then `course_scorer`).

- [ ] **Step 8: Engine routes course races**

```ruby
    def call
      resolved = Resolver.new(@input).call
      laps_races, course_races = @input.races.uniq(&:id).sort_by(&:id).partition { it.course.nil? }
      scored = cohorts(laps_races).flat_map { score(it, resolved) }
      courses = course_races.map { CourseScorer.new(@input, it, resolved).call }
      races = (scored.flat_map(&:race_results) + courses.map(&:race_result))
              .map { it.with(publication: Publication.for(it.race_id, resolved.rulings, it.digest)) }
      suggestions = Anomalies.new(@input, resolved, scored, courses).call
      Output.new(races:, suggestions:, unassigned: resolved.unassigned)
    end
```

`cohorts(races)` takes the laps races instead of reading `@input.races` (drop its first line). In `anomalies.rb`, accept the extra argument for now: `def initialize(input, resolved, scored_cohorts, courses = [])` storing `@courses` (used in Task 4).

- [ ] **Step 9: Run the engine suite**

Run: `bin/rails test packs/results/test`
Expected: PASS (golden, order-independence and flag-out tests unchanged).

- [ ] **Step 10: Rubocop and commit**

```bash
bin/rubocop
git add packs/results
git commit -m "Course events: the engine scores course races from checkpoint passes, with splits"
```

---

### Task 4: Engine — missed checkpoint, overdue and cutoff problems

**Files:**
- Create: `packs/results/lib/results/course_anomalies.rb`
- Modify: `packs/results/lib/results/anomalies.rb`, `packs/results/lib/results.rb`
- Test: `packs/results/test/course_anomalies_test.rb`

**Interfaces:**
- Consumes: `CourseScorer::Scored`, `CourseRacer`, `Checkpoint` (Task 3).
- Produces: suggestions of kind `:missed_checkpoint` (key `missed_checkpoint:#{bib}:#{checkpoint_id}`, fix `insert_capture` with `checkpoint_id`), `:overdue` (key `overdue:#{bib}:#{last_ref || 'start'}`, fix `dnf`), `:cutoff` (key `cutoff:#{bib}:#{checkpoint_id || 'finish'}`, fix `pull` at the cutoff).

- [ ] **Step 1: Write the failing tests**

```ruby
# packs/results/test/course_anomalies_test.rb
require "test_helper"

class CourseAnomaliesTest < Minitest::Test
  include ResultsTestHelpers

  # Gun at 0; Aid 1 at 30 km, Aid 2 at 60 km (cutoff 2:30 elapsed), finish at 100 km.
  SETUP = <<~YAML
    races:
      - {id: r1, start: 0, course: [{id: a1, name: Aid 1, km: 30}, {id: a2, name: Aid 2, km: 60, cutoff: 9000}], finish_km: 100}
    entrants:
      - {bib: 1, race: r1}
      - {bib: 2, race: r1}
      - {bib: 3, race: r1}
      - {bib: 4, race: r1}
  YAML

  def suggestions(yaml, now:) = Results.compute(input_from(SETUP + yaml + "now: #{now}\n")).suggestions

  def test_a_rider_seen_later_but_not_at_a_checkpoint_gets_an_insert_interpolated_by_distance
    found = suggestions("crossings:\n  1: [{at: 3000, cp: a1}, 10000]\n", now: 10_000).find { it.kind == :missed_checkpoint }
    assert_equal "missed_checkpoint:1:a2", found.key
    # 30 km at 3000 s, 100 km at 10000 s: 60 km at 6000 s.
    assert_equal({ "kind" => "insert_capture", "bib" => "1", "at_ms" => 6_000_000, "checkpoint_id" => "a2" }, found.fix)
    assert_match(/Aid 2/, found.message)
  end

  def test_without_distances_the_insert_is_the_midpoint
    yaml = SETUP.gsub(/, km: \d+/, "").sub(", finish_km: 100", "")
    found = Results.compute(input_from(yaml + "crossings:\n  1: [{at: 3000, cp: a1}, 10000]\nnow: 10000\n")).suggestions
                   .find { it.kind == :missed_checkpoint }
    assert_equal 6_500_000, found.fix["at_ms"]
  end

  def test_overdue_from_the_riders_own_pace
    # 30 km in 3000 s: 30 more km should take 3000 s; overdue after 1.5x that (7500 s), and past the cutoff too.
    assert_empty suggestions("crossings:\n  1: [{at: 3000, cp: a1}]\n", now: 7_400).select { it.kind == :overdue }
    found = suggestions("crossings:\n  1: [{at: 3000, cp: a1}]\n", now: 7_600).find { it.kind == :overdue }
    assert_equal [ "overdue:1:c-1-1", { "kind" => "dnf", "bib" => "1" } ], [ found.key, found.fix ]
  end

  def test_overdue_from_the_field_when_there_are_no_distances
    yaml = SETUP.gsub(/, km: \d+/, "").sub(", finish_km: 100", "").sub(", cutoff: 9000", "")
    crossings = "crossings:\n  1: [{at: 1000, cp: a1}, {at: 2000, cp: a2}]\n  2: [{at: 1000, cp: a1}, {at: 2100, cp: a2}]\n" \
                "  3: [{at: 1000, cp: a1}, {at: 2200, cp: a2}]\n  4: [{at: 1000, cp: a1}]\n"
    found = Results.compute(input_from(yaml + crossings + "now: 2700\n")).suggestions.select { it.kind == :overdue }
    assert_equal [ "4" ], found.map(&:bib) # field median 1100 s × 1.5 = 1650 s after 1000 s
    assert_empty Results.compute(input_from(yaml + "crossings:\n  4: [{at: 1000, cp: a1}]\nnow: 99000\n")).suggestions.select { it.kind == :overdue }
  end

  def test_cutoff_missed_or_reached_late_suggests_a_pull_at_the_cutoff
    late = suggestions("crossings:\n  1: [{at: 3000, cp: a1}, {at: 9500, cp: a2}]\n", now: 9_600).find { it.kind == :cutoff }
    assert_equal [ "cutoff:1:a2", { "kind" => "pull", "bib" => "1", "at_ms" => 9_000_000 } ], [ late.key, late.fix ]
    assert suggestions("crossings:\n  1: [{at: 3000, cp: a1}]\n", now: 9_100).any? { it.kind == :cutoff }
    assert_empty suggestions("crossings:\n  1: [{at: 3000, cp: a1}]\n", now: 8_900).select { it.kind == :cutoff }
  end

  def test_a_rider_pulled_at_the_cutoff_who_taps_the_finish_stays_pulled_with_no_new_problems
    yaml = "crossings:\n  1: [{at: 3000, cp: a1}, {at: 9500, cp: a2}, 12000]\nrulings:\n  - {kind: pull, bib: 1, at: 9000}\n"
    out = Results.compute(input_from(SETUP + yaml + "now: 12100\n"))
    assert_equal :pulled, out.races.first.rows.first.status
    assert_empty out.suggestions.select { it.bib == "1" }
  end

  def test_finished_and_dnf_riders_raise_nothing
    yaml = "crossings:\n  1: [{at: 3000, cp: a1}, {at: 6000, cp: a2}, 10000]\n  2: [{at: 3000, cp: a1}]\nrulings:\n  - {kind: dnf, bib: 2}\n"
    assert_empty suggestions(yaml, now: 99_000).select { %w[1 2].include?(it.bib) }
  end
end
```

- [ ] **Step 2: Run to verify it fails**

Run: `bin/rails test packs/results/test/course_anomalies_test.rb`
Expected: FAIL — no `:missed_checkpoint` suggestions.

- [ ] **Step 3: Implement `CourseAnomalies`**

```ruby
# packs/results/lib/results/course_anomalies.rb
module Results
  # Problems on course races: a checkpoint skipped, a rider overdue at their
  # next checkpoint, a cutoff missed. Suggestions only, like Anomalies.
  class CourseAnomalies
    OVERDUE_FACTOR = 1.5
    MIN_FIELD = 3

    def initialize(input, courses)
      @now = input.now_ms
      @courses = courses
    end

    def call = @courses.flat_map { |scored| scored.racers.flat_map { racer_suggestions(it, scored) } }

    private

    def racer_suggestions(racer, scored)
      return [] unless racer.race_start && %i[racing finished].include?(racer.status)
      course = scored.race.course
      missed = missed_checkpoints(racer, course, scored)
      return missed if racer.status == :finished
      missed + Array(cutoff(racer, course, scored)) + Array(overdue(racer, course, scored))
    end

    # A checkpoint with no pass while a later checkpoint (or the finish) has one.
    def missed_checkpoints(racer, course, scored)
      course.each_with_index.filter_map do |point, i|
        next if point.id.nil? || racer.passes.key?(point.id)
        after = course[(i + 1)..].find { racer.passes.key?(it.id) } or next
        before = course[0...i].reverse.find { racer.passes.key?(it.id) }
        at = interpolate(racer, before, point, after)
        bib = racer.entrant.bib
        Suggestion.new(key: "missed_checkpoint:#{bib}:#{point.id}", kind: :missed_checkpoint, bib:, race_id: scored.race.id,
                       message: "Bib #{bib} was seen at #{after.name} but not at #{point.name} — missed tap, or cut the course?",
                       fix: { "kind" => "insert_capture", "bib" => bib, "at_ms" => at, "checkpoint_id" => point.id })
      end
    end

    # By distance when all three are known (the start is 0 km), else the midpoint.
    def interpolate(racer, before, point, after)
      from_at = before ? racer.passes[before.id].at_ms : racer.race_start
      from_km = before ? before.distance_km : 0
      to_at = racer.passes[after.id].at_ms
      if from_km && point.distance_km && after.distance_km && after.distance_km > from_km
        from_at + ((to_at - from_at) * (point.distance_km - from_km) / (after.distance_km - from_km).to_f).round
      else
        (from_at + to_at) / 2
      end
    end

    # The first checkpoint whose cutoff has passed without the rider, or that they reached late.
    def cutoff(racer, course, scored)
      point = course.find do |p|
        next false unless p.cutoff_at_ms
        pass = racer.passes[p.id]
        pass ? pass.at_ms > p.cutoff_at_ms : @now > p.cutoff_at_ms && course.drop(p.position).none? { racer.passes.key?(it.id) }
      end
      return nil unless point
      bib = racer.entrant.bib
      Suggestion.new(key: "cutoff:#{bib}:#{point.id || 'finish'}", kind: :cutoff, bib:, race_id: scored.race.id,
                     message: "Bib #{bib} missed the #{point.name} cutoff — pull?",
                     fix: { "kind" => "pull", "bib" => bib, "at_ms" => point.cutoff_at_ms })
    end

    def overdue(racer, course, scored)
      last_point = course.select { racer.passes.key?(it.id) }.max_by(&:position)
      last_at = last_point ? racer.passes[last_point.id].at_ms : racer.race_start
      next_point = course[last_point ? last_point.position : 0] or return nil
      expected = own_pace(racer, last_point, next_point) || field(scored, last_point, next_point)
      return nil unless expected && @now > last_at + (expected * OVERDUE_FACTOR).round
      bib = racer.entrant.bib
      ref = last_point && racer.passes[last_point.id].ref
      where = last_point ? "at #{last_point.name}" : "since the start"
      Suggestion.new(key: "overdue:#{bib}:#{ref || 'start'}", kind: :overdue, bib:, race_id: scored.race.id,
                     message: "Bib #{bib} is overdue at #{next_point.name}: last seen #{where} #{fmt(@now - last_at)} ago, " \
                              "expected about #{fmt(expected)} — stopped? Mark DNF",
                     fix: { "kind" => "dnf", "bib" => bib })
    end

    # Their pace so far (time per km to their last checkpoint) over the next segment's distance.
    def own_pace(racer, last_point, next_point)
      return nil unless last_point&.distance_km&.positive? && next_point.distance_km && next_point.distance_km > last_point.distance_km
      elapsed = racer.passes[last_point.id].at_ms - racer.race_start
      elapsed * (next_point.distance_km - last_point.distance_km) / last_point.distance_km.to_f
    end

    # The median time others in the race took between the same two points.
    def field(scored, from, to)
      times = scored.racers.filter_map do |r|
        to_pass = r.passes[to.id] or next
        from_at = from ? r.passes[from.id]&.at_ms : r.race_start
        to_pass.at_ms - from_at if from_at
      end
      times.size >= MIN_FIELD ? Anomalies.median(times) : nil
    end

    def fmt(ms)
      minutes = (ms / 60_000.0).round
      format("%d:%02d", minutes / 60, minutes % 60)
    end
  end
end
```

Require it in `results.rb` before `anomalies`. In `Anomalies#call`, add `CourseAnomalies.new(@input, @courses).call` to the concatenation (before `clock_suggestions`), so dismissal and key order apply to it too.

- [ ] **Step 4: Run the engine suite**

Run: `bin/rails test packs/results/test`
Expected: PASS.

- [ ] **Step 5: Rubocop and commit**

```bash
bin/rubocop
git add packs/results
git commit -m "Course events: missed checkpoint, overdue and cutoff problems"
```

---

### Task 5: API — course setup, standings with splits, device locations

**Files:**
- Modify: `packs/timing/app/models/results_snapshot.rb`
- Modify: `packs/timing/app/models/ruling.rb` (comment only: `insert_capture` may carry `checkpoint_id`)
- Create: `packs/api/app/graphql/types/checkpoint_type.rb`, `types/checkpoint_input.rb`, `types/split_type.rb`
- Create: `packs/api/app/graphql/mutations/set_checkpoints.rb`, `mutations/set_device_checkpoint.rb`
- Modify: `types/event_type.rb`, `types/discipline_type.rb`, `types/sub_discipline_type.rb`, `types/standing_row_type.rb`, `types/racer_detail_type.rb`, `types/racer_crossing_type.rb`, `types/crossing_kind_enum.rb`, `types/suggestion_kind_enum.rb`, `types/device_type.rb`, `types/mutation_type.rb`
- Modify: `mutations/create_event.rb`, `mutations/update_event.rb`, `mutations/insert_crossing.rb`, `mutations/create_pairing_token.rb`, `packs/api/app/graphql/racer_detail.rb`
- Test: `test/integration/api/course_test.rb`

**Interfaces:**
- Consumes: Tasks 1–4.
- Produces (GraphQL):
  - `Event.raceFormat: String!`, `Event.checkpoints: [Checkpoint!]!` (`id name position distanceKm cutoffAtMs`), `Event.finishDistanceKm: Float`, `Event.finishCutoffAtMs: Millis`.
  - `Discipline.course`, `SubDiscipline.course: Boolean!`.
  - `createEvent/updateEvent(raceFormat: String)`.
  - `setCheckpoints(eventId: ID!, checkpoints: [CheckpointInput!]!, finishDistanceKm: Float, finishCutoffAtMs: Millis): { event, errors }` — replaces the list in the given order; `CheckpointInput { id: ID, name: String!, distanceKm: Float, cutoffAtMs: Millis }`.
  - `StandingRow.splits: [Split!]!` (`checkpointId: ID` — null is the finish — `atMs elapsedMs segmentMs inserted`); `RacerDetail.splits` (same); `RacerCrossing.checkpointId: ID`; `CrossingKind.SPLIT`; `SuggestionKind.MISSED_CHECKPOINT`, `CUTOFF`.
  - `insertCrossing(..., checkpointId: ID)`.
  - `Device.checkpointId: ID`; `setDeviceCheckpoint(deviceId: ID!, checkpointId: ID): { device, errors }` (chief); `createPairingToken(eventId, checkpointId: ID)`.

- [ ] **Step 1: Write the failing API test**

```ruby
# test/integration/api/course_test.rb
require "test_helper"

class CourseApiTest < ActionDispatch::IntegrationTest
  SET = <<~GQL
    mutation($id: ID!, $cps: [CheckpointInput!]!, $km: Float) {
      setCheckpoints(eventId: $id, checkpoints: $cps, finishDistanceKm: $km) { event { checkpoints { id name position distanceKm } finishDistanceKm } errors }
    }
  GQL
  STANDINGS = <<~GQL
    query($id: ID!) { standings(eventId: $id) { races { lapCount rows { bib place status splits { checkpointId atMs segmentMs inserted } } } suggestions { key kind } } }
  GQL

  setup do
    sign_in(create_official(name: "Admin Ann", role: "admin", pin: "2468"), "2468")
    @event = create_event(discipline: "gravel")
    @race = create_race(event: @event)
    register(race: @race, bib: "1")
  end

  def set(cps, km: nil) = gql(SET, id: @event.id, cps:, km:).dig("data", "setCheckpoints")

  test "an admin sets the course; checkpoints come back in order; the finish distance is the event's" do
    body = set([ { name: "Aid 1", distanceKm: 30 }, { name: "Aid 2", distanceKm: 62.5 } ], km: 100)
    assert_empty body["errors"]
    assert_equal [ [ "Aid 1", 1, 30.0 ], [ "Aid 2", 2, 62.5 ] ], body.dig("event", "checkpoints").map { it.values_at("name", "position", "distanceKm") }
    assert_equal 100.0, body.dig("event", "finishDistanceKm")
  end

  test "a checkpoint with captures can be renamed but not removed or moved" do
    ids = set([ { name: "Aid 1" }, { name: "Aid 2" } ]).dig("event", "checkpoints").map { it["id"] }
    record_capture(device: create_device(event: @event), seq: 1, at_ms: 1_000, bib: "1", checkpoint: Checkpoint.find(ids.first))
    assert_equal [ "Aid 1 has crossings recorded at it, so it can't be removed or moved" ], set([ { id: ids.last, name: "Aid 2" } ])["errors"]
    assert_equal [ "Aid 1 has crossings recorded at it, so it can't be removed or moved" ],
                 set([ { id: ids.last, name: "Aid 2" }, { id: ids.first, name: "Aid 1" } ])["errors"]
    assert_empty set([ { id: ids.first, name: "Aid One" }, { id: ids.last, name: "Aid 2" } ])["errors"]
  end

  test "standings carry splits; a missed checkpoint is a problem whose fix inserts a crossing there" do
    aid1, aid2 = set([ { name: "Aid 1", distanceKm: 30 }, { name: "Aid 2", distanceKm: 60 } ], km: 90).dig("event", "checkpoints").map { it["id"] }
    start = Clock.now_ms - 10_000_000
    rule(event: @event, kind: "set_race_start", race_id: @race.id, at_ms: start)
    tablet = create_device(event: @event)
    record_capture(device: tablet, seq: 1, at_ms: start + 3_000_000, bib: "1", checkpoint: Checkpoint.find(aid1))
    record_capture(device: tablet, seq: 2, at_ms: start + 9_000_000, bib: "1")
    report = gql(STANDINGS, id: @event.id).dig("data", "standings")
    row = report.dig("races", 0, "rows", 0)
    assert_equal [ aid1, aid2, nil ], row["splits"].map { it["checkpointId"] }
    assert_equal [ start + 3_000_000, nil, start + 9_000_000 ], row["splits"].map { it["atMs"] }
    assert_nil report.dig("races", 0, "lapCount")
    missed = report["suggestions"].find { it["kind"] == "MISSED_CHECKPOINT" }
    gql("mutation($id: ID!, $key: String!) { acceptSuggestion(eventId: $id, key: $key) { errors } }", id: @event.id, key: missed["key"])
    inserted = gql(STANDINGS, id: @event.id).dig("data", "standings", "races", 0, "rows", 0, "splits", 1)
    assert_equal [ start + 6_000_000, true ], inserted.values_at("atMs", "inserted")
  end

  test "insertCrossing takes a checkpoint, which must be this event's" do
    aid = set([ { name: "Aid 1" } ]).dig("event", "checkpoints", 0, "id")
    rule(event: @event, kind: "set_race_start", race_id: @race.id, at_ms: 0)
    query = "mutation($e: ID!, $cp: ID) { insertCrossing(eventId: $e, bib: \"1\", atMs: 5000, checkpointId: $cp) { errors } }"
    assert_empty gql(query, e: @event.id, cp: aid).dig("data", "insertCrossing", "errors")
    other = create_event(name: "Other").checkpoints.create!(position: 1, name: "X")
    assert_equal [ "That checkpoint isn't on this event's course" ], gql(query, e: @event.id, cp: other.id).dig("data", "insertCrossing", "errors")
  end

  test "the chief moves a device to a checkpoint, and a pairing code can carry one" do
    aid = set([ { name: "Aid 1" } ]).dig("event", "checkpoints", 0, "id")
    device = create_device(event: @event)
    body = gql("mutation($d: ID!, $cp: ID) { setDeviceCheckpoint(deviceId: $d, checkpointId: $cp) { device { checkpointId } errors } }", d: device.id, cp: aid)
    assert_equal aid, body.dig("data", "setDeviceCheckpoint", "device", "checkpointId")
    gql("mutation($e: ID!, $cp: ID) { createPairingToken(eventId: $e, checkpointId: $cp) { errors } }", e: @event.id, cp: aid)
    assert_equal aid, PairingToken.last.checkpoint_id
  end

  test "the event's format can be changed, and gravel defaults to course" do
    assert_equal "course", gql("query($id: ID!) { event(id: $id) { raceFormat } }", id: @event.id).dig("data", "event", "raceFormat")
    gql("mutation($id: ID!) { updateEvent(id: $id, raceFormat: \"laps\") { errors } }", id: @event.id)
    assert_equal "laps", @event.reload.race_format
  end
end
```

- [ ] **Step 2: Run to verify it fails**

Run: `bin/rails test test/integration/api/course_test.rb`
Expected: FAIL — `Field 'setCheckpoints' doesn't exist`.

- [ ] **Step 3: Snapshot**

In `results_snapshot.rb`, build the course once per event and pass checkpoints on captures:

```ruby
  def self.for(event, now_ms:)
    course = course_for(event)
    Results::Input.new(
      races: event.races.map do
        Results::RaceDef.new(id: it.id, scheduled_at_ms: it.scheduled_at_ms, finish_with_leader: it.effective_finish_with_leader,
                             expected_laps: it.expected_laps, course:)
      end,
```

and `checkpoint_id: it.checkpoint_id` in the `Results::Capture.new` call.

```ruby
  # A course event's checkpoints then the finish (id nil); nil for a laps event.
  def self.course_for(event)
    return nil unless event.course?
    points = event.checkpoints.map do
      Results::Checkpoint.new(id: it.id, name: it.name, position: it.position, distance_km: it.distance_km&.to_f, cutoff_at_ms: it.cutoff_at_ms)
    end
    points + [ Results::Checkpoint.new(id: nil, name: "Finish", position: points.size + 1, distance_km: event.finish_distance_km&.to_f,
                                       cutoff_at_ms: event.finish_cutoff_at_ms) ]
  end
```

- [ ] **Step 4: Types**

```ruby
# packs/api/app/graphql/types/checkpoint_type.rb
module Types
  class CheckpointType < BaseObject
    field :id, ID, null: false
    field :name, String, null: false
    field :position, Integer, null: false, description: "1 is the first after the start; the finish is always after the last"
    field :distance_km, Float
    field :cutoff_at_ms, Millis, description: "Clock time riders must reach it by, or null"

    def distance_km = object.distance_km&.to_f
  end
end
```

```ruby
# packs/api/app/graphql/types/checkpoint_input.rb
module Types
  class CheckpointInput < BaseInputObject
    argument :id, ID, required: false, description: "An existing checkpoint to keep (omit for a new one)"
    argument :name, String
    argument :distance_km, Float, required: false
    argument :cutoff_at_ms, Millis, required: false
  end
end
```

```ruby
# packs/api/app/graphql/types/split_type.rb
module Types
  class SplitType < BaseObject
    field :checkpoint_id, ID, description: "Null for the finish"
    field :at_ms, Millis, description: "Null when the racer has no crossing there"
    field :elapsed_ms, Millis
    field :segment_ms, Millis, description: "Since the previous checkpoint they were seen at (or the start)"
    field :inserted, Boolean, null: false
  end
end
```

`EventType`: add

```ruby
    field :race_format, String, null: false, description: "laps, or course (point to point / single loop)"
    field :checkpoints, [ CheckpointType ], null: false, description: "A course's timing points in order; the finish is after the last"
    field :finish_distance_km, Float
    field :finish_cutoff_at_ms, Millis

    def finish_distance_km = object.finish_distance_km&.to_f
```

`DisciplineType`/`SubDisciplineType`: `field :course, Boolean, null: false, description: "Default: point to point / single loop rather than laps"`.

`StandingRowType` and `RacerDetailType`: `field :splits, [ SplitType ], null: false, description: "Course races: one per checkpoint, then the finish"`. `RacerCrossingType`: `field :checkpoint_id, ID, description: "Where it was taken; null is the finish"`. `CrossingKindEnum`: `value "SPLIT", value: :split, description: "Counted at a checkpoint"`. `SuggestionKindEnum`: `value "MISSED_CHECKPOINT", value: :missed_checkpoint` and `value "CUTOFF", value: :cutoff`; change OVERDUE's description to `"Racing, but long past when they were expected (at the finish, or at their next checkpoint): stopped?"`. `DeviceType`: `field :checkpoint_id, ID, description: "Where it is on the course; null is the finish"`.

`racer_detail.rb`: add `splits: row&.splits || []` and, per crossing, `checkpoint_id: v.checkpoint_id`.

- [ ] **Step 5: Mutations**

`create_event.rb` and `update_event.rb`: `argument :race_format, String, required: false`.

```ruby
# packs/api/app/graphql/mutations/set_checkpoints.rb
module Mutations
  class SetCheckpoints < BaseMutation
    description "Replace a course's checkpoints, in course order. Checkpoints with crossings recorded at them stay, in place."
    argument :event_id, ID
    argument :checkpoints, [ Types::CheckpointInput ]
    argument :finish_distance_km, Float, required: false
    argument :finish_cutoff_at_ms, Types::Millis, required: false

    field :event, Types::EventType

    def resolve(event_id:, checkpoints:, finish_distance_km: nil, finish_cutoff_at_ms: nil)
      require_official!("admin")
      event = Event.find(event_id)
      existing = event.checkpoints.to_a
      used = Capture.where(checkpoint_id: existing.map(&:id)).distinct.pluck(:checkpoint_id).to_set
      wanted = checkpoints.map { it.to_h }
      kept_ids = wanted.filter_map { it[:id] }
      # A checkpoint with crossings recorded at it must stay, at the same position.
      stuck = existing.find { used.include?(it.id) && wanted.index { |w| w[:id] == it.id } != it.position - 1 }
      return { event: nil, errors: [ "#{stuck.name} has crossings recorded at it, so it can't be removed or moved" ] } if stuck
      Event.transaction do
        event.checkpoints.where.not(id: kept_ids).destroy_all
        event.checkpoints.update_all("position = position + 10000") # free the positions for the new order
        wanted.each.with_index(1) do |attrs, position|
          cp = attrs[:id] ? event.checkpoints.find(attrs[:id]) : event.checkpoints.build
          cp.update!(position:, name: attrs[:name], distance_km: attrs[:distance_km], cutoff_at_ms: attrs[:cutoff_at_ms])
        end
        event.update!(finish_distance_km:, finish_cutoff_at_ms:)
      end
      { event: event.reload, errors: [] }
    rescue ActiveRecord::RecordInvalid => e
      { event: nil, errors: e.record.errors.full_messages }
    end
  end
end
```

(`kept_ids` is `wanted.filter_map { it[:id] }`; keep that line above the check.)

```ruby
# packs/api/app/graphql/mutations/set_device_checkpoint.rb
module Mutations
  class SetDeviceCheckpoint < BaseMutation
    description "Move a phone to a checkpoint (null: the finish); it picks this up at its next sync"
    argument :device_id, ID
    argument :checkpoint_id, ID, required: false

    field :device, Types::DeviceType

    def resolve(device_id:, checkpoint_id: nil)
      require_official!("chief")
      device = Device.find(device_id)
      if checkpoint_id && !Checkpoint.exists?(id: checkpoint_id, event_id: device.event_id)
        return { device: nil, errors: [ "That checkpoint isn't on this event's course" ] }
      end
      device.move_to!(checkpoint_id, at_ms: Clock.now_ms)
      { device: device.reload, errors: [] }
    end
  end
end
```

`create_pairing_token.rb`: `argument :checkpoint_id, ID, required: false`; pass `checkpoint_id:` to `PairingToken.issue!`.

`insert_crossing.rb`:

```ruby
    argument :checkpoint_id, ID, required: false, description: "Where (a course checkpoint); omit for the finish"

    def resolve(event_id:, bib:, at_ms:, checkpoint_id: nil)
      ...
      if checkpoint_id && !event.checkpoints.exists?(id: checkpoint_id)
        return refuse("That checkpoint isn't on this event's course")
      end
      record(event:, kind: "insert_capture", payload: { bib:, at_ms:, checkpoint_id: }.compact)
```

Register `set_checkpoints` and `set_device_checkpoint` in `mutation_type.rb` next to their neighbours (`update_event`, `revoke_device`).

In `ruling.rb`, update the `KINDS` comment: `# kind => payload keys that must be present (insert_capture may also carry checkpoint_id)`.

- [ ] **Step 6: Run the API and full Ruby suites**

Run: `bin/rails test test/integration/api/course_test.rb && PARALLEL_WORKERS=1 bin/rails test`
Expected: PASS. Then dump the schema if the repo keeps one (`ls frontend/schema.graphql` — if present, regenerate with the same task the repo uses; `grep -rn "schema.graphql" bin lib Rakefile` finds it).

- [ ] **Step 7: Rubocop and commit**

```bash
bin/rubocop
git add packs test/integration/api/course_test.rb
git commit -m "Course events: API for courses, splits, checkpoint problems and device locations"
```

---

### Task 6: Phone capture app — location picker and stamped captures

**Files:**
- Create: `frontend/capture/src/location.ts`, `frontend/capture/src/location.test.ts`
- Modify: `frontend/capture/src/log.ts`, `frontend/capture/src/api.ts`, `frontend/capture/src/sync.ts`, `frontend/capture/src/App.tsx`
- Test: `frontend/capture/src/log.test.ts`, `frontend/capture/src/sync.test.ts`

**Interfaces:**
- Consumes: roster `checkpoints: {id, name}[]`, `device: {checkpoint_id: string|null, checkpoint_set_at_ms: number|null}` (Task 2); log entry `kind: "location"`.
- Produces:
  - `type Location = { checkpointId: string | null; changedAtMs: number }` stored in the `state` store under `"location"`.
  - `shouldAdopt(local: Location | null, hub: Roster["device"]): boolean`.
  - `locationName(checkpointId, roster): string` ("Finish" for null, "Unknown checkpoint" if not on the roster).
  - `appendLocation(db, checkpointId, atMs, offsetMs)`; `appendCapture(db, { atMs, offsetMs, bib, checkpointId })`.

- [ ] **Step 1: Write the failing tests**

```ts
// frontend/capture/src/location.test.ts
import { describe, expect, it } from "vitest";
import { locationName, shouldAdopt } from "./location";

const roster = { checkpoints: [{ id: "a1", name: "Aid 1" }] } as never;

describe("shouldAdopt", () => {
  it("takes the hub's location when an official moved the phone after its own last change", () => {
    expect(shouldAdopt({ checkpointId: null, changedAtMs: 1_000 }, { checkpoint_id: "a1", checkpoint_set_at_ms: 2_000 })).toBe(true);
  });
  it("keeps the phone's when its change is newer, or the hub already agrees", () => {
    expect(shouldAdopt({ checkpointId: null, changedAtMs: 3_000 }, { checkpoint_id: "a1", checkpoint_set_at_ms: 2_000 })).toBe(false);
    expect(shouldAdopt({ checkpointId: "a1", changedAtMs: 1_000 }, { checkpoint_id: "a1", checkpoint_set_at_ms: 2_000 })).toBe(false);
  });
  it("a phone that never chose takes whatever the hub has set, and ignores a hub that never set one", () => {
    expect(shouldAdopt(null, { checkpoint_id: "a1", checkpoint_set_at_ms: 2_000 })).toBe(true);
    expect(shouldAdopt(null, { checkpoint_id: null, checkpoint_set_at_ms: null })).toBe(false);
  });
});

describe("locationName", () => {
  it("names the finish and known checkpoints", () => {
    expect(locationName(null, roster)).toBe("Finish");
    expect(locationName("a1", roster)).toBe("Aid 1");
    expect(locationName("zz", roster)).toBe("Unknown checkpoint");
  });
});
```

Add to the `describe("the phone's log")` block in `log.test.ts` (import `appendLocation` too):

```ts
it("stamps a capture with its checkpoint, and logs location changes", async () => {
  const db = await fresh();
  const capture = await appendCapture(db, { atMs: 1_000, offsetMs: 0, bib: "7", checkpointId: "a1" });
  expect(capture.checkpoint_id).toBe("a1");
  const finish = await appendCapture(db, { atMs: 2_000, offsetMs: 0, bib: "7", checkpointId: null });
  expect("checkpoint_id" in finish).toBe(false); // omitted, so it hashes as before
  const moved = await appendLocation(db, "a2", 3_000, 0);
  expect([moved.kind, moved.checkpoint_id, moved.captured_at_ms]).toEqual(["location", "a2", 3_000]);
});
```

Add to `sync.test.ts` (import `allEntries` from `./log` and `type Roster` from `./api`):

```ts
const rosterWith = (device: Roster["device"]): Roster =>
  ({ event: { name: "E", races: [] }, racers: [], checkpoints: [{ id: "a1", name: "Aid 1" }], device, version: "v1" });

describe("location", () => {
  it("adopts a move the chief made after the phone's own last change, and logs it", async () => {
    const db = await setup();
    await db.put("state", { checkpointId: null, changedAtMs: 1_000 }, "location");
    const { api } = fakeHub();
    api.roster = async () => rosterWith({ checkpoint_id: "a1", checkpoint_set_at_ms: 2_000 });
    const s = sync(db, api);
    await s.load();
    await s.refreshRoster();
    expect(s.state().location).toEqual({ checkpointId: "a1", changedAtMs: 2_000 });
    const [entry] = await allEntries(db);
    expect([entry.kind, entry.checkpoint_id, entry.captured_at_ms]).toEqual(["location", "a1", 2_000]);
  });

  it("keeps the phone's choice when it is newer than the hub's", async () => {
    const db = await setup();
    await db.put("state", { checkpointId: null, changedAtMs: 3_000 }, "location");
    const { api } = fakeHub();
    api.roster = async () => rosterWith({ checkpoint_id: "a1", checkpoint_set_at_ms: 2_000 });
    const s = sync(db, api);
    await s.load();
    await s.refreshRoster();
    expect(s.state().location).toEqual({ checkpointId: null, changedAtMs: 3_000 });
    expect(await allEntries(db)).toEqual([]);
  });

  it("setLocation logs the move and remembers it", async () => {
    const db = await setup();
    const s = sync(db, fakeHub().api);
    await s.load();
    await s.setLocation("a1");
    expect(s.state().location?.checkpointId).toBe("a1");
    expect((await allEntries(db)).map((e) => e.kind)).toEqual(["location"]);
  });
});
```

- [ ] **Step 2: Run to verify they fail**

Run: `cd frontend && npx vitest run capture/src/location.test.ts capture/src/log.test.ts capture/src/sync.test.ts`
Expected: FAIL — module `./location` not found.

- [ ] **Step 3: Implement**

```ts
// frontend/capture/src/location.ts
import type { Roster } from "./api";

// Where this phone is on the course (null: the finish line), and when that was
// last chosen, in hub time.
export type Location = { checkpointId: string | null; changedAtMs: number };

// The hub wins when an official moved the phone after the phone's own last change.
export function shouldAdopt(local: Location | null, hub: Roster["device"]): boolean {
  if (hub.checkpoint_set_at_ms == null) return false;
  if (local && hub.checkpoint_id === local.checkpointId) return false;
  return !local || hub.checkpoint_set_at_ms > local.changedAtMs;
}

export function locationName(checkpointId: string | null, roster: Pick<Roster, "checkpoints"> | null): string {
  if (checkpointId == null) return "Finish";
  return roster?.checkpoints.find((c) => c.id === checkpointId)?.name ?? "Unknown checkpoint";
}
```

`api.ts`: extend `Roster` with `checkpoints: { id: string; name: string }[]; device: { checkpoint_id: string | null; checkpoint_set_at_ms: number | null }`.

`log.ts`: add `"location"` to `Entry["kind"]` and `checkpoint_id?: string` to `Entry`;

```ts
// checkpointId: where the phone is (absent or null: the finish, and the entry hashes exactly as before).
export function appendCapture(db: CaptureDb, tap: { atMs: number; offsetMs: number | null; bib: string; checkpointId?: string | null }): Promise<Entry> {
  return append(db, { kind: "capture", captured_at_ms: Math.round(tap.atMs), clock_offset_ms: tap.offsetMs ?? undefined, bib: tap.bib.trim() || undefined,
    checkpoint_id: tap.checkpointId ?? undefined });
}

// The phone moved (null: to the finish). atMs is phone time, like a capture's.
export const appendLocation = (db: CaptureDb, checkpointId: string | null, atMs: number, offsetMs: number | null) =>
  append(db, { kind: "location", checkpoint_id: checkpointId ?? undefined, captured_at_ms: Math.round(atMs), clock_offset_ms: offsetMs ?? undefined });
```

`sync.ts`: add `location: Location | null` to `SyncState` (loaded from `state`/`"location"` in `load()`), and export `setLocation(checkpointId)` from `createSync`'s returned object:

```ts
  // The volunteer (or, via the roster, an official) moved this phone.
  async function setLocation(checkpointId: string | null, hubAtMs = now() + (state.offsetMs ?? 0)) {
    const location = { checkpointId, changedAtMs: hubAtMs };
    await appendLocation(db, checkpointId, hubAtMs - (state.offsetMs ?? 0), state.offsetMs);
    await db.put("state", location, "location");
    set({ location });
    await countPending();
  }
```

In `refreshRoster`, inside `if (roster) { ... }` after `set({ roster })`, add:

```ts
        if (shouldAdopt(state.location, roster.device)) await setLocation(roster.device.checkpoint_id, roster.device.checkpoint_set_at_ms!);
```

and return `setLocation` from `createSync` alongside `refreshRoster`.

`App.tsx`: in the AppBar `Toolbar`, after the event name, a `Chip` (`data-testid="location"`) labelled `locationName(state?.location?.checkpointId ?? null, state?.roster ?? null)`, shown only when the roster has checkpoints. Tapping it opens a `Dialog` with a `List` of "Finish" plus each roster checkpoint (`ListItemButton`, the current one `selected`); choosing calls `sync.setLocation(id)` and closes. Pass `checkpointId: state?.location?.checkpointId ?? null` into every `appendCapture` call.

- [ ] **Step 4: Run tests and typecheck**

Run: `cd frontend && npx vitest run capture && npm run typecheck`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add frontend/capture/src
git commit -m "Capture app: choose this phone's checkpoint; captures carry it"
```

---

### Task 7: Console setup — format, checkpoints editor, phone locations

**Files:**
- Create: `frontend/src/course.ts`, `frontend/src/course.test.ts`, `frontend/src/views/CheckpointsEditor.tsx`
- Modify: `frontend/src/queries.ts`, `frontend/src/views/EventFields.tsx`, `frontend/src/views/SetupScreen.tsx`, `frontend/src/views/PhonesPanel.tsx`

**Interfaces:**
- Consumes: GraphQL from Task 5.
- Produces:
  - `parseCutoff(text: string, startMs: number | null, timeZone: string, date: string): { atMs: number } | { error: string } | null` — `""` → `null`; `"2:30 pm"`, `"14:30"` → clock time that day in the event's zone; `"+6:30"` or `"6:30 elapsed"` → `startMs + 6.5 h` (error `"Set a race's scheduled start before entering an elapsed cutoff"` when `startMs` is null).
  - `formatCutoff(atMs, timeZone): string` ("2:30 pm").
  - `queries.ts`: `EventInfo.raceFormat`, `checkpoints: CheckpointInfo[]`, `finishDistanceKm`, `finishCutoffAtMs`; `SET_CHECKPOINTS`, `SET_DEVICE_CHECKPOINT`; `PhoneRow.checkpointId`; `Discipline.course`.

- [ ] **Step 1: Write the failing tests**

```ts
// frontend/src/course.test.ts
import { describe, expect, it } from "vitest";
import { formatCutoff, parseCutoff } from "./course";

const zone = "America/Los_Angeles";
const start = Date.parse("2026-10-17T15:00:00Z"); // 8:00 am Pacific

describe("parseCutoff", () => {
  it("reads a clock time on the event's day, in its time zone", () => {
    expect(parseCutoff("2:30 pm", start, zone, "2026-10-17")).toEqual({ atMs: Date.parse("2026-10-17T21:30:00Z") });
    expect(parseCutoff("14:30", start, zone, "2026-10-17")).toEqual({ atMs: Date.parse("2026-10-17T21:30:00Z") });
  });
  it("reads an elapsed time from the start", () => {
    expect(parseCutoff("+6:30", start, zone, "2026-10-17")).toEqual({ atMs: start + 6.5 * 3_600_000 });
    expect(parseCutoff("6:30 elapsed", start, zone, "2026-10-17")).toEqual({ atMs: start + 6.5 * 3_600_000 });
  });
  it("empty clears the cutoff; nonsense and elapsed-without-a-start are errors", () => {
    expect(parseCutoff("  ", start, zone, "2026-10-17")).toBeNull();
    expect(parseCutoff("soon", start, zone, "2026-10-17")).toEqual({ error: "Enter a time like 2:30 pm, or +6:30 for elapsed" });
    expect(parseCutoff("+6:30", null, zone, "2026-10-17")).toEqual({ error: "Set a race's scheduled start before entering an elapsed cutoff" });
  });
});

describe("formatCutoff", () => {
  it("shows the clock time in the event's zone", () => {
    expect(formatCutoff(Date.parse("2026-10-17T21:30:00Z"), zone)).toBe("2:30 pm");
  });
});
```

- [ ] **Step 2: Run to verify it fails**

Run: `cd frontend && npx vitest run src/course.test.ts`
Expected: FAIL — module not found.

- [ ] **Step 3: Implement `course.ts`**

Check `frontend/src/format.ts` first for an existing "wall clock in a zone → ms" helper (the Start screen converts scheduled times); reuse it if present. Otherwise:

```ts
// frontend/src/course.ts
// Cutoffs are stored as clock times; officials may type either a clock time
// ("2:30 pm", "14:30") or an elapsed time from the start ("+6:30", "6:30 elapsed").

const ELAPSED = /^\+?\s*(\d{1,2}):(\d{2})(?:\s*elapsed)?$/i;
const CLOCK = /^(\d{1,2}):(\d{2})\s*(am|pm)?$/i;

export type Cutoff = { atMs: number } | { error: string } | null;

export function parseCutoff(text: string, startMs: number | null, timeZone: string, date: string): Cutoff {
  const t = text.trim();
  if (!t) return null;
  const elapsed = t.startsWith("+") || /elapsed$/i.test(t) ? t.match(ELAPSED) : null;
  if (elapsed) {
    if (startMs == null) return { error: "Set a race's scheduled start before entering an elapsed cutoff" };
    return { atMs: startMs + (Number(elapsed[1]) * 60 + Number(elapsed[2])) * 60_000 };
  }
  const clock = t.match(CLOCK);
  if (!clock) return { error: "Enter a time like 2:30 pm, or +6:30 for elapsed" };
  let hour = Number(clock[1]) % (clock[3] ? 12 : 24);
  if (clock[3]?.toLowerCase() === "pm") hour += 12;
  return { atMs: zonedMs(date, hour, Number(clock[2]), timeZone) };
}

// The instant a wall-clock time on a date happens in a time zone.
function zonedMs(date: string, hour: number, minute: number, timeZone: string): number {
  const guess = Date.parse(`${date}T${String(hour).padStart(2, "0")}:${String(minute).padStart(2, "0")}:00Z`);
  const parts = new Intl.DateTimeFormat("en-US", { timeZone, hourCycle: "h23", year: "numeric", month: "2-digit", day: "2-digit", hour: "2-digit", minute: "2-digit" })
    .formatToParts(guess).reduce<Record<string, string>>((acc, p) => ({ ...acc, [p.type]: p.value }), {});
  const shown = Date.parse(`${parts.year}-${parts.month}-${parts.day}T${parts.hour}:${parts.minute}:00Z`);
  return guess - (shown - guess);
}

export function formatCutoff(atMs: number, timeZone: string): string {
  return new Intl.DateTimeFormat("en-US", { timeZone, hour: "numeric", minute: "2-digit" }).format(atMs).replace(/\s?([AP])M$/, (_, x) => ` ${x.toLowerCase()}m`);
}
```

- [ ] **Step 4: Queries and screens**

`queries.ts`:

```ts
export type CheckpointInfo = { id: string; name: string; position: number; distanceKm: number | null; cutoffAtMs: number | null };
```

Add `raceFormat: string; checkpoints: CheckpointInfo[]; finishDistanceKm: number | null; finishCutoffAtMs: number | null` to `EventInfo`, and `raceFormat checkpoints { id name position distanceKm cutoffAtMs } finishDistanceKm finishCutoffAtMs` to the `EVENT` query. Add `raceFormat` to `EventInput`, `CREATE_EVENT` and `UPDATE_EVENT` (`$raceFormat: String` / `raceFormat: $raceFormat`). Add `course` to `Discipline`/`DISCIPLINES` (and to `subDisciplines`).

```ts
export const SET_CHECKPOINTS = gql`
  mutation SetCheckpoints($eventId: ID!, $checkpoints: [CheckpointInput!]!, $finishDistanceKm: Float, $finishCutoffAtMs: Millis) {
    setCheckpoints(eventId: $eventId, checkpoints: $checkpoints, finishDistanceKm: $finishDistanceKm, finishCutoffAtMs: $finishCutoffAtMs) { errors }
  }
`;
export const SET_DEVICE_CHECKPOINT = gql`
  mutation SetDeviceCheckpoint($deviceId: ID!, $checkpointId: ID) { setDeviceCheckpoint(deviceId: $deviceId, checkpointId: $checkpointId) { errors } }
`;
```

Add `checkpointId` to the `DEVICES` query and `PhoneRow`; add `$checkpointId: ID` to `CREATE_PAIRING_TOKEN`.

`EventFields.tsx`: a "Format" `TextField select` with `Laps` / `Point to point / single loop` (values `laps`/`course`). When the discipline or sub-discipline changes, reset it to the discipline default (`course ? "course" : "laps"`), the same way the field already resets `finishWithLeader`. Hide the finish-with-leader switch when the format is `course`.

`CheckpointsEditor.tsx` (rendered by `SetupScreen` under the Event paper when `event.raceFormat === "course"`): a `Paper` titled "Course" with a row per checkpoint — name `TextField`, distance (km) `TextField type="number"`, cutoff `TextField` (helper text: the parsed clock time via `formatCutoff`, or the parse error in red), up/down `IconButton`s, delete `IconButton` — then a fixed last row "Finish" with distance and cutoff only, "Add checkpoint" and "Save course" buttons. Cutoff text starts as `formatCutoff(cutoffAtMs)` for saved values. Elapsed cutoffs use the earliest race `scheduledAtMs` in the event as `startMs` (null when the event has no races). Save is disabled while any cutoff has an error; it calls `SET_CHECKPOINTS` with `{ id, name, distanceKm, cutoffAtMs }` per row and shows the returned errors in an `Alert`.

`PhonesPanel.tsx` (takes the event so it knows the checkpoints): when the event is a course event, each device row gets a `TextField select` (size small) of "Finish" + checkpoints bound to `checkpointId`, calling `SET_DEVICE_CHECKPOINT` on change and refetching `DEVICES`; the pairing dialog gets the same select before the code is created, passed as `checkpointId` to `CREATE_PAIRING_TOKEN`.

- [ ] **Step 5: Run tests, typecheck and lint**

Run: `cd frontend && npm test && npm run typecheck`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add frontend/src
git commit -m "Console: course format, checkpoints and cutoffs, and where each phone is"
```

---

### Task 8: Console race screen — splits, Course board, racer panel, problems

**Files:**
- Modify: `frontend/src/course.ts`, `frontend/src/course.test.ts`
- Create: `frontend/src/views/CourseStandings.tsx`, `frontend/src/views/CourseBoard.tsx`
- Modify: `frontend/src/queries.ts`, `frontend/src/views/RaceScreen.tsx`, `frontend/src/views/RacerPanel.tsx`, `frontend/src/racerPanel.ts`, `frontend/src/problems.ts`, `frontend/src/problems.test.ts`

**Interfaces:**
- Consumes: `Row.splits`, `RacerDetail.splits`, crossing `checkpointId`/`SPLIT`, suggestion kinds (Task 5); `CheckpointInfo` (Task 7).
- Produces:
  - `courseBoard(race: RaceStandings, checkpoints: CheckpointInfo[], nowMs: number): Board` where `Board = { points: { id: string | null; name: string; passed: number; toCome: number; cutoffAtMs: number | null }[]; out: { bib: string; name: string; lastName: string; lastAtMs: number | null; nextName: string; etaMs: number | null; late: boolean }[] }` — `out` lists riders still racing, furthest first; `etaMs` from the median segment time of riders who have done that segment (null with fewer than one); `late` when `nowMs > etaMs`.
  - Problem types `missedCheckpoint` ("Missed checkpoint", warning) and `cutoff` ("Missed cutoff", error).

- [ ] **Step 1: Write the failing tests**

Add to `course.test.ts`:

```ts
import { courseBoard } from "./course";

const checkpoints = [{ id: "a1", name: "Aid 1", position: 1, distanceKm: 30, cutoffAtMs: null }];
const split = (checkpointId: string | null, atMs: number | null) => ({ checkpointId, atMs, elapsedMs: null, segmentMs: null, inserted: false });
const race = {
  startAtMs: 0,
  rows: [
    { bib: "1", name: "Ann", status: "FINISHED", splits: [split("a1", 1_000), split(null, 3_000)] },
    { bib: "2", name: "Bo", status: "RACING", splits: [split("a1", 1_200), split(null, null)] },
    { bib: "3", name: "Cy", status: "RACING", splits: [split("a1", null), split(null, null)] },
  ],
} as never;

describe("courseBoard", () => {
  it("counts who has passed each point and lists riders still out, furthest first, with an ETA at their next point", () => {
    const board = courseBoard(race, checkpoints, 3_000);
    expect(board.points.map((p) => [p.name, p.passed, p.toCome])).toEqual([["Aid 1", 2, 1], ["Finish", 1, 2]]);
    expect(board.out.map((r) => [r.bib, r.lastName, r.nextName, r.etaMs])).toEqual([
      ["2", "Aid 1", "Finish", 1_200 + 2_000],
      ["3", "Start", "Aid 1", 1_000],
    ]);
    expect(board.out.map((r) => r.late)).toEqual([false, true]);
  });
});
```

In `problems.test.ts`: `MISSED_CHECKPOINT` maps to `missedCheckpoint` and `CUTOFF` to `cutoff`.

- [ ] **Step 2: Run to verify they fail**

Run: `cd frontend && npx vitest run src/course.test.ts src/problems.test.ts`
Expected: FAIL.

- [ ] **Step 3: Implement `courseBoard` and the problem types**

```ts
// in frontend/src/course.ts
import type { CheckpointInfo, RaceStandings } from "./queries";

export type Board = {
  points: { id: string | null; name: string; passed: number; toCome: number; cutoffAtMs: number | null }[];
  out: { bib: string; name: string; lastName: string; lastAtMs: number | null; nextName: string; etaMs: number | null; late: boolean }[];
};

const median = (xs: number[]) => {
  const s = [...xs].sort((a, b) => a - b);
  return s.length ? (s.length % 2 ? s[(s.length - 1) / 2] : (s[s.length / 2 - 1] + s[s.length / 2]) / 2) : null;
};

// Where everyone is on a course race: per point, how many have passed and are
// still to come; then each rider still out, furthest first, with an ETA at
// their next point from the field's median time on that segment.
export function courseBoard(race: RaceStandings, checkpoints: CheckpointInfo[], nowMs: number, finishCutoffAtMs: number | null = null): Board {
  const names = [...checkpoints.map((c) => c.name), "Finish"];
  const ids = [...checkpoints.map((c) => c.id), null];
  const cutoffs = [...checkpoints.map((c) => c.cutoffAtMs), finishCutoffAtMs];
  const racing = race.rows.filter((r) => r.status === "RACING");
  const points = ids.map((id, i) => {
    const passed = race.rows.filter((r) => r.splits[i]?.atMs != null).length;
    return { id, name: names[i], passed, toCome: racing.filter((r) => r.splits[i]?.atMs == null).length, cutoffAtMs: cutoffs[i] };
  });
  const segment = (i: number) =>
    median(race.rows.flatMap((r) => {
      const to = r.splits[i]?.atMs;
      const from = i === 0 ? race.startAtMs : r.splits[i - 1]?.atMs;
      return to != null && from != null ? [to - from] : [];
    }));
  const out = racing.map((r) => {
    const last = r.splits.reduce((acc, s, i) => (s.atMs != null ? i : acc), -1);
    const lastAtMs = last >= 0 ? r.splits[last].atMs : race.startAtMs;
    const next = Math.min(last + 1, ids.length - 1);
    const seg = segment(next);
    const etaMs = lastAtMs != null && seg != null ? lastAtMs + seg : null;
    return { bib: r.bib, name: r.name, lastName: last >= 0 ? names[last] : "Start", lastAtMs, nextName: names[next], etaMs, late: etaMs != null && nowMs > etaMs, _last: last };
  });
  out.sort((a, b) => b._last - a._last || (a.lastAtMs ?? 0) - (b.lastAtMs ?? 0));
  return { points, out: out.map(({ _last, ...rest }) => rest) };
}
```

In `queries.ts`: `export type Split = { checkpointId: string | null; atMs: number | null; elapsedMs: number | null; segmentMs: number | null; inserted: boolean };`, add `splits: Split[]` to `Row`, and `splits { checkpointId atMs elapsedMs segmentMs inserted }` to the `STANDINGS` rows and the `RACER` query (plus `checkpointId` on its crossings).

In `problems.ts` add `{ id: "missedCheckpoint", label: "Missed checkpoint", color: "warning" }` and `{ id: "cutoff", label: "Missed cutoff", color: "error" }` to `PROBLEM_TYPES` (after `overdue`), and `MISSED_CHECKPOINT: "missedCheckpoint"`, `CUTOFF: "cutoff"` to `BY_KIND`.

- [ ] **Step 4: Views**

`CourseStandings.tsx`: same `Paper`/`Table` shape and props as `Standings` (`race`, `controls`, `onRowClick`) plus `checkpoints`. Heading: `{race.race.name} — {state label}` (no lap count). Columns: place, bib, name, status chip (same `STATUS_COLOR`/`statusLabel`), one column per checkpoint then "Finish" showing the split's clock time (`formatClock` from `format.ts`) with `title` = `segment … · elapsed …` (`formatElapsed`), inserted ones in italics, missed as "—"; then total (`formatElapsed(row.elapsedMs)`) and gap.

`CourseBoard.tsx`: props `race`, `checkpoints`, `finishCutoffAtMs`, `timeZone`, `onRowClick`. Top: a row of small `Paper`s, one per point: name, "N passed · M to come", cutoff (`formatCutoff`) if set. Below: a `Table` of `board.out` (bib, name, last point + clock time, next point, ETA), rows with `late` highlighted (`sx={{ bgcolor: "warning.light" }}`) and clickable. Recompute with `Date.now()` on each render (standings already poll every 5 s).

`RaceScreen.tsx`: `const course = event.data.event.raceFormat === "course"`. The view toggle offers Category | Wave for laps events and Results | Course for course events (state values `"category" | "wave" | "course"`; `?view=course` remembered like `wave`). For course events: Results renders `CourseStandings` per race with `RaceControls` given a new `course` prop; Course renders `CourseBoard` per race. `RaceControls`: when `course` is true, hide the lap-count field and the Flag out controls (keep start/unstart).

`RacerPanel.tsx` / `racerPanel.ts`: when `detail.splits.length > 0`, show a "Checkpoints" list (name, clock time, segment, elapsed; "—" when missed; "inserted" tag) above the crossings, and label crossing kind `SPLIT` as the checkpoint's name in `kindLabel` (pass the checkpoint names map). The "Insert crossing" dialog gets a "Where" select (Finish + checkpoints) for course events, passed as `checkpointId` to `INSERT_CROSSING` (add `$checkpointId: ID` to that mutation).

- [ ] **Step 5: Run tests, typecheck, build**

Run: `cd frontend && npm test && npm run typecheck && npm run build`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add frontend/src
git commit -m "Console: course results with splits, the Course board, and checkpoint problems"
```

---

### Task 9: Course replay — a synthetic gravel race through the hub

**Files:**
- Create: `lib/race_simulator/data/gravel_demo/course.yml`
- Create: `lib/race_simulator/course_replay.rb`
- Modify: `bin/replay-race`, `lib/race_simulator/writer.rb`
- Test: `test/lib/race_simulator/course_replay_test.rb`

**Interfaces:**
- Consumes: everything above (models, `Capture.record!` stamping `device.checkpoint_id`, `ResultsSnapshot.compute`).
- Produces: `RaceSimulator::CourseReplay.load(name) -> Dataset`, `.setup!(dataset) -> Event`, `.run(event:, dataset:, out: $stdout)`; `bin/replay-race --dataset gravel_demo` picks it when the folder has `course.yml`. `Writer.new(event:, device_name:, checkpoint: nil)`.

- [ ] **Step 1: The dataset**

```yaml
# lib/race_simulator/data/gravel_demo/course.yml
# A made-up 100 km gravel race to exercise course events: elapsed times at each
# checkpoint, then the finish; "-" is a missed tap; a short list means the rider stopped.
event:
  name: Gravel Demo
  date: "2026-10-17"
  timezone: America/Los_Angeles
  discipline: gravel
  location: Hood River, OR
gun: "08:00"
checkpoints:
  - { name: Aid 1, km: 30 }
  - { name: Aid 2, km: 62, cutoff: "10:30" }
finish: { km: 100 }
races:
  - name: 100K Open
    riders:
      "105": ["1:02:00", "2:05:00", "3:20:00"]
      "101": ["1:00:00", "2:10:00", "3:30:00"]
      "102": ["1:05:00", "-", "3:40:00"]   # missed tap at Aid 2
      "103": ["1:20:00", "2:50:00"]        # reached Aid 2 after the cutoff, still out
      "104": ["1:10:00"]                   # stopped after Aid 1
```

- [ ] **Step 2: Write the failing test**

```ruby
# test/lib/race_simulator/course_replay_test.rb
require "test_helper"

class RaceSimulator::CourseReplayTest < ActiveSupport::TestCase
  DATASET = RaceSimulator::CourseReplay.load("gravel_demo")

  test "setup builds a course event with its checkpoints, cutoff and finish distance" do
    event = RaceSimulator::CourseReplay.setup!(DATASET)
    assert event.course?
    assert_equal [ [ "Aid 1", 30 ], [ "Aid 2", 62 ] ], event.checkpoints.map { [ it.name, it.distance_km.to_i ] }
    zone = Time.find_zone("America/Los_Angeles")
    assert_equal zone.parse("2026-10-17 10:30").to_i * 1000, event.checkpoints.last.cutoff_at_ms
    assert_equal 100, event.finish_distance_km.to_i
  end

  test "five hours in: places, splits and the expected problems" do
    event = RaceSimulator::CourseReplay.setup!(DATASET)
    RaceSimulator::CourseReplay.run(event:, dataset: DATASET, out: StringIO.new)
    gun = Time.find_zone("America/Los_Angeles").parse("2026-10-17 08:00").to_i * 1000
    output = ResultsSnapshot.compute(event, now_ms: gun + 5 * 3_600_000)
    rows = output.races.first.rows
    assert_equal [ [ 1, "105", :finished ], [ 2, "101", :finished ], [ 3, "102", :finished ], [ 4, "103", :racing ], [ 5, "104", :racing ] ],
                 rows.map { [ it.place, it.bib, it.status ] }
    assert_equal [ 3_720_000, 7_500_000, 12_000_000 ], rows.first.splits.map(&:elapsed_ms)
    problems = output.suggestions.map { [ it.kind, it.bib ] }.sort
    assert_equal [ [ :cutoff, "103" ], [ :cutoff, "104" ], [ :missed_checkpoint, "102" ], [ :overdue, "104" ] ], problems
  end
end
```

- [ ] **Step 3: Run to verify it fails**

Run: `bin/rails test test/lib/race_simulator/course_replay_test.rb`
Expected: FAIL — `uninitialized constant RaceSimulator::CourseReplay`.

- [ ] **Step 4: Implement**

`writer.rb`: `def initialize(event:, device_name: "Simulator", checkpoint: nil)`; `device` pairs with `checkpoint_id: @checkpoint&.id` (`Device.pair!(event: @event, name: @device_name, checkpoint_id: @checkpoint&.id).first`).

```ruby
# lib/race_simulator/course_replay.rb
require "yaml"

module RaceSimulator
  # Replays a course event (point to point / single loop) from a dataset of
  # elapsed times at each checkpoint: one phone per checkpoint and one at the finish.
  module CourseReplay
    Rider = Data.define(:bib, :elapsed_s) # elapsed_s: seconds per point, nil for a missed tap; short = stopped
    RaceData = Data.define(:name, :riders) # not Race: that would hide the Race model in this module
    Dataset = Data.define(:event, :gun, :checkpoints, :finish, :races)

    module_function

    def load(name)
      yaml = YAML.safe_load_file(Pathname(__dir__).join("data", name, "course.yml"))
      races = yaml.fetch("races").map do |r|
        RaceData.new(name: r.fetch("name"), riders: r.fetch("riders").map { |bib, times| Rider.new(bib: bib.to_s, elapsed_s: times.map { seconds(it) }) })
      end
      Dataset.new(event: yaml.fetch("event").transform_keys(&:to_sym), gun: yaml.fetch("gun"), checkpoints: yaml.fetch("checkpoints"),
                  finish: yaml.fetch("finish", {}), races:)
    end

    # "1:02:00" → 3720; "-" → nil.
    def seconds(text) = text == "-" ? nil : text.split(":").map(&:to_i).inject { |a, b| a * 60 + b }

    def setup!(dataset)
      details = dataset.event
      zone = Time.find_zone!(details[:timezone])
      clock = ->(hhmm) { hhmm && zone.parse("#{details[:date]} #{hhmm}").to_i * 1000 }
      event = Event.create!(name: Replay.unused_name(details[:name]), date: Date.parse(details[:date]), location: details[:location],
                            discipline: details[:discipline], timezone: details[:timezone], race_format: "course",
                            finish_distance_km: dataset.finish["km"], finish_cutoff_at_ms: clock.(dataset.finish["cutoff"]))
      dataset.checkpoints.each.with_index(1) do |c, position|
        event.checkpoints.create!(position:, name: c.fetch("name"), distance_km: c["km"], cutoff_at_ms: clock.(c["cutoff"]))
      end
      dataset.races.each do |r|
        race = Race.create!(event:, name_override: r.name, gender: "open", scheduled_at_ms: clock.(dataset.gun))
        r.riders.each do |rider|
          racer = Racer.create!(first_name: Replay::FIRST["F"].sample(random: Random.new(rider.bib.to_i)),
                                last_name: Replay::LAST.sample(random: Random.new(rider.bib.to_i)), gender: "F",
                                birth_date: Date.new(1990, 1, 1))
          Registration.create!(race:, racer:, bib: rider.bib)
        end
      end
      event
    end

    def run(event:, dataset:, out: $stdout)
      points = event.checkpoints.to_a + [ nil ]
      writers = points.map { Writer.new(event:, device_name: "#{it&.name || 'Finish'} phone", checkpoint: it) }
      event.races.each do |race|
        gun = race.scheduled_at_ms
        writers.last.start_races([ race ], at_ms: gun)
        dataset.races.find { it.name == race.name }.riders.each do |rider|
          rider.elapsed_s.each_with_index { |s, i| writers[i].capture(at_ms: gun + s * 1000, bib: rider.bib) if s }
        end
      end
      out.puts "#{event.name} (#{event.id}): replayed #{dataset.races.sum { it.riders.size }} riders over #{points.size} timing points"
    end
  end
end
```

`bin/replay-race`: after parsing options and loading the environment:

```ruby
if File.exist?(Rails.root.join("lib/race_simulator/data", options[:dataset], "course.yml"))
  dataset = RaceSimulator::CourseReplay.load(options[:dataset])
  event = RaceSimulator::CourseReplay.setup!(dataset)
  RaceSimulator::CourseReplay.run(event:, dataset:)
  exit
end
```

(`--speed`, `--check` and `--fit` apply to lap datasets only; say so in the option help: `"(lap datasets)"`.)

- [ ] **Step 5: Run the tests**

Run: `bin/rails test test/lib/race_simulator`
Expected: PASS (the Cascade Locks replays unchanged).

- [ ] **Step 6: Rubocop and commit**

```bash
bin/rubocop
git add lib/race_simulator bin/replay-race test/lib/race_simulator/course_replay_test.rb
git commit -m "Course replay: a made-up gravel race exercises splits, missed checkpoints, overdue and cutoffs"
```

---

### Task 10: End-to-end check and docs

**Files:**
- Modify: `frontend/e2e/seed.rb`
- Create: `frontend/e2e/course.spec.ts`
- Modify: `docs/TODO.md`, `docs/hub-runbook.md`

**Interfaces:**
- Consumes: everything above.

- [ ] **Step 1: Seed a course event**

In `frontend/e2e/seed.rb`, after the existing events, create "E2E Gravel" (gravel, `race_format: "course"`), checkpoints Aid 1 (30 km) and Aid 2 (60 km), finish 100 km, one race started an hour ago, bibs 701 and 702, an "Aid 1 phone" device at Aid 1 and a finish device; captures: 701 at Aid 1 (+20 min), Aid 2 (+40 min), finish (+55 min); 702 at Aid 1 (+25 min) and the finish (+58 min) — so 702 has a missed checkpoint. Follow the file's existing style for creating devices and captures (`Capture.record!`).

- [ ] **Step 2: Write the spec**

```ts
// frontend/e2e/course.spec.ts
import { expect, test } from "@playwright/test";
import { signIn, openEvent } from "./fixtures"; // use the helpers race.spec.ts uses

test("a course event shows splits, the Course board, and a missed checkpoint", async ({ page }) => {
  await signIn(page, "chief");
  await openEvent(page, "E2E Gravel", "race");
  const results = page.getByRole("region", { name: /E2E Gravel|Open/ }).first();
  await expect(results.getByRole("columnheader", { name: "Aid 1" })).toBeVisible();
  await expect(results.getByRole("columnheader", { name: "Finish" })).toBeVisible();
  await expect(results.getByRole("row", { name: /702/ })).toContainText("—");
  await page.getByRole("button", { name: "Course" }).click();
  await expect(page.getByText(/2 passed/).first()).toBeVisible();
  await expect(page.getByText("Missed checkpoint").first()).toBeVisible();
});
```

Adjust the helper imports and race-section name to what `frontend/e2e/race.spec.ts` actually uses (read it first; reuse its sign-in and navigation code rather than inventing helpers).

- [ ] **Step 3: Run the e2e suite**

Run: `cd frontend && npm run build && npx playwright test`
Expected: PASS (all specs; the full run reseeds).

- [ ] **Step 4: Docs**

`docs/TODO.md`: replace the "Intermediate timing (split points on course)" section with a note that course events have checkpoints (this plan), and add under it the deferred items: splits within laps (checkpoints on a laps course); out-and-back / repeated checkpoints; individual-start time trials; fixed-time races (most laps in N hours); per-race courses (short and long course in one event).

`docs/hub-runbook.md`: a short "Course events" section — set the format and checkpoints on the Event screen; pair each aid-station phone with its checkpoint (or pick it on the phone; the chief can move phones on the Devices screen); Results shows splits, Course shows who has passed where; problems: missed checkpoint, overdue, missed cutoff. And `bin/replay-race --dataset gravel_demo` for a demo course event.

- [ ] **Step 5: Full verification and commit**

Run: `bin/rubocop && PARALLEL_WORKERS=1 bin/rails test && cd frontend && npm test && npm run typecheck`
Expected: all PASS.

```bash
git add frontend/e2e docs/TODO.md docs/hub-runbook.md
git commit -m "Course events: end-to-end check and docs"
```
