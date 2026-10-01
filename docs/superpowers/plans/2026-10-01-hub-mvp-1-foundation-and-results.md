# Hub MVP — Plan 1: Foundation & Results Engine

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A Rails 8.1 app that runs in hub (SQLite) or cloud (Postgres) mode, holds the event setup data and append-only race log, and computes standings + anomaly suggestions with a pure-Ruby results engine verified by golden race files.

**Architecture:** One Rails codebase organized as packs (`packs/events`, `packs/timing`) with packwerk enforcing boundaries. The results engine lives in `packs/results/lib` as plain Ruby (no Rails, no DB) — a pure function from an `Input` snapshot to an `Output`. A thin adapter (`ResultsSnapshot`) turns DB records into that snapshot.

**Tech Stack:** Ruby 3.4.x, Rails 8.1.3, SQLite 3 (hub), PostgreSQL 17 (cloud/CI), Minitest, packs-rails, packwerk, GitHub Actions.

**Spec:** `docs/superpowers/specs/2026-10-01-hub-mvp-design.md` (§2, §3, §4, §8 durability, §10 results/CI testing)

**This is plan 1 of 3 for the Hub MVP spec.** Plan 2: sync protocol v1 + capture PWA. Plan 3: GraphQL API, access/pairing, ops console, race simulator, acceptance test.

## Global Constraints

- Ruby **3.4.x** (needed for `SecureRandom.uuid_v7`); Rails **8.1.3**.
- `TIMING_MODE` = `hub` (default) | `cloud`; `TIMING_DB` = `sqlite3` | `postgresql` (defaults: hub→sqlite3, cloud→postgresql).
- All primary keys are **UUIDv7 strings** (`id: :string`); domain timestamps are **integer milliseconds since epoch** (`*_ms` bigint columns).
- SQLite runs `journal_mode=WAL`, `synchronous=FULL`.
- `packs/results/lib` must not require Rails, ActiveSupport, or touch a database.
- Race log tables (`device_entries`, `rulings`) are append-only: persisted rows are read-only.
- Bibs are strings everywhere; bib is unique within an event.
- Engine defaults: debounce 10 000 ms; missed 1.7×–2.3×; neighbors 0.7×–1.3×; short < 0.5×; unassigned match window ±0.15 × reference lap.
- Full Rails suite runs on **both** SQLite and Postgres in CI.

## Review Focus

1. **Two riders crossing in the same millisecond** — order must be deterministic and identical regardless of arrival order (tie-break by crossing id). Test in Task 5.
2. **Race with no start ruling yet** (gun not fired) — engine returns `:not_started`, every rider at 0 laps, no crash, and crossings (warm-up laps) don't count. Test in Task 5.
3. **`flag_finish` pointing at a capture that was later voided or reassigned** — the flag must be ignored, not crash or finish the rider on a phantom crossing. Test in Task 5.
4. **Revert of a revert** — the original ruling must come back into force. Test in Task 4.
5. **`assign_bib` to a bib that isn't registered** (typo) — capture goes to unassigned with that bib shown, never silently dropped. Test in Task 4.

---

## File Structure

```
.ruby-version
Gemfile                                  (+ pg, packs-rails, packwerk)
config/application.rb                    requires lib/timing_mode, loads results lib
config/database.yml                      adapter chosen by TimingMode
lib/timing_mode.rb                       TIMING_MODE / TIMING_DB parsing
package.yml, packwerk.yml                root pack config
bin/test-results                         runs engine tests without Rails
.github/workflows/ci.yml                 sqlite + postgres matrix
app/models/application_record.rb         UUIDv7 ids
packs/events/package.yml
packs/events/app/models/{event,category,start_group,race,rider,registration,eligibility}.rb
packs/timing/package.yml
packs/timing/app/models/concerns/append_only.rb
packs/timing/app/models/{device,device_entry,capture,bib_assignment,ruling,results_snapshot}.rb
packs/results/lib/results.rb             entry point: Results.compute(input)
packs/results/lib/results/types.rb       Data structs (input, derived, output)
packs/results/lib/results/active_rulings.rb
packs/results/lib/results/resolver.rb    §4.1 crossing resolution
packs/results/lib/results/group_scorer.rb §4.2 finish logic
packs/results/lib/results/standings.rb   §4.3 ranking
packs/results/lib/results/log_digest.rb
packs/results/lib/results/publication.rb
packs/results/lib/results/anomalies.rb   §4.4 suggestions
packs/results/lib/results/engine.rb
packs/results/test/test_helper.rb
packs/results/test/support/fixture.rb    YAML race file → Input
packs/results/test/support/helpers.rb
packs/results/test/*_test.rb
packs/results/test/fixtures/races/*.yml  golden race files
db/migrate/*                             events + timing tables
test/support/build_helpers.rb
test/lib/timing_mode_test.rb
test/integration/database_config_test.rb
test/models/*_test.rb
```

---

### Task 1: Rails skeleton, modes, dual database, packs, CI

**Files:**
- Create: `.ruby-version`, `lib/timing_mode.rb`, `config/database.yml` (overwrite), `package.yml`, `packs/events/package.yml`, `packs/timing/package.yml`, `bin/test-results`, `.github/workflows/ci.yml`, `test/lib/timing_mode_test.rb`, `test/integration/database_config_test.rb`, `test/support/build_helpers.rb`
- Modify: `config/application.rb`, `app/models/application_record.rb`, `test/test_helper.rb`, `Gemfile`

**Interfaces:**
- Produces: `TimingMode.mode -> "hub"|"cloud"`, `TimingMode.hub?`, `TimingMode.cloud?`, `TimingMode.database_adapter -> "sqlite3"|"postgresql"`; `ApplicationRecord` assigns `SecureRandom.uuid_v7` ids; `bin/test-results`.

- [ ] **Step 1: Install Ruby 3.4 and Rails 8.1.3**

```bash
cd /Users/rmiles/1000paces/git/timing
RUBY_VER=$(rbenv install -l | grep -E '^3\.4\.[0-9]+$' | tail -1)
rbenv install -s "$RUBY_VER"
rbenv local "$RUBY_VER"
ruby -e 'require "securerandom"; puts SecureRandom.uuid_v7'
gem install rails -v 8.1.3
```
Expected: a UUID like `0199a1b2-...-7...` prints (version nibble `7`).

- [ ] **Step 2: Generate the API app into the existing repo**

```bash
rails _8.1.3_ new . --api --database=sqlite3 --skip-kamal --skip-thruster --skip-docker --skip-ci \
  --skip-action-mailer --skip-action-mailbox --skip-action-text --skip-active-storage --skip-jbuilder
bundle add pg packs-rails packwerk
bundle binstubs packwerk
```
When asked to overwrite `.gitignore` or other files, answer `Y`. `docs/` is untouched.

- [ ] **Step 3: Write the failing mode tests**

`test/lib/timing_mode_test.rb`:
```ruby
require "test_helper"

class TimingModeTest < ActiveSupport::TestCase
  def with_env(vars)
    old = vars.keys.to_h { [it, ENV[it]] }
    vars.each { |k, v| ENV[k] = v }
    yield
  ensure
    old.each { |k, v| ENV[k] = v }
  end

  test "defaults to hub mode on sqlite" do
    with_env("TIMING_MODE" => nil, "TIMING_DB" => nil) do
      assert TimingMode.hub?
      assert_equal "sqlite3", TimingMode.database_adapter
    end
  end

  test "cloud mode defaults to postgresql" do
    with_env("TIMING_MODE" => "cloud", "TIMING_DB" => nil) do
      assert TimingMode.cloud?
      assert_equal "postgresql", TimingMode.database_adapter
    end
  end

  test "TIMING_DB overrides the adapter" do
    with_env("TIMING_MODE" => "hub", "TIMING_DB" => "postgresql") do
      assert_equal "postgresql", TimingMode.database_adapter
    end
  end

  test "rejects unknown values" do
    with_env("TIMING_MODE" => "venue") { assert_raises(ArgumentError) { TimingMode.mode } }
    with_env("TIMING_MODE" => "hub", "TIMING_DB" => "mysql") { assert_raises(ArgumentError) { TimingMode.database_adapter } }
  end
end
```

`test/integration/database_config_test.rb`:
```ruby
require "test_helper"

class DatabaseConfigTest < ActiveSupport::TestCase
  test "sqlite runs WAL with synchronous=FULL" do
    conn = ActiveRecord::Base.connection
    skip "running on #{conn.adapter_name}" unless conn.adapter_name == "SQLite"
    assert_equal "wal", conn.select_value("PRAGMA journal_mode")
    assert_equal 2, conn.select_value("PRAGMA synchronous") # 2 = FULL
  end
end
```

- [ ] **Step 4: Run to verify failure**

Run: `bin/rails test test/lib/timing_mode_test.rb`
Expected: FAIL / error `uninitialized constant TimingModeTest::TimingMode`.

- [ ] **Step 5: Implement TimingMode, database.yml, UUIDv7 ids**

`lib/timing_mode.rb`:
```ruby
# Selects hub vs cloud behavior and the database adapter. Loaded before
# database.yml is evaluated, so it must not depend on Rails.
module TimingMode
  MODES = %w[hub cloud].freeze
  ADAPTERS = %w[sqlite3 postgresql].freeze

  module_function

  def mode
    value = ENV.fetch("TIMING_MODE", "hub")
    raise ArgumentError, "TIMING_MODE must be one of #{MODES.join(', ')} (got #{value.inspect})" unless MODES.include?(value)
    value
  end

  def hub? = mode == "hub"
  def cloud? = mode == "cloud"

  def database_adapter
    value = ENV.fetch("TIMING_DB") { cloud? ? "postgresql" : "sqlite3" }
    raise ArgumentError, "TIMING_DB must be one of #{ADAPTERS.join(', ')} (got #{value.inspect})" unless ADAPTERS.include?(value)
    value
  end
end
```

In `config/application.rb`, directly after `require_relative "boot"` add:
```ruby
require_relative "../lib/timing_mode"
```

Overwrite `config/database.yml`:
```yaml
<% adapter = TimingMode.database_adapter %>
<% sqlite = adapter == "sqlite3" %>
default: &default
  adapter: <%= adapter %>
  pool: <%= ENV.fetch("RAILS_MAX_THREADS") { 5 } %>
<% if sqlite %>
  timeout: 5000
  pragmas:
    journal_mode: wal
    synchronous: full
<% else %>
  host: <%= ENV.fetch("PGHOST", "localhost") %>
  username: <%= ENV.fetch("PGUSER", ENV["USER"]) %>
  password: <%= ENV["PGPASSWORD"] %>
<% end %>

development:
  <<: *default
  database: <%= sqlite ? "storage/development.sqlite3" : "timing_development" %>

test:
  <<: *default
  database: <%= sqlite ? "storage/test.sqlite3" : "timing_test" %>

production:
  primary: &primary_production
    <<: *default
    database: <%= sqlite ? "storage/production.sqlite3" : "timing_production" %>
  cache:
    <<: *primary_production
    database: <%= sqlite ? "storage/production_cache.sqlite3" : "timing_production_cache" %>
    migrations_paths: db/cache_migrate
  queue:
    <<: *primary_production
    database: <%= sqlite ? "storage/production_queue.sqlite3" : "timing_production_queue" %>
    migrations_paths: db/queue_migrate
  cable:
    <<: *primary_production
    database: <%= sqlite ? "storage/production_cable.sqlite3" : "timing_production_cable" %>
    migrations_paths: db/cable_migrate
```

`app/models/application_record.rb`:
```ruby
class ApplicationRecord < ActiveRecord::Base
  primary_abstract_class

  # UUIDv7: globally unique and time-ordered, so records made on a hub merge into the cloud.
  before_create { self.id ||= SecureRandom.uuid_v7 }
end
```

- [ ] **Step 6: Run to verify pass on both databases**

```bash
bin/rails db:prepare && bin/rails test
TIMING_DB=postgresql bin/rails db:create db:prepare && TIMING_DB=postgresql bin/rails test
```
Expected: all green on both (the pragma test is skipped on Postgres).

- [ ] **Step 7: Packs, packwerk, test helpers, engine runner**

```bash
bundle exec packwerk init
mkdir -p packs/events/app/models packs/timing/app/models/concerns packs/results/lib/results packs/results/test/support packs/results/test/fixtures/races test/support
```

Overwrite root `package.yml`:
```yaml
enforce_dependencies: false
```
`packs/events/package.yml`:
```yaml
enforce_dependencies: true
dependencies:
  - "."
```
`packs/timing/package.yml`:
```yaml
enforce_dependencies: true
dependencies:
  - "."
  - packs/events
```

`test/support/build_helpers.rb` (filled in Task 2; create now so the require works):
```ruby
module BuildHelpers
end
```

`test/test_helper.rb` — replace the generated body with:
```ruby
ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"
Dir[File.expand_path("support/**/*.rb", __dir__)].sort.each { require it }

module ActiveSupport
  class TestCase
    parallelize(workers: :number_of_processors)
    include BuildHelpers
  end
end
```

