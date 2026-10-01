# Hub MVP — Plan 2: Hub API, Access & Race Simulator

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Everything the ops console needs from the hub — signed-in officials with roles, a GraphQL API for setup, standings, the review queue and rulings, live "event changed" pushes, QR device pairing, the hub's own HTTPS certificate authority — plus a race simulator that writes realistic races straight into the hub, and a terminal standings view to watch them.

**Architecture:** Two new packs. `packs/access` owns officials, PIN sessions, pairing tokens, the local CA and the onboarding page. `packs/api` owns the GraphQL schema (graphql-ruby) and the ActionCable `EventChannel`. Rulings are created only through the API with server-set time and the signed-in official. Standings come from `StandingsService`, which wraps `ResultsSnapshot` and falls back to the last good result if the engine raises. The simulator (`lib/race_simulator`) generates ground-truth crossings and writes them as captures from a "Simulator" device.

**Tech Stack:** Ruby 4.0.2, Rails 8.1.4, graphql-ruby 2.6, bcrypt, csv, ActionCable (async in dev, test adapter in tests, Solid Cable in production), OpenSSL, Minitest.

**Spec:** `docs/superpowers/specs/2026-10-01-hub-mvp-design.md` (§6 data the console needs, §7 API, §8 security, §9 error handling, §10 simulator). Also `docs/TODO.md` → "Carry into upcoming plans → Ops console / API plan".

**Plan 2 of the Hub MVP** (user chose this order). Plan 3: React ops console. Plan 4: sync protocol + capture PWA + the spec §1 tablet acceptance test.

## Global Constraints

- Ruby **4.0.2**, Rails **8.1.4** (already locked). Add gems: `graphql` (2.6.x), `bcrypt`, `csv`.
- All primary keys UUIDv7 strings; every millisecond value crosses GraphQL as the `Millis` scalar (a JSON number), never GraphQL `Int` (32-bit).
- Roles, lowest to highest: `timer` < `chief` < `admin`. Queries need any signed-in official; rulings and start control need `chief`; setup, CSV import, officials and devices need `admin`.
- Officials sign in with name + PIN (4–8 digits) at `POST /session`; rate limit **5 attempts per minute per IP**; session cookie `_timing_session`, `SameSite=Strict`, `HttpOnly`, `Secure` when `HUB_TLS=1`.
- Requests with an `Origin` header that is not the hub's own origin (or listed in `TIMING_ALLOWED_ORIGINS`, comma-separated) get **403**.
- Clients never set `Ruling#created_at_ms` or `official_id`; the API sets both. Start times from "GO" use hub time.
- Pairing tokens: random, stored as SHA-256 digest, **10 minutes**, single use. Device credentials: 32 random bytes, stored as SHA-256 digest, revocable.
- Local CA: RSA 2048 root valid **3650 days**; server certificate valid **397 days**, renewed within 30 days of expiry or when its host/IP list changes. HTTPS port `HUB_TLS_PORT` (default **3443**). With `HUB_TLS=1`, plain HTTP serves only `/up` and `/onboarding*`.
- Live updates: one ActionCable stream per event, `event:<event_id>`, message `{"type":"changed","at_ms":<int>}`; clients refetch.
- `packs/results/lib` stays free of Rails.

## Review Focus

1. **Someone guessing PINs** — the 6th sign-in attempt within a minute from one address gets 429, even with the right PIN. Test in Task 1.
2. **Two officials act on the same suggestion** — accepting a suggestion that is no longer open returns a clear error and records nothing. Test in Task 6.
3. **The engine raises on some bad row** — the standings query returns the last good standings with `stale: true` and the error text, not a 500. Test in Task 5.
4. **A pairing QR code photographed and reused, or used after 10 minutes; a lost tablet** — reused or expired tokens are refused; a revoked device's credential no longer authenticates. Test in Task 8.
5. **A CSV with a few bad rows** (bad date, duplicate bib, unknown category) — the good rows still import and each bad row is reported by its spreadsheet row number. Test in Task 4.

---

## File Structure

```
Gemfile                                         + graphql, bcrypt, csv
config/application.rb                           session + cookies middleware, HubTlsGate, autoload ignores
config/routes.rb                                /session, /graphql, /cable, /devices/pair, /onboarding
config/puma.rb                                  ssl_bind when HUB_TLS=1
config/initializers/filter_parameter_logging.rb + :pin, :credential
bin/hub                                         start the hub with HTTPS
bin/simulate-race                               simulator CLI
lib/hub_tls_gate.rb                             HTTP→HTTPS gate middleware
lib/tasks/access.rake                           access:bootstrap
lib/tasks/hub.rake                              hub:certs, hub:demo, hub:standings
lib/race_simulator.rb, lib/race_simulator/{generator,writer,runner,demo,table}.rb
app/models/clock.rb                             Clock.now_ms
app/models/event_broadcast.rb                   ActionCable "event changed"
app/models/concerns/broadcasts_event_change.rb
app/channels/application_cable/{connection,channel}.rb
packs/access/package.yml
packs/access/app/models/{official,pairing_token,local_ca}.rb
packs/access/app/controllers/concerns/{same_origin,current_official}.rb
packs/access/app/controllers/{sessions,devices,onboarding}_controller.rb
packs/api/package.yml
packs/api/app/controllers/graphql_controller.rb
packs/api/app/channels/event_channel.rb
packs/api/app/graphql/timing_schema.rb
packs/api/app/graphql/authorization.rb
packs/api/app/graphql/suggestion_fix.rb
packs/api/app/graphql/types/*.rb
packs/api/app/graphql/mutations/*.rb
packs/api/app/models/ruling_writer.rb
packs/events/app/models/{rider_registrar,registration_import}.rb
packs/timing/app/models/standings_service.rb
packs/timing/app/models/device.rb               + pair!, authenticate, revoke!
packs/results/lib/results/active_rulings.rb     + cancelled_ids
db/migrate/2026100200000{1,2}_*.rb
test/support/api_helpers.rb
test/... (per task)
docs/hub-runbook.md
```

---

### Task 1: Officials, PIN sessions, same-origin guard

**Files:**
- Create: `db/migrate/20261002000001_create_officials.rb`, `packs/access/package.yml`, `packs/access/app/models/official.rb`, `packs/access/app/controllers/concerns/same_origin.rb`, `packs/access/app/controllers/concerns/current_official.rb`, `packs/access/app/controllers/sessions_controller.rb`, `lib/tasks/access.rake`, `test/support/api_helpers.rb`, `test/models/official_test.rb`, `test/integration/sessions_test.rb`
- Modify: `Gemfile`, `config/application.rb`, `config/routes.rb`, `config/initializers/filter_parameter_logging.rb`, `test/support/build_helpers.rb`, spec §8

**Interfaces:**
- Produces: `Official` (`name`, `role`, `active`, `has_secure_password :pin`, `#at_least?(role)`, `Official::ROLES`), concerns `SameOrigin` and `CurrentOfficial#current_official`, `SessionsController::RATE_LIMIT_STORE`, routes `POST/GET/DELETE /session`. Test helpers `create_official(name:, role:, pin:)`, `sign_in(official, pin)`.

- [ ] **Step 1: Add gems and write failing tests**

```bash
bundle add bcrypt
```

Append inside `module BuildHelpers` in `test/support/build_helpers.rb`:
```ruby
  def create_official(name: "Official #{SecureRandom.hex(3)}", role: "chief", pin: "2468")
    Official.create!(name:, role:, pin:)
  end
```

`test/support/api_helpers.rb`:
```ruby
module ApiHelpers
  JSON_HEADERS = { "CONTENT_TYPE" => "application/json" }.freeze

  def sign_in(official, pin)
    post "/session", params: { name: official.name, pin: }.to_json, headers: JSON_HEADERS
  end

  def gql(query, **variables)
    post "/graphql", params: { query:, variables: }.to_json, headers: JSON_HEADERS
    JSON.parse(response.body)
  end
end

ActiveSupport.on_load(:action_dispatch_integration_test) do
  include ApiHelpers
  setup { SessionsController::RATE_LIMIT_STORE.clear }
end
```

`test/models/official_test.rb`:
```ruby
require "test_helper"

class OfficialTest < ActiveSupport::TestCase
  test "PIN must be 4 to 8 digits and is stored as a digest" do
    official = create_official(pin: "123456")
    refute_equal "123456", official.pin_digest
    assert official.authenticate_pin("123456")
    refute official.authenticate_pin("654321")
    refute Official.new(name: "x", role: "chief", pin: "12").valid?
    refute Official.new(name: "x", role: "chief", pin: "12ab").valid?
  end

  test "roles are ordered timer < chief < admin" do
    chief = create_official(role: "chief")
    assert chief.at_least?("timer")
    assert chief.at_least?("chief")
    refute chief.at_least?("admin")
    refute Official.new(name: "x", role: "boss", pin: "1234").valid?
  end

  test "names are unique" do
    create_official(name: "Pat")
    refute Official.new(name: "Pat", role: "timer", pin: "1234").valid?
  end
end
```

`test/integration/sessions_test.rb`:
```ruby
require "test_helper"

class SessionsTest < ActionDispatch::IntegrationTest
  setup { @official = create_official(name: "Pat", role: "chief", pin: "1357") }

  test "signs in with name and PIN, shows and ends the session" do
    sign_in(@official, "1357")
    assert_response :created
    assert_equal({ "id" => @official.id, "name" => "Pat", "role" => "chief" }, response.parsed_body)
    get "/session"
    assert_response :ok
    delete "/session"
    assert_response :no_content
    get "/session"
    assert_response :unauthorized
  end

  test "wrong PIN and unknown or inactive officials are refused alike" do
    sign_in(@official, "0000")
    assert_response :unauthorized
    assert_equal "Name or PIN is incorrect", response.parsed_body["error"]
    @official.update!(active: false)
    sign_in(@official, "1357")
    assert_response :unauthorized
  end

  # Review Focus 1
  test "sixth attempt in a minute is rate limited even with the right PIN" do
    5.times { sign_in(@official, "0000") }
    sign_in(@official, "1357")
    assert_response :too_many_requests
  end

  test "cross-origin requests are refused" do
    post "/session", params: { name: "Pat", pin: "1357" }.to_json,
                     headers: ApiHelpers::JSON_HEADERS.merge("Origin" => "http://evil.example")
    assert_response :forbidden
  end

  test "origins listed in TIMING_ALLOWED_ORIGINS are accepted" do
    ENV["TIMING_ALLOWED_ORIGINS"] = "http://localhost:5173"
    post "/session", params: { name: "Pat", pin: "1357" }.to_json,
                     headers: ApiHelpers::JSON_HEADERS.merge("Origin" => "http://localhost:5173")
    assert_response :created
  ensure
    ENV.delete("TIMING_ALLOWED_ORIGINS")
  end
end
```

- [ ] **Step 2: Run to verify failure**

Run: `bin/rails test test/models/official_test.rb test/integration/sessions_test.rb`
Expected: errors `uninitialized constant Official` / `SessionsController`.

- [ ] **Step 3: Migration, pack, model**

`db/migrate/20261002000001_create_officials.rb`:
```ruby
class CreateOfficials < ActiveRecord::Migration[8.1]
  def change
    create_table :officials, id: :string do |t|
      t.string :name, null: false
      t.string :role, null: false
      t.string :pin_digest, null: false
      t.boolean :active, null: false, default: true
      t.timestamps
    end
    add_index :officials, :name, unique: true
  end
end
```

`packs/access/package.yml`:
```yaml
enforce_dependencies: true
dependencies:
  - "."
  - packs/events
  - packs/timing
```

`packs/access/app/models/official.rb`:
```ruby
class Official < ApplicationRecord
  ROLES = %w[timer chief admin].freeze

  has_secure_password :pin

  scope :active, -> { where(active: true) }

  validates :name, presence: true, uniqueness: true
  validates :role, inclusion: { in: ROLES }
  validates :pin, format: { with: /\A\d{4,8}\z/, message: "must be 4 to 8 digits" }, allow_nil: true

  def at_least?(role) = ROLES.index(self.role).to_i >= ROLES.index(role.to_s).to_i
end
```

- [ ] **Step 4: Session middleware, concerns, controller, routes**

In `config/application.rb`, after `config.api_only = true` add:
```ruby
    # API-only apps drop cookies and sessions; officials sign in with a session cookie.
    config.session_store :cookie_store, key: "_timing_session", same_site: :strict, httponly: true,
                                        secure: ENV["HUB_TLS"] == "1"
    config.middleware.use ActionDispatch::Cookies
    config.middleware.use config.session_store, config.session_options
```

`packs/access/app/controllers/concerns/same_origin.rb`:
```ruby
# Refuses browser requests from other origins: the session cookie must only act
# for pages the hub itself served.
module SameOrigin
  extend ActiveSupport::Concern

  included { before_action :verify_same_origin }

  private

  def verify_same_origin
    origin = request.headers["Origin"]
    return if origin.blank? || origin == request.base_url || allowed_origins.include?(origin)
    render json: { error: "cross-origin request refused" }, status: :forbidden
  end

  def allowed_origins = ENV.fetch("TIMING_ALLOWED_ORIGINS", "").split(",").map(&:strip)
end
```

`packs/access/app/controllers/concerns/current_official.rb`:
```ruby
module CurrentOfficial
  extend ActiveSupport::Concern

  private

  def current_official
    return @current_official if defined?(@current_official)
    @current_official = Official.active.find_by(id: session[:official_id])
  end
end
```

`packs/access/app/controllers/sessions_controller.rb`:
```ruby
class SessionsController < ApplicationController
  include SameOrigin
  include CurrentOfficial

  RATE_LIMIT_STORE = ActiveSupport::Cache::MemoryStore.new

  rate_limit to: 5, within: 1.minute, only: :create, store: RATE_LIMIT_STORE,
             with: -> { render json: { error: "Too many attempts. Wait a minute and try again." }, status: :too_many_requests }

  def create
    official = Official.active.find_by(name: params[:name].to_s)
    if official&.authenticate_pin(params[:pin].to_s)
      reset_session
      session[:official_id] = official.id
      render json: official_json(official), status: :created
    else
      render json: { error: "Name or PIN is incorrect" }, status: :unauthorized
    end
  end

  def show
    return head(:unauthorized) unless current_official
    render json: official_json(current_official)
  end

  def destroy
    reset_session
    head :no_content
  end

  private

  def official_json(official) = { id: official.id, name: official.name, role: official.role }
end
```

In `config/routes.rb`, above the health check line add:
```ruby
  resource :session, only: %i[create show destroy]
```

In `config/initializers/filter_parameter_logging.rb`, add `:pin, :credential` to the list.

- [ ] **Step 5: Bootstrap task**

`lib/tasks/access.rake`:
```ruby
namespace :access do
  desc "Create the first admin official: NAME=... [PIN=...] (prints a random PIN if none given)"
  task bootstrap: :environment do
    abort "Officials already exist; sign in as an admin to add more." if Official.exists?
    pin = ENV["PIN"].presence || format("%06d", SecureRandom.random_number(1_000_000))
    official = Official.create!(name: ENV.fetch("NAME", "Admin"), role: "admin", pin:)
    puts "Created admin #{official.name} with PIN #{pin}"
  end
end
```

- [ ] **Step 6: Spec note**

In `docs/superpowers/specs/2026-10-01-hub-mvp-design.md` §8, replace the bullet beginning "**Officials**: PIN login at the hub." with:
"**Officials**: sign in at the hub with name + PIN (4–8 digits) via `POST /session` (rate limited to 5 attempts per minute per address); the session cookie is `SameSite=Strict`, `HttpOnly`, and `Secure` over HTTPS, and cross-origin requests are refused. Roles: `timer` (capture only), `chief` (rulings, start control, publishing), `admin` (setup, devices, officials). Every ruling records `official_id`, set by the hub."

- [ ] **Step 7: Run to verify pass on both databases**

```bash
bin/rails db:migrate && bin/rails test
TIMING_DB=postgresql bin/rails db:migrate && TIMING_DB=postgresql bin/rails test
bin/packwerk check
```
Restore the sqlite-generated `db/schema.rb` if the Postgres run rewrote it. Expected: all green, `No offenses detected`.

- [ ] **Step 8: Commit**

```bash
git add -A
git commit -m "feat(access): officials with PIN sessions, roles, rate limit, same-origin guard

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 2: GraphQL foundation — schema, endpoint, read queries

**Files:**
- Create: `packs/api/package.yml`, `packs/api/app/controllers/graphql_controller.rb`, `packs/api/app/graphql/timing_schema.rb`, `packs/api/app/graphql/authorization.rb`, `packs/api/app/graphql/types/{base_object,base_enum,base_input_object,millis,official_type,category_type,race_type,start_group_type,event_type,query_type}.rb`, `test/integration/api/graphql_test.rb`
- Modify: `Gemfile`, `config/routes.rb`

**Interfaces:**
- Consumes: `CurrentOfficial`, `SameOrigin`, `Official#at_least?` (Task 1); AR models.
- Produces: `TimingSchema`; `Authorization#require_official!(role = "timer") -> Official` (raises `GraphQL::ExecutionError` "Sign in required" / "Requires the <role> role"); `Types::Millis`; `Types::BaseObject`, `Types::BaseEnum`, `Types::BaseInputObject`; types `OfficialType`, `CategoryType`, `RaceType`, `StartGroupType`, `EventType`; query fields `me`, `events`, `event(id:)`, `categories`. Context keys: `:current_official`, `:base_url`. Later tasks add fields to `QueryType` and `EventType`, and add `mutation Types::MutationType` to the schema.

