require "test_helper"

class SyncTest < ActionDispatch::IntegrationTest
  setup do
    @event = create_event
    @race = create_race(event: @event)
    register(race: @race, bib: "101", racer: create_racer(first_name: "Ann", last_name: "Lee", birth_date: Date.new(1980, 1, 1), license_number: "L1"))
    Ruling.create!(event: @event, kind: "set_race_start", payload: { "race_id" => @race.id, "at_ms" => 0 })
    @device, @credential = Device.pair!(event: @event, name: "Finish phone")
  end

  def auth(device = @device, credential = @credential) = { "Authorization" => "Device #{device.id}:#{credential}", "CONTENT_TYPE" => "application/json" }
  def push(entries, headers: auth) = post("/sync/v1/push", params: { entries: }.to_json, headers:)

  # A phone's entries: sequence numbers and the hash chain, as the app builds them.
  def chain(specs, from: 1, prev: DeviceHash.genesis(@device.id))
    specs.each_with_index.map do |spec, i|
      entry = { "id" => spec[:id] || SecureRandom.uuid_v7, "kind" => spec[:kind] || "capture", "device_seq" => from + i, "prev_hash" => prev }
      entry.merge!(spec.except(:id, :kind).transform_keys(&:to_s)).compact!
      prev = DeviceHash.digest(entry)
      entry.merge("hash" => prev)
    end
  end

  test "unknown, wrong or revoked credentials are refused" do
    post "/sync/v1/clock", params: { t0: 1 }.to_json, headers: { "CONTENT_TYPE" => "application/json" }
    assert_response :unauthorized
    post "/sync/v1/clock", params: { t0: 1 }.to_json, headers: auth(@device, "nope")
    assert_response :unauthorized
    @device.revoke!
    post "/sync/v1/clock", params: { t0: 1 }.to_json, headers: auth
    assert_response :unauthorized
  end

  test "clock returns hub receive and reply times, and records the phone's offset and last seen" do
    post "/sync/v1/clock", params: { t0: 5 }.to_json, headers: auth.merge("X-Clock-Offset-Ms" => "-40")
    body = response.parsed_body
    assert body["t1"].is_a?(Integer) && body["t1"] <= body["t2"]
    @device.reload
    assert_equal -40, @device.clock_offset_ms
    assert @device.last_seen_at_ms.present?
  end

  test "push stores a chain, is idempotent, and resumes after a lost ack" do
    batch = chain([ { captured_at_ms: 60_000, clock_offset_ms: 0, bib: "101" }, { captured_at_ms: 70_000, clock_offset_ms: 0 } ])
    push(batch)
    assert_equal({ "ack_seq" => 2 }, response.parsed_body)
    push(batch)
    assert_equal({ "ack_seq" => 2 }, response.parsed_body)
    assert_equal 2, Capture.where(device: @device).count

    # Review Focus 1: an overlap plus new entries
    more = chain([ { captured_at_ms: 120_000, clock_offset_ms: 0, bib: "101" } ], from: 3, prev: batch.last["hash"])
    push(batch.drop(1) + more)
    assert_equal({ "ack_seq" => 3 }, response.parsed_body)
    assert_equal 3, Capture.where(device: @device).count
    assert @device.reload.last_sync_at_ms.present?
    assert_equal @event, Capture.find(batch.first["id"]).event
  end

  test "a gap or a bad hash is a chain mismatch: nothing applied, the device is flagged" do
    batch = chain([ { captured_at_ms: 1_000, clock_offset_ms: 0, bib: "101" }, { captured_at_ms: 2_000, clock_offset_ms: 0 } ])
    push([ batch.last ])
    assert_response :conflict
    assert_equal({ "error" => "chain_mismatch", "ack_seq" => 0 }, response.parsed_body)
    assert @device.reload.sync_stopped_at_ms.present?

    @device.update!(sync_stopped_at_ms: nil)
    tampered = batch.map(&:dup)
    tampered.first["bib"] = "999"
    push(tampered)
    assert_response :conflict
    assert_equal 0, DeviceEntry.where(device: @device).count
  end

  # Review Focus 5
  test "a void or bib fix for another device's capture is a chain mismatch" do
    other = Capture.record!(device: create_device(event: @event, name: "Other"), at_ms: 1, bib: "101")
    push(chain([ { kind: "capture_void", capture_id: other.id } ]))
    assert_response :conflict
    assert_equal 0, CaptureVoid.count
  end

  test "pushes are capped at 500 entries" do
    push(chain(Array.new(501) { { captured_at_ms: it, clock_offset_ms: 0 } }))
    assert_response :unprocessable_content
  end

  test "pushed captures, fixes and voids reach results; status reports them back" do
    batch = chain([ { captured_at_ms: 60_000, clock_offset_ms: 0, bib: "999" }, { captured_at_ms: 90_000, clock_offset_ms: 0, bib: "101" },
                   { captured_at_ms: 120_000, clock_offset_ms: 0, bib: "101" } ])
    fix = chain([ { kind: "bib_assignment", capture_id: batch[0]["id"], bib: "101" }, { kind: "capture_void", capture_id: batch[1]["id"] } ],
                from: 4, prev: batch.last["hash"])
    push(batch + fix)
    assert_equal({ "ack_seq" => 5 }, response.parsed_body)
    assert_equal 2, StandingsService.report(@event).output.races.first.rows.first.laps

    get "/sync/v1/status", headers: auth
    rows = response.parsed_body["captures"].index_by { it["id"] }
    assert_equal({ "bib" => "101", "entered_bib" => "999", "bib_source" => "device", "lap" => 1, "voided" => false },
                 rows[batch[0]["id"]].slice("bib", "entered_bib", "bib_source", "lap", "voided"))
    assert rows[batch[1]["id"]]["voided"]
    assert_equal 2, rows[batch[2]["id"]]["lap"]
  end

  test "the roster has bib, name and race only, with a version for If-None-Match" do
    get "/sync/v1/roster", headers: auth
    body = response.parsed_body
    assert_equal({ "name" => @event.name, "races" => [ { "id" => @race.id, "name" => @race.name } ] }, body["event"])
    assert_equal [ { "bib" => "101", "name" => "Ann Lee", "race_id" => @race.id } ], body["racers"]
    refute_match(/1980|L1/, response.body)
    get "/sync/v1/roster", headers: auth.merge("If-None-Match" => body["version"])
    assert_response :not_modified
  end

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
end