`bin/test-results` (then `chmod +x bin/test-results`):
```ruby
#!/usr/bin/env ruby
# Runs the pure-Ruby results engine tests without booting Rails.
root = File.expand_path("../packs/results", __dir__)
$LOAD_PATH.unshift(File.join(root, "lib"), File.join(root, "test"))
Dir[File.join(root, "test/**/*_test.rb")].sort.each { require it }
```

Run: `bin/packwerk validate && bin/packwerk check`
Expected: `Validation successful` and `No offenses detected`.

- [ ] **Step 8: CI workflow**

`.github/workflows/ci.yml`:
```yaml
name: CI
on: [push, pull_request]
jobs:
  rails:
    runs-on: ubuntu-latest
    strategy:
      fail-fast: false
      matrix:
        db: [sqlite3, postgresql]
    services:
      postgres:
        image: postgres:17
        env:
          POSTGRES_PASSWORD: postgres
        ports: ["5432:5432"]
        options: >-
          --health-cmd pg_isready --health-interval 10s --health-timeout 5s --health-retries 5
    env:
      RAILS_ENV: test
      TIMING_DB: ${{ matrix.db }}
      PGHOST: localhost
      PGUSER: postgres
      PGPASSWORD: postgres
    steps:
      - uses: actions/checkout@v4
      - uses: ruby/setup-ruby@v1
        with:
          bundler-cache: true
      - run: bin/rails db:create db:schema:load
      - run: bin/rails test
      - run: bin/packwerk check
      - run: bundle exec bin/test-results
```

- [ ] **Step 9: Commit**

```bash
git add -A
git commit -m "chore: Rails 8.1 skeleton with hub/cloud modes, dual DB, packs, CI

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 2: Events pack — setup data models and eligibility

**Files:**
- Create: `db/migrate/20261001000001_create_events_tables.rb`, `packs/events/app/models/{event,category,start_group,race,rider,registration,eligibility}.rb`, `test/models/events_test.rb`, `test/models/eligibility_test.rb`
- Modify: `test/support/build_helpers.rb`

**Interfaces:**
- Produces: AR models `Event`, `Category`, `StartGroup`, `Race`, `Rider`, `Registration`; `Event#age_of(birth_date) -> Integer|nil`; `Eligibility.warnings(rider:, category:, event:) -> Array<String>`; `Registration#eligibility_warnings`; `StartGroup#finish_rule` is a string-keyed Hash. Build helpers: `create_event`, `create_category`, `create_start_group(event:)`, `create_race(event:, start_group:, category:)`, `create_rider`, `register(race:, bib:, rider:)`.

- [ ] **Step 1: Write build helpers and failing tests**

`test/support/build_helpers.rb`:
```ruby
module BuildHelpers
  def create_event(**attrs) = Event.create!({ name: "Test CX", date: Date.new(2026, 10, 18) }.merge(attrs))

  def create_category(**attrs) = Category.create!({ name: "Cat 3 Men", gender: "M", ability_levels: ["Cat 3"] }.merge(attrs))

  def create_start_group(event:, **attrs)
    StartGroup.create!({ event:, name: "10:00", finish_rule: { "type" => "fixed_laps", "laps" => 3 } }.merge(attrs))
  end

  def create_race(event:, start_group: create_start_group(event:), category: create_category, **attrs)
    Race.create!({ event:, start_group:, category: }.merge(attrs))
  end

  def create_rider(**attrs)
    Rider.create!({ first_name: "Ada", last_name: "Rider", gender: "M", birth_date: Date.new(1985, 6, 1), ability_level: "Cat 3" }.merge(attrs))
  end

  def register(race:, bib:, rider: create_rider) = Registration.create!(race:, rider:, bib:)
end
```

`test/models/events_test.rb`:
```ruby
require "test_helper"

class EventsTest < ActiveSupport::TestCase
  test "records get UUIDv7 string ids" do
    event = create_event
    assert_match(/\A\h{8}-\h{4}-7\h{3}-\h{4}-\h{12}\z/, event.id)
  end

  test "racing age is year difference; age on event date respects birthdays" do
    event = create_event(date: Date.new(2026, 3, 1))
    assert_equal 41, event.age_of(Date.new(1985, 6, 1))
    event.update!(age_rule: "age_on_event_date")
    assert_equal 40, event.age_of(Date.new(1985, 6, 1))
    assert_equal 41, event.age_of(Date.new(1985, 3, 1))
    assert_nil event.age_of(nil)
  end

  test "start group finish rule must be fixed_laps or timed with positive values" do
    event = create_event
    assert StartGroup.new(event:, name: "a", finish_rule: { type: "fixed_laps", laps: 5 }).valid?
    assert StartGroup.new(event:, name: "a", finish_rule: { type: "timed", target_duration_ms: 2_700_000 }).valid?
    refute StartGroup.new(event:, name: "a", finish_rule: { type: "fixed_laps", laps: 0 }).valid?
    refute StartGroup.new(event:, name: "a", finish_rule: { type: "sprint" }).valid?
    refute StartGroup.new(event:, name: "a", finish_rule: nil).valid?
  end

  test "finish rule keys are stored as strings" do
    group = create_start_group(event: create_event, finish_rule: { type: "fixed_laps", laps: 4 })
    assert_equal({ "type" => "fixed_laps", "laps" => 4 }, group.reload.finish_rule)
  end

  test "race start group must belong to the same event" do
    other_group = create_start_group(event: create_event(name: "Other"))
    race = Race.new(event: create_event, category: create_category, start_group: other_group)
    refute race.valid?
    assert_includes race.errors[:start_group], "must belong to the same event"
  end

  test "category age range must be ordered" do
    refute Category.new(name: "x", gender: "M", age_min: 50, age_max: 40).valid?
    assert Category.new(name: "x", gender: "open", age_min: 35).valid?
  end

  test "bib is unique within an event across races, but reusable across events" do
    event = create_event
    group = create_start_group(event:)
    race_a = create_race(event:, start_group: group)
    race_b = create_race(event:, start_group: group, category: create_category(name: "Cat 4"))
    register(race: race_a, bib: "101")
    dup = Registration.new(race: race_b, rider: create_rider, bib: "101")
    refute dup.valid?
    other = create_event(name: "Next week")
    assert register(race: create_race(event: other), bib: "101").persisted?
  end

  test "registration takes its event from the race and strips the bib" do
    race = create_race(event: create_event)
    reg = register(race:, bib: " 7 ")
    assert_equal race.event_id, reg.event_id
    assert_equal "7", reg.bib
  end
end
```

`test/models/eligibility_test.rb`:
```ruby
require "test_helper"

class EligibilityTest < ActiveSupport::TestCase
  setup { @event = create_event(date: Date.new(2026, 10, 18)) }

  def warnings(rider_attrs = {}, category_attrs = {})
    Eligibility.warnings(rider: Rider.new({ first_name: "A", last_name: "B", gender: "M", birth_date: Date.new(1980, 1, 1), ability_level: "Cat 3" }.merge(rider_attrs)),
                         category: Category.new({ name: "C", gender: "M", ability_levels: ["Cat 3"], age_min: 35, age_max: 49 }.merge(category_attrs)),
                         event: @event)
  end

  test "eligible rider has no warnings" do
    assert_empty warnings
  end

  test "warns on gender, ability, and age mismatches" do
    assert_match(/gender F/, warnings(gender: "F").first)
    assert_match(/ability level Cat 4/, warnings(ability_level: "Cat 4").first)
    assert_match(/below minimum 35/, warnings(birth_date: Date.new(2000, 1, 1)).first)
    assert_match(/above maximum 49/, warnings(birth_date: Date.new(1970, 1, 1)).first)
  end

  test "open gender and empty ability levels accept anyone" do
    assert_empty warnings({ gender: "X", ability_level: nil }, { gender: "open", ability_levels: [] })
  end

  test "unknown birth date warns only when the category has an age range" do
    assert_match(/birth date unknown/, warnings(birth_date: nil).first)
    assert_empty warnings({ birth_date: nil }, { age_min: nil, age_max: nil })
  end
end
```

- [ ] **Step 2: Run to verify failure**

Run: `bin/rails test test/models`
Expected: errors `uninitialized constant Event` (and similar).

- [ ] **Step 3: Migration**

`db/migrate/20261001000001_create_events_tables.rb`:
```ruby
class CreateEventsTables < ActiveRecord::Migration[8.1]
  def change
    create_table :events, id: :string do |t|
      t.string :name, null: false
      t.date :date, null: false
      t.string :venue
      t.string :timezone, null: false, default: "UTC"
      t.string :age_rule, null: false, default: "racing_age_dec31"
      t.timestamps
    end

    create_table :categories, id: :string do |t|
      t.string :name, null: false
      t.json :ability_levels, null: false, default: []
      t.integer :age_min
      t.integer :age_max
      t.string :gender, null: false
      t.timestamps
    end

    create_table :start_groups, id: :string do |t|
      t.references :event, type: :string, null: false, foreign_key: true
      t.string :name, null: false
      t.bigint :scheduled_at_ms
      t.json :finish_rule, null: false
      t.timestamps
    end

    create_table :races, id: :string do |t|
      t.references :event, type: :string, null: false, foreign_key: true
      t.references :category, type: :string, null: false, foreign_key: true
      t.references :start_group, type: :string, null: false, foreign_key: true
      t.integer :start_offset_ms, null: false, default: 0
      t.timestamps
    end

    create_table :riders, id: :string do |t|
      t.string :first_name, null: false
      t.string :last_name, null: false
      t.string :gender, null: false
      t.date :birth_date
      t.string :ability_level
      t.string :license_number
      t.string :team
      t.timestamps
    end

    create_table :registrations, id: :string do |t|
      t.references :event, type: :string, null: false, foreign_key: true
      t.references :race, type: :string, null: false, foreign_key: true
      t.references :rider, type: :string, null: false, foreign_key: true
      t.string :bib, null: false
      t.timestamps
    end
    add_index :registrations, [:event_id, :bib], unique: true
  end
end
```

- [ ] **Step 4: Models**

`packs/events/app/models/event.rb`:
```ruby
class Event < ApplicationRecord
  AGE_RULES = %w[racing_age_dec31 age_on_event_date].freeze

  has_many :start_groups, dependent: :destroy
  has_many :races, dependent: :destroy
  has_many :registrations, dependent: :destroy

  validates :name, :date, presence: true
  validates :age_rule, inclusion: { in: AGE_RULES }

  def age_of(birth_date)
    return nil unless birth_date
    age = date.year - birth_date.year
    return age if age_rule == "racing_age_dec31"
    birth_date.advance(years: age) > date ? age - 1 : age
  end
end
```

`packs/events/app/models/category.rb`:
```ruby
class Category < ApplicationRecord
  GENDERS = %w[M F X open].freeze

  validates :name, presence: true
  validates :gender, inclusion: { in: GENDERS }
  validate :ability_levels_are_strings
  validate :age_range_ordered

  private

  def ability_levels_are_strings
    errors.add(:ability_levels, "must be a list of strings") unless ability_levels.is_a?(Array) && ability_levels.all?(String)
  end

  def age_range_ordered
    errors.add(:age_max, "must be greater than or equal to age_min") if age_min && age_max && age_max < age_min
  end
end
```

`packs/events/app/models/start_group.rb`:
```ruby
class StartGroup < ApplicationRecord
  belongs_to :event
  has_many :races, dependent: :restrict_with_error

  before_validation { self.finish_rule = finish_rule.deep_stringify_keys if finish_rule.is_a?(Hash) }

  validates :name, presence: true
  validate :finish_rule_shape

  private

  def finish_rule_shape
    rule = finish_rule.is_a?(Hash) ? finish_rule : {}
    case rule["type"]
    when "fixed_laps"
      errors.add(:finish_rule, "laps must be a positive integer") unless positive_int?(rule["laps"])
    when "timed"
      errors.add(:finish_rule, "target_duration_ms must be a positive integer") unless positive_int?(rule["target_duration_ms"])
    else
      errors.add(:finish_rule, "type must be fixed_laps or timed")
    end
  end

  def positive_int?(value) = value.is_a?(Integer) && value.positive?
end
```

`packs/events/app/models/race.rb`:
```ruby
class Race < ApplicationRecord
  belongs_to :event
  belongs_to :category
  belongs_to :start_group
  has_many :registrations, dependent: :restrict_with_error

  validates :start_offset_ms, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validate :start_group_in_same_event

  delegate :name, to: :category

  private

  def start_group_in_same_event
    errors.add(:start_group, "must belong to the same event") if start_group && start_group.event_id != event_id
  end
end
```

`packs/events/app/models/rider.rb`:
```ruby
class Rider < ApplicationRecord
  GENDERS = %w[M F X].freeze

  has_many :registrations, dependent: :restrict_with_error

  validates :first_name, :last_name, presence: true
  validates :gender, inclusion: { in: GENDERS }

  def full_name = "#{first_name} #{last_name}"
end
```