- [ ] **Step 1: Add the gem and write failing tests**

```bash
bundle add graphql --version "~> 2.6"
```

`test/integration/api/graphql_test.rb`:
```ruby
require "test_helper"

class GraphqlTest < ActionDispatch::IntegrationTest
  test "queries other than me require sign in" do
    body = gql("{ events { id } }")
    assert_equal "Sign in required", body["errors"].first["message"]
  end

  test "me is null when signed out and the official when signed in" do
    assert_nil gql("{ me { name } }").dig("data", "me")
    official = create_official(name: "Pat", role: "chief", pin: "1357")
    sign_in(official, "1357")
    assert_equal({ "name" => "Pat", "role" => "chief" }, gql("{ me { name role } }").dig("data", "me"))
  end

  test "event query returns setup, with millisecond values as JSON numbers" do
    sign_in(create_official(pin: "2468"), "2468")
    event = create_event
    group = create_start_group(event:, scheduled_at_ms: 1_791_000_000_000)
    create_race(event:, start_group: group, start_offset_ms: 30_000)
    data = gql(<<~GQL, id: event.id).dig("data", "event")
      query($id: ID!) { event(id: $id) { name startGroups { scheduledAtMs finishRule races { name startOffsetMs } } } }
    GQL
    group_data = data["startGroups"].first
    assert_equal 1_791_000_000_000, group_data["scheduledAtMs"]
    assert_equal({ "type" => "fixed_laps", "laps" => 3 }, group_data["finishRule"])
    assert_equal [{ "name" => "Cat 3 Men", "startOffsetMs" => 30_000 }], group_data["races"]
  end

  test "a missing record is a GraphQL error, not a server error" do
    sign_in(create_official(pin: "2468"), "2468")
    body = gql("query($id: ID!) { event(id: $id) { name } }", id: "nope")
    assert_response :ok
    assert_equal "Not found", body["errors"].first["message"]
  end

  test "cross-origin GraphQL requests are refused" do
    post "/graphql", params: { query: "{ me { name } }" }.to_json,
                     headers: ApiHelpers::JSON_HEADERS.merge("Origin" => "http://evil.example")
    assert_response :forbidden
  end
end
```

- [ ] **Step 2: Run to verify failure**

Run: `bin/rails test test/integration/api/graphql_test.rb`
Expected: failures — `/graphql` is not routed (404 / JSON parse errors).

- [ ] **Step 3: Pack, schema, base types, authorization**

`packs/api/package.yml`:
```yaml
enforce_dependencies: true
dependencies:
  - "."
  - packs/events
  - packs/timing
  - packs/access
```

`packs/api/app/graphql/authorization.rb`:
```ruby
module Authorization
  private

  def require_official!(role = "timer")
    official = context[:current_official]
    raise GraphQL::ExecutionError, "Sign in required" unless official
    raise GraphQL::ExecutionError, "Requires the #{role} role" unless official.at_least?(role)
    official
  end
end
```

`packs/api/app/graphql/types/base_object.rb`:
```ruby
module Types
  class BaseObject < GraphQL::Schema::Object
    include Authorization
  end
end
```

`packs/api/app/graphql/types/base_enum.rb`:
```ruby
module Types
  class BaseEnum < GraphQL::Schema::Enum
  end
end
```

`packs/api/app/graphql/types/base_input_object.rb`:
```ruby
module Types
  class BaseInputObject < GraphQL::Schema::InputObject
  end
end
```

`packs/api/app/graphql/types/millis.rb`:
```ruby
module Types
  # Milliseconds (epoch time or a duration). GraphQL Int is 32-bit, too small.
  class Millis < GraphQL::Schema::Scalar
    description "Milliseconds, as a JSON number"

    def self.coerce_input(value, _context)
      return value if value.is_a?(Integer)
      return value.to_i if value.is_a?(Float) && value == value.floor
      raise GraphQL::CoercionError, "#{value.inspect} is not a whole number of milliseconds"
    end

    def self.coerce_result(value, _context) = value&.to_i
  end
end
```

`packs/api/app/graphql/timing_schema.rb`:
```ruby
class TimingSchema < GraphQL::Schema
  query Types::QueryType

  rescue_from(ActiveRecord::RecordNotFound) { raise GraphQL::ExecutionError, "Not found" }
end
```

- [ ] **Step 4: Read types and the query root**

`packs/api/app/graphql/types/official_type.rb`:
```ruby
module Types
  class OfficialType < BaseObject
    field :id, ID, null: false
    field :name, String, null: false
    field :role, String, null: false
  end
end
```

`packs/api/app/graphql/types/category_type.rb`:
```ruby
module Types
  class CategoryType < BaseObject
    field :id, ID, null: false
    field :name, String, null: false
    field :gender, String, null: false
    field :ability_levels, [String], null: false
    field :age_min, Integer
    field :age_max, Integer
  end
end
```

`packs/api/app/graphql/types/race_type.rb`:
```ruby
module Types
  class RaceType < BaseObject
    field :id, ID, null: false
    field :name, String, null: false
    field :start_offset_ms, Millis, null: false
    field :start_group_id, ID, null: false
    field :category, CategoryType, null: false
  end
end
```

`packs/api/app/graphql/types/start_group_type.rb`:
```ruby
module Types
  class StartGroupType < BaseObject
    field :id, ID, null: false
    field :name, String, null: false
    field :scheduled_at_ms, Millis
    field :finish_rule, GraphQL::Types::JSON, null: false
    field :races, [RaceType], null: false

    def races = object.races.includes(:category).order(:start_offset_ms, :id)
  end
end
```

`packs/api/app/graphql/types/event_type.rb`:
```ruby
module Types
  class EventType < BaseObject
    field :id, ID, null: false
    field :name, String, null: false
    field :date, GraphQL::Types::ISO8601Date, null: false
    field :venue, String
    field :timezone, String, null: false
    field :age_rule, String, null: false
    field :start_groups, [StartGroupType], null: false
    field :races, [RaceType], null: false

    def start_groups = object.start_groups.order(:scheduled_at_ms, :name, :id)
    def races = object.races.includes(:category).order(:start_offset_ms, :id)
  end
end
```

`packs/api/app/graphql/types/query_type.rb`:
```ruby
module Types
  class QueryType < BaseObject
    field :me, OfficialType, description: "The signed-in official, or null"
    field :events, [EventType], null: false
    field :event, EventType, null: false do
      argument :id, ID
    end
    field :categories, [CategoryType], null: false

    def me = context[:current_official]

    def events
      require_official!
      Event.order(date: :desc, name: :asc)
    end

    def event(id:)
      require_official!
      Event.find(id)
    end

    def categories
      require_official!
      Category.order(:name)
    end
  end
end
```

- [ ] **Step 5: Controller and route**

`packs/api/app/controllers/graphql_controller.rb`:
```ruby
class GraphqlController < ApplicationController
  include SameOrigin
  include CurrentOfficial

  def execute
    result = TimingSchema.execute(
      params[:query],
      variables: prepare_variables(params[:variables]),
      operation_name: params[:operationName],
      context: { current_official:, base_url: request.base_url }
    )
    render json: result
  rescue JSON::ParserError
    render json: { errors: [{ message: "variables must be a JSON object" }] }, status: :bad_request
  end

  private

  def prepare_variables(variables)
    case variables
    when String then variables.present? ? JSON.parse(variables) : {}
    when ActionController::Parameters then variables.to_unsafe_hash
    when Hash then variables
    when nil then {}
    else raise ArgumentError, "Unexpected variables: #{variables.inspect}"
    end
  end
end
```

In `config/routes.rb` add:
```ruby
  post "graphql", to: "graphql#execute"
```

- [ ] **Step 6: Run to verify pass**

```bash
bin/rails test && TIMING_DB=postgresql bin/rails test && bin/packwerk check && bin/rails zeitwerk:check
```
Expected: all green.

- [ ] **Step 7: Commit**

```bash
git add -A
git commit -m "feat(api): GraphQL endpoint with signed-in read queries and Millis scalar

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 3: Setup mutations and registrations

**Files:**
- Create: `packs/events/app/models/rider_registrar.rb`, `packs/api/app/graphql/types/{mutation_type,rider_type,rider_input,registration_type}.rb`, `packs/api/app/graphql/mutations/{base_mutation,create_event,create_category,create_start_group,update_start_group,create_race,register_rider,create_official}.rb`, `test/models/rider_registrar_test.rb`, `test/integration/api/setup_mutations_test.rb`
- Modify: `packs/api/app/graphql/timing_schema.rb`, `packs/api/app/graphql/types/event_type.rb`, `packs/api/app/graphql/types/query_type.rb`

**Interfaces:**
- Consumes: `Authorization`, base types (Task 2).
- Produces: `RiderRegistrar.register(race:, bib:, rider_attrs:) -> Registration` (persisted, or unsaved with merged rider + registration errors; reuses an existing rider with the same `license_number`); `Mutations::BaseMutation` (includes `Authorization`, `field :errors, [String], null: false`, helper `persist(record, key)`); `Types::MutationType`; `RegistrationType`, `RiderType`, `RiderInput`; `EventType#registrations`; query `officials` (admin).

- [ ] **Step 1: Write failing tests**

`test/models/rider_registrar_test.rb`:
```ruby
require "test_helper"

class RiderRegistrarTest < ActiveSupport::TestCase
  setup do
    @event = create_event
    @race = create_race(event: @event)
  end

  def attrs(**over) = { first_name: "Ann", last_name: "Lee", gender: "M", ability_level: "Cat 3", license_number: "L1" }.merge(over)

  test "creates rider and registration together" do
    reg = RiderRegistrar.register(race: @race, bib: "101", rider_attrs: attrs)
    assert reg.persisted?
    assert_equal "Ann Lee", reg.rider.full_name
  end

  test "reuses a rider with the same license number" do
    first = RiderRegistrar.register(race: @race, bib: "101", rider_attrs: attrs)
    other_event = create_event(name: "Week 2")
    second = RiderRegistrar.register(race: create_race(event: other_event), bib: "5", rider_attrs: attrs)
    assert_equal first.rider_id, second.rider_id
  end

  test "an invalid registration leaves no orphan rider" do
    RiderRegistrar.register(race: @race, bib: "101", rider_attrs: attrs)
    assert_no_difference("Rider.count") do
      reg = RiderRegistrar.register(race: @race, bib: "101", rider_attrs: attrs(license_number: "L2"))
      refute reg.persisted?
      assert_includes reg.errors.full_messages, "Bib has already been taken"
    end
  end

  test "rider validation errors are reported on the registration" do
    reg = RiderRegistrar.register(race: @race, bib: "102", rider_attrs: attrs(first_name: "", license_number: nil))
    refute reg.persisted?
    assert_includes reg.errors.full_messages, "First name can't be blank"
  end
end
```

`test/integration/api/setup_mutations_test.rb`:
```ruby
require "test_helper"

class SetupMutationsTest < ActionDispatch::IntegrationTest
  setup do
    admin = create_official(role: "admin", pin: "1111")
    sign_in(admin, "1111")
  end

  test "admin builds an event, start group, race, and registers a rider with warnings" do
    event_id = gql(<<~GQL).dig("data", "createEvent", "event", "id")
      mutation { createEvent(name: "Sunday CX", date: "2026-10-18", venue: "Park") { event { id } errors } }
    GQL
    category_id = gql(<<~GQL).dig("data", "createCategory", "category", "id")
      mutation { createCategory(name: "Masters 50+ Men", gender: "M", abilityLevels: [], ageMin: 50) { category { id } errors } }
    GQL
    group_id = gql(<<~GQL, eventId: event_id).dig("data", "createStartGroup", "startGroup", "id")
      mutation($eventId: ID!) {
        createStartGroup(eventId: $eventId, name: "10:00", finishRule: {type: "timed", target_duration_ms: 2700000}) { startGroup { id } errors }
      }
    GQL
    race_id = gql(<<~GQL, eventId: event_id, categoryId: category_id, groupId: group_id).dig("data", "createRace", "race", "id")
      mutation($eventId: ID!, $categoryId: ID!, $groupId: ID!) {
        createRace(eventId: $eventId, categoryId: $categoryId, startGroupId: $groupId, startOffsetMs: 30000) { race { id name } errors }
      }
    GQL
    result = gql(<<~GQL, raceId: race_id).dig("data", "registerRider")
      mutation($raceId: ID!) {
        registerRider(raceId: $raceId, bib: "201", rider: {firstName: "Bo", lastName: "Yu", gender: "M", birthDate: "1990-01-01"}) {
          registration { bib rider { firstName } } warnings errors
        }
      }
    GQL
    assert_equal({ "bib" => "201", "rider" => { "firstName" => "Bo" } }, result["registration"])
    assert_equal ["age 36 is below minimum 50"], result["warnings"]
    assert_empty result["errors"]

    regs = gql("query($id: ID!) { event(id: $id) { registrations { bib raceId eligibilityWarnings } } }", id: event_id)
    assert_equal [{ "bib" => "201", "raceId" => race_id, "eligibilityWarnings" => ["age 36 is below minimum 50"] }],
                 regs.dig("data", "event", "registrations")
  end

  test "validation problems come back as errors data" do
    event = create_event
    body = gql(<<~GQL, eventId: event.id)
      mutation($eventId: ID!) { createStartGroup(eventId: $eventId, name: "x", finishRule: {type: "sprint"}) { startGroup { id } errors } }
    GQL
    assert_nil body.dig("data", "createStartGroup", "startGroup")
    assert_equal ["Finish rule type must be fixed_laps or timed"], body.dig("data", "createStartGroup", "errors")
  end

  test "update start group changes the finish rule" do
    group = create_start_group(event: create_event)
    body = gql(<<~GQL, id: group.id)
      mutation($id: ID!) { updateStartGroup(id: $id, finishRule: {type: "fixed_laps", laps: 8}) { startGroup { finishRule } errors } }
    GQL
    assert_equal({ "type" => "fixed_laps", "laps" => 8 }, body.dig("data", "updateStartGroup", "startGroup", "finishRule"))
  end

  test "admin creates officials and lists them" do
    body = gql('mutation { createOfficial(name: "Timer Tom", role: "timer", pin: "4321") { official { name role } errors } }')
    assert_equal({ "name" => "Timer Tom", "role" => "timer" }, body.dig("data", "createOfficial", "official"))
    assert_includes gql("{ officials { name } }").dig("data", "officials").map { it["name"] }, "Timer Tom"
  end

  test "setup requires the admin role" do
    delete "/session"
    chief = create_official(role: "chief", pin: "2222")
    sign_in(chief, "2222")
    body = gql('mutation { createEvent(name: "x", date: "2026-10-18") { event { id } errors } }')
    assert_equal "Requires the admin role", body["errors"].first["message"]
  end
end
```

- [ ] **Step 2: Run to verify failure**

Run: `bin/rails test test/models/rider_registrar_test.rb test/integration/api/setup_mutations_test.rb`
Expected: errors `uninitialized constant RiderRegistrar`; GraphQL errors about missing mutation type.

- [ ] **Step 3: RiderRegistrar**

`packs/events/app/models/rider_registrar.rb`:
```ruby
# Registers a rider for a race, creating the rider unless one with the same
# license number exists. Rider and registration succeed or fail together.
class RiderRegistrar
  def self.register(race:, bib:, rider_attrs:)
    attrs = rider_attrs.to_h.transform_keys(&:to_sym)
    registration = nil
    Registration.transaction do
      license = attrs[:license_number].presence
      rider = (license && Rider.find_by(license_number: license)) || Rider.new(attrs)
      registration = Registration.new(race:, rider:, bib:)
      rider_ok = rider.persisted? || rider.save
      registration.errors.merge!(rider.errors) unless rider_ok
      raise ActiveRecord::Rollback unless rider_ok && registration.save
    end
    registration
  end
end
```

- [ ] **Step 4: Mutation base, types, mutations**

`packs/api/app/graphql/mutations/base_mutation.rb`:
```ruby
module Mutations
  class BaseMutation < GraphQL::Schema::Mutation
    include Authorization

    field :errors, [String], null: false

    private

    def persist(record, key)
      record.save ? { key => record, errors: [] } : { key => nil, errors: record.errors.full_messages }
    end
  end
end
```

`packs/api/app/graphql/types/rider_type.rb`:
```ruby
module Types
  class RiderType < BaseObject
    field :id, ID, null: false
    field :first_name, String, null: false
    field :last_name, String, null: false
    field :gender, String, null: false
    field :birth_date, GraphQL::Types::ISO8601Date
    field :ability_level, String
    field :license_number, String
    field :team, String
  end
end
```

`packs/api/app/graphql/types/rider_input.rb`:
```ruby
module Types
  class RiderInput < BaseInputObject
    argument :first_name, String
    argument :last_name, String
    argument :gender, String
    argument :birth_date, GraphQL::Types::ISO8601Date, required: false
    argument :ability_level, String, required: false
    argument :license_number, String, required: false
    argument :team, String, required: false
  end
end
```

`packs/api/app/graphql/types/registration_type.rb`:
```ruby
module Types
  class RegistrationType < BaseObject
    field :id, ID, null: false
    field :bib, String, null: false
    field :race_id, ID, null: false
    field :rider, RiderType, null: false
    field :eligibility_warnings, [String], null: false
  end
end
```

