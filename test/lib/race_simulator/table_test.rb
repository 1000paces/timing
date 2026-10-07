require "test_helper"

class RaceSimulator::TableTest < ActiveSupport::TestCase
  test "renders each race as a text table" do
    event = create_event
    race = create_race(event:, category: nil, gender: "women", name_override: "Women Open", expected_laps: 3)
    register(race:, bib: "301", racer: create_racer(first_name: "Ann", last_name: "Lee", gender: "F"))
    rule(event:, kind: "set_race_start", race_id: race.id, at_ms: 0)
    record_capture(device: create_device(event:), seq: 1, at_ms: 61_500, bib: "301")
    text = RaceSimulator::Table.render(StandingsService.report(event, now_ms: 100_000))
    assert_includes text, "Women Open — in progress — 3 laps"
    assert_match(/^\s*1\s+301\s+Ann Lee\s+racing\s+1\s+1:01\.5/, text)
  end
end