`packs/events/app/models/registration.rb`:
```ruby
class Registration < ApplicationRecord
  belongs_to :event
  belongs_to :race
  belongs_to :rider

  before_validation do
    self.event_id ||= race&.event_id
    self.bib = bib.to_s.strip.presence
  end

  validates :bib, presence: true, uniqueness: { scope: :event_id }
  validate :race_in_same_event

  # Warnings, not errors: officials may let riders race up a category.
  def eligibility_warnings = Eligibility.warnings(rider:, category: race.category, event:)

  private

  def race_in_same_event
    errors.add(:race, "must belong to the same event") if race && race.event_id != event_id
  end
end
```

`packs/events/app/models/eligibility.rb`:
```ruby
module Eligibility
  module_function

  def warnings(rider:, category:, event:)
    warnings = []
    if category.gender != "open" && rider.gender != category.gender
      warnings << "gender #{rider.gender} does not match category gender #{category.gender}"
    end
    if category.ability_levels.present? && !category.ability_levels.include?(rider.ability_level)
      warnings << "ability level #{rider.ability_level || 'none'} is not one of #{category.ability_levels.join(', ')}"
    end
    age = event.age_of(rider.birth_date)
    if age.nil?
      warnings << "birth date unknown; category has an age range" if category.age_min || category.age_max
    else
      warnings << "age #{age} is below minimum #{category.age_min}" if category.age_min && age < category.age_min
      warnings << "age #{age} is above maximum #{category.age_max}" if category.age_max && age > category.age_max
    end
    warnings
  end
end
```

- [ ] **Step 5: Run to verify pass on both databases**

```bash
bin/rails db:migrate && bin/rails test
TIMING_DB=postgresql bin/rails db:migrate && TIMING_DB=postgresql bin/rails test
bin/packwerk check
```
Expected: all green; `No offenses detected`.

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "feat(events): event setup models, start groups, registrations, eligibility warnings

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 3: Timing pack — devices and the append-only race log

**Files:**
- Create: `db/migrate/20261001000002_create_timing_tables.rb`, `packs/timing/app/models/concerns/append_only.rb`, `packs/timing/app/models/{device,device_entry,capture,bib_assignment,ruling}.rb`, `test/models/timing_test.rb`
- Modify: `test/support/build_helpers.rb`

**Interfaces:**
- Consumes: `Event`, build helpers from Task 2.
- Produces: `Device` (`revoked?`), `DeviceEntry` (STI base: `Capture`, `BibAssignment`), `Ruling` with `Ruling::KINDS` (kind → required payload keys) and string-keyed `payload`. Build helpers `create_device(event:)`, `record_capture(device:, seq:, at_ms:, bib: nil, offset_ms: 0)`, `rule(event:, kind:, **payload)`. All log rows are read-only once persisted.

- [ ] **Step 1: Write failing tests**

Append to `test/support/build_helpers.rb` inside the module:
```ruby
  def create_device(event:, name: "Tablet 1")
    Device.create!(event:, name:, paired_at_ms: 0, credential_digest: "test-digest")
  end

  def record_capture(device:, seq:, at_ms:, bib: nil, offset_ms: 0, id: SecureRandom.uuid_v7)
    Capture.create!(id:, event_id: device.event_id, device:, device_seq: seq, captured_at_ms: at_ms,
                    clock_offset_ms: offset_ms, bib:, prev_hash: "p#{seq}", entry_hash: "h#{seq}")
  end

  def rule(event:, kind:, created_at_ms: nil, **payload)
    Ruling.create!(event:, kind:, payload: payload.transform_keys(&:to_s), created_at_ms:)
  end
```

`test/models/timing_test.rb`:
```ruby
require "test_helper"

class TimingTest < ActiveSupport::TestCase
  setup do
    @event = create_event
    @device = create_device(event: @event)
  end

  test "captures are read-only once persisted" do
    capture = record_capture(device: @device, seq: 1, at_ms: 1_000, bib: "1")
    assert_raises(ActiveRecord::ReadOnlyRecord) { capture.update!(bib: "2") }
    assert_raises(ActiveRecord::ReadOnlyRecord) { capture.destroy }
  end

  test "device_seq is unique per device across captures and bib assignments" do
    capture = record_capture(device: @device, seq: 1, at_ms: 1_000)
    clash = BibAssignment.new(event: @event, device: @device, device_seq: 1, capture:, bib: "5", prev_hash: "a", entry_hash: "b")
    refute clash.valid?
    other = create_device(event: @event, name: "Tablet 2")
    assert record_capture(device: other, seq: 1, at_ms: 1_000).persisted?
  end

  test "bib assignment must come from the capture's own device" do
    capture = record_capture(device: @device, seq: 1, at_ms: 1_000)
    other = create_device(event: @event, name: "Tablet 2")
    assignment = BibAssignment.new(event: @event, device: other, device_seq: 1, capture:, bib: "5", prev_hash: "a", entry_hash: "b")
    refute assignment.valid?
    assert_includes assignment.errors[:capture], "must belong to the same device"
  end

  test "capture source must be manual or chip; received_at_ms defaults to now" do
    capture = record_capture(device: @device, seq: 1, at_ms: 1_000)
    assert_equal "manual", capture.source
    assert_operator capture.received_at_ms, :>, 1_700_000_000_000
    refute Capture.new(event: @event, device: @device, device_seq: 2, captured_at_ms: 1, source: "gps", prev_hash: "a", entry_hash: "b").valid?
  end

  test "rulings validate kind and required payload keys" do
    assert rule(event: @event, kind: "set_lap_count", start_group_id: "g1", laps: 5).persisted?
    refute Ruling.new(event: @event, kind: "set_lap_count", payload: { "laps" => 5 }).valid?
    refute Ruling.new(event: @event, kind: "teleport", payload: {}).valid?
  end

  test "rulings are append-only and stamp created_at_ms" do
    ruling = rule(event: @event, kind: "dnf", bib: "7")
    assert_operator ruling.created_at_ms, :>, 1_700_000_000_000
    assert_raises(ActiveRecord::ReadOnlyRecord) { ruling.update!(reason: "oops") }
  end

  test "revoked? reflects revoked_at_ms" do
    refute @device.revoked?
    assert Device.new(revoked_at_ms: 1).revoked?
  end
end
```

- [ ] **Step 2: Run to verify failure**

Run: `bin/rails test test/models/timing_test.rb`
Expected: error `uninitialized constant Device`.

- [ ] **Step 3: Migration**

`db/migrate/20261001000002_create_timing_tables.rb`:
```ruby
class CreateTimingTables < ActiveRecord::Migration[8.1]
  def change
    create_table :devices, id: :string do |t|
      t.references :event, type: :string, null: false, foreign_key: true
      t.string :name, null: false
      t.bigint :paired_at_ms, null: false
      t.bigint :revoked_at_ms
      t.string :credential_digest, null: false
      t.timestamps
    end

    # One table for the whole device log: captures and bib assignments share device_seq.
    create_table :device_entries, id: :string do |t|
      t.string :type, null: false
      t.references :event, type: :string, null: false, foreign_key: true
      t.references :device, type: :string, null: false, foreign_key: true
      t.bigint :device_seq, null: false
      t.bigint :captured_at_ms
      t.bigint :clock_offset_ms
      t.string :bib
      t.string :source
      t.references :capture, type: :string, foreign_key: { to_table: :device_entries }
      t.string :prev_hash, null: false
      t.string :entry_hash, null: false
      t.bigint :received_at_ms, null: false
    end
    add_index :device_entries, [:device_id, :device_seq], unique: true

    create_table :rulings, id: :string do |t|
      t.references :event, type: :string, null: false, foreign_key: true
      t.string :kind, null: false
      t.json :payload, null: false, default: {}
      t.string :official_id
      t.string :reason
      t.bigint :created_at_ms, null: false
    end
    add_index :rulings, [:event_id, :created_at_ms]
  end
end
```

- [ ] **Step 4: Models**

`packs/timing/app/models/concerns/append_only.rb`:
```ruby
# Race log rows are facts: once written they are never updated or destroyed.
module AppendOnly
  extend ActiveSupport::Concern

  def readonly? = persisted? || super
end
```

`packs/timing/app/models/device.rb`:
```ruby
class Device < ApplicationRecord
  belongs_to :event
  has_many :device_entries, dependent: :restrict_with_error

  validates :name, :paired_at_ms, :credential_digest, presence: true

  def revoked? = revoked_at_ms.present?
end
```

`packs/timing/app/models/device_entry.rb`:
```ruby
class DeviceEntry < ApplicationRecord
  include AppendOnly

  belongs_to :event
  belongs_to :device

  before_validation { self.received_at_ms ||= (Time.now.to_r * 1000).to_i }

  validates :device_seq, numericality: { only_integer: true, greater_than: 0 }, uniqueness: { scope: :device_id }
  validates :prev_hash, :entry_hash, :received_at_ms, presence: true
end
```

`packs/timing/app/models/capture.rb`:
```ruby
class Capture < DeviceEntry
  SOURCES = %w[manual chip].freeze

  has_many :bib_assignments, foreign_key: :capture_id, inverse_of: :capture, dependent: :restrict_with_error

  attribute :source, :string, default: "manual"

  validates :captured_at_ms, presence: true
  validates :source, inclusion: { in: SOURCES }
end
```

`packs/timing/app/models/bib_assignment.rb`:
```ruby
# "Tap now, bib later": a device adds a bib to one of its own earlier captures.
class BibAssignment < DeviceEntry
  belongs_to :capture

  validates :bib, presence: true
  validate :same_device_as_capture

  private

  def same_device_as_capture
    errors.add(:capture, "must belong to the same device") if capture && capture.device_id != device_id
  end
end
```

`packs/timing/app/models/ruling.rb`:
```ruby
class Ruling < ApplicationRecord
  include AppendOnly

  # kind => payload keys that must be present
  KINDS = {
    "set_group_start" => %w[start_group_id at_ms],
    "set_race_start" => %w[race_id at_ms],
    "set_lap_count" => %w[start_group_id laps],
    "assign_bib" => %w[capture_id bib],
    "void_capture" => %w[capture_id],
    "insert_capture" => %w[bib at_ms],
    "flag_finish" => %w[bib capture_id],
    "pull" => %w[bib at_ms],
    "dnf" => %w[bib],
    "dns" => %w[bib],
    "dsq" => %w[bib],
    "dismiss_suggestion" => %w[suggestion_key],
    "publish_results" => %w[race_id log_digest],
    "revert" => %w[ruling_id]
  }.freeze

  belongs_to :event

  before_validation do
    self.payload = payload.deep_stringify_keys if payload.is_a?(Hash)
    self.created_at_ms ||= (Time.now.to_r * 1000).to_i
  end

  validates :kind, inclusion: { in: KINDS.keys }
  validate :payload_has_required_keys

  private

  def payload_has_required_keys
    return unless KINDS.key?(kind)
    missing = KINDS[kind] - (payload.is_a?(Hash) ? payload.keys : [])
    errors.add(:payload, "missing #{missing.join(', ')}") if missing.any?
  end
end
```

- [ ] **Step 5: Run to verify pass on both databases**

```bash
bin/rails db:migrate && bin/rails test
TIMING_DB=postgresql bin/rails db:migrate && TIMING_DB=postgresql bin/rails test
bin/packwerk check
```
Expected: all green; `No offenses detected`.

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "feat(timing): devices, append-only device log (captures, bib assignments), rulings

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 4: Results engine — types, fixture loader, ruling and crossing resolution

**Files:**
- Create: `packs/results/lib/results.rb`, `packs/results/lib/results/{types,active_rulings,resolver}.rb`, `packs/results/test/test_helper.rb`, `packs/results/test/support/{fixture,helpers}.rb`, `packs/results/test/resolver_test.rb`

**Interfaces:**
- Produces (all in `module Results`):
  - Input structs: `StartGroupDef(id, finish_rule)` (string-keyed hash), `RaceDef(id, start_group_id, start_offset_ms)`, `Entrant(bib, race_id, name)`, `Capture(id, device_id, device_seq, captured_at_ms, clock_offset_ms, bib)`, `BibAssignment(id, capture_id, bib, device_seq)`, `Ruling(id, kind, payload, created_at_ms)`, `Config(...)` with `Config::DEFAULT`, `Input(start_groups:, races:, entrants:, captures:, bib_assignments: [], rulings: [], now_ms: 0, config: Config::DEFAULT)`.
  - Derived: `Crossing(bib, at_ms, ref, inserted)`, `UnassignedCrossing(capture_id, at_ms, bib)`.
  - `ActiveRulings.new(rulings)` with `#of(kind) -> [Ruling]` (chronological), `#latest_by(kind) { |r| key } -> {key => Ruling}`, `#all`.
  - `Resolver.new(input).call -> Resolver::Resolved(crossings_by_bib: {bib => [Crossing]}, unassigned: [UnassignedCrossing], aliases: {dropped_ref => kept_ref}, rulings: ActiveRulings, unsynced_devices: [device_id])`.
  - Test support: `Results::Fixture.parse(yaml) -> [Input, expected_hash]`, `Results::Fixture.load(path)`; `ResultsTestHelpers#setup_yaml(...)`, `#input_from(yaml)`.