Add to `packs/api/app/graphql/types/event_type.rb` (field + method):
```ruby
    field :registrations, [RegistrationType], null: false

    def registrations = object.registrations.includes(:rider, race: :category).order(:bib)
```

Add to `packs/api/app/graphql/types/query_type.rb`:
```ruby
    field :officials, [OfficialType], null: false

    def officials
      require_official!("admin")
      Official.order(:name)
    end
```

`packs/api/app/graphql/mutations/create_event.rb`:
```ruby
module Mutations
  class CreateEvent < BaseMutation
    argument :name, String
    argument :date, GraphQL::Types::ISO8601Date
    argument :venue, String, required: false
    argument :timezone, String, required: false
    argument :age_rule, String, required: false

    field :event, Types::EventType

    def resolve(**attrs)
      require_official!("admin")
      persist(Event.new(attrs.compact), :event)
    end
  end
end
```

`packs/api/app/graphql/mutations/create_category.rb`:
```ruby
module Mutations
  class CreateCategory < BaseMutation
    argument :name, String
    argument :gender, String
    argument :ability_levels, [String], required: false
    argument :age_min, Integer, required: false
    argument :age_max, Integer, required: false

    field :category, Types::CategoryType

    def resolve(**attrs)
      require_official!("admin")
      persist(Category.new({ ability_levels: [] }.merge(attrs.compact)), :category)
    end
  end
end
```

`packs/api/app/graphql/mutations/create_start_group.rb`:
```ruby
module Mutations
  class CreateStartGroup < BaseMutation
    argument :event_id, ID
    argument :name, String
    argument :finish_rule, GraphQL::Types::JSON
    argument :scheduled_at_ms, Types::Millis, required: false

    field :start_group, Types::StartGroupType

    def resolve(event_id:, **attrs)
      require_official!("admin")
      persist(Event.find(event_id).start_groups.new(attrs), :start_group)
    end
  end
end
```

`packs/api/app/graphql/mutations/update_start_group.rb`:
```ruby
module Mutations
  class UpdateStartGroup < BaseMutation
    argument :id, ID
    argument :name, String, required: false
    argument :finish_rule, GraphQL::Types::JSON, required: false
    argument :scheduled_at_ms, Types::Millis, required: false

    field :start_group, Types::StartGroupType

    def resolve(id:, **attrs)
      require_official!("admin")
      group = StartGroup.find(id)
      group.assign_attributes(attrs)
      persist(group, :start_group)
    end
  end
end
```

`packs/api/app/graphql/mutations/create_race.rb`:
```ruby
module Mutations
  class CreateRace < BaseMutation
    argument :event_id, ID
    argument :category_id, ID
    argument :start_group_id, ID
    argument :start_offset_ms, Types::Millis, required: false

    field :race, Types::RaceType

    def resolve(event_id:, category_id:, start_group_id:, start_offset_ms: 0)
      require_official!("admin")
      persist(Race.new(event: Event.find(event_id), category: Category.find(category_id),
                       start_group: StartGroup.find(start_group_id), start_offset_ms:), :race)
    end
  end
end
```

`packs/api/app/graphql/mutations/register_rider.rb`:
```ruby
module Mutations
  class RegisterRider < BaseMutation
    argument :race_id, ID
    argument :bib, String
    argument :rider, Types::RiderInput

    field :registration, Types::RegistrationType
    field :warnings, [String], null: false

    def resolve(race_id:, bib:, rider:)
      require_official!("admin")
      registration = RiderRegistrar.register(race: Race.find(race_id), bib:, rider_attrs: rider.to_h)
      return { registration: nil, warnings: [], errors: registration.errors.full_messages } unless registration.persisted?
      { registration:, warnings: registration.eligibility_warnings, errors: [] }
    end
  end
end
```

`packs/api/app/graphql/mutations/create_official.rb`:
```ruby
module Mutations
  class CreateOfficial < BaseMutation
    argument :name, String
    argument :role, String
    argument :pin, String

    field :official, Types::OfficialType

    def resolve(name:, role:, pin:)
      require_official!("admin")
      persist(Official.new(name:, role:, pin:), :official)
    end
  end
end
```

`packs/api/app/graphql/types/mutation_type.rb`:
```ruby
module Types
  class MutationType < BaseObject
    field :create_event, mutation: Mutations::CreateEvent
    field :create_category, mutation: Mutations::CreateCategory
    field :create_start_group, mutation: Mutations::CreateStartGroup
    field :update_start_group, mutation: Mutations::UpdateStartGroup
    field :create_race, mutation: Mutations::CreateRace
    field :register_rider, mutation: Mutations::RegisterRider
    field :create_official, mutation: Mutations::CreateOfficial
  end
end
```

In `packs/api/app/graphql/timing_schema.rb`, after `query Types::QueryType` add:
```ruby
  mutation Types::MutationType
```

- [ ] **Step 5: Run to verify pass**

```bash
bin/rails test && TIMING_DB=postgresql bin/rails test && bin/packwerk check
```
Expected: all green.

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "feat(api): setup mutations, rider registration with eligibility warnings, officials

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 4: CSV registration import

**Files:**
- Create: `packs/events/app/models/registration_import.rb`, `packs/api/app/graphql/types/row_message_type.rb`, `packs/api/app/graphql/mutations/import_registrations.rb`, `test/models/registration_import_test.rb`, `test/integration/api/import_registrations_test.rb`
- Modify: `Gemfile`, `packs/api/app/graphql/types/mutation_type.rb`

**Interfaces:**
- Consumes: `RiderRegistrar` (Task 3).
- Produces: `RegistrationImport.call(event:, csv:, mapping: {}) -> RegistrationImport::Result(created:, errors:, warnings:)` where errors/warnings are `[RegistrationImport::RowMessage(row:, message:)]`, row = spreadsheet row number (header is row 1). `RegistrationImport::FIELDS`. Mutation `importRegistrations(eventId, csv, mapping)` (admin).

- [ ] **Step 1: Add gem and write failing tests**

```bash
bundle add csv
```

`test/models/registration_import_test.rb`:
```ruby
require "test_helper"

class RegistrationImportTest < ActiveSupport::TestCase
  CSV_TEXT = <<~CSV
    first_name,last_name,gender,birth_date,ability_level,team,license_number,bib,category
    Ann,Lee,F,1980-04-02,Cat 3,Velo,L1,301,Women Open
    Bob,Ray,M,1990-01-01,Cat 3,,,101,Cat 3 Men
    Cy,Dee,M,not-a-date,Cat 3,,,102,Cat 3 Men
    Di,Eve,M,1985-05-05,Cat 3,,,101,Cat 3 Men
    Ed,Fox,M,1985-05-05,Cat 3,,,103,Juniors
    Flo,Gee,M,2010-05-05,Cat 4,,,104,cat 3 men
  CSV

  setup do
    @event = create_event
    group = create_start_group(event: @event)
    create_race(event: @event, start_group: group, category: create_category(name: "Women Open", gender: "F", ability_levels: []))
    create_race(event: @event, start_group: group, category: create_category(name: "Cat 3 Men"))
  end

  # Review Focus 5
  test "good rows import; bad rows are reported by spreadsheet row number" do
    result = RegistrationImport.call(event: @event, csv: CSV_TEXT)
    assert_equal 3, result.created
    assert_equal [[4, "birth_date must be YYYY-MM-DD"], [5, "Bib has already been taken"], [6, "unknown category Juniors"]],
                 result.errors.map { [it.row, it.message] }
    assert_equal [[7, "ability level Cat 4 is not one of Cat 3"]], result.warnings.map { [it.row, it.message] }
    assert_equal %w[101 104 301], @event.registrations.order(:bib).pluck(:bib)
  end

  test "column mapping lets headers differ" do
    csv = "First,Last,Sex,Number,Race\nAnn,Lee,F,301,Women Open\n"
    mapping = { "first_name" => "First", "last_name" => "Last", "gender" => "Sex", "bib" => "Number", "category" => "Race" }
    result = RegistrationImport.call(event: @event, csv:, mapping:)
    assert_equal 1, result.created
    assert_empty result.errors
  end

  test "a missing required column stops the import" do
    result = RegistrationImport.call(event: @event, csv: "first_name,last_name,gender,category\nAnn,Lee,F,Women Open\n")
    assert_equal 0, result.created
    assert_equal [[1, "missing column bib"]], result.errors.map { [it.row, it.message] }
  end
end
```

`test/integration/api/import_registrations_test.rb`:
```ruby
require "test_helper"

class ImportRegistrationsTest < ActionDispatch::IntegrationTest
  test "admin imports registrations over GraphQL" do
    sign_in(create_official(role: "admin", pin: "1111"), "1111")
    event = create_event
    create_race(event:, category: create_category(name: "Women Open", gender: "F", ability_levels: []))
    csv = "first_name,last_name,gender,bib,category\nAnn,Lee,F,301,Women Open\nBea,Kim,F,301,Women Open\n"
    body = gql(<<~GQL, eventId: event.id, csv:)
      mutation($eventId: ID!, $csv: String!) {
        importRegistrations(eventId: $eventId, csv: $csv) { created rowErrors { row message } warnings { row message } errors }
      }
    GQL
    data = body.dig("data", "importRegistrations")
    assert_equal 1, data["created"]
    assert_equal [{ "row" => 3, "message" => "Bib has already been taken" }], data["rowErrors"]
  end
end
```

- [ ] **Step 2: Run to verify failure**

Run: `bin/rails test test/models/registration_import_test.rb test/integration/api/import_registrations_test.rb`
Expected: `uninitialized constant RegistrationImport`.

- [ ] **Step 3: Implement the import**

`packs/events/app/models/registration_import.rb`:
```ruby
require "csv"

# Imports registrations from a CSV export. Rows are independent: a bad row is
# reported and skipped, the rest still import.
class RegistrationImport
  FIELDS = %w[first_name last_name gender birth_date ability_level team license_number bib category].freeze
  REQUIRED = %w[first_name last_name gender bib category].freeze
  RIDER_FIELDS = %w[first_name last_name gender ability_level team license_number].freeze

  RowMessage = Data.define(:row, :message)
  Result = Data.define(:created, :errors, :warnings)

  def self.call(event:, csv:, mapping: {}) = new(event, csv, mapping).call

  def initialize(event, csv, mapping)
    @event = event
    @csv = csv
    @mapping = FIELDS.to_h { [it, it] }.merge(mapping.to_h.transform_keys(&:to_s))
  end

  def call
    table = CSV.parse(@csv, headers: true)
    missing = REQUIRED.reject { table.headers.include?(@mapping[it]) }
    return Result.new(created: 0, errors: missing.map { RowMessage.new(row: 1, message: "missing column #{it}") }, warnings: []) if missing.any?

    races = @event.races.includes(:category).index_by { it.category.name.downcase }
    created = 0
    errors = []
    warnings = []
    table.each.with_index(2) do |row, number|
      value = ->(field) { row[@mapping[field]]&.strip.presence }
      race = races[value.("category").to_s.downcase]
      next errors << RowMessage.new(row: number, message: "unknown category #{value.('category')}") unless race

      attrs = RIDER_FIELDS.to_h { [it, value.(it)] }
      if (raw_date = value.("birth_date"))
        attrs["birth_date"] = Date.iso8601(raw_date)
      end
      registration = RiderRegistrar.register(race:, bib: value.("bib"), rider_attrs: attrs)
      if registration.persisted?
        created += 1
        registration.eligibility_warnings.each { warnings << RowMessage.new(row: number, message: it) }
      else
        registration.errors.full_messages.each { errors << RowMessage.new(row: number, message: it) }
      end
    rescue Date::Error
      errors << RowMessage.new(row: number, message: "birth_date must be YYYY-MM-DD")
    end
    Result.new(created:, errors:, warnings:)
  end
end
```

- [ ] **Step 4: GraphQL mutation**

`packs/api/app/graphql/types/row_message_type.rb`:
```ruby
module Types
  class RowMessageType < BaseObject
    field :row, Integer, null: false
    field :message, String, null: false
  end
end
```

`packs/api/app/graphql/mutations/import_registrations.rb`:
```ruby
module Mutations
  class ImportRegistrations < BaseMutation
    argument :event_id, ID
    argument :csv, String
    argument :mapping, GraphQL::Types::JSON, required: false, description: "field name => CSV header"

    field :created, Integer, null: false
    field :row_errors, [Types::RowMessageType], null: false
    field :warnings, [Types::RowMessageType], null: false

    def resolve(event_id:, csv:, mapping: {})
      require_official!("admin")
      result = RegistrationImport.call(event: Event.find(event_id), csv:, mapping:)
      { created: result.created, row_errors: result.errors, warnings: result.warnings, errors: [] }
    rescue CSV::MalformedCSVError => e
      { created: 0, row_errors: [], warnings: [], errors: ["CSV could not be read: #{e.message}"] }
    end
  end
end
```

Add to `Types::MutationType`:
```ruby
    field :import_registrations, mutation: Mutations::ImportRegistrations
```

- [ ] **Step 5: Run to verify pass**

```bash
bin/rails test && TIMING_DB=postgresql bin/rails test && bin/packwerk check
```
Expected: all green.

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "feat(events,api): CSV registration import with per-row errors and warnings

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 5: Standings service and standings / review-queue query

**Files:**
- Create: `app/models/clock.rb`, `packs/timing/app/models/standings_service.rb`, `packs/api/app/graphql/suggestion_fix.rb`, `packs/api/app/graphql/types/{race_state_enum,publication_enum,rider_status_enum,suggestion_kind_enum,standing_row_type,race_standings_type,suggestion_type,unassigned_capture_type,standings_report_type}.rb`, `test/models/standings_service_test.rb`, `test/integration/api/standings_query_test.rb`
- Modify: `packs/api/app/graphql/types/query_type.rb`

**Interfaces:**
- Consumes: `ResultsSnapshot.compute(event, now_ms:)`, `Results::Output/RaceResult/RiderResult/Suggestion/UnassignedCrossing`.
- Produces: `Clock.now_ms -> Integer`. `StandingsService.report(event, now_ms: Clock.now_ms, compute: ResultsSnapshot.method(:compute)) -> StandingsService::Report(event:, output:, computed_at_ms:, stale:, error:)`. `SuggestionFix.missing(fix) -> [String]`, `SuggestionFix.complete(fix, capture_id:, bib:) -> Hash` (fix with blanks filled). Query `standings(eventId:) -> StandingsReport { races { race { … } state lapCount publication digest rows { … } } suggestions { key kind bib raceId message fix needs } unassigned { captureId atMs bib } computedAtMs stale error }`.

- [ ] **Step 1: Write failing tests**

`test/models/standings_service_test.rb`:
```ruby
require "test_helper"

class StandingsServiceTest < ActiveSupport::TestCase
  setup do
    @event = create_event
    race = create_race(event: @event)
    register(race:, bib: "1")
    rule(event: @event, kind: "set_group_start", start_group_id: race.start_group_id, at_ms: 0)
    record_capture(device: create_device(event: @event), seq: 1, at_ms: 100_000, bib: "1")
  end

  test "reports fresh standings" do
    report = StandingsService.report(@event, now_ms: 500_000)
    refute report.stale
    assert_nil report.error
    assert_equal 500_000, report.computed_at_ms
    assert_equal ["1"], report.output.races.first.rows.map(&:bib)
  end

  # Review Focus 3
  test "falls back to the last good standings when computing fails" do
    StandingsService.report(@event, now_ms: 500_000)
    broken = ->(*, **) { raise ArgumentError, "comparison of Integer with nil failed" }
    report = StandingsService.report(@event, now_ms: 600_000, compute: broken)
    assert report.stale
    assert_equal "ArgumentError: comparison of Integer with nil failed", report.error
    assert_equal 500_000, report.computed_at_ms
    assert_equal ["1"], report.output.races.first.rows.map(&:bib)
  end

  test "with no previous result the fallback is empty" do
    other = create_event(name: "Other")
    report = StandingsService.report(other, compute: ->(*, **) { raise "boom" })
    assert report.stale
    assert_empty report.output.races
  end
end
```

`test/integration/api/standings_query_test.rb`:
```ruby
require "test_helper"

class StandingsQueryTest < ActionDispatch::IntegrationTest
  QUERY = <<~GQL
    query($id: ID!) {
      standings(eventId: $id) {
        stale error
        races { race { name } state lapCount publication digest
                rows { place bib name status laps elapsedMs gapLapsDown gapMs lapTimesMs } }
        suggestions { key kind bib message fix needs }
        unassigned { captureId atMs bib }
      }
    }
  GQL

  setup do
    sign_in(create_official(role: "timer", pin: "1111"), "1111")
    @event = create_event
    group = create_start_group(event: @event, finish_rule: { "type" => "fixed_laps", "laps" => 2 })
    race = create_race(event: @event, start_group: group)
    register(race:, bib: "1", rider: create_rider(first_name: "Ann", last_name: "Lee"))
    register(race:, bib: "2", rider: create_rider(first_name: "Bo", last_name: "Yu"))
    rule(event: @event, kind: "set_group_start", start_group_id: group.id, at_ms: 0)
    device = create_device(event: @event)
    [[1, "1", 300_000], [2, "2", 320_000], [3, "1", 600_000], [4, "2", 640_000], [5, nil, 700_000]].each do |seq, bib, at|
      record_capture(device:, seq:, at_ms: at, bib:, id: "cap-#{seq}")
    end
  end

  test "returns standings rows, the review queue, and unassigned captures" do
    data = gql(QUERY, id: @event.id).dig("data", "standings")
    refute data["stale"]
    race = data["races"].first
    assert_equal "FINISH_OPEN", race["state"]
    assert_equal "PROVISIONAL", race["publication"]
    assert_equal 2, race["lapCount"]
    assert_equal 64, race["digest"].length
    assert_equal({ "place" => 1, "bib" => "1", "name" => "Ann Lee", "status" => "FINISHED", "laps" => 2, "elapsedMs" => 600_000,
                   "gapLapsDown" => nil, "gapMs" => nil, "lapTimesMs" => [300_000, 300_000] }, race["rows"][0])
    assert_equal 40_000, race["rows"][1]["gapMs"]
    assert_equal [{ "captureId" => "cap-5", "atMs" => 700_000, "bib" => nil }], data["unassigned"]
    unassigned = data["suggestions"].find { it["kind"] == "UNASSIGNED_CAPTURE" }
    assert_equal "unassigned:cap-5", unassigned["key"]
    assert_equal ["bib"], unassigned["needs"]
  end
end
```

