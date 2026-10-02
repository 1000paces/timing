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
    @race = create_race(event: @event, expected_laps: 5)
    %w[1 2 3].each { register(race: @race, bib: it) }
  end

  test "setRaceStart defaults to hub time and records the signed-in official" do
    before = Clock.now_ms
    result = mutate("setRaceStart", "$id: ID!", "raceId: $id", id: @race.id)
    assert_empty result["errors"]
    ruling = Ruling.find(result["ruling"]["id"])
    assert_equal "set_race_start", ruling.kind
    assert_operator ruling.payload["at_ms"], :>=, before
    assert_equal @chief.id, ruling.official_id
  end

  # Review Focus 5
  test "setLapCount applies to the race's whole cohort; setRaceStart takes a time" do
    partner = create_race(event: @event, category: "Cat 4")
    alone = create_race(event: @event, category: "Novice", finish_with_leader: false)
    body = gql("mutation($id: ID!) { setLapCount(raceId: $id, laps: 3) { rulings { payload } errors } }", id: @race.id)
    payloads = body.dig("data", "setLapCount", "rulings").map { it["payload"] }
    assert_equal [@race.id, partner.id].sort, payloads.map { it["race_id"] }.sort
    assert_equal [3], payloads.map { it["laps"] }.uniq
    refute_includes payloads.map { it["race_id"] }, alone.id
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
    rule(event: @event, kind: "set_race_start", race_id: @race.id, at_ms: 0)
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
    rule(event: @event, kind: "set_race_start", race_id: @race.id, at_ms: 0)
    record_capture(device: create_device(event: @event), seq: 1, at_ms: 100_000, bib: nil, id: "loose")
    missing = mutate("acceptSuggestion", "$id: ID!", 'eventId: $id, key: "unassigned:loose"', id: @event.id)
    assert_equal ["Provide bib to accept this suggestion"], missing["errors"]
    done = mutate("acceptSuggestion", "$id: ID!", 'eventId: $id, key: "unassigned:loose", bib: "3"', id: @event.id)
    assert_equal({ "capture_id" => "loose", "bib" => "3" }, done.dig("ruling", "payload"))
  end

  test "dismissSuggestion hides it" do
    rule(event: @event, kind: "set_race_start", race_id: @race.id, at_ms: 0)
    record_capture(device: create_device(event: @event), seq: 1, at_ms: 100_000, bib: nil, id: "loose")
    mutate("dismissSuggestion", "$id: ID!", 'eventId: $id, key: "unassigned:loose"', id: @event.id)
    refute_includes suggestion_keys, "unassigned:loose"
  end

  test "publishResults records the race's current digest" do
    rule(event: @event, kind: "set_race_start", race_id: @race.id, at_ms: 0)
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
    body = gql("mutation($id: ID!) { setRaceStart(raceId: $id) { errors } }", id: @race.id)
    assert_equal "Requires the chief role", body["errors"].first["message"]
  end

  test "stale standings refuse accept and publish and record nothing" do
    rule(event: @event, kind: "set_race_start", race_id: @race.id, at_ms: 0)
    record_capture(device: create_device(event: @event), seq: 1, at_ms: 100_000, bib: nil, id: "loose")
    original = StandingsService.method(:report)
    StandingsService.define_singleton_method(:report) do |event, **|
      StandingsService::Report.new(event:, output: original.call(event).output, computed_at_ms: 0, stale: true, error: "boom")
    end
    before = Ruling.count
    msg = ["Standings are out of date; try again in a moment"]
    assert_equal msg, mutate("acceptSuggestion", "$id: ID!", 'eventId: $id, key: "unassigned:loose", bib: "3"', id: @event.id)["errors"]
    assert_equal msg, mutate("publishResults", "$id: ID!", "raceId: $id", id: @race.id)["errors"]
    assert_equal before, Ruling.count
  ensure
    StandingsService.define_singleton_method(:report, original) if original
  end

  test "recordRuling rejects a non-object payload" do
    result = gql("mutation($id: ID!) { recordRuling(eventId: $id, kind: DNF, payload: \"x\") { errors } }", id: @event.id)
    assert_equal ["payload must be a JSON object"], result.dig("data", "recordRuling", "errors")
  end

  test "signed-out callers are told to sign in before any lookup" do
    delete "/session"
    body = gql("mutation { setRaceStart(raceId: \"nope\") { errors } }")
    assert_equal "Sign in required", body["errors"].first["message"]
  end
end