**Fixture format** (seconds in YAML, converted to ms; used by every engine test):
```yaml
now: 1000                      # optional, seconds
start_groups:
  - {id: g1, finish_rule: {type: fixed_laps, laps: 3}, gun: 0}   # gun → set_group_start ruling "gun-g1" (omit gun = not started)
races:
  - {id: r1, group: g1, offset: 0}                               # offset seconds
entrants:
  - {bib: 1, race: r1, name: Rider 1}
crossings:                      # bib => crossing times; ids c-<bib>-<n>, device d1, offset 0
  1: [300, 600]
captures:                       # explicit captures: {id, bib?, at, device?, offset_ms?}; offset_ms: ~ means unsynced
  - {id: x-1, bib: 2, at: 305, device: d2}
unassigned: [935]               # bib-less captures; ids u-<n>
bib_assignments:
  - {id: b-1, capture: u-1, bib: 2}
rulings:                        # id defaults r-<n>; created (seconds) defaults n; "at" → at_ms; bib stringified
  - {kind: set_lap_count, start_group_id: g1, laps: 5, created: 600}
expect:
  races:
    r1:
      - [1, 1, finished, 3, 900]   # [place, bib, status, laps, elapsed_seconds]
  suggestions: [missed:2:c-2-2:c-2-3]
```

- [ ] **Step 1: Write types, entry point, and test support**

`packs/results/lib/results/types.rb`:
```ruby
module Results
  # --- Input: setup ---
  StartGroupDef = Data.define(:id, :finish_rule) # finish_rule: {"type"=>"fixed_laps","laps"=>n} | {"type"=>"timed","target_duration_ms"=>d}
  RaceDef = Data.define(:id, :start_group_id, :start_offset_ms)
  Entrant = Data.define(:bib, :race_id, :name)

  # --- Input: race log ---
  Capture = Data.define(:id, :device_id, :device_seq, :captured_at_ms, :clock_offset_ms, :bib)
  BibAssignment = Data.define(:id, :capture_id, :bib, :device_seq)
  Ruling = Data.define(:id, :kind, :payload, :created_at_ms) # payload: string-keyed hash

  Config = Data.define(:debounce_ms, :missed_low, :missed_high, :neighbor_low, :neighbor_high, :short_ratio, :match_window_ratio)
  Config::DEFAULT = Config.new(debounce_ms: 10_000, missed_low: 1.7, missed_high: 2.3, neighbor_low: 0.7,
                               neighbor_high: 1.3, short_ratio: 0.5, match_window_ratio: 0.15)

  Input = Data.define(:start_groups, :races, :entrants, :captures, :bib_assignments, :rulings, :now_ms, :config) do
    def initialize(start_groups:, races:, entrants:, captures:, bib_assignments: [], rulings: [], now_ms: 0, config: Config::DEFAULT)
      super
    end
  end

  # --- Derived ---
  Crossing = Data.define(:bib, :at_ms, :ref, :inserted) # ref: capture id, or ruling id for inserted crossings
  UnassignedCrossing = Data.define(:capture_id, :at_ms, :bib)
end
```

`packs/results/lib/results.rb`:
```ruby
require "set"
require_relative "results/types"
require_relative "results/active_rulings"
require_relative "results/resolver"

# Pure results engine: Input snapshot in, standings and suggestions out.
# Must not depend on Rails or a database.
module Results
end
```

`packs/results/test/support/fixture.rb`:
```ruby
require "yaml"

module Results
  # Builds an Input from a compact YAML race description (times in seconds).
  module Fixture
    module_function

    def load(path) = parse(File.read(path))

    def parse(yaml)
      data = YAML.safe_load(yaml)
      ms = ->(seconds) { seconds.nil? ? nil : (seconds * 1000).round }
      seqs = Hash.new(0)
      next_seq = ->(device) { seqs[device] += 1 }
      devices = {}

      captures = []
      (data["crossings"] || {}).each do |bib, times|
        times.each_with_index do |t, i|
          id = "c-#{bib}-#{i + 1}"
          devices[id] = "d1"
          captures << Capture.new(id:, device_id: "d1", device_seq: next_seq.("d1"), captured_at_ms: ms.(t), clock_offset_ms: 0, bib: bib.to_s)
        end
      end
      (data["captures"] || []).each do |c|
        device = c.fetch("device", "d1")
        devices[c["id"]] = device
        captures << Capture.new(id: c["id"], device_id: device, device_seq: next_seq.(device), captured_at_ms: ms.(c["at"]),
                                clock_offset_ms: c.key?("offset_ms") ? c["offset_ms"] : 0, bib: c["bib"]&.to_s)
      end
      (data["unassigned"] || []).each_with_index do |t, i|
        id = "u-#{i + 1}"
        devices[id] = "d1"
        captures << Capture.new(id:, device_id: "d1", device_seq: next_seq.("d1"), captured_at_ms: ms.(t), clock_offset_ms: 0, bib: nil)
      end

      assignments = (data["bib_assignments"] || []).map do |b|
        BibAssignment.new(id: b["id"], capture_id: b["capture"], bib: b["bib"].to_s, device_seq: next_seq.(devices.fetch(b["capture"])))
      end

      groups = data.fetch("start_groups")
      rulings = groups.select { it.key?("gun") }.map do |g|
        Ruling.new(id: "gun-#{g['id']}", kind: "set_group_start", payload: { "start_group_id" => g["id"], "at_ms" => ms.(g["gun"]) }, created_at_ms: 0)
      end
      (data["rulings"] || []).each_with_index do |r, i|
        payload = r.except("id", "kind", "created").to_h do |k, v|
          case k
          when "at" then ["at_ms", ms.(v)]
          when "bib" then ["bib", v&.to_s]
          else [k, v]
          end
        end
        rulings << Ruling.new(id: r.fetch("id", "r-#{i + 1}"), kind: r.fetch("kind"), payload:, created_at_ms: ms.(r.fetch("created", i + 1)))
      end

      input = Input.new(
        start_groups: groups.map { StartGroupDef.new(id: it["id"], finish_rule: it.fetch("finish_rule")) },
        races: data.fetch("races").map { RaceDef.new(id: it["id"], start_group_id: it["group"], start_offset_ms: ms.(it.fetch("offset", 0))) },
        entrants: data.fetch("entrants").map { Entrant.new(bib: it["bib"].to_s, race_id: it["race"], name: it.fetch("name", "Rider #{it['bib']}")) },
        captures:, bib_assignments: assignments, rulings:, now_ms: ms.(data.fetch("now", 0))
      )
      [input, data["expect"] || {}]
    end
  end
end
```

`packs/results/test/support/helpers.rb`:
```ruby
module ResultsTestHelpers
  # Setup section for a single start group g1 with one race r1.
  def setup_yaml(bibs: [1, 2, 3], finish_rule: "{type: fixed_laps, laps: 3}", gun: 0, offset: 0)
    group = "  - {id: g1, finish_rule: #{finish_rule}#{gun.nil? ? '' : ", gun: #{gun}"}}"
    lines = ["start_groups:", group, "races:", "  - {id: r1, group: g1, offset: #{offset}}", "entrants:"]
    lines += bibs.map { "  - {bib: #{it}, race: r1}" }
    lines.join("\n") + "\n"
  end

  def input_from(yaml) = Results::Fixture.parse(yaml).first

  def compact_rows(rows)
    rows.map { [it.place, it.bib, it.status.to_s, it.laps, it.elapsed_ms && it.elapsed_ms / 1000] }
  end

  def normalize_rows(rows)
    rows.map { |place, bib, status, laps, elapsed| [place, bib.to_s, status.to_s, laps, elapsed] }
  end
end
```

`packs/results/test/test_helper.rb`:
```ruby
require "minitest/autorun"
require "results"
require_relative "support/fixture"
require_relative "support/helpers"
```

- [ ] **Step 2: Write the failing resolver tests**

`packs/results/test/resolver_test.rb`:
```ruby
require "test_helper"

class ResolverTest < Minitest::Test
  include ResultsTestHelpers

  def resolve(yaml) = Results::Resolver.new(input_from(setup_yaml + yaml)).call

  def times(resolved, bib) = resolved.crossings_by_bib.fetch(bib.to_s, []).map { it.at_ms / 1000 }

  def test_capture_bib_maps_to_crossings_sorted_by_time
    r = resolve("crossings:\n  1: [600, 300]\n")
    assert_equal [300, 600], times(r, 1)
  end

  def test_clock_offset_is_applied_and_missing_offset_flags_device
    r = resolve(<<~YAML)
      captures:
        - {id: a, bib: 1, at: 300, device: d1, offset_ms: 2000}
        - {id: b, bib: 2, at: 300, device: d2, offset_ms: ~}
    YAML
    assert_equal [302], times(r, 1)
    assert_equal [300], times(r, 2)
    assert_equal ["d2"], r.unsynced_devices
  end

  def test_device_bib_assignment_names_a_bibless_tap
    r = resolve("unassigned: [300]\nbib_assignments:\n  - {id: b-1, capture: u-1, bib: 2}\n")
    assert_equal [300], times(r, 2)
    assert_empty r.unassigned
  end

  def test_assign_bib_ruling_overrides_device_assignment
    r = resolve(<<~YAML)
      unassigned: [300]
      bib_assignments:
        - {id: b-1, capture: u-1, bib: 2}
      rulings:
        - {kind: assign_bib, capture_id: u-1, bib: 3}
    YAML
    assert_equal [], times(r, 2)
    assert_equal [300], times(r, 3)
  end

  def test_void_removes_and_insert_adds
    r = resolve(<<~YAML)
      crossings:
        1: [300, 600]
      rulings:
        - {kind: void_capture, capture_id: c-1-2}
        - {id: ins, kind: insert_capture, bib: 1, at: 900}
    YAML
    assert_equal [300, 900], times(r, 1)
    assert r.crossings_by_bib["1"].last.inserted
  end

  # Review Focus 5: a typo'd bib is kept, visible, and unassigned.
  def test_assign_bib_to_unregistered_bib_goes_to_unassigned_with_that_bib
    r = resolve("crossings:\n  1: [300]\nrulings:\n  - {kind: assign_bib, capture_id: c-1-1, bib: 999}\n")
    assert_equal [], times(r, 1)
    assert_equal [Results::UnassignedCrossing.new(capture_id: "c-1-1", at_ms: 300_000, bib: "999")], r.unassigned
  end

  # Review Focus 4: reverting a revert restores the original ruling.
  def test_revert_of_revert_restores_original
    r = resolve(<<~YAML)
      crossings:
        1: [300, 600]
      rulings:
        - {id: v, kind: void_capture, capture_id: c-1-2, created: 700}
        - {id: rv, kind: revert, ruling_id: v, created: 800}
        - {id: rrv, kind: revert, ruling_id: rv, created: 900}
    YAML
    assert_equal [300], times(r, 1)
  end

  def test_single_revert_cancels_ruling
    r = resolve(<<~YAML)
      crossings:
        1: [300, 600]
      rulings:
        - {id: v, kind: void_capture, capture_id: c-1-2, created: 700}
        - {id: rv, kind: revert, ruling_id: v, created: 800}
    YAML
    assert_equal [300, 600], times(r, 1)
  end

  def test_taps_within_debounce_window_collapse_to_earliest
    r = resolve(<<~YAML)
      captures:
        - {id: a, bib: 1, at: 300, device: d1}
        - {id: b, bib: 1, at: 306, device: d2}
        - {id: c, bib: 1, at: 600, device: d1}
    YAML
    assert_equal [300, 600], times(r, 1)
    assert_equal({ "b" => "a" }, r.aliases)
  end

  def test_latest_by_uses_chronological_order_not_input_order
    rulings = Results::ActiveRulings.new([
      Results::Ruling.new(id: "late", kind: "set_lap_count", payload: { "start_group_id" => "g1", "laps" => 5 }, created_at_ms: 900),
      Results::Ruling.new(id: "early", kind: "set_lap_count", payload: { "start_group_id" => "g1", "laps" => 6 }, created_at_ms: 600)
    ])
    assert_equal "late", rulings.latest_by("set_lap_count") { it.payload["start_group_id"] }["g1"].id
  end
end
```

- [ ] **Step 3: Run to verify failure**

Run: `bundle exec ruby -Ipacks/results/lib -Ipacks/results/test packs/results/test/resolver_test.rb`
Expected: error `cannot load such file -- .../results/active_rulings`.

- [ ] **Step 4: Implement ActiveRulings and Resolver**