- [ ] **Step 2: Run to verify failure**

Run: `bin/rails test test/models/standings_service_test.rb test/integration/api/standings_query_test.rb`
Expected: `uninitialized constant StandingsService`; GraphQL error "Field 'standings' doesn't exist".

- [ ] **Step 3: Clock and StandingsService**

`app/models/clock.rb`:
```ruby
module Clock
  def self.now_ms = (Time.now.to_r * 1000).to_i
end
```

`packs/timing/app/models/standings_service.rb`:
```ruby
# Computes an event's standings for the API. If the engine raises, officials keep
# seeing the last good standings, marked stale, instead of an error page (spec §9).
class StandingsService
  Report = Data.define(:event, :output, :computed_at_ms, :stale, :error)
  EMPTY = Results::Output.new(races: [], suggestions: [], unassigned: [])
  LAST_GOOD = Concurrent::Map.new

  def self.report(event, now_ms: Clock.now_ms, compute: ResultsSnapshot.method(:compute))
    output = compute.call(event, now_ms:)
    LAST_GOOD[event.id] = [output, now_ms]
    Report.new(event:, output:, computed_at_ms: now_ms, stale: false, error: nil)
  rescue StandardError => e
    Rails.logger.error("[standings] event #{event.id}: #{e.class}: #{e.message}")
    output, at = LAST_GOOD[event.id]
    Report.new(event:, output: output || EMPTY, computed_at_ms: at, stale: true, error: "#{e.class}: #{e.message}")
  end
end
```

- [ ] **Step 4: SuggestionFix, enums, types, query field**

`packs/api/app/graphql/suggestion_fix.rb`:
```ruby
# Suggestion fixes are ruling templates; some need an official to fill a blank
# (the bib for an unassigned capture, the crossing for an early flag).
module SuggestionFix
  module_function

  def missing(fix)
    return [] unless fix
    blanks = fix.select { |_key, value| value.nil? }.keys
    blanks << "capture_id" if fix["kind"] == "flag_finish" && !fix.key?("capture_id")
    blanks
  end

  def complete(fix, capture_id: nil, bib: nil)
    filled = fix.dup
    filled["capture_id"] = capture_id if capture_id && (filled["capture_id"].nil? || !filled.key?("capture_id"))
    filled["bib"] = bib if bib && filled.key?("bib") && filled["bib"].nil?
    filled
  end
end
```

`packs/api/app/graphql/types/race_state_enum.rb`:
```ruby
module Types
  class RaceStateEnum < BaseEnum
    value "NOT_STARTED", value: :not_started
    value "IN_PROGRESS", value: :in_progress
    value "FINISH_OPEN", value: :finish_open
  end
end
```

`packs/api/app/graphql/types/publication_enum.rb`:
```ruby
module Types
  class PublicationEnum < BaseEnum
    value "PROVISIONAL", value: :provisional
    value "PUBLISHED", value: :published
    value "CHANGED_SINCE_PUBLISHED", value: :changed_since_published
  end
end
```

`packs/api/app/graphql/types/rider_status_enum.rb`:
```ruby
module Types
  class RiderStatusEnum < BaseEnum
    value "FINISHED", value: :finished
    value "RACING", value: :racing
    value "PULLED", value: :pulled
    value "DNF", value: :dnf
    value "DNS", value: :dns
    value "DSQ", value: :dsq
  end
end
```

`packs/api/app/graphql/types/suggestion_kind_enum.rb`:
```ruby
module Types
  class SuggestionKindEnum < BaseEnum
    value "SUSPECTED_MISSED_CROSSING", value: :suspected_missed_crossing
    value "SUSPECTED_DUPLICATE", value: :suspected_duplicate
    value "ABOUT_TO_BE_LAPPED", value: :about_to_be_lapped
    value "UNSYNCED_CLOCK", value: :unsynced_clock
    value "UNASSIGNED_CAPTURE", value: :unassigned_capture
  end
end
```

`packs/api/app/graphql/types/standing_row_type.rb`:
```ruby
module Types
  class StandingRowType < BaseObject
    field :place, Integer
    field :bib, String, null: false
    field :name, String, null: false
    field :status, RiderStatusEnum, null: false
    field :laps, Integer, null: false
    field :elapsed_ms, Millis
    field :gap_laps_down, Integer
    field :gap_ms, Millis
    field :lap_times_ms, [Millis], null: false

    def gap_laps_down = object.gap&.laps_down
    def gap_ms = object.gap&.ms
  end
end
```

`packs/api/app/graphql/types/race_standings_type.rb`:
```ruby
module Types
  # object: { result: Results::RaceResult, race: Race }
  class RaceStandingsType < BaseObject
    field :race, RaceType, null: false
    field :state, RaceStateEnum, null: false
    field :lap_count, Integer
    field :publication, PublicationEnum, null: false
    field :digest, String, null: false
    field :rows, [StandingRowType], null: false

    def race = object[:race]
    def state = object[:result].state
    def lap_count = object[:result].lap_count
    def publication = object[:result].publication
    def digest = object[:result].digest
    def rows = object[:result].rows
  end
end
```

`packs/api/app/graphql/types/suggestion_type.rb`:
```ruby
module Types
  class SuggestionType < BaseObject
    field :key, String, null: false
    field :kind, SuggestionKindEnum, null: false
    field :bib, String
    field :race_id, ID
    field :message, String, null: false
    field :fix, GraphQL::Types::JSON, description: "Ruling template; see needs"
    field :needs, [String], null: false, description: "Payload fields an official must supply before accepting"

    def needs = SuggestionFix.missing(object.fix)
  end
end
```

`packs/api/app/graphql/types/unassigned_capture_type.rb`:
```ruby
module Types
  class UnassignedCaptureType < BaseObject
    field :capture_id, ID, null: false
    field :at_ms, Millis, null: false
    field :bib, String
  end
end
```

`packs/api/app/graphql/types/standings_report_type.rb`:
```ruby
module Types
  class StandingsReportType < BaseObject
    field :races, [RaceStandingsType], null: false
    field :suggestions, [SuggestionType], null: false
    field :unassigned, [UnassignedCaptureType], null: false
    field :computed_at_ms, Millis
    field :stale, Boolean, null: false
    field :error, String

    def races
      by_id = object.event.races.includes(:category).index_by(&:id)
      object.output.races.filter_map { |result| (race = by_id[result.race_id]) && { result:, race: } }
    end

    def suggestions = object.output.suggestions
    def unassigned = object.output.unassigned
  end
end
```

Add to `Types::QueryType`:
```ruby
    field :standings, StandingsReportType, null: false do
      argument :event_id, ID
    end

    def standings(event_id:)
      require_official!
      StandingsService.report(Event.find(event_id))
    end
```

- [ ] **Step 5: Run to verify pass**

```bash
bin/rails test && TIMING_DB=postgresql bin/rails test && bin/packwerk check
```
Expected: all green.

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "feat(api): standings and review queue query with last-good fallback

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 6: Ruling mutations, start control, publishing, ruling history

**Files:**
- Create: `packs/api/app/models/ruling_writer.rb`, `packs/api/app/graphql/types/{ruling_type,ruling_kind_enum}.rb`, `packs/api/app/graphql/mutations/{ruling_mutation,fire_start,set_race_start,set_lap_count,record_ruling,revert_ruling,accept_suggestion,dismiss_suggestion,publish_results}.rb`, `test/integration/api/ruling_mutations_test.rb`
- Modify: `packs/results/lib/results/active_rulings.rb`, `packs/results/test/resolver_test.rb`, `packs/api/app/graphql/types/{mutation_type,query_type}.rb`, spec §7

**Interfaces:**
- Consumes: `StandingsService.report`, `SuggestionFix` (Task 5); `Ruling` validations.
- Produces: `RulingWriter.write(event:, official:, kind:, payload:, reason: nil) -> Ruling` (persisted or with errors; sets `official_id`, never `created_at_ms`); `Results::ActiveRulings#cancelled_ids -> Set`; mutations `fireStart(startGroupId)`, `setRaceStart(raceId, atMs?)`, `setLapCount(startGroupId, laps)`, `recordRuling(eventId, kind, payload, reason?)`, `revertRuling(rulingId, reason?)`, `acceptSuggestion(eventId, key, captureId?, bib?)`, `dismissSuggestion(eventId, key)`, `publishResults(raceId)` — each returns `{ ruling, errors }`; query `rulings(eventId) -> [Ruling { id kind payload reason createdAtMs officialName reverted }]` newest first. `RulingKindEnum` (generic kinds only): ASSIGN_BIB, VOID_CAPTURE, INSERT_CAPTURE, FLAG_FINISH, PULL, DNF, DNS, DSQ.

- [ ] **Step 1: Write failing tests**

Add to `packs/results/test/resolver_test.rb`:
```ruby
  def test_cancelled_ids_lists_reverted_rulings_including_reverted_reverts
    rulings = Results::ActiveRulings.new([
      Results::Ruling.new(id: "v", kind: "void_capture", payload: { "capture_id" => "c" }, created_at_ms: 1),
      Results::Ruling.new(id: "rv", kind: "revert", payload: { "ruling_id" => "v" }, created_at_ms: 2),
      Results::Ruling.new(id: "d", kind: "dnf", payload: { "bib" => "1" }, created_at_ms: 3),
      Results::Ruling.new(id: "rd", kind: "revert", payload: { "ruling_id" => "d" }, created_at_ms: 4),
      Results::Ruling.new(id: "rrd", kind: "revert", payload: { "ruling_id" => "rd" }, created_at_ms: 5)
    ])
    assert_equal Set["v", "rd"], rulings.cancelled_ids
  end
```

`test/integration/api/ruling_mutations_test.rb`:
```ruby
require "test_helper"

class RulingMutationsTest < ActionDispatch::IntegrationTest
  def mutate(name, args_sig, args_call, **vars)
    gql("mutation(#{args_sig}) { #{name}(#{args_call}) { ruling { id kind payload } errors } }", **vars).dig("data", name)
  end

  def suggestion_keys = gql("query($id: ID!) { standings(eventId: $id) { suggestions { key } } }", id: @event.id)
                          .dig("data", "standings", "suggestions").map { it["key"] }

  setup do
    @chief = create_official(name: "Chief Pat", role: "chief", pin: "2468")
    sign_in(@chief, "2468")
    @event = create_event
    @group = create_start_group(event: @event, finish_rule: { "type" => "fixed_laps", "laps" => 5 })
    @race = create_race(event: @event, start_group: @group)
    %w[1 2 3].each { register(race: @race, bib: it) }
  end

  test "fireStart records the gun at hub time with the signed-in official" do
    before = Clock.now_ms
    result = mutate("fireStart", "$id: ID!", "startGroupId: $id", id: @group.id)
    assert_empty result["errors"]
    ruling = Ruling.find(result["ruling"]["id"])
    assert_equal "set_group_start", ruling.kind
    assert_operator ruling.payload["at_ms"], :>=, before
    assert_equal @chief.id, ruling.official_id
  end

  test "setLapCount and setRaceStart" do
    assert_equal({ "start_group_id" => @group.id, "laps" => 3 },
                 mutate("setLapCount", "$id: ID!", "startGroupId: $id, laps: 3", id: @group.id).dig("ruling", "payload"))
    assert_equal 5_000, mutate("setRaceStart", "$id: ID!", "raceId: $id, atMs: 5000", id: @race.id).dig("ruling", "payload", "at_ms")
  end

  test "recordRuling validates through the model" do
    ok = mutate("recordRuling", "$id: ID!", 'eventId: $id, kind: DNF, payload: {bib: "2"}, reason: "crash"', id: @event.id)
    assert_empty ok["errors"]
    assert_equal "crash", Ruling.find(ok["ruling"]["id"]).reason
    bad = mutate("recordRuling", "$id: ID!", 'eventId: $id, kind: DNF, payload: {bib: "99"}', id: @event.id)
    assert_nil bad["ruling"]
    assert_equal ["Payload bib 99 is not registered in this event"], bad["errors"]
  end

  test "revertRuling and the ruling history" do
    dnf = mutate("recordRuling", "$id: ID!", 'eventId: $id, kind: DNF, payload: {bib: "2"}', id: @event.id)["ruling"]["id"]
    mutate("revertRuling", "$id: ID!", 'rulingId: $id, reason: "wrong bib"', id: dnf)
    history = gql("query($id: ID!) { rulings(eventId: $id) { kind reverted officialName } }", id: @event.id).dig("data", "rulings")
    assert_equal [{ "kind" => "revert", "reverted" => false, "officialName" => "Chief Pat" },
                  { "kind" => "dnf", "reverted" => true, "officialName" => "Chief Pat" }], history
  end

  test "acceptSuggestion applies the fix; a handled suggestion can't be accepted twice" do
    rule(event: @event, kind: "set_group_start", start_group_id: @group.id, at_ms: 0)
    device = create_device(event: @event)
    seq = 0
    { "1" => [300, 600, 900, 1200, 1500], "2" => [310, 620, 1240, 1550], "3" => [305, 610, 915, 1220, 1525] }.each do |bib, times|
      times.each { record_capture(device:, seq: seq += 1, at_ms: it * 1000, bib:) }
    end
    untagged = record_capture(device:, seq: seq + 1, at_ms: 935_000, bib: nil)
    key = suggestion_keys.find { it.start_with?("missed:2:") }

    accepted = mutate("acceptSuggestion", "$id: ID!, $key: String!", "eventId: $id, key: $key", id: @event.id, key:)
    assert_empty accepted["errors"]
    assert_equal({ "capture_id" => untagged.id, "bib" => "2" }, accepted.dig("ruling", "payload"))
    assert_equal "assign_bib", accepted.dig("ruling", "kind")

    # Review Focus 2
    again = mutate("acceptSuggestion", "$id: ID!, $key: String!", "eventId: $id, key: $key", id: @event.id, key:)
    assert_nil again["ruling"]
    assert_equal ["That suggestion is no longer open; it may already have been handled"], again["errors"]
  end

  test "suggestions that need a blank filled say so until it is provided" do
    rule(event: @event, kind: "set_group_start", start_group_id: @group.id, at_ms: 0)
    record_capture(device: create_device(event: @event), seq: 1, at_ms: 100_000, bib: nil, id: "loose")
    missing = mutate("acceptSuggestion", "$id: ID!", 'eventId: $id, key: "unassigned:loose"', id: @event.id)
    assert_equal ["Provide bib to accept this suggestion"], missing["errors"]
    done = mutate("acceptSuggestion", "$id: ID!", 'eventId: $id, key: "unassigned:loose", bib: "3"', id: @event.id)
    assert_equal({ "capture_id" => "loose", "bib" => "3" }, done.dig("ruling", "payload"))
  end

  test "dismissSuggestion hides it" do
    rule(event: @event, kind: "set_group_start", start_group_id: @group.id, at_ms: 0)
    record_capture(device: create_device(event: @event), seq: 1, at_ms: 100_000, bib: nil, id: "loose")
    mutate("dismissSuggestion", "$id: ID!", 'eventId: $id, key: "unassigned:loose"', id: @event.id)
    refute_includes suggestion_keys, "unassigned:loose"
  end

  test "publishResults records the race's current digest" do
    rule(event: @event, kind: "set_group_start", start_group_id: @group.id, at_ms: 0)
    result = mutate("publishResults", "$id: ID!", "raceId: $id", id: @race.id)
    assert_empty result["errors"]
    pub = gql("query($id: ID!) { standings(eventId: $id) { races { publication } } }", id: @event.id)
    assert_equal "PUBLISHED", pub.dig("data", "standings", "races", 0, "publication")
  end

  test "a race that hasn't started can't be published" do
    assert_equal ["Race has not started"], mutate("publishResults", "$id: ID!", "raceId: $id", id: @race.id)["errors"]
  end

  test "timers can't record rulings" do
    delete "/session"
    sign_in(create_official(role: "timer", pin: "1111"), "1111")
    body = gql("mutation($id: ID!) { fireStart(startGroupId: $id) { errors } }", id: @group.id)
    assert_equal "Requires the chief role", body["errors"].first["message"]
  end
end
```

- [ ] **Step 2: Run to verify failure**

Run: `bin/rails test test/integration/api/ruling_mutations_test.rb && bundle exec bin/test-results`
Expected: GraphQL "Field 'fireStart' doesn't exist"; engine test `NoMethodError: undefined method 'cancelled_ids'`.

