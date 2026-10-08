require "test_helper"

class RacerFixesTest < ActionDispatch::IntegrationTest
  T0 = Time.utc(2026, 10, 18, 10, 0, 0).to_i * 1000
  def at(min, sec) = T0 + ((min * 60) + sec) * 1000

  RACER = <<~GQL
    query($id: ID!, $bib: String!) {
      racer(eventId: $id, bib: $bib) {
        bib name race { name } status place laps startAtMs pullAtMs finishRef lapPositions
        crossings { ref atMs inserted kind lap lapMs source }
        rulings { id kind description officialName undone undoneBy }
      }
    }
  GQL

  setup do
    @event = create_event
    @race = create_race(event: @event)
    register(race: @race, bib: "101", racer: create_racer(first_name: "Ann", last_name: "Lee"))
    register(race: @race, bib: "102", racer: create_racer(first_name: "Bo", last_name: "Yu"))
    rule(event: @event, kind: "set_race_start", race_id: @race.id, at_ms: T0)
    @phone = create_device(event: @event, name: "Finish phone")
    @lap1 = record_capture(device: @phone, seq: 1, at_ms: at(6, 5), bib: "101", id: "lap1")
    @dup = record_capture(device: @phone, seq: 2, at_ms: at(6, 8), bib: "101", id: "dup")
    @lap2 = record_capture(device: @phone, seq: 3, at_ms: at(12, 10), bib: "101", id: "lap2")
    @other = record_capture(device: @phone, seq: 4, at_ms: at(6, 20), bib: "102", id: "other")
    @chief = create_official(name: "Pat", role: "chief", pin: "1111")
  end

  def chief! = sign_in(@chief, "1111")
  def racer(bib = "101") = gql(RACER, id: @event.id, bib:).dig("data", "racer")
  def mutate(name, sig, call, **vars) = gql("mutation(#{sig}) { #{name}(#{call}) { ruling { id kind payload } errors } }", **vars).dig("data", name)

  test "the racer query shows each crossing, its source, lap times and positions — for timers too" do
    sign_in(create_official(role: "timer", pin: "2222"), "2222")
    r = racer
    assert_equal [ "Ann Lee", "Cat 3 Men", "RACING", 1, 2, T0 ], r.values_at("name").push(r.dig("race", "name"), r["status"], r["place"], r["laps"], r["startAtMs"])
    assert_equal [ [ "lap1", "LAP", 1, 365_000, "Finish phone" ], [ "dup", "DUPLICATE", nil, nil, "Finish phone" ], [ "lap2", "LAP", 2, 365_000, "Finish phone" ] ],
                 r["crossings"].map { it.values_at("ref", "kind", "lap", "lapMs", "source") }
    assert_equal [ 1, 1 ], r["lapPositions"]
  end

  # Review Focus 5
  test "an unregistered bib is a clear error" do
    chief!
    body = gql(RACER, id: @event.id, bib: "999")
    assert_equal "No racer with bib 999 in this event", body["errors"].first["message"]
  end

  test "void, move, insert, pull and flag finish write the right rulings; timers are refused" do
    sign_in(create_official(role: "timer", pin: "2222"), "2222")
    refused = gql("mutation($e: ID!) { voidCrossing(eventId: $e, ref: \"dup\") { errors } }", e: @event.id)
    assert_equal "Requires the chief role", refused["errors"].first["message"]

    chief!
    assert_equal({ "capture_id" => "dup" }, mutate("voidCrossing", "$e: ID!", 'eventId: $e, ref: "dup"', e: @event.id).dig("ruling", "payload"))
    assert_equal({ "capture_id" => "other", "bib" => "101" },
                 mutate("moveCrossing", "$e: ID!", 'eventId: $e, captureId: "other", bib: "101"', e: @event.id).dig("ruling", "payload"))
    insert = mutate("insertCrossing", "$e: ID!, $at: Millis!", 'eventId: $e, bib: "102", atMs: $at', e: @event.id, at: at(12, 30))
    assert_equal "insert_capture", insert.dig("ruling", "kind")
    assert_equal({ "bib" => "102", "at_ms" => at(13, 0) },
                 mutate("pullRacer", "$e: ID!, $at: Millis!", 'eventId: $e, bib: "102", atMs: $at', e: @event.id, at: at(13, 0)).dig("ruling", "payload"))
    assert_equal({ "bib" => "101", "capture_id" => "lap2" },
                 mutate("flagFinish", "$e: ID!", 'eventId: $e, bib: "101", ref: "lap2"', e: @event.id).dig("ruling", "payload"))
    assert_equal "FINISHED", racer["status"]
    assert_equal "PULLED", racer("102")["status"]

    # voiding an inserted crossing undoes the insert
    voided = mutate("voidCrossing", "$e: ID!, $r: String!", "eventId: $e, ref: $r", e: @event.id, r: insert.dig("ruling", "id"))
    assert_equal({ "kind" => "revert", "payload" => { "ruling_id" => insert.dig("ruling", "id") } }, voided["ruling"].except("id"))
  end

  test "refusals say why" do
    chief!
    other_event = create_event(name: "Other")
    stranger = record_capture(device: create_device(event: other_event), seq: 1, at_ms: 1, bib: "1", id: "stranger")
    errors = ->(data) { data["errors"] }
    assert_equal [ "That crossing isn't part of this event" ], errors.(mutate("voidCrossing", "$e: ID!", 'eventId: $e, ref: "stranger"', e: @event.id))
    assert_equal [ "Bib 999 is not registered in this event" ],
                 errors.(mutate("moveCrossing", "$e: ID!", 'eventId: $e, captureId: "lap1", bib: "999"', e: @event.id))
    assert_equal [ "A crossing can't be inserted before the race started" ],
                 errors.(mutate("insertCrossing", "$e: ID!, $at: Millis!", 'eventId: $e, bib: "101", atMs: $at', e: @event.id, at: T0 - 1000))
    assert_equal [ "That crossing isn't one of bib 101's" ],
                 errors.(mutate("flagFinish", "$e: ID!", 'eventId: $e, bib: "101", ref: "other"', e: @event.id))
    assert stranger
  end

  # Review Focus 4
  test "undo can't be done twice, and an undo can't be undone" do
    chief!
    void = mutate("voidCrossing", "$e: ID!", 'eventId: $e, ref: "dup"', e: @event.id).dig("ruling", "id")
    revert = "mutation($id: ID!) { revertRuling(rulingId: $id) { ruling { id } errors } }"
    undo = gql(revert, id: void).dig("data", "revertRuling")
    assert_equal [], undo["errors"]
    assert_equal [ "That fix is already undone" ], gql(revert, id: void).dig("data", "revertRuling", "errors")
    assert_equal [ "An undo can't be undone" ], gql(revert, id: undo.dig("ruling", "id")).dig("data", "revertRuling", "errors")

    fixes = racer["rulings"]
    assert_equal [ [ "void_capture", "Void crossing 10:06:08 (bib 101)", "Pat", true, "Pat" ] ],
                 fixes.map { it.values_at("kind", "description", "officialName", "undone", "undoneBy") }
  end
end