`packs/results/lib/results/active_rulings.rb`:
```ruby
module Results
  # Rulings in chronological order with reverts applied. A revert can itself be
  # reverted, which restores its target.
  class ActiveRulings
    attr_reader :all

    def initialize(rulings)
      sorted = rulings.uniq(&:id).sort_by { [it.created_at_ms, it.id] }
      cancelled = Set.new
      sorted.reverse_each do |r|
        next if cancelled.include?(r.id)
        cancelled << r.payload["ruling_id"] if r.kind == "revert"
      end
      @all = sorted.reject { cancelled.include?(it.id) || it.kind == "revert" }
    end

    def of(kind) = @all.select { it.kind == kind }

    def latest_by(kind, &key) = of(kind).group_by(&key).transform_values(&:last)
  end
end
```

`packs/results/lib/results/resolver.rb`:
```ruby
module Results
  # Spec §4.1: turns the raw log into per-bib crossings plus unassigned captures.
  class Resolver
    Resolved = Data.define(:crossings_by_bib, :unassigned, :aliases, :rulings, :unsynced_devices)

    def initialize(input)
      @input = input
    end

    def call
      rulings = ActiveRulings.new(@input.rulings)
      registered = @input.entrants.map(&:bib).to_set
      voided = rulings.of("void_capture").map { it.payload["capture_id"] }.to_set
      overrides = rulings.latest_by("assign_bib") { it.payload["capture_id"] }
      device_bibs = @input.bib_assignments.uniq(&:id).group_by(&:capture_id)
                          .transform_values { |list| list.max_by { [it.device_seq, it.id] }.bib }

      crossings = []
      unassigned = []
      unsynced = Set.new
      @input.captures.uniq(&:id).each do |c|
        next if voided.include?(c.id)
        unsynced << c.device_id if c.clock_offset_ms.nil?
        at = c.captured_at_ms + (c.clock_offset_ms || 0)
        bib = (overrides[c.id]&.payload&.fetch("bib") || device_bibs[c.id] || c.bib)&.to_s
        if bib && registered.include?(bib)
          crossings << Crossing.new(bib:, at_ms: at, ref: c.id, inserted: false)
        else
          unassigned << UnassignedCrossing.new(capture_id: c.id, at_ms: at, bib:)
        end
      end

      rulings.of("insert_capture").each do |r|
        bib = r.payload["bib"].to_s
        crossings << Crossing.new(bib:, at_ms: r.payload["at_ms"], ref: r.id, inserted: true) if registered.include?(bib)
      end

      by_bib, aliases = debounce(crossings)
      Resolved.new(crossings_by_bib: by_bib, unassigned: unassigned.sort_by { [it.at_ms, it.capture_id] },
                   aliases:, rulings:, unsynced_devices: unsynced.to_a.sort)
    end

    private

    # Collapses taps for the same bib that fall within the debounce window of the
    # last kept crossing, keeping the earliest. Returns [by_bib, dropped_ref => kept_ref].
    def debounce(crossings)
      aliases = {}
      by_bib = crossings.group_by(&:bib).transform_values do |list|
        list.sort_by { [it.at_ms, it.ref] }.each_with_object([]) do |c, kept|
          if kept.any? && c.at_ms - kept.last.at_ms < @input.config.debounce_ms
            aliases[c.ref] = kept.last.ref
          else
            kept << c
          end
        end
      end
      [by_bib, aliases]
    end
  end
end
```

- [ ] **Step 5: Run to verify pass**

Run: `bundle exec bin/test-results`
Expected: `10 runs, ... 0 failures, 0 errors`.

- [ ] **Step 6: Commit**

```bash
git add packs/results
git commit -m "feat(results): engine types, YAML race fixtures, ruling and crossing resolution

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 5: Results engine — finish logic, standings, publication

**Files:**
- Create: `packs/results/lib/results/{group_scorer,standings,log_digest,publication,engine}.rb`, `packs/results/test/standings_test.rb`
- Modify: `packs/results/lib/results.rb`, `packs/results/lib/results/types.rb`

**Interfaces:**
- Consumes: `Resolver`, `ActiveRulings`, types from Task 4.
- Produces:
  - Types: `RiderResult(place, bib, name, status, laps, elapsed_ms, gap, lap_times_ms)` — `status` ∈ `:finished :racing :pulled :dnf :dns :dsq`, `place` nil for dnf/dns/dsq; `Gap(laps_down, ms)`; `RaceResult(race_id, state, lap_count, publication, rows)` — `state` ∈ `:not_started :in_progress :finish_open`, `publication` ∈ `:provisional :published :changed_since_published`; `Suggestion(key, kind, bib, race_id, message, fix)`; `Output(races, suggestions, unassigned, log_digest)`.
  - `GroupScorer.new(input, group, resolved).call -> GroupScorer::Scored(group, lap_count, finish_open_at, riders, race_results)`; `GroupScorer::RiderState(entrant, race_start, crossings, counted, status, finish, pull_at)`.
  - `Results.compute(input) -> Output`; `LogDigest.compute(input) -> String` (hex SHA-256).

- [ ] **Step 1: Write failing standings tests**

`packs/results/test/standings_test.rb`:
```ruby
require "test_helper"

class StandingsTest < Minitest::Test
  include ResultsTestHelpers

  def compute(yaml, **setup) = Results.compute(input_from(setup_yaml(**setup) + yaml))
  def race(out) = out.races.find { it.race_id == "r1" }
  def rows(out) = compact_rows(race(out).rows)

  def test_fixed_laps_finish_opens_on_leader_and_ranks_by_laps_then_time
    out = compute("crossings:\n  1: [100, 200, 300]\n  2: [110, 220, 330]\n  3: [150, 310]\n")
    assert_equal [[1, "1", "finished", 3, 300], [2, "2", "finished", 3, 330], [3, "3", "finished", 2, 310]], rows(out)
    assert_equal :finish_open, race(out).state
  end

  def test_timed_group_without_lap_count_is_in_progress_ranked_live
    out = compute("crossings:\n  1: [100, 200]\n  2: [110]\n  3: [105, 215]\n", finish_rule: "{type: timed, target_duration_ms: 2700000}")
    assert_equal :in_progress, race(out).state
    assert_nil race(out).lap_count
    assert_equal [[1, "1", "racing", 2, 200], [2, "3", "racing", 2, 215], [3, "2", "racing", 1, 110]], rows(out)
  end

  # Review Focus 2
  def test_no_gun_means_not_started_and_crossings_do_not_count
    out = compute("crossings:\n  1: [100, 200]\n", gun: nil)
    assert_equal :not_started, race(out).state
    assert_equal [[1, "1", "racing", 0, nil], [2, "2", "racing", 0, nil], [3, "3", "racing", 0, nil]], rows(out)
  end

  def test_crossings_before_race_start_are_ignored
    out = compute("crossings:\n  1: [50, 150, 250, 350]\n", gun: 100)
    assert_equal [1, "1", "finished", 3, 250], rows(out).first
  end

  # Review Focus 1
  def test_identical_times_tie_break_deterministically_by_crossing_id
    out = compute("crossings:\n  2: [100]\n  1: [100]\n", bibs: [1, 2], finish_rule: "{type: fixed_laps, laps: 1}")
    assert_equal ["1", "2"], race(out).rows.map(&:bib)
  end

  # Review Focus 3
  def test_flag_finish_on_voided_capture_is_ignored
    out = compute(<<~YAML)
      crossings:
        1: [100, 200, 300]
        2: [180, 360]
      rulings:
        - {kind: void_capture, capture_id: c-2-1}
        - {kind: flag_finish, bib: 2, capture_id: c-2-1}
    YAML
    assert_equal [2, "2", "finished", 1, 360], rows(out)[1]
  end

  def test_flag_finish_follows_debounced_alias
    out = compute(<<~YAML, bibs: [1, 2])
      crossings:
        1: [100, 200, 300]
      captures:
        - {id: a, bib: 2, at: 180}
        - {id: b, bib: 2, at: 185, device: d2}
      rulings:
        - {kind: flag_finish, bib: 2, capture_id: b}
    YAML
    assert_equal [2, "2", "finished", 1, 180], rows(out)[1]
  end

  def test_set_race_start_overrides_group_gun_plus_offset
    out = compute("crossings:\n  1: [130, 230, 330]\nrulings:\n  - {kind: set_race_start, race_id: r1, at: 30}\n", bibs: [1])
    assert_equal [1, "1", "finished", 3, 300], rows(out).first
  end

  def test_gap_and_lap_times
    out = compute("crossings:\n  1: [100, 200, 300]\n  2: [110, 220, 340]\n  3: [150, 310]\n")
    leader, second, third = race(out).rows
    assert_nil leader.gap
    assert_equal Results::Gap.new(laps_down: 0, ms: 40_000), second.gap
    assert_equal Results::Gap.new(laps_down: 1, ms: nil), third.gap
    assert_equal [110_000, 110_000, 120_000], second.lap_times_ms
  end

  def test_statuses_rank_after_placed_riders_without_places
    out = compute(<<~YAML, bibs: [1, 2, 3, 4])
      crossings:
        1: [100, 200, 300]
        4: [120]
      rulings:
        - {kind: dsq, bib: 4}
        - {kind: dns, bib: 3}
        - {kind: dnf, bib: 2}
    YAML
    assert_equal [[1, "1", "finished", 3, 300], [nil, "2", "dnf", 0, nil], [nil, "3", "dns", 0, nil], [nil, "4", "dsq", 1, nil]], rows(out)
  end

  def test_publication_lifecycle
    yaml = "crossings:\n  1: [100, 200, 300]\n"
    first = compute(yaml)
    assert_equal :provisional, race(first).publication
    published = yaml + "rulings:\n  - {kind: publish_results, race_id: r1, log_digest: #{first.log_digest}}\n"
    assert_equal :published, race(compute(published)).publication
    changed = published + "unassigned: [400]\n"
    assert_equal :changed_since_published, race(compute(changed)).publication
  end
end
```

- [ ] **Step 2: Run to verify failure**

Run: `bundle exec ruby -Ipacks/results/lib -Ipacks/results/test packs/results/test/standings_test.rb`
Expected: `NoMethodError: undefined method 'compute' for module Results`.

- [ ] **Step 3: Add output types**

Append inside `module Results` in `packs/results/lib/results/types.rb`:
```ruby
  # --- Output ---
  RiderResult = Data.define(:place, :bib, :name, :status, :laps, :elapsed_ms, :gap, :lap_times_ms)
  Gap = Data.define(:laps_down, :ms) # ms only when on the same lap as the race leader
  RaceResult = Data.define(:race_id, :state, :lap_count, :publication, :rows)
  Suggestion = Data.define(:key, :kind, :bib, :race_id, :message, :fix) # fix: ruling-shaped string-keyed hash, or nil
  Output = Data.define(:races, :suggestions, :unassigned, :log_digest)
```

- [ ] **Step 4: Implement GroupScorer, Standings, LogDigest, Publication, Engine**

`packs/results/lib/results/group_scorer.rb`:
```ruby
module Results
  # Spec §4.2: finish logic is decided per start group; scoring is per race.
  class GroupScorer
    STATUS_KINDS = %w[dnf dns dsq].freeze

    RiderState = Data.define(:entrant, :race_start, :crossings, :counted, :status, :finish, :pull_at)
    Scored = Data.define(:group, :lap_count, :finish_open_at, :riders, :race_results)

    def initialize(input, group, resolved)
      @input = input
      @group = group
      @resolved = resolved
      rulings = resolved.rulings
      @rulings = rulings
      @flags = rulings.latest_by("flag_finish") { it.payload["bib"].to_s }
      @pulls = rulings.latest_by("pull") { it.payload["bib"].to_s }
      @statuses = rulings.all.select { STATUS_KINDS.include?(it.kind) }.group_by { it.payload["bib"].to_s }.transform_values(&:last)
    end

    def call
      races = @input.races.select { it.start_group_id == @group.id }.sort_by(&:id)
      starts = race_starts(races)
      race_ids = races.map(&:id)
      entrants = @input.entrants.select { race_ids.include?(it.race_id) }
      crossings = entrants.to_h { |e| [e.bib, post_start(e, starts[e.race_id])] }
      lap_count = resolve_lap_count
      finish_open_at = lap_count && crossings.values.filter_map { it[lap_count - 1] }.min_by { [it.at_ms, it.ref] }&.at_ms
      riders = entrants.map { |e| rider_state(e, starts[e.race_id], crossings[e.bib], finish_open_at) }

      race_results = races.map do |race|
        state = if starts[race.id].nil? then :not_started
                elsif finish_open_at then :finish_open
                else :in_progress
                end
        RaceResult.new(race_id: race.id, state:, lap_count:, publication: :provisional,
                       rows: Standings.rows(riders.select { it.entrant.race_id == race.id }))
      end
      Scored.new(group: @group, lap_count:, finish_open_at:, riders:, race_results:)
    end

    private

    def resolve_lap_count
      rule = @group.finish_rule
      case rule["type"]
      when "fixed_laps" then rule["laps"]
      when "timed" then @rulings.latest_by("set_lap_count") { it.payload["start_group_id"] }[@group.id]&.payload&.fetch("laps")
      end
    end

    def race_starts(races)
      gun = @rulings.latest_by("set_group_start") { it.payload["start_group_id"] }[@group.id]&.payload&.fetch("at_ms")
      overrides = @rulings.latest_by("set_race_start") { it.payload["race_id"] }
      races.to_h { |r| [r.id, overrides[r.id]&.payload&.fetch("at_ms") || (gun && gun + r.start_offset_ms)] }
    end

    def post_start(entrant, start)
      return [] unless start
      @resolved.crossings_by_bib.fetch(entrant.bib, []).select { it.at_ms >= start }
    end

    def rider_state(entrant, start, crossings, finish_open_at)
      finish = finish_crossing(entrant.bib, crossings, finish_open_at)
      pull_at = @pulls[entrant.bib]&.payload&.fetch("at_ms")
      status = if (s = @statuses[entrant.bib]) then s.kind.to_sym
               elsif pull_at then :pulled
               elsif finish then :finished
               else :racing
               end
      counted = if status == :pulled then crossings.select { it.at_ms <= pull_at }
                elsif finish then crossings[0..crossings.index(finish)]
                else crossings
                end
      RiderState.new(entrant:, race_start: start, crossings:, counted:, status:, finish: (finish if status == :finished), pull_at:)
    end

    # Earliest of: the flagged crossing (early checkered flag) and the first
    # crossing once the finish is open. A flag on a crossing this rider no longer
    # has (voided or reassigned) is ignored.
    def finish_crossing(bib, crossings, finish_open_at)
      flag_ref = @flags[bib]&.payload&.fetch("capture_id")
      flag_ref = @resolved.aliases.fetch(flag_ref, flag_ref)
      candidates = [crossings.find { it.ref == flag_ref }]
      candidates << crossings.find { it.at_ms >= finish_open_at } if finish_open_at
      candidates.compact.min_by { [it.at_ms, it.ref] }
    end
  end