- [ ] **Step 3: ActiveRulings#cancelled_ids**

Replace `packs/results/lib/results/active_rulings.rb` with:
```ruby
module Results
  # Rulings in chronological order with reverts applied. A revert can itself be
  # reverted, which restores its target.
  class ActiveRulings
    attr_reader :all, :cancelled_ids

    def initialize(rulings)
      sorted = rulings.select { RulingShape.valid?(it) }.uniq(&:id).sort_by { [it.created_at_ms, it.id] }
      @cancelled_ids = Set.new
      sorted.reverse_each do |r|
        next if @cancelled_ids.include?(r.id)
        @cancelled_ids << r.payload["ruling_id"] if r.kind == "revert"
      end
      @all = sorted.reject { @cancelled_ids.include?(it.id) || it.kind == "revert" }
    end

    def of(kind) = @all.select { it.kind == kind }

    def latest_by(kind, &key) = of(kind).group_by(&key).transform_values(&:last)
  end
end
```

- [ ] **Step 4: RulingWriter, types, mutations**

`packs/api/app/models/ruling_writer.rb`:
```ruby
# The only way the API creates rulings: hub time and the signed-in official are
# set here, never taken from the client.
class RulingWriter
  def self.write(event:, official:, kind:, payload:, reason: nil)
    ruling = Ruling.new(event:, kind:, payload: payload.to_h.transform_keys(&:to_s), reason:, official_id: official.id)
    ruling.save
    ruling
  end
end
```

`packs/api/app/graphql/types/ruling_kind_enum.rb`:
```ruby
module Types
  # Kinds recorded through recordRuling; start control, publishing, reverts and
  # suggestions have their own mutations.
  class RulingKindEnum < BaseEnum
    %w[assign_bib void_capture insert_capture flag_finish pull dnf dns dsq].each { value it.upcase, value: it }
  end
end
```

`packs/api/app/graphql/types/ruling_type.rb`:
```ruby
module Types
  class RulingType < BaseObject
    field :id, ID, null: false
    field :kind, String, null: false
    field :payload, GraphQL::Types::JSON, null: false
    field :reason, String
    field :created_at_ms, Millis, null: false
    field :official_name, String
    field :reverted, Boolean, null: false

    def official_name = object.official_id && Official.find_by(id: object.official_id)&.name
    def reverted = context.fetch(:cancelled_ruling_ids, Set.new).include?(object.id)
  end
end
```

`packs/api/app/graphql/mutations/ruling_mutation.rb`:
```ruby
module Mutations
  class RulingMutation < BaseMutation
    field :ruling, Types::RulingType

    private

    def record(event:, kind:, payload:, reason: nil)
      official = require_official!("chief")
      ruling = RulingWriter.write(event:, official:, kind:, payload:, reason:)
      ruling.persisted? ? { ruling:, errors: [] } : { ruling: nil, errors: ruling.errors.full_messages }
    end

    def refuse(message) = { ruling: nil, errors: [message] }
  end
end
```

`packs/api/app/graphql/mutations/fire_start.rb`:
```ruby
module Mutations
  class FireStart < RulingMutation
    description "GO: the start group's gun, at hub time"
    argument :start_group_id, ID

    def resolve(start_group_id:)
      group = StartGroup.find(start_group_id)
      record(event: group.event, kind: "set_group_start", payload: { start_group_id: group.id, at_ms: Clock.now_ms })
    end
  end
end
```

`packs/api/app/graphql/mutations/set_race_start.rb`:
```ruby
module Mutations
  class SetRaceStart < RulingMutation
    description "Override one race's start (held or delayed wave); defaults to hub time now"
    argument :race_id, ID
    argument :at_ms, Types::Millis, required: false

    def resolve(race_id:, at_ms: nil)
      race = Race.find(race_id)
      record(event: race.event, kind: "set_race_start", payload: { race_id: race.id, at_ms: at_ms || Clock.now_ms })
    end
  end
end
```

`packs/api/app/graphql/mutations/set_lap_count.rb`:
```ruby
module Mutations
  class SetLapCount < RulingMutation
    description "Set the start group's lap count; overrides the finish rule (fixed or timed)"
    argument :start_group_id, ID
    argument :laps, Integer

    def resolve(start_group_id:, laps:)
      group = StartGroup.find(start_group_id)
      record(event: group.event, kind: "set_lap_count", payload: { start_group_id: group.id, laps: })
    end
  end
end
```

`packs/api/app/graphql/mutations/record_ruling.rb`:
```ruby
module Mutations
  class RecordRuling < RulingMutation
    argument :event_id, ID
    argument :kind, Types::RulingKindEnum
    argument :payload, GraphQL::Types::JSON
    argument :reason, String, required: false

    def resolve(event_id:, kind:, payload:, reason: nil)
      record(event: Event.find(event_id), kind:, payload:, reason:)
    end
  end
end
```

`packs/api/app/graphql/mutations/revert_ruling.rb`:
```ruby
module Mutations
  class RevertRuling < RulingMutation
    argument :ruling_id, ID
    argument :reason, String, required: false

    def resolve(ruling_id:, reason: nil)
      target = Ruling.find(ruling_id)
      record(event: target.event, kind: "revert", payload: { ruling_id: target.id }, reason:)
    end
  end
end
```

`packs/api/app/graphql/mutations/accept_suggestion.rb`:
```ruby
module Mutations
  class AcceptSuggestion < RulingMutation
    argument :event_id, ID
    argument :key, String
    argument :capture_id, ID, required: false
    argument :bib, String, required: false

    def resolve(event_id:, key:, capture_id: nil, bib: nil)
      require_official!("chief")
      event = Event.find(event_id)
      suggestion = StandingsService.report(event).output.suggestions.find { it.key == key }
      return refuse("That suggestion is no longer open; it may already have been handled") unless suggestion
      return refuse("This suggestion has no automatic fix; record a ruling instead") unless suggestion.fix
      fix = SuggestionFix.complete(suggestion.fix, capture_id:, bib:)
      missing = SuggestionFix.missing(fix)
      return refuse("Provide #{missing.join(' and ')} to accept this suggestion") if missing.any?
      record(event:, kind: fix["kind"], payload: fix.except("kind"))
    end
  end
end
```

`packs/api/app/graphql/mutations/dismiss_suggestion.rb`:
```ruby
module Mutations
  class DismissSuggestion < RulingMutation
    argument :event_id, ID
    argument :key, String

    def resolve(event_id:, key:)
      record(event: Event.find(event_id), kind: "dismiss_suggestion", payload: { suggestion_key: key })
    end
  end
end
```

`packs/api/app/graphql/mutations/publish_results.rb`:
```ruby
module Mutations
  class PublishResults < RulingMutation
    description "Mark the race's current standings official"
    argument :race_id, ID

    def resolve(race_id:)
      require_official!("chief")
      race = Race.find(race_id)
      result = StandingsService.report(race.event).output.races.find { it.race_id == race.id }
      return refuse("Race has not started") if result.nil? || result.state == :not_started
      record(event: race.event, kind: "publish_results", payload: { race_id: race.id, result_digest: result.digest })
    end
  end
end
```

Add to `Types::MutationType`:
```ruby
    field :fire_start, mutation: Mutations::FireStart
    field :set_race_start, mutation: Mutations::SetRaceStart
    field :set_lap_count, mutation: Mutations::SetLapCount
    field :record_ruling, mutation: Mutations::RecordRuling
    field :revert_ruling, mutation: Mutations::RevertRuling
    field :accept_suggestion, mutation: Mutations::AcceptSuggestion
    field :dismiss_suggestion, mutation: Mutations::DismissSuggestion
    field :publish_results, mutation: Mutations::PublishResults
```

Add to `Types::QueryType`:
```ruby
    field :rulings, [RulingType], null: false, description: "Newest first" do
      argument :event_id, ID
    end

    def rulings(event_id:)
      require_official!
      rulings = Ruling.where(event_id:).order(created_at_ms: :desc, id: :desc).to_a
      engine_rulings = rulings.map { Results::Ruling.new(id: it.id, kind: it.kind, payload: it.payload, created_at_ms: it.created_at_ms) }
      context[:cancelled_ruling_ids] = Results::ActiveRulings.new(engine_rulings).cancelled_ids
      rulings
    end
```

- [ ] **Step 5: Spec note**

In spec §7, replace the bullet "Mutations map 1:1 to ruling kinds plus setup CRUD." with:
"Mutations: setup CRUD and CSV import (admin); start control `fireStart` (hub time), `setRaceStart`, `setLapCount`; `recordRuling(kind, payload)` for log rulings (assign/void/insert/flag/pull/DNF/DNS/DSQ); `revertRuling`; `acceptSuggestion` (applies a suggestion's fix, with any blank the official fills in) and `dismissSuggestion`; `publishResults` (the hub computes the digest). The hub sets each ruling's time and official; clients can't."

- [ ] **Step 6: Run to verify pass**

```bash
bundle exec bin/test-results && bin/rails test && TIMING_DB=postgresql bin/rails test && bin/packwerk check
```
Expected: all green.

- [ ] **Step 7: Commit**

```bash
git add -A
git commit -m "feat(api): ruling mutations, start control, suggestions, publishing, ruling history

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 7: Live "event changed" updates over ActionCable

**Files:**
- Create: `app/models/event_broadcast.rb`, `app/models/concerns/broadcasts_event_change.rb`, `app/channels/application_cable/connection.rb`, `app/channels/application_cable/channel.rb`, `packs/api/app/channels/event_channel.rb`, `test/models/event_broadcast_test.rb`, `test/channels/application_cable/connection_test.rb`, `test/channels/event_channel_test.rb`
- Modify: `packs/timing/app/models/device_entry.rb`, `packs/timing/app/models/ruling.rb`, `packs/events/app/models/{registration,race,start_group}.rb`, `config/routes.rb`, spec §7

**Interfaces:**
- Produces: `EventBroadcast.stream(event_id) -> "event:<id>"`, `EventBroadcast.changed(event_id)` broadcasting `{ type: "changed", at_ms: }`; concern `BroadcastsEventChange` (after_commit → `EventBroadcast.changed(event_id)`); `ApplicationCable::Connection` identified by `current_official` (from the encrypted session cookie; rejects anonymous); `EventChannel` (params `event_id`) streaming `EventBroadcast.stream`; route `/cable`.

- [ ] **Step 1: Write failing tests**

`test/models/event_broadcast_test.rb`:
```ruby
require "test_helper"

class EventBroadcastTest < ActiveSupport::TestCase
  include ActionCable::TestHelper

  setup do
    @event = create_event
    @race = create_race(event: @event)
    @stream = EventBroadcast.stream(@event.id)
  end

  test "new captures, rulings and registrations announce the event changed" do
    assert_broadcasts(@stream, 1) { record_capture(device: create_device(event: @event), seq: 1, at_ms: 1, bib: "1") }
    assert_broadcasts(@stream, 1) { rule(event: @event, kind: "set_lap_count", start_group_id: @race.start_group_id, laps: 3) }
    assert_broadcasts(@stream, 1) { register(race: @race, bib: "7") }
  end

  test "setup edits announce too" do
    assert_broadcasts(@stream, 1) { @race.start_group.update!(name: "10:05") }
    assert_broadcasts(@stream, 1) { @race.update!(start_offset_ms: 30_000) }
  end

  test "message shape" do
    EventBroadcast.changed(@event.id)
    message = JSON.parse(broadcasts(@stream).last)
    assert_equal "changed", message["type"]
    assert_kind_of Integer, message["at_ms"]
  end
end
```

`test/channels/application_cable/connection_test.rb`:
```ruby
require "test_helper"

class ApplicationCable::ConnectionTest < ActionCable::Connection::TestCase
  test "connects a signed-in official from the session cookie" do
    official = create_official
    cookies.encrypted["_timing_session"] = { "official_id" => official.id }
    connect
    assert_equal official, connection.current_official
  end

  test "rejects anonymous connections" do
    assert_reject_connection { connect }
  end
end
```

`test/channels/event_channel_test.rb`:
```ruby
require "test_helper"

class EventChannelTest < ActionCable::Channel::TestCase
  test "streams the event's changes" do
    event = create_event
    stub_connection current_official: create_official
    subscribe event_id: event.id
    assert subscription.confirmed?
    assert_has_stream EventBroadcast.stream(event.id)
  end

  test "rejects unknown events" do
    stub_connection current_official: create_official
    subscribe event_id: "nope"
    assert subscription.rejected?
  end
end
```

- [ ] **Step 2: Run to verify failure**

Run: `bin/rails test test/models/event_broadcast_test.rb test/channels`
Expected: `uninitialized constant EventBroadcast`, `ApplicationCable`.

- [ ] **Step 3: Broadcast module and concern**

`app/models/event_broadcast.rb`:
```ruby
# One stream per event. Clients refetch what they show when told it changed.
module EventBroadcast
  module_function

  def stream(event_id) = "event:#{event_id}"

  def changed(event_id) = ActionCable.server.broadcast(stream(event_id), { type: "changed", at_ms: Clock.now_ms })
end
```

`app/models/concerns/broadcasts_event_change.rb`:
```ruby
module BroadcastsEventChange
  extend ActiveSupport::Concern

  included { after_commit { EventBroadcast.changed(event_id) } }
end
```

Add `include BroadcastsEventChange` as the first line inside the class body of `DeviceEntry`, `Ruling`, `Registration`, `Race` and `StartGroup`.

- [ ] **Step 4: Connection, channel, route**

`app/channels/application_cable/connection.rb`:
```ruby
module ApplicationCable
  class Connection < ActionCable::Connection::Base
    identified_by :current_official

    def connect
      self.current_official = official_from_session || reject_unauthorized_connection
    end

    private

    def official_from_session
      session = cookies.encrypted[Rails.application.config.session_options[:key]]
      session && Official.active.find_by(id: session["official_id"])
    end
  end
end
```

`app/channels/application_cable/channel.rb`:
```ruby
module ApplicationCable
  class Channel < ActionCable::Channel::Base
  end
end
```

`packs/api/app/channels/event_channel.rb`:
```ruby
class EventChannel < ApplicationCable::Channel
  def subscribed
    event = Event.find_by(id: params[:event_id])
    return reject unless event
    stream_from EventBroadcast.stream(event.id)
  end
end
```

In `config/routes.rb` add:
```ruby
  mount ActionCable.server => "/cable"
```

- [ ] **Step 5: Spec note**

In spec §7, replace the "**Subscriptions** via ActionCable …" bullet with:
"**Live updates** over ActionCable (Solid Cable in production, so no Redis on the hub): one stream per event, `EventChannel` / `event:<event_id>`, carrying `{type: "changed", at_ms}` whenever a capture, ruling, registration, race or start group changes. Clients refetch the GraphQL queries they display. Connections require a signed-in official."

- [ ] **Step 6: Run to verify pass**

```bash
bin/rails test && TIMING_DB=postgresql bin/rails test && bin/packwerk check && bin/rails zeitwerk:check
```
Expected: all green.

- [ ] **Step 7: Commit**

```bash
git add -A
git commit -m "feat(api): live event-changed broadcasts over ActionCable for signed-in officials

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 8: Device pairing, credentials, revocation, device list

**Files:**
- Create: `db/migrate/20261002000002_create_pairing_tokens.rb`, `packs/access/app/models/pairing_token.rb`, `packs/access/app/controllers/devices_controller.rb`, `packs/api/app/graphql/types/device_type.rb`, `packs/api/app/graphql/mutations/{create_pairing_token,revoke_device}.rb`, `test/models/pairing_token_test.rb`, `test/models/device_credentials_test.rb`, `test/integration/device_pairing_test.rb`
- Modify: `packs/timing/app/models/device.rb`, `config/routes.rb`, `packs/api/app/graphql/types/{mutation_type,query_type}.rb`, `test/support/api_helpers.rb`

**Interfaces:**
- Produces: `Device.pair!(event:, name:) -> [Device, credential]`, `Device.authenticate(id, credential) -> Device | nil`, `Device.digest(credential)`, `Device#revoke!`. `PairingToken.issue!(event:, official:) -> [PairingToken, raw_token]`, `PairingToken.redeem!(raw, device_name:) -> [Device, credential]` (raises `PairingToken::Invalid` with a message). `POST /devices/pair` `{token, name}` → 201 `{device_id, credential, event_id}` / 422 `{error}`; `DevicesController::RATE_LIMIT_STORE`. GraphQL: `createPairingToken(eventId) { token expiresAtMs pairingUrl errors }` (admin), `revokeDevice(deviceId) { device errors }` (admin), query `devices(eventId) [Device { id name pairedAtMs revokedAtMs lastSeenAtMs entryCount clockOffsetMs }]`. The pairing URL is `<hub base url>/capture/pair?token=<raw>` (the capture app, Plan 4, handles it).

- [ ] **Step 1: Write failing tests**

In `test/support/api_helpers.rb`, change the setup line to:
```ruby
  setup do
    SessionsController::RATE_LIMIT_STORE.clear
    DevicesController::RATE_LIMIT_STORE.clear
  end
```

