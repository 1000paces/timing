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

  test "a pairing code can't carry another event's checkpoint" do
    other = create_event(name: "Other").checkpoints.create!(position: 1, name: "X")
    body = gql("mutation($e: ID!, $cp: ID) { createPairingToken(eventId: $e, checkpointId: $cp) { token errors } }", e: @event.id, cp: other.id)
    assert_equal [ "That checkpoint isn't on this event's course" ], body.dig("data", "createPairingToken", "errors")
    assert_nil body.dig("data", "createPairingToken", "token")
  end

  test "the event's format can be changed, and gravel defaults to course" do
    assert_equal "course", gql("query($id: ID!) { event(id: $id) { raceFormat } }", id: @event.id).dig("data", "event", "raceFormat")
    gql("mutation($id: ID!) { updateEvent(id: $id, raceFormat: \"laps\") { errors } }", id: @event.id)
    assert_equal "laps", @event.reload.race_format
  end
end