end
```

`packs/results/lib/results/standings.rb`:
```ruby
module Results
  # Spec §4.3: ranking within one race.
  module Standings
    UNPLACED = %i[dnf dns dsq].freeze

    module_function

    def rows(riders)
      running = riders.select { %i[finished racing].include?(it.status) }
                      .sort_by { [-it.counted.size, it.counted.last&.at_ms || Float::INFINITY, it.counted.last&.ref || "", it.entrant.bib] }
      pulled = riders.select { it.status == :pulled }.sort_by { [-it.counted.size, it.pull_at, it.entrant.bib] }
      unplaced = UNPLACED.flat_map { |s| riders.select { it.status == s }.sort_by { it.entrant.bib } }
      placed = running + pulled
      leader = placed.first
      placed.each_with_index.map { |r, i| row(r, i + 1, leader) } + unplaced.map { row(it, nil, nil) }
    end

    def row(rider, place, leader)
      last = rider.counted.last
      elapsed = (last.at_ms - rider.race_start if place && last && rider.race_start)
      RiderResult.new(place:, bib: rider.entrant.bib, name: rider.entrant.name, status: rider.status, laps: rider.counted.size,
                      elapsed_ms: elapsed, gap: gap(rider, elapsed, place, leader), lap_times_ms: lap_times(rider))
    end

    def gap(rider, elapsed, place, leader)
      return nil if place.nil? || place == 1 || elapsed.nil? || rider.status == :pulled || leader.counted.empty?
      lead_laps = leader.counted.size
      return Gap.new(laps_down: lead_laps - rider.counted.size, ms: nil) if rider.counted.size != lead_laps
      Gap.new(laps_down: 0, ms: elapsed - (leader.counted.last.at_ms - leader.race_start))
    end

    def lap_times(rider)
      return [] unless rider.race_start
      ([rider.race_start] + rider.counted.map(&:at_ms)).each_cons(2).map { |a, b| b - a }
    end
  end
end
```

`packs/results/lib/results/log_digest.rb`:
```ruby
require "digest"

module Results
  # Fingerprint of everything that can change standings. Publishing and dismissing
  # suggestions don't change standings, so they are excluded.
  module LogDigest
    EXCLUDED_KINDS = %w[publish_results dismiss_suggestion].freeze

    module_function

    def compute(input)
      ids = input.captures.map { "c:#{it.id}" } +
            input.bib_assignments.map { "b:#{it.id}" } +
            input.rulings.reject { EXCLUDED_KINDS.include?(it.kind) }.map { "r:#{it.id}" }
      Digest::SHA256.hexdigest(ids.uniq.sort.join("\n"))
    end
  end
end
```

`packs/results/lib/results/publication.rb`:
```ruby
module Results
  module Publication
    module_function

    def for(race_id, rulings, digest)
      published = rulings.latest_by("publish_results") { it.payload["race_id"] }[race_id]
      return :provisional unless published
      published.payload["log_digest"] == digest ? :published : :changed_since_published
    end
  end
end
```

`packs/results/lib/results/engine.rb`:
```ruby
module Results
  class Engine
    def initialize(input)
      @input = input
    end

    def call
      resolved = Resolver.new(@input).call
      digest = LogDigest.compute(@input)
      scored = @input.start_groups.uniq(&:id).sort_by(&:id).map { GroupScorer.new(@input, it, resolved).call }
      races = scored.flat_map(&:race_results).map { it.with(publication: Publication.for(it.race_id, resolved.rulings, digest)) }
      Output.new(races:, suggestions: [], unassigned: resolved.unassigned, log_digest: digest)
    end
  end
end
```

Replace `packs/results/lib/results.rb` with:
```ruby
require "set"
require_relative "results/types"
require_relative "results/active_rulings"
require_relative "results/resolver"
require_relative "results/standings"
require_relative "results/group_scorer"
require_relative "results/log_digest"
require_relative "results/publication"
require_relative "results/engine"

# Pure results engine: Input snapshot in, standings and suggestions out.
# Must not depend on Rails or a database.
module Results
  def self.compute(input) = Engine.new(input).call
end
```

- [ ] **Step 5: Run to verify pass**

Run: `bundle exec bin/test-results`
Expected: all resolver and standings tests pass, 0 failures.

- [ ] **Step 6: Commit**

```bash
git add packs/results
git commit -m "feat(results): start-group finish logic, per-race standings, publication digest

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 6: Results engine — anomaly suggestions

**Files:**
- Create: `packs/results/lib/results/anomalies.rb`, `packs/results/test/anomalies_test.rb`
- Modify: `packs/results/lib/results/engine.rb`, `packs/results/lib/results.rb`

**Interfaces:**
- Consumes: `GroupScorer::Scored`, `GroupScorer::RiderState`, `Resolver::Resolved`, `Suggestion`.
- Produces: `Anomalies.new(input, resolved, scored_groups).call -> [Suggestion]` sorted by key. Keys: `missed:<bib>:<from_ref>:<to_ref>`, `short:<bib>:<from_ref>:<to_ref>`, `lapped:<bib>:<laps>`, `clock:<device_id>`, `unassigned:<capture_id>` (`from_ref` is `start` for lap 1). Kinds: `:suspected_missed_crossing`, `:suspected_duplicate`, `:about_to_be_lapped`, `:unsynced_clock`, `:unassigned_capture`. `Output#suggestions` is now populated, minus dismissed keys.

- [ ] **Step 1: Write failing tests**

`packs/results/test/anomalies_test.rb`:
```ruby
require "test_helper"

class AnomaliesTest < Minitest::Test
  include ResultsTestHelpers

  # Three riders, 5 laps of ~300s. Bib 2 misses lap 3's crossing; bib 3 misses lap 4's.
  MISSED = <<~YAML
    crossings:
      1: [300, 600, 900, 1200, 1500]
      2: [310, 620, 1240, 1550]
      3: [305, 610, 915, 1525]
  YAML

  def compute(yaml, **setup) = Results.compute(input_from(setup_yaml(**setup) + yaml))
  def find(out, key) = out.suggestions.find { it.key == key }

  def test_missed_crossing_prefers_matching_unassigned_capture
    out = compute(MISSED + "unassigned: [935]\n", finish_rule: "{type: fixed_laps, laps: 5}")
    assert_equal ["missed:2:c-2-2:c-2-3", "missed:3:c-3-3:c-3-4", "unassigned:u-1"], out.suggestions.map(&:key)
    assert_equal({ "kind" => "assign_bib", "capture_id" => "u-1", "bib" => "2" }, find(out, "missed:2:c-2-2:c-2-3").fix)
    assert_equal({ "kind" => "insert_capture", "bib" => "3", "at_ms" => 1_220_000 }, find(out, "missed:3:c-3-3:c-3-4").fix)
    assert_equal :suspected_missed_crossing, find(out, "missed:3:c-3-3:c-3-4").kind
  end

  def test_accepting_the_suggestion_fixes_laps_and_clears_it
    yaml = MISSED + "unassigned: [935]\nrulings:\n  - {kind: assign_bib, capture_id: u-1, bib: 2}\n"
    out = compute(yaml, finish_rule: "{type: fixed_laps, laps: 5}")
    refute find(out, "missed:2:c-2-2:c-2-3")
    assert_equal [2, "2", "finished", 5, 1550], compact_rows(out.races.first.rows).find { it[1] == "2" }
  end

  def test_dismissed_suggestions_are_suppressed
    yaml = MISSED + "rulings:\n  - {kind: dismiss_suggestion, suggestion_key: \"missed:3:c-3-3:c-3-4\"}\n"
    out = compute(yaml, finish_rule: "{type: fixed_laps, laps: 5}")
    refute find(out, "missed:3:c-3-3:c-3-4")
    assert find(out, "missed:2:c-2-2:c-2-3")
  end

  def test_short_lap_suggests_voiding_the_extra_crossing
    out = compute("crossings:\n  1: [300, 600, 700, 900, 1200]\n  2: [310, 620, 930, 1240]\n", bibs: [1, 2], finish_rule: "{type: fixed_laps, laps: 10}")
    short = out.suggestions.select { it.kind == :suspected_duplicate }
    assert_includes short.map(&:key), "short:1:c-1-2:c-1-3"
    assert_equal({ "kind" => "void_capture", "capture_id" => "c-1-3" }, find(out, "short:1:c-1-2:c-1-3").fix)
  end

  def test_short_start_loop_is_not_flagged
    # XC-style: the start loop is about half a lap for everyone.
    out = compute("crossings:\n  1: [150, 450, 750]\n  2: [155, 460, 765]\n  3: [160, 470, 780]\n", finish_rule: "{type: fixed_laps, laps: 10}")
    assert_empty out.suggestions
  end

  def test_slow_rider_is_not_flagged_as_missing_crossings
    out = compute("crossings:\n  1: [100, 200, 300, 400]\n  2: [190, 380, 570]\n", bibs: [1, 2], finish_rule: "{type: fixed_laps, laps: 20}")
    assert_empty out.suggestions.reject { it.kind == :about_to_be_lapped }
  end

  def test_about_to_be_lapped_uses_projected_positions
    crossings = "crossings:\n  1: [#{(1..10).map { it * 100 }.join(', ')}]\n  2: [190, 380, 570, 760, 950]\n  3: [#{(1..10).map { it * 105 }.join(', ')}]\n"
    out = compute("now: 1050\n" + crossings, finish_rule: "{type: fixed_laps, laps: 20}")
    assert_equal ["lapped:2:5"], out.suggestions.map(&:key)
    assert_equal({ "kind" => "flag_finish", "bib" => "2" }, out.suggestions.first.fix)
  end

  def test_no_lapping_suggestions_once_finish_is_open
    out = compute("now: 400\ncrossings:\n  1: [100, 200, 300]\n  2: [190]\n")
    assert_empty out.suggestions.select { it.kind == :about_to_be_lapped }
  end

  def test_unsynced_clock_is_reported_per_device
    out = compute(<<~YAML)
      captures:
        - {id: a, bib: 1, at: 100, device: d2, offset_ms: ~}
        - {id: b, bib: 2, at: 110, device: d2, offset_ms: ~}
    YAML
    assert_equal ["clock:d2"], out.suggestions.map(&:key)
  end
end
```

- [ ] **Step 2: Run to verify failure**

Run: `bundle exec ruby -Ipacks/results/lib -Ipacks/results/test packs/results/test/anomalies_test.rb`
Expected: failures — `suggestions` is always `[]`.

- [ ] **Step 3: Implement Anomalies**