`test/models/device_credentials_test.rb`:
```ruby
require "test_helper"

class DeviceCredentialsTest < ActiveSupport::TestCase
  setup { @event = create_event }

  test "pair! issues a credential stored only as a digest" do
    device, credential = Device.pair!(event: @event, name: "Tablet A")
    assert_equal 43, credential.length
    assert_equal Device.digest(credential), device.credential_digest
    assert_equal device, Device.authenticate(device.id, credential)
    assert_nil Device.authenticate(device.id, "wrong")
    assert_nil Device.authenticate("nope", credential)
  end

  # Review Focus 4 (lost tablet)
  test "a revoked device no longer authenticates" do
    device, credential = Device.pair!(event: @event, name: "Tablet A")
    device.revoke!
    assert_nil Device.authenticate(device.id, credential)
  end
end
```

`test/models/pairing_token_test.rb`:
```ruby
require "test_helper"

class PairingTokenTest < ActiveSupport::TestCase
  setup do
    @event = create_event
    @official = create_official(role: "admin")
  end

  test "a token pairs one device" do
    _record, raw = PairingToken.issue!(event: @event, official: @official)
    device, credential = PairingToken.redeem!(raw, device_name: "Tablet A")
    assert_equal @event, device.event
    assert_equal device, Device.authenticate(device.id, credential)
  end

  # Review Focus 4 (reused or late QR code)
  test "a used or expired token is refused" do
    _record, raw = PairingToken.issue!(event: @event, official: @official)
    PairingToken.redeem!(raw, device_name: "Tablet A")
    error = assert_raises(PairingToken::Invalid) { PairingToken.redeem!(raw, device_name: "Tablet B") }
    assert_equal "This pairing code has already been used", error.message

    record, late = PairingToken.issue!(event: @event, official: @official)
    record.update!(expires_at_ms: Clock.now_ms - 1)
    assert_equal "This pairing code has expired",
                 assert_raises(PairingToken::Invalid) { PairingToken.redeem!(late, device_name: "Tablet C") }.message
    assert_equal "Unknown pairing code",
                 assert_raises(PairingToken::Invalid) { PairingToken.redeem!("made-up", device_name: "Tablet D") }.message
  end

  test "tokens expire ten minutes after issue and are stored as digests" do
    record, raw = PairingToken.issue!(event: @event, official: @official)
    assert_in_delta Clock.now_ms + 600_000, record.expires_at_ms, 2_000
    refute_equal raw, record.token_digest
  end
end
```

`test/integration/device_pairing_test.rb`:
```ruby
require "test_helper"

class DevicePairingTest < ActionDispatch::IntegrationTest
  setup do
    sign_in(create_official(role: "admin", pin: "1111"), "1111")
    @event = create_event
  end

  def pairing_token
    gql("mutation($id: ID!) { createPairingToken(eventId: $id) { token expiresAtMs pairingUrl errors } }", id: @event.id)
      .dig("data", "createPairingToken")
  end

  test "admin issues a pairing code; a tablet redeems it once; admin sees and revokes the device" do
    issued = pairing_token
    assert_equal "http://www.example.com/capture/pair?token=#{issued['token']}", issued["pairingUrl"]

    delete "/session" # the tablet has no official session
    post "/devices/pair", params: { token: issued["token"], name: "Finish tablet" }.to_json, headers: ApiHelpers::JSON_HEADERS
    assert_response :created
    paired = response.parsed_body
    assert_equal @event.id, paired["event_id"]
    assert Device.authenticate(paired["device_id"], paired["credential"])

    post "/devices/pair", params: { token: issued["token"], name: "Again" }.to_json, headers: ApiHelpers::JSON_HEADERS
    assert_response :unprocessable_content
    assert_equal "This pairing code has already been used", response.parsed_body["error"]

    sign_in(Official.find_by!(role: "admin"), "1111")
    devices = gql("query($id: ID!) { devices(eventId: $id) { id name revokedAtMs entryCount } }", id: @event.id).dig("data", "devices")
    assert_equal [{ "id" => paired["device_id"], "name" => "Finish tablet", "revokedAtMs" => nil, "entryCount" => 0 }], devices
    gql("mutation($id: ID!) { revokeDevice(deviceId: $id) { errors } }", id: paired["device_id"])
    assert_nil Device.authenticate(paired["device_id"], paired["credential"])
  end

  test "pairing requires the admin role" do
    delete "/session"
    sign_in(create_official(role: "chief", pin: "2222"), "2222")
    body = gql("mutation($id: ID!) { createPairingToken(eventId: $id) { token } }", id: @event.id)
    assert_equal "Requires the admin role", body["errors"].first["message"]
  end
end
```

- [ ] **Step 2: Run to verify failure**

Run: `bin/rails test test/models/device_credentials_test.rb test/models/pairing_token_test.rb test/integration/device_pairing_test.rb`
Expected: `NoMethodError: undefined method 'pair!'`, `uninitialized constant PairingToken`.

- [ ] **Step 3: Device credentials**

Replace `packs/timing/app/models/device.rb` with:
```ruby
class Device < ApplicationRecord
  belongs_to :event
  has_many :device_entries, dependent: :restrict_with_error

  validates :name, :paired_at_ms, :credential_digest, presence: true

  def self.digest(credential) = Digest::SHA256.hexdigest(credential)

  # Returns [device, credential]; only the digest is stored.
  def self.pair!(event:, name:)
    credential = SecureRandom.urlsafe_base64(32)
    [create!(event:, name:, paired_at_ms: Clock.now_ms, credential_digest: digest(credential)), credential]
  end

  def self.authenticate(id, credential)
    device = find_by(id:)
    return nil unless device && !device.revoked? && credential.is_a?(String)
    ActiveSupport::SecurityUtils.secure_compare(device.credential_digest, digest(credential)) ? device : nil
  end

  def revoked? = revoked_at_ms.present?

  def revoke! = update!(revoked_at_ms: Clock.now_ms)
end
```

- [ ] **Step 4: Pairing tokens**

`db/migrate/20261002000002_create_pairing_tokens.rb`:
```ruby
class CreatePairingTokens < ActiveRecord::Migration[8.1]
  def change
    create_table :pairing_tokens, id: :string do |t|
      t.references :event, type: :string, null: false, foreign_key: true
      t.string :token_digest, null: false
      t.bigint :expires_at_ms, null: false
      t.bigint :used_at_ms
      t.string :created_by_official_id, null: false
      t.timestamps
    end
    add_index :pairing_tokens, :token_digest, unique: true
  end
end
```

`packs/access/app/models/pairing_token.rb`:
```ruby
# One-time code shown as a QR code; a tablet trades it for a device credential.
class PairingToken < ApplicationRecord
  TTL_MS = 10 * 60 * 1000

  class Invalid < StandardError; end

  belongs_to :event

  def self.issue!(event:, official:)
    raw = SecureRandom.urlsafe_base64(24)
    record = create!(event:, token_digest: Device.digest(raw), expires_at_ms: Clock.now_ms + TTL_MS,
                     created_by_official_id: official.id)
    [record, raw]
  end

  def self.redeem!(raw, device_name:)
    transaction do
      token = lock.find_by(token_digest: Device.digest(raw.to_s))
      raise Invalid, "Unknown pairing code" unless token
      raise Invalid, "This pairing code has already been used" if token.used_at_ms
      raise Invalid, "This pairing code has expired" if token.expires_at_ms < Clock.now_ms
      token.update!(used_at_ms: Clock.now_ms)
      Device.pair!(event: token.event, name: device_name.presence || "Tablet")
    end
  end
end
```

`packs/access/app/controllers/devices_controller.rb`:
```ruby
class DevicesController < ApplicationController
  include SameOrigin

  RATE_LIMIT_STORE = ActiveSupport::Cache::MemoryStore.new

  rate_limit to: 10, within: 1.minute, only: :pair, store: RATE_LIMIT_STORE,
             with: -> { render json: { error: "Too many attempts. Wait a minute and try again." }, status: :too_many_requests }

  def pair
    device, credential = PairingToken.redeem!(params[:token].to_s, device_name: params[:name].to_s)
    render json: { device_id: device.id, credential:, event_id: device.event_id }, status: :created
  rescue PairingToken::Invalid => e
    render json: { error: e.message }, status: :unprocessable_content
  end
end
```

In `config/routes.rb` add:
```ruby
  post "devices/pair", to: "devices#pair"
```

- [ ] **Step 5: GraphQL device type and mutations**

`packs/api/app/graphql/types/device_type.rb`:
```ruby
module Types
  class DeviceType < BaseObject
    field :id, ID, null: false
    field :name, String, null: false
    field :paired_at_ms, Millis, null: false
    field :revoked_at_ms, Millis
    field :last_seen_at_ms, Millis, description: "When the hub last received an entry from it"
    field :entry_count, Integer, null: false
    field :clock_offset_ms, Millis, description: "Offset on its latest capture"

    def last_seen_at_ms = object.device_entries.maximum(:received_at_ms)
    def entry_count = object.device_entries.count
    def clock_offset_ms = Capture.where(device: object).order(device_seq: :desc).pick(:clock_offset_ms)
  end
end
```

`packs/api/app/graphql/mutations/create_pairing_token.rb`:
```ruby
module Mutations
  class CreatePairingToken < BaseMutation
    argument :event_id, ID

    field :token, String
    field :expires_at_ms, Types::Millis
    field :pairing_url, String

    def resolve(event_id:)
      official = require_official!("admin")
      record, raw = PairingToken.issue!(event: Event.find(event_id), official:)
      { token: raw, expires_at_ms: record.expires_at_ms, pairing_url: "#{context[:base_url]}/capture/pair?token=#{raw}", errors: [] }
    end
  end
end
```

`packs/api/app/graphql/mutations/revoke_device.rb`:
```ruby
module Mutations
  class RevokeDevice < BaseMutation
    argument :device_id, ID

    field :device, Types::DeviceType

    def resolve(device_id:)
      require_official!("admin")
      device = Device.find(device_id)
      device.revoke!
      { device:, errors: [] }
    end
  end
end
```

Add to `Types::MutationType`:
```ruby
    field :create_pairing_token, mutation: Mutations::CreatePairingToken
    field :revoke_device, mutation: Mutations::RevokeDevice
```

Add to `Types::QueryType`:
```ruby
    field :devices, [DeviceType], null: false do
      argument :event_id, ID
    end

    def devices(event_id:)
      require_official!
      Device.where(event_id:).order(:paired_at_ms, :id)
    end
```

- [ ] **Step 6: Run to verify pass on both databases**

```bash
bin/rails db:migrate && bin/rails test
TIMING_DB=postgresql bin/rails db:migrate && TIMING_DB=postgresql bin/rails test
bin/packwerk check
```
Restore the sqlite-generated `db/schema.rb` if Postgres rewrote it. Expected: all green.

- [ ] **Step 7: Commit**

```bash
git add -A
git commit -m "feat(access,api): QR pairing tokens, device credentials, revocation, device list

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 9: Local certificate authority, HTTPS gate, onboarding page, `bin/hub`

**Files:**
- Create: `packs/access/app/models/local_ca.rb`, `packs/access/app/controllers/onboarding_controller.rb`, `lib/hub_tls_gate.rb`, `lib/tasks/hub.rake`, `bin/hub`, `test/models/local_ca_test.rb`, `test/lib/hub_tls_gate_test.rb`, `test/integration/onboarding_test.rb`
- Modify: `config/application.rb`, `config/routes.rb`, `config/puma.rb`, `.gitignore`

**Interfaces:**
- Produces: `LocalCa.new(dir = Rails.root.join("storage/certs"))` with `#ensure!(hosts:, ips:)`, `#root_cert_path`, `#server_cert_path`, `#server_key_path`; `LocalCa.lan_ips`, `LocalCa.default_hosts`; `HubTlsGate` Rack middleware (`new(app, enabled:)`); `GET /onboarding` (HTML), `GET /onboarding/ca.crt`; rake `hub:certs`; `bin/hub`.

- [ ] **Step 1: Write failing tests**

`test/models/local_ca_test.rb`:
```ruby
require "test_helper"

class LocalCaTest < ActiveSupport::TestCase
  setup do
    @dir = Dir.mktmpdir
    @ca = LocalCa.new(@dir)
  end

  teardown { FileUtils.remove_entry(@dir) }

  def verify(cert_path)
    store = OpenSSL::X509::Store.new
    store.add_cert(OpenSSL::X509::Certificate.new(File.read(@ca.root_cert_path)))
    store.verify(OpenSSL::X509::Certificate.new(File.read(cert_path)))
  end

  def san(path)
    cert = OpenSSL::X509::Certificate.new(File.read(path))
    cert.extensions.find { it.oid == "subjectAltName" }.value
  end

  test "creates a root CA and a server certificate it signs, with hosts and IPs" do
    @ca.ensure!(hosts: ["hub.local", "localhost"], ips: ["192.168.1.20", "127.0.0.1"])
    assert verify(@ca.server_cert_path)
    assert_includes san(@ca.server_cert_path), "IP Address:192.168.1.20"
    assert_includes san(@ca.server_cert_path), "DNS:hub.local"
    server = OpenSSL::X509::Certificate.new(File.read(@ca.server_cert_path))
    assert_operator server.not_after, :<=, Time.now + 397 * 86_400
    assert_equal "600", format("%o", File.stat(@ca.server_key_path).mode & 0o777)
  end

  test "keeps a current certificate, reissues when the network address changes" do
    @ca.ensure!(hosts: ["hub.local"], ips: ["192.168.1.20"])
    root = File.read(@ca.root_cert_path)
    first = File.read(@ca.server_cert_path)
    @ca.ensure!(hosts: ["hub.local"], ips: ["192.168.1.20"])
    assert_equal first, File.read(@ca.server_cert_path)
    @ca.ensure!(hosts: ["hub.local"], ips: ["10.0.0.5"])
    refute_equal first, File.read(@ca.server_cert_path)
    assert_equal root, File.read(@ca.root_cert_path)
    assert verify(@ca.server_cert_path)
  end
end
```

`test/lib/hub_tls_gate_test.rb`:
```ruby
require "test_helper"

class HubTlsGateTest < ActiveSupport::TestCase
  APP = ->(_env) { [200, {}, ["ok"]] }

  def call(path, https: false, enabled: true)
    env = Rack::MockRequest.env_for("#{https ? 'https' : 'http'}://hub.local:3000#{path}")
    HubTlsGate.new(APP, enabled:).call(env)
  end

  test "plain HTTP only reaches onboarding and the health check" do
    assert_equal 200, call("/onboarding").first
    assert_equal 200, call("/onboarding/ca.crt").first
    assert_equal 200, call("/up").first
    status, _headers, body = call("/graphql")
    assert_equal 403, status
    assert_includes body.join, "/onboarding"
  end

  test "HTTPS passes, and the gate is off unless enabled" do
    assert_equal 200, call("/graphql", https: true).first
    assert_equal 200, call("/graphql", enabled: false).first
  end
end
```

`test/integration/onboarding_test.rb`:
```ruby
require "test_helper"

class OnboardingTest < ActionDispatch::IntegrationTest
  setup do
    @dir = Dir.mktmpdir
    @ca = LocalCa.new(@dir)
    @ca.ensure!(hosts: ["localhost"], ips: ["127.0.0.1"])
    OnboardingController.local_ca = @ca
  end

  teardown do
    OnboardingController.local_ca = nil
    FileUtils.remove_entry(@dir)
  end

  test "onboarding page explains setup and links the CA certificate" do
    get "/onboarding"
    assert_response :ok
    assert_includes response.body, "/onboarding/ca.crt"
    assert_includes response.body, "https://"
  end

  test "CA certificate downloads" do
    get "/onboarding/ca.crt"
    assert_response :ok
    assert_equal "application/x-x509-ca-cert", response.media_type
    assert_equal File.read(@ca.root_cert_path), response.body
  end
end
```

- [ ] **Step 2: Run to verify failure**

Run: `bin/rails test test/models/local_ca_test.rb test/lib/hub_tls_gate_test.rb test/integration/onboarding_test.rb`
Expected: `uninitialized constant LocalCa`, `HubTlsGate`.

- [ ] **Step 3: LocalCa**

