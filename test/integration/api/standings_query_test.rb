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
    race = create_race(event: @event, expected_laps: 2)
    register(race:, bib: "1", rider: create_rider(first_name: "Ann", last_name: "Lee"))
    register(race:, bib: "2", rider: create_rider(first_name: "Bo", last_name: "Yu"))
    rule(event: @event, kind: "set_race_start", race_id: race.id, at_ms: 0)
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