`packs/results/lib/results/anomalies.rb`:
```ruby
module Results
  # Spec §4.4: suggestions only — never modifies data.
  class Anomalies
    Segment = Data.define(:index, :from_ref, :from_at, :to, :ms)

    def self.median(values)
      sorted = values.sort
      mid = sorted.size / 2
      (sorted.size.odd? ? sorted[mid] : (sorted[mid - 1] + sorted[mid]) / 2.0).to_f
    end

    def self.segments_for(rider)
      return [] unless rider.race_start
      prev_ref = "start"
      prev_at = rider.race_start
      rider.counted.each_with_index.map do |c, i|
        seg = Segment.new(index: i + 1, from_ref: prev_ref, from_at: prev_at, to: c, ms: c.at_ms - prev_at)
        prev_ref = c.ref
        prev_at = c.at_ms
        seg
      end
    end

    # Typical lap times for one race (see spec §4.4 "Reference lap time").
    class RaceLaps
      def initialize(riders)
        @segments = riders.to_h { [it.entrant.bib, Anomalies.segments_for(it)] }
      end

      def segments(bib) = @segments.fetch(bib)

      def typical(bib, index, exclude)
        base = own_median(bib, exclude)
        return (base && start_factor && base * start_factor) if index == 1
        base || race_median(bib, index)
      end

      private

      def own_median(bib, exclude)
        laps = @segments[bib].select { it.index >= 2 && !exclude.include?(it.index) }.map(&:ms)
        laps.any? ? Anomalies.median(laps) : nil
      end

      def race_median(bib, index)
        laps = @segments.except(bib).values.filter_map { |segs| segs.find { it.index == index }&.ms }
        laps.any? ? Anomalies.median(laps) : nil
      end

      # How long lap 1 runs relative to a normal lap, across the race.
      def start_factor
        return @start_factor if defined?(@start_factor)
        ratios = @segments.filter_map do |bib, segs|
          base = own_median(bib, [])
          segs.first.ms / base if segs.any? && base&.positive?
        end
        @start_factor = ratios.any? ? Anomalies.median(ratios) : nil
      end
    end

    def initialize(input, resolved, scored_groups)
      @input = input
      @config = input.config
      @resolved = resolved
      @groups = scored_groups
    end

    def call
      dismissed = @resolved.rulings.of("dismiss_suggestion").map { it.payload["suggestion_key"] }.to_set
      (lap_suggestions + lapping_suggestions + clock_suggestions + unassigned_suggestions)
        .reject { dismissed.include?(it.key) }
        .sort_by(&:key)
    end

    private

    def lap_suggestions
      @groups.flat_map do |group|
        group.riders.group_by { it.entrant.race_id }.flat_map do |race_id, riders|
          laps = RaceLaps.new(riders)
          riders.flat_map { |r| rider_lap_suggestions(r.entrant.bib, race_id, laps) }
        end
      end
    end

    def rider_lap_suggestions(bib, race_id, laps)
      own = laps.segments(bib)
      own.filter_map do |seg|
        ref = laps.typical(bib, seg.index, [seg.index])
        next unless ref&.positive?
        ratio = seg.ms / ref
        if ratio.between?(@config.missed_low, @config.missed_high) && neighbors_normal?(bib, seg, own, laps)
          missed(bib, race_id, seg, ref)
        elsif ratio < @config.short_ratio && !seg.to.inserted
          Suggestion.new(key: "short:#{bib}:#{seg.from_ref}:#{seg.to.ref}", kind: :suspected_duplicate, bib:, race_id:,
                         message: "Bib #{bib} lap #{seg.index} took #{fmt(seg.ms)}, much shorter than typical #{fmt(ref)} — duplicate tap or wrong bib?",
                         fix: { "kind" => "void_capture", "capture_id" => seg.to.ref })
        end
      end
    end

    def neighbors_normal?(bib, seg, own, laps)
      own.select { (it.index - seg.index).abs == 1 }.all? do |n|
        ref = laps.typical(bib, n.index, [seg.index, n.index])
        ref.nil? || (n.ms / ref).between?(@config.neighbor_low, @config.neighbor_high)
      end
    end

    def missed(bib, race_id, seg, ref)
      mid = (seg.from_at + seg.to.at_ms) / 2
      window = ref * @config.match_window_ratio
      match = @resolved.unassigned.select { (it.at_ms - mid).abs <= window }.min_by { [(it.at_ms - mid).abs, it.capture_id] }
      fix = if match then { "kind" => "assign_bib", "capture_id" => match.capture_id, "bib" => bib }
            else { "kind" => "insert_capture", "bib" => bib, "at_ms" => mid }
            end
      Suggestion.new(key: "missed:#{bib}:#{seg.from_ref}:#{seg.to.ref}", kind: :suspected_missed_crossing, bib:, race_id:,
                     message: "Bib #{bib} lap #{seg.index} took #{fmt(seg.ms)}, about #{(seg.ms / ref).round(1)}× typical #{fmt(ref)} — missed crossing?",
                     fix:)
    end

    def lapping_suggestions
      @groups.reject(&:finish_open_at).flat_map do |group|
        racing = group.riders.select { it.status == :racing && it.counted.any? }
        leader = racing.min_by { [-it.counted.size, it.counted.last.at_ms, it.counted.last.ref] }
        next [] unless leader
        lead_ref = lap_ref(leader)
        racing.reject { it.equal?(leader) }.filter_map { lapping(leader, lead_ref, it) }
      end
    end

    def lap_ref(rider)
      segs = Anomalies.segments_for(rider)
      later = segs.select { it.index >= 2 }.map(&:ms)
      later.any? ? Anomalies.median(later) : segs.first.ms.to_f
    end

    # Projects both riders forward at their typical pace; flags the rider if the
    # leader gains another whole lap on them before their next crossing.
    def lapping(leader, lead_ref, rider)
      ref = lap_ref(rider)
      now = @input.now_ms
      next_crossing = rider.counted.last.at_ms + ref
      return nil if next_crossing < now || lead_ref <= 0 || ref <= 0
      position = ->(r, r_ref, t) { r.counted.size + (t - r.counted.last.at_ms) / r_ref }
      gap_now = position.(leader, lead_ref, now) - position.(rider, ref, now)
      gap_next = position.(leader, lead_ref, next_crossing) - (rider.counted.size + 1)
      return nil unless gap_next >= 1 && gap_next.floor > gap_now.floor
      bib = rider.entrant.bib
      Suggestion.new(key: "lapped:#{bib}:#{rider.counted.size}", kind: :about_to_be_lapped, bib:, race_id: rider.entrant.race_id,
                     message: "Bib #{bib} will likely be lapped by the group leader before their next crossing",
                     fix: { "kind" => "flag_finish", "bib" => bib })
    end

    def clock_suggestions
      @resolved.unsynced_devices.map do |device|
        Suggestion.new(key: "clock:#{device}", kind: :unsynced_clock, bib: nil, race_id: nil,
                       message: "Device #{device} recorded captures before its clock was synced with the hub; their times are provisional",
                       fix: nil)
      end
    end

    def unassigned_suggestions
      @resolved.unassigned.map do |u|
        message = u.bib ? "Capture #{u.capture_id} has unregistered bib #{u.bib}" : "Capture #{u.capture_id} has no bib"
        Suggestion.new(key: "unassigned:#{u.capture_id}", kind: :unassigned_capture, bib: u.bib, race_id: nil, message:,
                       fix: { "kind" => "assign_bib", "capture_id" => u.capture_id, "bib" => nil })
      end
    end

    def fmt(ms)
      seconds = (ms / 1000.0).round
      format("%d:%02d", seconds / 60, seconds % 60)
    end
  end
end
```

In `packs/results/lib/results/engine.rb`, replace the `Output.new(...)` line with:
```ruby
      suggestions = Anomalies.new(@input, resolved, scored).call
      Output.new(races:, suggestions:, unassigned: resolved.unassigned, log_digest: digest)
```

In `packs/results/lib/results.rb`, add before `require_relative "results/engine"`:
```ruby
require_relative "results/anomalies"
```

- [ ] **Step 4: Run to verify pass**

Run: `bundle exec bin/test-results`
Expected: all tests pass, 0 failures. (If `test_short_lap_suggests_voiding_the_extra_crossing` also reports a `short:1:c-1-3:c-1-4` key, that is expected — the assertion uses `assert_includes`.)

- [ ] **Step 5: Commit**

```bash
git add packs/results
git commit -m "feat(results): missed-crossing, duplicate, about-to-be-lapped, clock and unassigned suggestions

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 7: Golden race files and order-independence property tests

**Files:**
- Create: `packs/results/test/fixtures/races/{road-race-single-lap,crit-lapped-riders,cx-timed-lap-count-changed,waves-30s-offsets,flag-finish-and-pulls,missed-crossings,duplicate-taps-two-devices,reverted-insert}.yml`, `packs/results/test/golden_test.rb`, `packs/results/test/order_independence_test.rb`

**Interfaces:**
- Consumes: `Results.compute`, `Results::Fixture.load`, `ResultsTestHelpers#compact_rows/#normalize_rows`.
- Produces: golden files reused by Plan 3's race simulator acceptance test.

- [ ] **Step 1: Write the golden test runners**

`packs/results/test/golden_test.rb`:
```ruby
require "test_helper"

class GoldenTest < Minitest::Test
  include ResultsTestHelpers

  Dir[File.expand_path("fixtures/races/*.yml", __dir__)].sort.each do |path|
    name = File.basename(path, ".yml")
    define_method("test_#{name.tr('-', '_')}") do
      input, expected = Results::Fixture.load(path)
      out = Results.compute(input)
      expected.fetch("races").each do |race_id, rows|
        race = out.races.find { it.race_id == race_id }
        assert race, "#{name}: missing race #{race_id}"
        assert_equal normalize_rows(rows), compact_rows(race.rows), "#{name}: race #{race_id}"
      end
      if expected.key?("suggestions")
        assert_equal expected["suggestions"].sort, out.suggestions.map(&:key), "#{name}: suggestions"
      end
    end
  end
end
```

`packs/results/test/order_independence_test.rb`:
```ruby
require "test_helper"

# Records reach the hub in any order and may arrive twice; results must not change.
class OrderIndependenceTest < Minitest::Test
  Dir[File.expand_path("fixtures/races/*.yml", __dir__)].sort.each do |path|
    define_method("test_order_independent_#{File.basename(path, '.yml').tr('-', '_')}") do
      input, = Results::Fixture.load(path)
      baseline = Results.compute(input)
      rng = Random.new(42)
      20.times { assert_equal baseline, Results.compute(scramble(input, rng)) }
    end
  end

  private

  def scramble(input, rng)
    with_dups = ->(list) { (list + list.select { rng.rand < 0.3 }).shuffle(random: rng) }
    input.with(start_groups: input.start_groups.shuffle(random: rng), races: input.races.shuffle(random: rng),
               entrants: input.entrants.shuffle(random: rng), captures: with_dups.(input.captures),
               bib_assignments: with_dups.(input.bib_assignments), rulings: with_dups.(input.rulings))
  end
end
```

- [ ] **Step 2: Write the golden race files**

`packs/results/test/fixtures/races/road-race-single-lap.yml`:
```yaml
# Mass-start road race = 1 lap. Covers DNF / DNS / DSQ ordering.
start_groups:
  - {id: g1, finish_rule: {type: fixed_laps, laps: 1}, gun: 0}
races:
  - {id: r1, group: g1, offset: 0}
entrants:
  - {bib: 1, race: r1}
  - {bib: 2, race: r1}
  - {bib: 3, race: r1}
  - {bib: 4, race: r1}
  - {bib: 5, race: r1}
  - {bib: 6, race: r1}
  - {bib: 7, race: r1}
crossings:
  1: [3600]
  2: [3610]
  3: [3700]
  7: [3650]
rulings:
  - {kind: dnf, bib: 5}
  - {kind: dns, bib: 6}
  - {kind: dsq, bib: 7}
expect:
  races:
    r1:
      - [1, 1, finished, 1, 3600]
      - [2, 2, finished, 1, 3610]
      - [3, 3, finished, 1, 3700]
      - [4, 4, racing, 0, ~]
      - [~, 5, dnf, 0, ~]
      - [~, 6, dns, 0, ~]
      - [~, 7, dsq, 1, ~]
```

`packs/results/test/fixtures/races/crit-lapped-riders.yml`:
```yaml
# 6-lap crit. Riders lapped 1x, 2x, 3x finish on their first crossing after the
# leader finishes. Bib 3 crosses before bib 2 but has fewer laps. Bib 1's cool-down
# crossing at 700 is ignored.
start_groups:
  - {id: g1, finish_rule: {type: fixed_laps, laps: 6}, gun: 0}
races:
  - {id: r1, group: g1, offset: 0}
entrants:
  - {bib: 1, race: r1}
  - {bib: 2, race: r1}
  - {bib: 3, race: r1}
  - {bib: 4, race: r1}
  - {bib: 5, race: r1}
crossings:
  1: [100, 200, 300, 400, 500, 600, 700]
  2: [121, 242, 363, 484, 605]
  3: [151, 302, 453, 604]
  4: [220, 440, 660]
  5: [102, 204, 306, 408, 510, 612]
expect:
  races:
    r1:
      - [1, 1, finished, 6, 600]
      - [2, 5, finished, 6, 612]
      - [3, 2, finished, 5, 605]
      - [4, 3, finished, 4, 604]
      - [5, 4, finished, 3, 660]
```