`packs/access/app/models/local_ca.rb`:
```ruby
require "openssl"

# The hub's own certificate authority (spec §8, option A): crew tablets trust the
# root once; the hub issues itself a server certificate for its LAN addresses.
class LocalCa
  ROOT_DAYS = 3650
  SERVER_DAYS = 397 # Apple's limit for TLS server certificates
  RENEW_WITHIN_DAYS = 30
  DAY = 86_400

  def self.lan_ips = Socket.ip_address_list.select { it.ipv4? && !it.ipv4_loopback? }.map(&:ip_address)

  def self.default_hosts
    host = Socket.gethostname
    [host, "#{host.split('.').first}.local", "localhost"].uniq
  end

  def initialize(dir = Rails.root.join("storage/certs"))
    @dir = Pathname(dir)
  end

  def root_cert_path = @dir.join("root-ca.crt")
  def root_key_path = @dir.join("root-ca.key")
  def server_cert_path = @dir.join("server.crt")
  def server_key_path = @dir.join("server.key")

  def ensure!(hosts:, ips:)
    FileUtils.mkdir_p(@dir)
    ensure_root!
    ensure_server!(hosts.uniq, ips.uniq)
    self
  end

  private

  def ensure_root!
    return if root_cert_path.exist? && root_key_path.exist?
    key = OpenSSL::PKey::RSA.new(2048)
    cert = build(subject: "/CN=Timing Hub Local CA #{SecureRandom.hex(4)}", key:, issuer: nil, issuer_key: key, days: ROOT_DAYS) do |c, ef|
      c.add_extension ef.create_extension("basicConstraints", "CA:TRUE", true)
      c.add_extension ef.create_extension("keyUsage", "keyCertSign,cRLSign", true)
      c.add_extension ef.create_extension("subjectKeyIdentifier", "hash", false)
    end
    write(root_key_path, key.to_pem, 0o600)
    write(root_cert_path, cert.to_pem, 0o644)
  end

  def ensure_server!(hosts, ips)
    root = OpenSSL::X509::Certificate.new(root_cert_path.read)
    return if current?(root, hosts, ips)
    key = OpenSSL::PKey::RSA.new(2048)
    alt_names = (hosts.map { "DNS:#{it}" } + ips.map { "IP:#{it}" }).join(",")
    cert = build(subject: "/CN=#{hosts.first || 'timing-hub'}", key:, issuer: root,
                 issuer_key: OpenSSL::PKey::RSA.new(root_key_path.read), days: SERVER_DAYS) do |c, ef|
      c.add_extension ef.create_extension("basicConstraints", "CA:FALSE", true)
      c.add_extension ef.create_extension("keyUsage", "digitalSignature,keyEncipherment", true)
      c.add_extension ef.create_extension("extendedKeyUsage", "serverAuth", false)
      c.add_extension ef.create_extension("subjectAltName", alt_names, false)
    end
    write(server_key_path, key.to_pem, 0o600)
    write(server_cert_path, cert.to_pem, 0o644)
  end

  def current?(root, hosts, ips)
    return false unless server_cert_path.exist? && server_key_path.exist?
    cert = OpenSSL::X509::Certificate.new(server_cert_path.read)
    return false if cert.issuer.to_s != root.subject.to_s
    return false if cert.not_after < Time.now + RENEW_WITHIN_DAYS * DAY
    alt = cert.extensions.find { it.oid == "subjectAltName" }&.value.to_s.split(", ").sort
    alt == (hosts.map { "DNS:#{it}" } + ips.map { "IP Address:#{it}" }).sort
  end

  def build(subject:, key:, issuer:, issuer_key:, days:)
    cert = OpenSSL::X509::Certificate.new
    cert.version = 2
    cert.serial = OpenSSL::BN.rand(64)
    cert.subject = OpenSSL::X509::Name.parse(subject)
    cert.issuer = issuer ? issuer.subject : cert.subject
    cert.public_key = key
    cert.not_before = Time.now - 60
    cert.not_after = Time.now + days * DAY
    ef = OpenSSL::X509::ExtensionFactory.new
    ef.subject_certificate = cert
    ef.issuer_certificate = issuer || cert
    yield cert, ef
    cert.add_extension ef.create_extension("authorityKeyIdentifier", "keyid:always", false) if issuer
    cert.sign(issuer_key, OpenSSL::Digest.new("SHA256"))
    cert
  end

  def write(path, contents, mode)
    File.write(path, contents)
    File.chmod(mode, path)
  end
end
```

- [ ] **Step 4: HubTlsGate middleware and application config**

`lib/hub_tls_gate.rb`:
```ruby
# With HUB_TLS=1, plain HTTP only serves the device onboarding page (to fetch the
# hub's CA certificate) and the health check; everything else needs HTTPS.
class HubTlsGate
  OPEN_PATHS = %w[/up /onboarding].freeze

  def initialize(app, enabled: ENV["HUB_TLS"] == "1")
    @app = app
    @enabled = enabled
  end

  def call(env)
    request = Rack::Request.new(env)
    return @app.call(env) if !@enabled || request.ssl? || open_path?(request.path)
    [403, { "content-type" => "text/plain" },
     ["This hub only answers over HTTPS. Set up this device first: http://#{request.host_with_port}/onboarding\n"]]
  end

  private

  def open_path?(path) = OPEN_PATHS.any? { path == it || path.start_with?("#{it}/") }
end
```

In `config/application.rb`:
- after `require_relative "../lib/timing_mode"` add `require_relative "../lib/hub_tls_gate"`;
- change `config.autoload_lib(ignore: %w[assets tasks])` to `config.autoload_lib(ignore: %w[assets tasks timing_mode.rb hub_tls_gate.rb])`;
- after the session middleware lines add `config.middleware.insert_before 0, HubTlsGate`.

- [ ] **Step 5: Onboarding controller and routes**

`packs/access/app/controllers/onboarding_controller.rb`:
```ruby
# Served over plain HTTP so a new tablet can fetch and trust the hub's CA.
class OnboardingController < ApplicationController
  class_attribute :local_ca

  def show
    render body: page, content_type: "text/html"
  end

  def ca
    send_data ca_store.root_cert_path.read, type: "application/x-x509-ca-cert", filename: "timing-hub-ca.crt"
  end

  private

  def ca_store = self.class.local_ca || LocalCa.new

  def page
    port = ENV.fetch("HUB_TLS_PORT", "3443")
    urls = (LocalCa.lan_ips.presence || ["127.0.0.1"]).map { "https://#{it}:#{port}" }
    <<~HTML
      <!doctype html>
      <html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
      <title>Set up this device</title>
      <style>body{font:16px/1.5 system-ui,sans-serif;max-width:40rem;margin:2rem auto;padding:0 1rem}a{word-break:break-all}</style></head>
      <body>
        <h1>Set up this device for the timing hub</h1>
        <ol>
          <li><a href="/onboarding/ca.crt">Download the hub certificate</a>.</li>
          <li><strong>iPhone/iPad:</strong> Settings → Profile Downloaded → Install. Then Settings → General → About →
              Certificate Trust Settings → turn on “Timing Hub Local CA”.</li>
          <li><strong>Android:</strong> Settings → Security → Encryption &amp; credentials → Install a certificate → CA certificate.</li>
          <li>Open the hub: #{urls.map { "<a href=\"#{it}\">#{it}</a>" }.join(' or ')}</li>
        </ol>
      </body></html>
    HTML
  end
end
```

In `config/routes.rb` add:
```ruby
  get "onboarding", to: "onboarding#show"
  get "onboarding/ca.crt", to: "onboarding#ca"
```

- [ ] **Step 6: Rake task, puma TLS bind, bin/hub, gitignore**

`lib/tasks/hub.rake`:
```ruby
namespace :hub do
  desc "Create or refresh the hub's local CA and HTTPS certificate for this machine's addresses"
  task certs: :environment do
    ca = LocalCa.new.ensure!(hosts: LocalCa.default_hosts, ips: LocalCa.lan_ips + ["127.0.0.1"])
    puts "Root CA:     #{ca.root_cert_path}"
    puts "Server cert: #{ca.server_cert_path}"
  end
end
```

Append to `config/puma.rb`:
```ruby
# Hub HTTPS (spec §8): bin/hub sets HUB_TLS=1 after running hub:certs.
if ENV["HUB_TLS"] == "1"
  certs = File.expand_path("../storage/certs", __dir__)
  ssl_bind "0.0.0.0", ENV.fetch("HUB_TLS_PORT", "3443"), key: "#{certs}/server.key", cert: "#{certs}/server.crt"
end
```

`bin/hub` (then `chmod +x bin/hub`):
```bash
#!/usr/bin/env bash
# Starts the venue hub: HTTPS on HUB_TLS_PORT (default 3443) with the hub's own
# certificate, plain HTTP on PORT (default 3000) for device onboarding only.
set -euo pipefail
cd "$(dirname "$0")/.."
export TIMING_MODE=hub HUB_TLS=1
bin/rails db:prepare
bin/rails hub:certs
exec bin/rails server -b 0.0.0.0 -p "${PORT:-3000}"
```

Append to `.gitignore`:
```
/storage/certs/
```

- [ ] **Step 7: Run tests, then verify HTTPS by hand**

```bash
bin/rails test && TIMING_DB=postgresql bin/rails test && bin/packwerk check && bin/rails zeitwerk:check
PORT=3100 HUB_TLS_PORT=3543 bin/hub &   # wait for "Listening on ssl://0.0.0.0:3543"
curl -s --cacert storage/certs/root-ca.crt https://localhost:3543/up -o /dev/null -w "https %{http_code}\n"
curl -s http://localhost:3100/graphql -X POST -o /dev/null -w "http graphql %{http_code}\n"
curl -s http://localhost:3100/onboarding -o /dev/null -w "http onboarding %{http_code}\n"
kill %1
```
Expected: `https 200`, `http graphql 403`, `http onboarding 200`. Paste this output into the report.

- [ ] **Step 8: Commit**

```bash
git add -A
git commit -m "feat(access): hub local CA, HTTPS-only gate, device onboarding page, bin/hub

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 10: Race simulator, demo event, terminal standings

**Files:**
- Create: `lib/race_simulator.rb`, `lib/race_simulator/{generator,writer,runner,demo,table}.rb`, `bin/simulate-race`, `test/lib/race_simulator/generator_test.rb`, `test/lib/race_simulator/writer_runner_test.rb`, `test/lib/race_simulator/table_test.rb`
- Modify: `lib/tasks/hub.rake`

**Interfaces:**
- Consumes: `Device.pair!` (Task 8), `Ruling`, `Capture`, `StandingsService` (Task 5).
- Produces:
  - `RaceSimulator::RaceSpec(race_id:, offset_ms:, bibs:)`, `RaceSimulator::RiderTruth(bib:, race_id:, crossings_ms:, untagged:)` — crossings relative to the gun; `untagged` = indexes tapped without a bib.
  - `RaceSimulator.specs_for(start_group) -> [RaceSpec]`.
  - `RaceSimulator::Generator.new(races:, laps:, seed: 1, lap_ms: 300_000, spread: 0.12, jitter: 0.03, start_lap_factor: 0.8, untagged_rate: 0.0, untagged_min_gap_ms: 120_000).call -> [RiderTruth]`.
  - `RaceSimulator::Writer.new(event:, device_name: "Simulator")` with `#fire_gun(start_group, at_ms:)`, `#set_lap_count(start_group, laps)`, `#capture(at_ms:, bib:) -> Capture`.
  - `RaceSimulator::Runner.new(writer:, gun_at_ms:, truths:, speed: 0, sleeper: ->(s) { sleep(s) }).call`; `RaceSimulator::Runner.taps(truths) -> [Tap(at_ms:, bib:)]`.
  - `RaceSimulator::Demo.create!(riders_per_race: 10, name: "Demo CX") -> Event` (one timed start group, 3 races at 0/30/60 s, bibs 101.., 201.., 301..).
  - `RaceSimulator.run(event:, speed:, seed:, laps:, untagged_rate:, out:)`.
  - `RaceSimulator::Table.render(report) -> String`.
  - `bin/simulate-race`; rake `hub:demo`, `hub:standings EVENT=<id>`.

- [ ] **Step 1: Write failing tests**

`test/lib/race_simulator/generator_test.rb`:
```ruby
require "test_helper"

class RaceSimulator::GeneratorTest < ActiveSupport::TestCase
  RACES = [RaceSimulator::RaceSpec.new(race_id: "a", offset_ms: 0, bibs: (101..110).to_a),
           RaceSimulator::RaceSpec.new(race_id: "b", offset_ms: 30_000, bibs: (201..210).to_a)].freeze

  def generate(**opts) = RaceSimulator::Generator.new(races: RACES, laps: 5, seed: 7, **opts).call

  test "is deterministic for a seed" do
    assert_equal generate, generate
    refute_equal generate, RaceSimulator::Generator.new(races: RACES, laps: 5, seed: 8).call
  end

  test "every rider finishes on their first crossing once the leader completes the laps" do
    truths = generate
    leader_finish = truths.filter_map { it.crossings_ms[4] }.min
    truths.each do |t|
      assert_operator t.crossings_ms.last, :>=, leader_finish
      assert t.crossings_ms[0..-2].all? { it < leader_finish }, "bib #{t.bib} has crossings after its finish"
      assert_equal t.crossings_ms.sort, t.crossings_ms
    end
    assert_equal 5, truths.map { it.crossings_ms.size }.max
  end

  test "untagged taps are never a rider's first or last crossing and are spread out" do
    truths = generate(untagged_rate: 1.0)
    picked = truths.flat_map { |t| t.untagged.map { [t, it] } }
    assert_operator picked.size, :>=, 3
    picked.each { |t, i| assert i.between?(1, t.crossings_ms.size - 2) }
    times = picked.map { |t, i| t.crossings_ms[i] }.sort
    assert times.each_cons(2).all? { |a, b| b - a >= 120_000 }
    assert truths.all? { it.untagged.size <= 1 }
  end
end
```

`test/lib/race_simulator/writer_runner_test.rb`:
```ruby
require "test_helper"

class RaceSimulator::WriterRunnerTest < ActiveSupport::TestCase
  setup do
    @event = RaceSimulator::Demo.create!(riders_per_race: 3)
    @group = @event.start_groups.first
  end

  test "demo event has one timed start group with three races at 30 s offsets" do
    assert_equal({ "type" => "timed", "target_duration_ms" => 1_500_000 }, @group.finish_rule)
    assert_equal [0, 30_000, 60_000], @group.races.order(:start_offset_ms).pluck(:start_offset_ms)
    assert_equal %w[101 102 103 201 202 203 301 302 303], @event.registrations.order(:bib).pluck(:bib)
  end

  test "writer and runner record the gun, lap count, and taps — untagged ones without a bib" do
    truths = RaceSimulator::Generator.new(races: RaceSimulator.specs_for(@group), laps: 3, seed: 3, untagged_rate: 1.0).call
    writer = RaceSimulator::Writer.new(event: @event)
    writer.fire_gun(@group, at_ms: 1_000_000)
    writer.set_lap_count(@group, 3)
    slept = []
    RaceSimulator::Runner.new(writer:, gun_at_ms: 1_000_000, truths:, speed: 1000, sleeper: ->(s) { slept << s }).call

    taps = RaceSimulator::Runner.taps(truths)
    captures = Capture.where(event: @event).order(:device_seq)
    assert_equal taps.size, captures.count
    assert_equal taps.map { 1_000_000 + it.at_ms }, captures.pluck(:captured_at_ms)
    assert_equal truths.sum { it.untagged.size }, captures.where(bib: nil).count
    assert_equal (1..taps.size).to_a, captures.pluck(:device_seq)
    assert slept.any?
    assert_equal %w[set_group_start set_lap_count], Ruling.where(event: @event).order(:created_at_ms, :id).pluck(:kind)
  end
end
```

`test/lib/race_simulator/table_test.rb`:
```ruby
require "test_helper"

class RaceSimulator::TableTest < ActiveSupport::TestCase
  test "renders each race as a text table" do
    event = create_event
    race = create_race(event:, category: create_category(name: "Women Open", gender: "F", ability_levels: []))
    register(race:, bib: "301", rider: create_rider(first_name: "Ann", last_name: "Lee", gender: "F"))
    rule(event:, kind: "set_group_start", start_group_id: race.start_group_id, at_ms: 0)
    record_capture(device: create_device(event:), seq: 1, at_ms: 61_500, bib: "301")
    text = RaceSimulator::Table.render(StandingsService.report(event, now_ms: 100_000))
    assert_includes text, "Women Open — in progress — 3 laps"
    assert_match(/^\s*1\s+301\s+Ann Lee\s+racing\s+1\s+1:01\.5/, text)
  end
end
```

- [ ] **Step 2: Run to verify failure**

Run: `bin/rails test test/lib/race_simulator`
Expected: `uninitialized constant RaceSimulator`.

- [ ] **Step 3: Simulator modules**

`lib/race_simulator.rb`:
```ruby
# Writes realistic races straight into the hub, as if a tablet were tapping.
module RaceSimulator
  RaceSpec = Data.define(:race_id, :offset_ms, :bibs)
  RiderTruth = Data.define(:bib, :race_id, :crossings_ms, :untagged)

  def self.specs_for(start_group)
    start_group.races.includes(:registrations).order(:start_offset_ms, :id).map do |race|
      RaceSpec.new(race_id: race.id, offset_ms: race.start_offset_ms, bibs: race.registrations.map(&:bib).sort)
    end
  end

  def self.run(event:, speed:, seed:, laps:, untagged_rate:, out: $stdout)
    writer = Writer.new(event:)
    gun = Clock.now_ms
    truths = event.start_groups.order(:id).flat_map do |group|
      writer.fire_gun(group, at_ms: gun)
      writer.set_lap_count(group, laps) if group.finish_rule["type"] == "timed"
      Generator.new(races: specs_for(group), laps:, seed:, untagged_rate:).call
    end
    out.puts "Event #{event.id}: gun fired, #{Runner.taps(truths).size} taps to write at #{speed.positive? ? "#{speed}x" : 'once'}"
    Runner.new(writer:, gun_at_ms: gun, truths:, speed:).call
    out.puts "Done. See standings: bin/rails hub:standings EVENT=#{event.id}"
  end
end
```

