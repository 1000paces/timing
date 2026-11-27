require "test_helper"

class FlagOutTest < ActionDispatch::IntegrationTest
  STANDINGS = <<~GQL
    query($id: ID!) { standings(eventId: $id) { races { flagOutAtMs flagOutLeaderBib } suggestions { key kind bib } } }
  GQL

  setup do
    sign_in(create_official(name: "Chief Pat", role: "chief", pin: "2468"), "2468")
    @event = create_event
    @race = create_race(event: @event)
    %w[1 2].each { register(race: @race, bib: it) }
    @start = Clock.now_ms - 3_600_000
    tablet = create_device(event: @event)
    # 1 leads (still on course: last crossed 10 min ago); 2 rides three 10-minute laps and stops before the flag.
    { "1" => [ 600, 1_200, 1_800, 2_400, 3_000 ], "2" => [ 610, 1_210, 1_810 ] }.each.with_index do |(bib, laps), i|
      laps.each_with_index { |s, lap| record_capture(device: tablet, seq: i * 10 + lap + 1, at_ms: @start + s * 1000, bib:) }
    end
    rule(event: @event, kind: "set_race_start", race_id: @race.id, at_ms: @start)
    rule(event: @event, kind: "set_lap_count", race_id: @race.id, laps: 6) # not reached: only the flag opens the finish
  end

  def standings = gql(STANDINGS, id: @event.id).dig("data", "standings")

  test "after the flag, standings name the rider who rode on, and a rider who stopped is overdue until marked DNF" do
    assert_empty standings["suggestions"].select { it["kind"] == "OVERDUE" }, "not before the finish opens"
    gql("mutation($id: ID!, $at: Millis!) { flagOut(raceId: $id, atMs: $at) { errors } }", id: @race.id, at: @start + 1_900_000)
    report = standings
    assert_equal [ { "flagOutAtMs" => @start + 1_900_000, "flagOutLeaderBib" => "1" } ], report["races"]
    overdue = report["suggestions"].find { it["kind"] == "OVERDUE" }
    assert_equal "2", overdue["bib"]

    body = gql("mutation($id: ID!, $key: String!) { acceptSuggestion(eventId: $id, key: $key) { errors } }", id: @event.id, key: overdue["key"])
    assert_empty body.dig("data", "acceptSuggestion", "errors")
    assert_equal [ "2" ], Ruling.where(event: @event, kind: "dnf").map { it.payload["bib"] }
    assert_empty standings["suggestions"].select { it["kind"] == "OVERDUE" }
  end

  test "the current wave carries the hub's time, so a flag from the line can be stamped when it was first pressed" do
    before = Clock.now_ms
    as_of = gql("query($id: ID!) { currentWave(eventId: $id) { asOfMs } }", id: @event.id).dig("data", "currentWave", "asOfMs")
    assert_operator as_of, :>=, before
    assert_operator as_of, :<=, Clock.now_ms
  end
end