`packs/results/test/fixtures/races/cx-timed-lap-count-changed.yml`:
```yaml
# 45-minute CX. Lap count set to 6, then lowered to 5 after the leader had already
# done more laps: finish opens retroactively at the leader's 5th crossing.
start_groups:
  - {id: g1, finish_rule: {type: timed, target_duration_ms: 2700000}, gun: 0}
races:
  - {id: r1, group: g1, offset: 0}
entrants:
  - {bib: 10, race: r1}
  - {bib: 11, race: r1}
  - {bib: 12, race: r1}
crossings:
  10: [500, 1000, 1500, 2000, 2500, 3000]
  11: [520, 1040, 1560, 2080, 2600]
  12: [600, 1200, 1800, 2400, 3000]
rulings:
  - {kind: set_lap_count, start_group_id: g1, laps: 6, created: 600}
  - {kind: set_lap_count, start_group_id: g1, laps: 5, created: 900}
expect:
  races:
    r1:
      - [1, 10, finished, 5, 2500]
      - [2, 11, finished, 5, 2600]
      - [3, 12, finished, 5, 3000]
```

`packs/results/test/fixtures/races/waves-30s-offsets.yml`:
```yaml
# Three races released 30 s apart in one start group. The group leader is in the
# second wave (first to 3 laps on the road). Elapsed times are per race start.
# Bib 301's crossing at 1050 is before its wave starts (1060) and is ignored.
start_groups:
  - {id: g1, finish_rule: {type: fixed_laps, laps: 3}, gun: 1000}
races:
  - {id: rA, group: g1, offset: 0}
  - {id: rB, group: g1, offset: 30}
  - {id: rC, group: g1, offset: 60}
entrants:
  - {bib: 101, race: rA}
  - {bib: 102, race: rA}
  - {bib: 201, race: rB}
  - {bib: 301, race: rC}
  - {bib: 302, race: rC}
crossings:
  101: [1300, 1600, 1900]
  102: [1310, 1620, 1930]
  201: [1320, 1610, 1895]
  301: [1050, 1400, 1750, 2100]
  302: [1500, 1950]
expect:
  races:
    rA:
      - [1, 101, finished, 3, 900]
      - [2, 102, finished, 3, 930]
    rB:
      - [1, 201, finished, 3, 865]
    rC:
      - [1, 301, finished, 3, 1040]
      - [2, 302, finished, 2, 890]
```

`packs/results/test/fixtures/races/flag-finish-and-pulls.yml`:
```yaml
# Bib 2 is shown the checkered flag early (before the leader finishes) to avoid
# being lapped. Bibs 3 and 4 are pulled; same laps, so pull order decides.
start_groups:
  - {id: g1, finish_rule: {type: fixed_laps, laps: 4}, gun: 0}
races:
  - {id: r1, group: g1, offset: 0}
entrants:
  - {bib: 1, race: r1}
  - {bib: 2, race: r1}
  - {bib: 3, race: r1}
  - {bib: 4, race: r1}
  - {bib: 5, race: r1}
crossings:
  1: [100, 200, 300, 400]
  2: [180, 360, 540]
  3: [130, 260]
  4: [140]
  5: [105, 210, 315, 420]
rulings:
  - {kind: pull, bib: 3, at: 250, created: 251}
  - {kind: pull, bib: 4, at: 300, created: 301}
  - {kind: flag_finish, bib: 2, capture_id: c-2-2, created: 370}
expect:
  races:
    r1:
      - [1, 1, finished, 4, 400]
      - [2, 5, finished, 4, 420]
      - [3, 2, finished, 2, 360]
      - [4, 3, pulled, 1, 130]
      - [5, 4, pulled, 1, 140]
```

`packs/results/test/fixtures/races/missed-crossings.yml`:
```yaml
# Bib 2 missed lap 3 (an unassigned tap at 935 matches); bib 3 missed lap 4 (no match).
start_groups:
  - {id: g1, finish_rule: {type: fixed_laps, laps: 5}, gun: 0}
races:
  - {id: r1, group: g1, offset: 0}
entrants:
  - {bib: 1, race: r1}
  - {bib: 2, race: r1}
  - {bib: 3, race: r1}
crossings:
  1: [300, 600, 900, 1200, 1500]
  2: [310, 620, 1240, 1550]
  3: [305, 610, 915, 1525]
unassigned: [935]
expect:
  races:
    r1:
      - [1, 1, finished, 5, 1500]
      - [2, 3, finished, 4, 1525]
      - [3, 2, finished, 4, 1550]
  suggestions:
    - missed:2:c-2-2:c-2-3
    - missed:3:c-3-3:c-3-4
    - unassigned:u-1
```

`packs/results/test/fixtures/races/duplicate-taps-two-devices.yml`:
```yaml
# Two tablets both tap bib 1 on lap 1 (2 s apart): one crossing, no suggestions.
start_groups:
  - {id: g1, finish_rule: {type: fixed_laps, laps: 2}, gun: 0}
races:
  - {id: r1, group: g1, offset: 0}
entrants:
  - {bib: 1, race: r1}
  - {bib: 2, race: r1}
captures:
  - {id: a1, bib: 1, at: 300, device: d1}
  - {id: b1, bib: 1, at: 302, device: d2}
  - {id: a2, bib: 2, at: 320, device: d1}
  - {id: a3, bib: 1, at: 600, device: d1}
  - {id: a4, bib: 2, at: 640, device: d1}
expect:
  races:
    r1:
      - [1, 1, finished, 2, 600]
      - [2, 2, finished, 2, 640]
  suggestions: []
```

`packs/results/test/fixtures/races/reverted-insert.yml`:
```yaml
# An official inserted a crossing for bib 2, then reverted it.
start_groups:
  - {id: g1, finish_rule: {type: fixed_laps, laps: 2}, gun: 0}
races:
  - {id: r1, group: g1, offset: 0}
entrants:
  - {bib: 1, race: r1}
  - {bib: 2, race: r1}
crossings:
  1: [300, 600]
  2: [310]
rulings:
  - {id: ins-1, kind: insert_capture, bib: 2, at: 620, created: 700}
  - {id: rev-1, kind: revert, ruling_id: ins-1, created: 800}
expect:
  races:
    r1:
      - [1, 1, finished, 2, 600]
      - [2, 2, racing, 1, 310]
```

- [ ] **Step 3: Run golden and property tests**

Run: `bundle exec bin/test-results`
Expected: all pass, including 8 `GoldenTest` and 8 `OrderIndependenceTest` cases. If a golden file fails, compare the failure diff against the comment at the top of that file: fix the engine if the comment's race story is right; only change the expected rows if the story itself is wrong, and say why in the commit message.

- [ ] **Step 4: Commit**

```bash
git add packs/results/test
git commit -m "test(results): golden race files and order-independence property tests

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 8: ResultsSnapshot — compute results from the database (both adapters)

**Files:**
- Create: `packs/timing/app/models/results_snapshot.rb`, `test/models/results_snapshot_test.rb`
- Modify: `config/application.rb`

**Interfaces:**
- Consumes: AR models (Tasks 2–3), `Results` engine (Tasks 4–6).
- Produces: `ResultsSnapshot.for(event, now_ms:) -> Results::Input`; `ResultsSnapshot.compute(event, now_ms: current) -> Results::Output`. Plan 3's GraphQL layer calls `ResultsSnapshot.compute`.

- [ ] **Step 1: Write the failing integration test**

`test/models/results_snapshot_test.rb`:
```ruby
require "test_helper"

class ResultsSnapshotTest < ActiveSupport::TestCase
  setup do
    @event = create_event
    @group = create_start_group(event: @event, finish_rule: { "type" => "timed", "target_duration_ms" => 2_700_000 })
    @race = create_race(event: @event, start_group: @group)
    register(race: @race, bib: "1", rider: create_rider(first_name: "Ann", last_name: "Lee"))
    register(race: @race, bib: "2")
    @device = create_device(event: @event)
  end

  test "computes standings from stored captures and rulings" do
    rule(event: @event, kind: "set_group_start", start_group_id: @group.id, at_ms: 0, created_at_ms: 0)
    [[1, "1", 100_000], [2, "2", 110_000], [3, "1", 200_000], [4, nil, 215_000]].each do |seq, bib, at|
      record_capture(device: @device, seq:, at_ms: at, bib:, id: "cap-#{seq}")
    end
    rule(event: @event, kind: "assign_bib", capture_id: "cap-4", bib: "2", created_at_ms: 300_000)
    rule(event: @event, kind: "set_lap_count", start_group_id: @group.id, laps: 2, created_at_ms: 300_001)

    out = ResultsSnapshot.compute(@event, now_ms: 400_000)
    race = out.races.find { it.race_id == @race.id }
    assert_equal :finish_open, race.state
    assert_equal [[1, "1", "Ann Lee", :finished, 2, 200_000], [2, "2", "Ada Rider", :finished, 2, 215_000]],
                 race.rows.map { [it.place, it.bib, it.name, it.status, it.laps, it.elapsed_ms] }
    assert_empty out.unassigned
  end

  test "payload keys survive a database round trip as strings" do
    rule(event: @event, kind: "pull", bib: "2", at_ms: 50_000)
    input = ResultsSnapshot.for(@event, now_ms: 0)
    assert_equal({ "bib" => "2", "at_ms" => 50_000 }, input.rulings.first.payload)
    assert_equal({ "type" => "timed", "target_duration_ms" => 2_700_000 }, input.start_groups.first.finish_rule)
  end

  test "scopes the snapshot to one event" do
    other = create_event(name: "Other")
    record_capture(device: create_device(event: other), seq: 1, at_ms: 1, bib: "1")
    assert_empty ResultsSnapshot.for(@event, now_ms: 0).captures
  end
end
```

- [ ] **Step 2: Run to verify failure**

Run: `bin/rails test test/models/results_snapshot_test.rb`
Expected: error `uninitialized constant ResultsSnapshot`.

- [ ] **Step 3: Load the engine in Rails and implement the adapter**

In `config/application.rb`, after `require_relative "../lib/timing_mode"` add:
```ruby
$LOAD_PATH.unshift File.expand_path("../packs/results/lib", __dir__)
require "results"
```

`packs/timing/app/models/results_snapshot.rb`:
```ruby
# Builds the results engine's input from the database. The engine itself never
# touches ActiveRecord.
class ResultsSnapshot
  def self.compute(event, now_ms: (Time.now.to_r * 1000).to_i) = Results.compute(self.for(event, now_ms:))

  def self.for(event, now_ms:)
    Results::Input.new(
      start_groups: event.start_groups.map { Results::StartGroupDef.new(id: it.id, finish_rule: it.finish_rule) },
      races: event.races.map { Results::RaceDef.new(id: it.id, start_group_id: it.start_group_id, start_offset_ms: it.start_offset_ms) },
      entrants: event.registrations.includes(:rider).map { Results::Entrant.new(bib: it.bib, race_id: it.race_id, name: it.rider.full_name) },
      captures: Capture.where(event:).map do
        Results::Capture.new(id: it.id, device_id: it.device_id, device_seq: it.device_seq, captured_at_ms: it.captured_at_ms,
                             clock_offset_ms: it.clock_offset_ms, bib: it.bib)
      end,
      bib_assignments: BibAssignment.where(event:).map do
        Results::BibAssignment.new(id: it.id, capture_id: it.capture_id, bib: it.bib, device_seq: it.device_seq)
      end,
      rulings: Ruling.where(event:).map { Results::Ruling.new(id: it.id, kind: it.kind, payload: it.payload, created_at_ms: it.created_at_ms) },
      now_ms:
    )
  end
end
```

- [ ] **Step 4: Run the full suites on both databases**

```bash
bin/rails test
TIMING_DB=postgresql bin/rails test
bin/packwerk check
bundle exec bin/test-results
```
Expected: all green everywhere; `No offenses detected`.

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "feat(timing): ResultsSnapshot adapter computes results from the database

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

## Coverage map (spec → task)

| Spec | Task |
|---|---|
| §2 modular monolith, modes, packs, single codebase | 1 |
| §3.1 setup data, eligibility warnings, bib unique per event | 2 |
| §3.2 devices, captures, bib assignments, rulings, append-only | 3 |
| §3.3 derived data computed from the log | 4–6, 8 |
| §4.1 resolution, reverts, debounce, unassigned | 4 |
| §4.2 finish logic per start group, flags, lapped riders | 5, 7 |
| §4.3 standings, elapsed per race start, gaps, publication | 5, 7 |
| §4.4 suggestions, dismissals | 6, 7 |
| §8 SQLite WAL + synchronous=FULL | 1 |
| §10 golden files, property tests, dual-DB CI | 1, 7, 8 |
| §5 sync + capture app, §5.3 hash chain verification | **Plan 2** |
| §6 ops console, §7 GraphQL, §8 pairing/PINs/local CA, §10 simulator + acceptance | **Plan 3** |