`lib/race_simulator/generator.rb`:
```ruby
module RaceSimulator
  # Ground-truth crossings for a start group. Each rider has a pace within
  # ±spread of lap_ms, laps vary by ±jitter, and the start lap is shorter.
  # Riders stop on their first crossing after the leader completes `laps`.
  class Generator
    def initialize(races:, laps:, seed: 1, lap_ms: 300_000, spread: 0.12, jitter: 0.03, start_lap_factor: 0.8,
                   untagged_rate: 0.0, untagged_min_gap_ms: 120_000)
      @races = races
      @laps = laps
      @seed = seed
      @lap_ms = lap_ms
      @spread = spread
      @jitter = jitter
      @start_lap_factor = start_lap_factor
      @untagged_rate = untagged_rate
      @untagged_min_gap_ms = untagged_min_gap_ms
    end

    def call
      rng = Random.new(@seed)
      raw = @races.flat_map do |race|
        race.bibs.map do |bib|
          pace = @lap_ms * (1 + rng.rand(-@spread..@spread))
          t = race.offset_ms
          crossings = Array.new(@laps + 3) do |i|
            t += (pace * (i.zero? ? @start_lap_factor : 1) * (1 + rng.rand(-@jitter..@jitter))).round
          end
          [bib.to_s, race.race_id, crossings]
        end
      end
      leader_finish = raw.map { |_, _, crossings| crossings[@laps - 1] }.min
      truths = raw.map do |bib, race_id, crossings|
        RiderTruth.new(bib:, race_id:, crossings_ms: crossings[0..crossings.index { it >= leader_finish }], untagged: [])
      end
      pick_untagged(truths, rng)
    end

    private

    # At most one bib-less tap per rider, never the first or last crossing, and
    # far enough apart that each lines up with only one rider's missed crossing.
    def pick_untagged(truths, rng)
      taken = []
      truths.sort_by(&:bib).to_h do |truth|
        candidates = (1..truth.crossings_ms.size - 2).to_a
        pick = nil
        if candidates.any? && rng.rand < @untagged_rate
          index = candidates[rng.rand(candidates.size)]
          at = truth.crossings_ms[index]
          if taken.all? { (it - at).abs >= @untagged_min_gap_ms }
            taken << at
            pick = index
          end
        end
        [truth.bib, truth.with(untagged: pick ? [pick] : [])]
      end.then { |by_bib| truths.map { by_bib.fetch(it.bib) } }
    end
  end
end
```

`lib/race_simulator/writer.rb`:
```ruby
module RaceSimulator
  # Records the simulation as a "Simulator" device would. Its hash chain is a
  # placeholder: simulator entries never go through device sync verification.
  class Writer
    def initialize(event:, device_name: "Simulator")
      @event = event
      @device_name = device_name
    end

    def device
      @device ||= Device.find_by(event: @event, name: @device_name) || Device.pair!(event: @event, name: @device_name).first
    end

    def fire_gun(start_group, at_ms:)
      Ruling.create!(event: @event, kind: "set_group_start", payload: { "start_group_id" => start_group.id, "at_ms" => at_ms })
    end

    def set_lap_count(start_group, laps)
      Ruling.create!(event: @event, kind: "set_lap_count", payload: { "start_group_id" => start_group.id, "laps" => laps })
    end

    def capture(at_ms:, bib:)
      last = DeviceEntry.where(device:).order(:device_seq).last
      prev = last&.entry_hash || Digest::SHA256.hexdigest(device.id)
      id = SecureRandom.uuid_v7
      Capture.create!(id:, event: @event, device:, device_seq: (last&.device_seq || 0) + 1, captured_at_ms: at_ms,
                      clock_offset_ms: 0, bib:, prev_hash: prev, entry_hash: Digest::SHA256.hexdigest("#{prev}|#{id}|#{at_ms}|#{bib}"))
    end
  end
end
```

`lib/race_simulator/runner.rb`:
```ruby
module RaceSimulator
  # Writes taps in time order; with speed > 0 it waits so the race plays out
  # `speed` times faster than real time (speed 0 writes everything at once).
  class Runner
    Tap = Data.define(:at_ms, :bib)

    def self.taps(truths)
      truths.flat_map do |truth|
        truth.crossings_ms.each_with_index.map { |ms, i| Tap.new(at_ms: ms, bib: truth.untagged.include?(i) ? nil : truth.bib) }
      end.sort_by { [it.at_ms, it.bib.to_s] }
    end

    def initialize(writer:, gun_at_ms:, truths:, speed: 0, sleeper: ->(seconds) { sleep(seconds) })
      @writer = writer
      @gun_at_ms = gun_at_ms
      @truths = truths
      @speed = speed
      @sleeper = sleeper
    end

    def call
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      self.class.taps(@truths).each do |tap|
        if @speed.positive?
          wait = tap.at_ms / 1000.0 / @speed - (Process.clock_gettime(Process::CLOCK_MONOTONIC) - started)
          @sleeper.call(wait) if wait.positive?
        end
        @writer.capture(at_ms: @gun_at_ms + tap.at_ms, bib: tap.bib)
      end
    end
  end
end
```

`lib/race_simulator/demo.rb`:
```ruby
module RaceSimulator
  # A ready-made CX event: one timed start group, three races 30 s apart.
  module Demo
    RACES = [
      { category: "Masters 35+ Men", gender: "M", age_min: 35, offset_ms: 0, first_bib: 101 },
      { category: "Masters 50+ Men", gender: "M", age_min: 50, offset_ms: 30_000, first_bib: 201 },
      { category: "Women Open", gender: "F", age_min: nil, offset_ms: 60_000, first_bib: 301 }
    ].freeze
    FIRST = %w[Ana Ben Cara Dev Eli Fay Gus Hana Ivo Jun Kai Lia Max Noa Oli Pia].freeze
    LAST = %w[Abe Bose Cruz Diaz Eng Ford Gray Hale Ito Jain Kerr Lund Moss Nash Ortiz Park].freeze

    module_function

    def create!(riders_per_race: 10, name: "Demo CX")
      event = Event.create!(name:, date: Date.current, venue: "Demo Park")
      group = StartGroup.create!(event:, name: "10:00 Masters + Women",
                                 finish_rule: { "type" => "timed", "target_duration_ms" => 1_500_000 })
      RACES.each do |spec|
        category = Category.find_or_create_by!(name: spec[:category]) do |c|
          c.gender = spec[:gender]
          c.age_min = spec[:age_min]
          c.ability_levels = []
        end
        race = Race.create!(event:, start_group: group, category:, start_offset_ms: spec[:offset_ms])
        riders_per_race.times do |i|
          bib = spec[:first_bib] + i
          rider = Rider.create!(first_name: FIRST[bib % FIRST.size], last_name: LAST[(bib * 7) % LAST.size], gender: spec[:gender],
                                birth_date: Date.new(Date.current.year - (spec[:age_min] || 25) - 3 - (i % 5), 6, 1))
          Registration.create!(race:, rider:, bib: bib.to_s)
        end
      end
      event
    end
  end
end
```

`lib/race_simulator/table.rb`:
```ruby
module RaceSimulator
  # Plain-text standings, for watching races before the ops console exists.
  module Table
    module_function

    def render(report)
      races = report.event.races.includes(:category).index_by(&:id)
      lines = []
      lines << "STALE (#{report.error})" if report.stale
      report.output.races.each do |result|
        name = races[result.race_id]&.name || result.race_id
        lines << "#{name} — #{result.state.to_s.tr('_', ' ')} — #{result.lap_count ? "#{result.lap_count} laps" : 'lap count not set'}"
        result.rows.each do |row|
          lines << format("%4s  %-5s %-22s %-9s %3d  %s", row.place || "-", row.bib, row.name, row.status, row.laps, clock(row.elapsed_ms))
        end
        lines << ""
      end
      open = report.output.suggestions.size
      lines << "#{open} open suggestion#{'s' unless open == 1}" if open.positive?
      lines.join("\n")
    end

    def clock(ms)
      return "" unless ms
      tenths = (ms / 100.0).round
      minutes, rest = tenths.divmod(600)
      hours, minutes = minutes.divmod(60)
      seconds = format("%04.1f", rest / 10.0)
      hours.positive? ? format("%d:%02d:%s", hours, minutes, seconds) : "#{minutes}:#{seconds}"
    end
  end
end
```

Note: the table test seeds a fixed 3-lap group, so the header is "3 laps".

- [ ] **Step 4: CLI and rake tasks**

`bin/simulate-race` (then `chmod +x bin/simulate-race`):
```ruby
#!/usr/bin/env ruby
require "optparse"

options = { speed: 20.0, seed: 1, laps: 5, untagged_rate: 0.1 }
OptionParser.new do |o|
  o.banner = "Usage: bin/simulate-race (--demo | --event ID) [options]"
  o.on("--demo", "Create a demo CX event and race it") { options[:demo] = true }
  o.on("--event ID", "Race an existing event") { options[:event] = it }
  o.on("--speed N", Float, "Times faster than real time; 0 writes everything at once (default 20)") { options[:speed] = it }
  o.on("--seed N", Integer, "Random seed (default 1)") { options[:seed] = it }
  o.on("--laps N", Integer, "Laps for the leader (default 5)") { options[:laps] = it }
  o.on("--untagged-rate R", Float, "Share of riders with one bib-less tap (default 0.1)") { options[:untagged_rate] = it }
end.parse!

require_relative "../config/environment"
event = if options[:demo] then RaceSimulator::Demo.create!
        elsif options[:event] then Event.find(options[:event])
        else abort "Pass --demo or --event ID"
        end
RaceSimulator.run(event:, **options.slice(:speed, :seed, :laps, :untagged_rate))
```

Append inside `namespace :hub` in `lib/tasks/hub.rake`:
```ruby
  desc "Create a demo CX event (prints its id)"
  task demo: :environment do
    event = RaceSimulator::Demo.create!
    puts "Demo event #{event.id}. Race it: bin/simulate-race --event #{event.id}"
  end

  desc "Print standings in the terminal: EVENT=<id> [WATCH=1 to refresh every 2 s]"
  task standings: :environment do
    event = Event.find(ENV.fetch("EVENT") { abort "Set EVENT=<event id>" })
    loop do
      print "\e[H\e[2J" if ENV["WATCH"]
      puts RaceSimulator::Table.render(StandingsService.report(event))
      break unless ENV["WATCH"]
      sleep 2
    end
  end
```

- [ ] **Step 5: Run tests, then try it by hand**

```bash
bin/rails test && TIMING_DB=postgresql bin/rails test && bin/packwerk check && bin/rails zeitwerk:check
bin/simulate-race --demo --speed 0 --seed 7
bin/rails hub:standings EVENT=<id printed above>
```
Expected: tests green; the simulator prints the event id and tap count; `hub:standings` prints three race tables with finished riders and a suggestion count. Paste the standings output into the report.

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "feat(simulator): race simulator, demo CX event, terminal standings view

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 11: Race-day API test and hub runbook

**Files:**
- Create: `test/integration/api/race_day_test.rb`, `docs/hub-runbook.md`

**Interfaces:**
- Consumes: everything above.
- Produces: the plan's acceptance test; `docs/hub-runbook.md`.

- [ ] **Step 1: Write the acceptance test**

`test/integration/api/race_day_test.rb`:
```ruby
require "test_helper"

# Spec §10 (simulator-driven): a CX start group with three waves is timed with
# some bib-less taps; officials fix them from the review queue and publish. The
# result must equal what perfect timing would have produced.
class RaceDayTest < ActionDispatch::IntegrationTest
  STANDINGS = <<~GQL
    query($id: ID!) {
      standings(eventId: $id) {
        races { race { id } publication rows { place bib status laps elapsedMs } }
        suggestions { key kind }
      }
    }
  GQL

  def standings = gql(STANDINGS, id: @event.id).dig("data", "standings")

  def perfect_rows(group, truths, gun)
    rulings = [
      Results::Ruling.new(id: "gun", kind: "set_group_start", payload: { "start_group_id" => group.id, "at_ms" => gun }, created_at_ms: 0),
      Results::Ruling.new(id: "laps", kind: "set_lap_count", payload: { "start_group_id" => group.id, "laps" => 5 }, created_at_ms: 1)
    ]
    captures = truths.flat_map do |t|
      t.crossings_ms.each_with_index.map do |ms, i|
        Results::Capture.new(id: "#{t.bib}-#{i}", device_id: "d", device_seq: 0, captured_at_ms: gun + ms, clock_offset_ms: 0, bib: t.bib)
      end
    end
    input = ResultsSnapshot.for(@event, now_ms: Clock.now_ms).with(captures:, bib_assignments: [], rulings:)
    Results.compute(input).races.to_h do |race|
      [race.race_id, race.rows.map { [it.place, it.bib, it.status.to_s.upcase, it.laps, it.elapsed_ms] }]
    end
  end

  test "untagged taps fixed from the review queue give the same published standings as perfect timing" do
    sign_in(create_official(role: "chief", pin: "2468"), "2468")
    @event = RaceSimulator::Demo.create!(riders_per_race: 8)
    group = @event.start_groups.first

    gun = gql("mutation($id: ID!) { fireStart(startGroupId: $id) { ruling { payload } errors } }", id: group.id)
            .dig("data", "fireStart", "ruling", "payload", "at_ms")
    assert_empty gql("mutation($id: ID!) { setLapCount(startGroupId: $id, laps: 5) { errors } }", id: group.id)
                   .dig("data", "setLapCount", "errors")

    truths = RaceSimulator::Generator.new(races: RaceSimulator.specs_for(group), laps: 5, seed: 7, untagged_rate: 0.5).call
    untagged = truths.sum { it.untagged.size }
    assert_operator untagged, :>=, 3
    RaceSimulator::Runner.new(writer: RaceSimulator::Writer.new(event: @event), gun_at_ms: gun, truths:).call

    missed = standings["suggestions"].select { it["kind"] == "SUSPECTED_MISSED_CROSSING" }
    assert_equal untagged, missed.size
    missed.each do |suggestion|
      result = gql("mutation($id: ID!, $key: String!) { acceptSuggestion(eventId: $id, key: $key) { errors } }",
                   id: @event.id, key: suggestion["key"])
      assert_empty result.dig("data", "acceptSuggestion", "errors"), suggestion["key"]
    end
    assert_empty standings["suggestions"]

    expected = perfect_rows(group, truths, gun)
    standings["races"].each do |race|
      actual = race["rows"].map { [it["place"], it["bib"], it["status"], it["laps"], it["elapsedMs"]] }
      assert_equal expected.fetch(race.dig("race", "id")), actual
      published = gql("mutation($id: ID!) { publishResults(raceId: $id) { errors } }", id: race.dig("race", "id"))
      assert_empty published.dig("data", "publishResults", "errors")
    end
    assert_equal %w[PUBLISHED], standings["races"].map { it["publication"] }.uniq
  end
end
```

- [ ] **Step 2: Run it**

Run: `bin/rails test test/integration/api/race_day_test.rb && TIMING_DB=postgresql bin/rails test test/integration/api/race_day_test.rb`
Expected: PASS on both. If it fails, find the cause in the earlier tasks' code (simulator, suggestions, accept flow) — do not weaken the assertions. If the engine produces a suggestion other than the expected missed crossings, report it with the suggestion keys and messages instead of filtering it out.

- [ ] **Step 3: Runbook**

`docs/hub-runbook.md`:
````markdown
# Running the hub

## First time on a laptop

```bash
bin/rails db:prepare
NAME="Your Name" bin/rails access:bootstrap   # prints the admin PIN
```

## Development (HTTP on port 3000)

```bash
bin/rails server
```

## At the venue (HTTPS)

```bash
bin/hub
```

- HTTPS on port 3443 with the hub's own certificate (`storage/certs/`).
- Plain HTTP on port 3000 only serves `/onboarding` (tablets download and trust the hub certificate there, once) and `/up`.
- Keep `storage/` backed up: it holds the database and the certificate authority. A new CA means re-trusting every tablet.

## Watch a simulated race

```bash
bin/simulate-race --demo                  # 20× real time; --speed 0 writes it all at once
bin/rails hub:standings EVENT=<id> WATCH=1
```

## API

- `POST /session` with `{"name": "...", "pin": "..."}` signs in (session cookie).
- `POST /graphql` — queries: `me`, `events`, `event(id)`, `categories`, `officials`, `standings(eventId)`, `rulings(eventId)`, `devices(eventId)`.
- `/cable` — `EventChannel` with `event_id`; `{"type":"changed"}` means refetch.
- `POST /devices/pair` with `{"token": "...", "name": "..."}` pairs a tablet (token from `createPairingToken`).
````

- [ ] **Step 4: Full verification**

```bash
bundle exec bin/test-results && bin/rails test && TIMING_DB=postgresql bin/rails test && bin/packwerk check && bin/rails zeitwerk:check
```
Expected: all green.

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "test(api): simulator-driven race-day acceptance test; hub runbook

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

## Coverage map (spec → task)

| Spec / TODO | Task |
|---|---|
| §8 officials, PINs, roles, every ruling records official | 1, 6 |
| §7 GraphQL schema, mode-agnostic | 2–6, 8 |
| §6 data the console needs: setup + CSV import with warnings | 3, 4 |
| §6 devices: pairing QR code, last-seen, clock offset, revoke | 8 |
| §6 start control: GO, per-race start, lap count (any group) | 6 |
| §6 review queue: suggestions, accept/dismiss; ruling history + revert | 5, 6 |
| §6 standings: provisional/published/changed, publish | 5, 6 |
| §7 live updates | 7 |
| §8 pairing tokens 10 min single use; credentials revocable | 8 |
| §8 local CA (option A), onboarding page, HTTPS | 9 |
| §9 last good standings on engine error | 5 |
| §10 race simulator | 10, 11 |
| TODO: clients never set created_at_ms | 6 (RulingWriter) |
| TODO: suggestion fixes are templates to complete | 5, 6 (SuggestionFix) |
| TODO: lap count on any group | 6 (setLapCount) |
| **Not here:** React ops console | Plan 3 |
| **Not here:** device sync, capture PWA, hash-chain verification, tablet acceptance test | Plan 4 |
